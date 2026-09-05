# Mermaid in mrkd — options, measured

Investigated 2026-09-05. All numbers below were measured on this machine, not estimated.

## The problem

Mermaid rendering is parse → layout → draw. Layout is the hard part (Sugiyama-style ranked graph layout for flowcharts; deterministic geometry for the other ~20 diagram types). Upstream mermaid.js needs a DOM to measure text, which is why `mermaid-cli` drives headless Chrome. JavaScriptCore alone is not enough — there is no DOM.

## Candidates

| Option | Verdict |
| --- | --- |
| Offscreen `WKWebView` + mermaid.js | Full fidelity, but reintroduces a webview and ~3 MB of JS. Kills the positioning. |
| JavaScriptCore + mermaid.js | Doesn't work — mermaid needs `document` and `getBBox`. |
| Pure-Swift subset renderer | Ferrite's Rust implementation is ~330 KB of source across 18 files for 11 diagram types. Months of work, permanent maintenance against a moving spec. |
| **[merman](https://github.com/Latias94/merman)** (Rust, MIT/Apache-2.0, ★541, pushed 2026-09-05) | **Recommended.** Headless Rust implementation, parity-checked against pinned mermaid source and fixtures. Emits SVG, PNG, JPEG, PDF. |
| [mermaid-rs-renderer](https://github.com/1jehuang/mermaid-rs-renderer) (MIT, ★1696) | Larger star count, similar claims. Not benchmarked here; worth a second look before committing. |
| [flowmaid](https://crates.io/crates/flowmaid) (zero-dep, pure std Rust) | Smallest dependency footprint, "mermaid-like" rather than parity. Fallback if merman's size is unacceptable. |

## What was measured

Spike at `/tmp/merman-spike` — merman 0.8.0-alpha.6, `default-features = false`.

**Rendering works and looks right.** A flowchart and a dark-theme sequence diagram both rendered correctly and are visually indistinguishable from mermaid.js output. merman honours mermaid init directives, so `%%{init: {'theme':'dark'}}%%` and `themeVariables` work — meaning diagrams can be themed to match the active mrkd theme and body font, the same way theme-matched syntax highlighting was handled.

**SVG output alone is not enough.** merman's default SVG contains `foreignObject` for labels. `SvgPipeline::resvg_safe()` removes it, but the SVG still carries its styling in an embedded `<style>` block with `@keyframes`. SwiftDraw (the best native Swift SVG renderer, Zlib, ★643) fails to parse that block and renders every node solid black with edges as filled wedges — correct geometry, no styling. So the raster step has to happen on the Rust side (`png` feature, via resvg/tiny-skia), not in Swift.

**Timing:** ~250 ms one-time cost on the first render (system font database load), then **~10 ms per diagram**. This is the architectural constraint: a process spawned per diagram pays the 250 ms every time, so the renderer must be either a long-lived helper process or linked in-process.

**Binary size**, `svg,png` features only, stripped, fat LTO, `panic = "abort"`:

| Profile | Size | Warm render |
| --- | --- | --- |
| `opt-level = 3` | 11.7 MB | 7 ms |
| `opt-level = "s"` + `opt-level = 3` overrides for tiny-skia/resvg/usvg/png | **9.5 MB** | 10 ms |
| `opt-level = "z"` | 6.6 MB | 1100 ms — rejected, size opts destroy raster performance |

Adding `pdf` costs ~4 MB more and the first PDF render takes ~370 ms. Not worth it; PNG re-rendered at the current scale covers Retina and Cmd-+/- zoom.

## Size in context

The README's "~1 MB binary" is the *executable* (`.build/release/mrkd` is 1.19 MB). The shipped `.app` is already much larger because of ~9.6 MB of bundled variable fonts. So the honest framing is that a 9.5 MB helper roughly doubles a bundle that is already ~12–20 MB, rather than making a 1 MB app 10x bigger. Marky ships under 15 MB and Ferrite around 15 MB, both with a webview or full GUI toolkit inside.

## Recommended architecture

1. Build merman as a **long-lived helper executable** in `Contents/Helpers/`, started lazily the first time a document contains a ```` ```mermaid ```` block, fed diagram source over a pipe, returning PNG bytes. Process isolation means a renderer panic cannot take down the app, and it keeps the Rust boundary at the edge rather than threaded through Swift.
2. Cache by `hash(source + theme + font + scale)`. Agent-rewritten files re-render constantly and most diagrams won't have changed.
3. Inject the active mrkd theme's colours and body font as mermaid `themeVariables` so diagrams match the document rather than sitting on a white rectangle in a dark theme.
4. Insert as an `NSTextAttachment` — `ImageAttachmentProvider` already does this for images.
5. Re-render on zoom and on theme change, at the current backing-scale factor.

Build cost: the release workflow gains a Rust toolchain step and the helper needs its own signature under the hardened runtime. Both are one-time.

## Open question

Whether to take the size at all. The alternative is to render mermaid blocks as styled code with a "Copy" affordance and accept the gap — cheap, honest, and leaves mrkd the smallest app in the category. That is a positioning decision, not an engineering one.

## Side finding

[SwaTex](https://github.com/PhraseHQ/SwaTex) (MIT, ★222) is a pure-Swift KaTeX-coverage LaTeX math renderer — "no JavaScript, no WebView, no DOM". If math support is ever wanted, it is a Swift package with no Rust boundary and no size cliff. Much cheaper than the mermaid path.
