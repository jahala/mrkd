# Plan: mrkd, next round

Derived from `docs/research/markdown-viewer-competitive-scan.md` and `docs/research/mermaid-rendering-options.md`. Every claim about the current code below was checked against the source, and the two renderer dependencies were built and run before being planned in.

## Two findings that shape the whole plan

**1. The Quick Look extension is sandboxed; the app is not.** `Sources/QLExtension/QLExtension.entitlements` sets `com.apple.security.app-sandbox`, while `Sources/Resources/mrkd.entitlements` is empty. A sandboxed app extension cannot spawn a helper executable, so the "long-lived helper process" architecture I recommended for Mermaid would work in the app and silently not work in Quick Look previews. Since `project.yml` deliberately shares `Sources/Engine` and `MarkdownViewController` between the two targets, that divergence is unacceptable. **Mermaid must be linked as a library, embedded once in `Contents/Frameworks/` and linked by both targets.**

**2. mrkd already has the exact pipeline both renderers need.** `MarkdownRenderer` emits an `NSTextAttachment` carrying a placeholder image plus a custom attribute holding the source URL (line ~249); `MarkdownViewController` resolves it asynchronously through `ImageAttachmentProvider` and swaps the image in. Mermaid diagrams and math formulas are the same shape: a source string that resolves to an image, asynchronously, cached, re-rendered when the theme or scale changes. This is the single largest risk-reducer in the plan — neither renderer needs new architecture, only a new provider behind the existing seam.

Consequence for ordering: **do math before Mermaid.** SwaTex is pure Swift, 548 KB of fonts, no build-system change, and it exercises the whole generalised attachment path — including the harder half, inline baseline alignment. Mermaid then reuses a proven pipeline and only has to solve the Rust boundary.

---

## 1. Live reload — DONE

Replaces the manual reload banner. `FileWatcher` already fires on write; `MarkdownViewController.fileWatcher(_:didDetectChangeFor:)` currently only calls `showReloadBanner()`, and `reloadFile()` calls `loadMarkdownFile()`, which re-reads from disk and discards the previous source.

- Test first: reloading a document preserves the scroll anchor; a rapid burst of writes coalesces into one render.
- Debounce writes (agents write in bursts; a single save often fires several events).
- Capture the topmost visible heading before reload, restore to it after. Absolute scroll offset is wrong — the document above the viewport changes length.
- Keep an explicit prompt only for deletion, and suppress auto-reload while the user has a live text selection (reloading would destroy it).
- Retain the previous source string on the controller — needed by task 2.

Acceptance: an agent rewriting the open file updates the view within ~200 ms with the reading position intact, and no banner.

## 2. Changed-block highlight — DONE

Depends on 1. Scope note: this only covers changes while the file is open, which is precisely the agent case. Git-vs-HEAD review is a different, much larger feature and is **not** in this plan.

- Test first: given an old and new source, the changed block indices are exactly the expected set; an unchanged reload highlights nothing.
- Diff old against new `BlockSplitter.split()` output.
- Mark changed blocks with a brief left-gutter accent that fades after a couple of seconds. Themed, not hardcoded.

Acceptance: editing one paragraph of a long document highlights that paragraph and nothing else.

## 3. `mrkd` CLI — DONE

- `mrkd FILE` opens or focuses a window on that file; `mrkd` with no args restores the last document; `cat plan.md | mrkd` renders stdin.
- stdin joins the existing "New from Clipboard" path in `AppDelegate`, which already handles source-without-a-file.
- Ship as a small launcher installed to `~/.local/bin`, with a Settings action to install it (Marky's `install-cli.sh` is the reference; a menu action is friendlier than a script).
- Test first: argument parsing — file, directory, `-`, missing file, no args.

Acceptance: `mrkd README.md` from a terminal opens a rendered window; piping works; a second invocation reuses the existing window rather than stacking new ones.

## 4. Find in page — DONE

Nothing exists today — the only `find` in the codebase is `ThemeImporter.findTokenColor`.

- `NSTextFinder` wired to the TextKit 2 text view, with the standard find bar.
- Menu items under Edit: Find (`Cmd F`), Find Next (`Cmd G`), Find Previous (`Cmd Shift G`), Use Selection for Find (`Cmd E`). `MenuBuilder`'s Edit menu currently has only Copy and Select All.
- Must work in the Quick Look preview too, since both targets share `MarkdownViewController`.

Acceptance: matches highlight and cycle, the find bar respects the active theme, and the incremental-search highlight survives a live reload from task 1.

## 5. Math via SwaTex — DONE

[SwaTex](https://github.com/PhraseHQ/SwaTex) — MIT, pure Swift, macOS 15 (matches mrkd's deployment target), 548 KB of bundled KaTeX fonts. Verified locally: rendered three formulas including a Lagrangian, output is KaTeX-quality, 1–15 ms each. `ImageRenderer.png(latex:)` and `SwaTexView.baselineFromTop` are the relevant API — the latter is what makes inline alignment tractable.

- Generalise the attachment seam first: rename the image-source attribute to a neutral "deferred attachment" concept carrying a kind (image / math / diagram) plus its source, so `MarkdownViewController` resolves all three through one path. One home for the idea, not three.
- Parse `$…$` and `$$…$$` in `MarkdownRenderer`. cmark-gfm has no math extension, so this is a scan of text nodes — must respect code spans and code blocks, which is the main correctness risk. Test that first, with `$5 and $10` and `` `$x$` `` as the failing cases.
- Inline math aligns to the surrounding text baseline; display math is centred on its own line.
- Render at the current backing scale; re-render on zoom and theme change. Formula colour comes from the theme's body colour.
- Cache by `hash(latex + fontSize + colour + scale)`.

Acceptance: a document with inline and display math renders correctly in both the app and Quick Look, math tracks Cmd-+/-, and `$5 and $10` is left alone.

## 6. Mermaid via merman — DONE

[merman](https://github.com/Latias94/merman) 0.8.0-alpha.6 — MIT/Apache-2.0. Verified locally: flowchart and dark-theme sequence diagram both render indistinguishably from mermaid.js; it honours `%%{init:…}%%` so diagrams can be themed to match mrkd; ~10 ms per diagram after a ~250 ms one-time system-font-database load.

Note the version: this is a pre-1.0 alpha. Pin it exactly and vendor the lockfile.

- A thin Rust `staticlib` shim crate exposing a C ABI: `render_png(source, theme_json, scale) -> bytes`. Keep `panic = "unwind"` and wrap the entry point in `catch_unwind` so a renderer panic returns an error instead of aborting the host process — this matters more now that it runs in-process rather than in a helper.
- Build `arm64` and `x86_64`, `lipo` them, embed as one dynamic framework in `Contents/Frameworks/`, linked by both `mrkd` and `QLPlugin` so the payload is paid once.
- Hook: `MarkdownRenderer`'s code-block path already extracts the fence language (`cmark_node_get_fence_info`). Branch on `mermaid` to a deferred attachment instead of the Highlightr path.
- Feed the active theme's colours and body font in as mermaid `themeVariables`, mirroring how theme-matched syntax highlighting was handled. A white diagram in a Catppuccin document is a bug, not a default.
- Cache by `hash(source + theme + scale)`; agent-rewritten files re-render constantly and most diagrams will be unchanged.
- Investigate supplying an explicit font list to resvg instead of letting it scan the system — that ~250 ms warmup is the whole cold-start cost and is likely avoidable.
- On a render error, fall back to the styled code block, not a blank space.

Build-system cost: a Rust toolchain step in `release.yml`, two architecture builds plus `lipo`, and the framework needs its own signature under the hardened runtime. `swift test` in CI must still pass without a local Rust install, so the Swift side needs to degrade cleanly when the framework is absent.

Size: ~9.5 MB. **Decided 2026-09-05: Intel dropped** — `release.yml` now builds `ARCHS="arm64"` only, so the Mermaid payload is ~9.5 MB rather than the ~19 MB a universal build would have cost.

Acceptance: a document with several Mermaid blocks renders them themed and correctly in both the app and Quick Look; a malformed diagram shows the source, not a gap; a 20-diagram document stays responsive.

## 7. Print / Export PDF — optional

The cheapest item and the least important. `NSPrintOperation` over the existing attributed string gives real pagination and correct typography for roughly a day's work, and it is the one place where a webview competitor structurally cannot match mrkd. Include it if the roadmap has room; drop it without regret if not.

## Deferred

- **Folder sidebar / `Cmd K` quick open** — needs its own evaluation. Current leaning: fuzzy quick-open scoped to the current file's directory tree, no persistent sidebar, no vault concept.
- **Git diff review** — the larger half of the HN "what changed" ask. Out of scope until the in-session version proves the interaction is worth it.

## Status at 2026-09-05

Tasks 1–6 are implemented and audited: 324 Swift tests plus 13 Rust tests green, `xcodebuild` succeeds for app and Quick Look, and every new pure function was mutation-tested (break the code, confirm a test fails, restore byte-identically). Two test gaps found by that audit — an untested LCS alignment in `BlockDiff` and an unpinned relative-path fix in the CLI — were sent back and closed with failing-first tests.

Mermaid ships as a Rust `cdylib` (11.8 MB — a cdylib strips less than the executable I measured, and `panic = "unwind"` costs a further 1.3 MB in unwind tables, which is the price of a renderer panic not killing the Quick Look extension) embedded once in `Contents/Frameworks/` and reachable from the sandboxed extension via `@rpath`, dyld-verified. The debug bundle is now ~40 MB.

The deferred-attachment seam task 5 generalised is `Sources/Engine/DeferredAttachment.swift`: a `kind` (image / inlineMath / displayMath) plus a source string, resolved in one pass by `MarkdownViewController`. Mermaid adds a `case diagram`, a provider, and one branch.

## Sequencing

1 → 2 establishes the reload story. 3 and 4 are independent and can land any time. 5 before 6, because SwaTex proves the attachment pipeline with no build-system risk, and Mermaid inherits it. 7 last or never.

## What would prove this plan wrong

- If the generalised attachment path in task 5 turns out to fight TextKit 2 line-fragment layout for inline math, the shared-pipeline premise collapses and Mermaid should be reconsidered as block-only with its own simpler path.
- If merman's alpha API churns or parity regresses, the fallback is `flowmaid` (zero dependencies, smaller, lower fidelity) or shipping styled code blocks and no diagrams.
- If the universal-binary size proves unacceptable and dropping `x86_64` is off the table, Mermaid is not worth 19 MB and should be cut.
