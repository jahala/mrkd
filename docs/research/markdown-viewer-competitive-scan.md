# Competitive scan: Ferrite, Marky, Write.md

Research date: 2026-09-05. Sources: three HN threads plus the projects' own repos/sites.

| Project | HN | Stack | Shape |
| --- | --- | --- | --- |
| [Ferrite](https://github.com/OlaProeis/Ferrite) | [46571980](https://news.ycombinator.com/item?id=46571980), 241 pts | Rust + egui, ~15 MB | Kitchen-sink editor: WYSIWYG, split view, minimap, terminal, JSON/YAML/TOML tree, native Mermaid |
| [Marky](https://github.com/GRVYDEV/marky) | [47795468](https://news.ycombinator.com/item?id=47795468), 75 pts | Tauri v2 + React + markdown-it, <15 MB | Viewer for agent-generated markdown: CLI, folders, live reload, Cmd+K |
| [Write.md](https://writemd.app/) | [49258011](https://news.ycombinator.com/item?id=49258011) | Electron | Minimal themeable editor, "glass" aesthetic, appearance profiles |

## What the threads actually say

**"Native" is a contested claim and people care.** Marky's README said "fast, native markdown viewer" while being a Tauri webview; the top critical subthread is people rejecting that ("Words have meaning. Native implies you are *directly* using OS-specific APIs"). Write.md took the same beating for Electron plus a "Made for Apple silicon" badge, and the author retracted the badge. mrkd is the only one of the four that can make the claim honestly — AppKit + TextKit 2 + cmark-gfm, no webview, ~1 MB. That is a marketing asset, not just an engineering preference.

**Marky's niche is mrkd's niche.** Verbatim from the author: "In this age of agentic coding I've found myself spending a lot of time reviewing markdown files… I spend more time reading markdown than code." Five other people in that one thread announced the same tool they'd just built (Vantage, seams, mdreader, sdocs, hyprmark). The category is real and getting crowded fast, and everyone is building the same Tauri/Electron shape.

**Repeated asks in those threads, in order of how often they came up:**
1. Live update as the agent rewrites the file, plus "make it easy to see the new parts" (zmmmmm)
2. CLI entry point — `marky FILE` / `marky ./docs/`; the stated reason Obsidian lost (no CLI, vault-only)
3. Folder/workspace browsing with fuzzy file switch
4. Adjustable text size and resizable panes (accessibility; author shipped it same-day)
5. Git status and local diff review
6. Printing rendered markdown — "seems like a lacuna in the overall ecosystem" (msluyter)
7. Mermaid, near-universally assumed present

**Distribution lesson.** Marky ships unsigned and tells users to run `xattr -cr`. Ferrite isn't notarized and is blocked by Gatekeeper on macOS 15.6+ (their issue #130). mrkd is already notarized, so a Homebrew cask is pure upside.

## Recommendation

### Ship
1. **Live reload replacing the "File has been modified externally" banner.** `FileWatcher` already fires on write; today it gates behind a manual Reload button. For agent-written files that rewrite every few seconds the gate is the wrong default. Auto-reload, preserve scroll by anchoring to the nearest heading/block rather than absolute offset, and keep an explicit prompt only for deletion or when the user has a live selection.
2. **Changed-block highlight on reload.** `BlockSplitter` already gives a block list; diff old against new and flash the changed ones with a brief gutter mark. This is the thing HN asked for that *nobody in the field has shipped*, and mrkd's architecture makes it cheap. Best differentiation-per-line-of-code on this list.
3. **`mrkd` CLI, including stdin.** `mrkd FILE`, `mrkd .`, and `cat plan.md | mrkd` — the last pairs with the existing "New from Clipboard" path and is the natural agent-pipeline entry. This is the feature that made Marky adoptable and Obsidian rejected.
4. **Cmd+F find in page.** Absent today. `NSTextFinder` drops into a TextKit 2 text view; table stakes for a doc reader.
5. **Print / Export PDF.** Named as an ecosystem gap on HN, and it is exactly where a real text system beats a webview: `NSPrintOperation` over the existing attributed string gives proper pagination, ligatures and hyphenation for near-zero cost. Web-based competitors print badly and structurally can't fix it.

### Decide
- **Mermaid.** The one place where no-webview costs real capability, and agents emit mermaid constantly. Three options: (a) skip and accept the gap; (b) native Core Graphics renderer for a flowchart/sequence subset — significant work; (c) wait for Ferrite's `mermaid-rs` crate (v0.3.0 promises `render_svg`/`render_png` with no browser) and shell out or link it, at the cost of the single ~1 MB binary. My inclination is (c) tracked, not built now — but it's a positioning call, not an engineering one.
- **Folder sidebar + Cmd+K quick open.** Every competitor has it and the agentic workflow points at a directory, not a file. It also turns mrkd from "viewer for the file you opened" into a doc browser, which is a different product. Middle path: Cmd+K fuzzy open across the current file's directory tree, no persistent sidebar, no vault concept.

### Skip
Wikilinks/backlinks/knowledge graph (Obsidian's turf), editing and split view (mrkd is a viewer — that's the point), integrated terminal, plugin system, JSON/YAML tree viewers, LLM chat panels. Ferrite's feature list is a cautionary tale: an editor, a CSV viewer, a terminal multiplexer and a shell pipeline in one app.

### Positioning
Lead with what the other three got publicly punished for missing: genuinely native rendering, ~1 MB, instant launch, real text selection and VoiceOver, Quick Look integration, notarized. A measured comparison table (binary size, RSS, cold start vs. Marky/Ferrite/Obsidian) is the Show HN post. The threads prove the audience already primes itself for that argument.
