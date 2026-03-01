# mrkd

A native macOS markdown viewer built with AppKit and TextKit 2. Fast, lightweight, and designed to feel like a first-party Mac app.

No Electron. No WebView. Markdown is parsed with cmark-gfm and rendered directly to NSAttributedString via TextKit 2 -- native text selection, native accessibility, ~1MB binary.

## Features

- **Native rendering** -- GFM markdown via cmark-gfm, styled with NSAttributedString
- **Themes** -- Built-in themes and import your own from iTerm2 or VS Code
- **Typography** -- Variable font support with configurable body and code fonts (Geist, Inter, iA Writer Mono, JetBrains Mono, and more)
- **Open With** -- Send the current file to any app on your Mac with one click
- **Quick Look** -- Preview markdown files in Finder with your selected theme, fonts, and an Open button
- **Performance** -- Tiered rendering pipeline for files of any size
- **Accessibility** -- VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency

## Requirements

- macOS 15.0+
- Xcode 16+

## Building

```bash
git clone https://github.com/jahala/mrkd.git
cd mrkd
open mrkd.xcodeproj
```

Build and run the **mrkd** scheme in Xcode. Code signing is set to Automatic -- Xcode will use your own developer identity.

## Usage

Open any `.md`, `.markdown`, or `.mdown` file with mrkd. You can also drag files onto the Dock icon or use `File > Open`.

**Keyboard shortcuts:**
- `Cmd +` / `Cmd -` / `Cmd 0` -- Adjust font size
- `Cmd O` -- Open file
- `Space` / `Shift-Space` -- Page down / up

**Settings** (`Cmd ,`): Choose a theme, body font, and code font. Import custom themes from iTerm2 `.itermcolors` or VS Code `.json` theme files.

## License

MIT. See [LICENSE](LICENSE).

Bundled fonts are distributed under their respective open-source licenses (SIL OFL 1.1 or Apache 2.0).
