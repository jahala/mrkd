# mrkd

A native macOS markdown viewer built with AppKit and TextKit 2. Fast, lightweight, and designed to feel like a first-party Mac app.

No Electron. No WebView. Markdown is parsed with cmark-gfm and rendered directly to NSAttributedString via TextKit 2 -- native text selection, native accessibility.

Built for reading markdown that something else is writing: open a file and it keeps up as an AI coding agent, or your editor, rewrites it underneath you.

## Features

- **Native rendering** -- GFM markdown via cmark-gfm, styled with NSAttributedString
- **Live reload** -- edits on disk appear immediately, with your reading position kept and the blocks that changed briefly marked
- **Command line** -- `mrkd FILE`, `mrkd` to reopen the last document, or `cat plan.md | mrkd` to pipe markdown in
- **Find in page** -- `Cmd F`, themed to the document, in the app and in Quick Look
- **Math** -- `$inline$` and `$$display$$` LaTeX rendered natively via SwaTex, no JavaScript
- **Mermaid** -- flowcharts, sequence diagrams and the rest, rendered natively via merman and themed to match the document
- **Themes** -- Built-in themes and import your own from iTerm2 or VS Code
- **Typography** -- Variable font support with configurable body and code fonts (Geist, Inter, iA Writer Mono, JetBrains Mono, and more)
- **Open With** -- Send the current file to any app on your Mac with one click
- **Quick Look** -- Preview markdown files in Finder with your selected theme, fonts, and an Open button
- **Performance** -- Tiered rendering pipeline for files of any size
- **Accessibility** -- VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency

## Requirements

- macOS 15.0+ (Apple silicon)
- Xcode 16+

## Building

```bash
git clone https://github.com/jahala/mrkd.git
cd mrkd
open mrkd.xcodeproj
```

Mermaid rendering is a small Rust library over [merman](https://github.com/Latias94/merman), so build it first:

```bash
./scripts/build-mermaid.sh
```

That needs a Rust toolchain ([rustup.rs](https://rustup.rs)) and has to run before `swift test` or an Xcode build -- both link against it. Then build and run the **mrkd** scheme in Xcode. Code signing is set to Automatic -- Xcode will use your own developer identity.

## Usage

Open any `.md`, `.markdown`, or `.mdown` file with mrkd. You can also drag files onto the Dock icon or use `File > Open`.

**Keyboard shortcuts:**
- `Cmd +` / `Cmd -` / `Cmd 0` -- Adjust font size
- `Cmd O` -- Open file
- `Cmd F` / `Cmd G` / `Cmd Shift G` -- Find, find next, find previous
- `Space` / `Shift-Space` -- Page down / up

**Command line:** install the `mrkd` command from Settings, then:

```bash
mrkd README.md        # open a file
mrkd                  # reopen the last document
cat plan.md | mrkd    # render piped markdown
```

**Settings** (`Cmd ,`): Choose a theme, body font, and code font. Import custom themes from iTerm2 `.itermcolors` or VS Code `.json` theme files.

## License

MIT. See [LICENSE](LICENSE).

Bundled fonts are distributed under their respective open-source licenses (SIL OFL 1.1 or Apache 2.0).
