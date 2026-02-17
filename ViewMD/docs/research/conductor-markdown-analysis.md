# Conductor App — Markdown Rendering Analysis

**Date:** 2026-02-11
**Method:** Binary extraction of embedded Tauri frontend assets + static analysis of JS/CSS bundles
**App version:** Conductor.app (com.conductor.app)

---

## Architecture Overview

Conductor is **not** an Electron app — it is a **Tauri** app (Rust backend + WebKit/WKWebView frontend). Frontend assets are Brotli-compressed and embedded directly in the Mach-O binary at build time. The app ships as a single binary with no external HTML/JS/CSS files.

**Extracted assets:** 26 files (~8.2 MB total)
- `index-CngLaRdD.js` (5 MB) — core bundle: React, markdown pipeline, syntax highlighting
- `SettingsAPI-DamJHSo2.js` (2.1 MB) — settings, CodeMirror, KaTeX
- `index-CidqMwxW.css` (200 KB) — all styles (Tailwind output, hljs themes, KaTeX, prose)
- 23 additional JS chunks (language modes, workers, utilities)

---

## Markdown Pipeline

```
Source text
    ↓
remark-parse (MDAST - Markdown Abstract Syntax Tree)
    ↓
remark-gfm (GitHub Flavored Markdown extensions)
    ↓
remarkRehype (MDAST → HAST bridge)
    ↓
rehype-highlight / Lowlight (syntax highlighting injection)
    ↓
React component tree (custom renderers)
    ↓
DOM
```

### Libraries (with occurrence counts in main bundle)

| Library | Count | Purpose |
|---------|-------|---------|
| `react-markdown` | 1 | Top-level React component for rendering markdown |
| `unified` | 15 | Pipeline orchestration framework |
| `remarkParse` | 2 | Markdown → MDAST parser |
| `remarkGfm` | 3 | GFM tables, strikethrough, task lists, autolinks |
| `remarkRehype` | 4 | MDAST → HAST (HTML AST) bridge |
| `rehypeHighlight` | 3 | Injects syntax highlighting at HAST level |
| `lowlight` / `createLowlight` | 198 / 2 | React wrapper for highlight.js (virtual DOM, no DOM manipulation) |
| `highlight.js` | 4 | Core syntax highlighting engine |
| `KaTeX` / `katex` | 7 / 16 | LaTeX math rendering |
| `CodeMirror` | 35 | Diff viewer (not for code blocks — separate feature) |

### Key design choice: Lowlight over highlight.js direct

Conductor uses **Lowlight** (198 references) rather than calling highlight.js directly. Lowlight produces a virtual DOM tree (`hast` nodes) that React can diff efficiently, avoiding innerHTML-based highlighting. This is the standard approach for React + highlight.js integration.

---

## Fonts

### Font families

| CSS Variable | Value | Usage |
|-------------|-------|-------|
| `--font-sans` | `"SF Pro", system-ui, sans-serif` | Body text, UI elements |
| `--font-mono` | `"Geist Mono"` | Code blocks, inline code |
| `--font-body` | (references `--font-sans`) | Markdown body content |

### Direct font-family declarations found in CSS

- `Geist` — used directly in some body contexts
- `Geist Mono` — primary code font
- `Geist Mono, monospace` — code with fallback
- `var(--font-mono), Monaco, "Courier New", monospace` — CodeMirror diff viewer
- `var(--font-mono), Consolas, "Liberation Mono", Menlo, Courier, monospace` — highlight.js
- `iA Writer Mono` — appears in settings/alternate mode
- `Georgia, Times New Roman, serif` — not clear where used (possibly KaTeX fallback)
- 8 KaTeX font families (KaTeX_Main, KaTeX_Math, KaTeX_AMS, etc.)

---

## Theming

### Color system: Radix UI color scales

Conductor uses **Radix Colors** — a 12-step perceptual color scale system. Each color has steps 1–12 (lightest to darkest for light theme, reversed for dark).

**Color scales in use:**

| Scale | Steps | Purpose |
|-------|-------|---------|
| `slate` | 1–12 | Neutral grays (backgrounds, borders, text) |
| `blue` | 1–12 | Primary accent (links, selections, focus states) |
| `grass` | 1–12 | Success / info admonitions |
| `red` | 1–12 | Error / danger admonitions |
| `amber` | 1–12 | Warning / caution admonitions |
| `cyan` | 1–12 | Tip admonitions |

### Semantic color tokens

Built on top of Radix scales using CSS custom properties:

```
--accentBase      → var(--blue-1)
--accentBg        → var(--blue-3)
--accentBgHover   → var(--blue-4)
--accentBgActive  → var(--blue-5)
--accentBorder    → var(--blue-7)
--accentSolid     → var(--blue-9)
--accentText      → var(--blue-11)
```

**Total CSS custom properties:** 267 unique names, 809 declarations (light + dark variants).

### Theme switching

Uses `:root` blocks (26 total) with `html.light` / `html.dark` selectors (13 blocks each). Theme toggle flips a class on the `<html>` element. Supports P3 wide-gamut displays via `@supports (color: color(display-p3 1 1 1))`.

---

## Code Blocks

### Inline code

Styled via `.prose-code` (Tailwind prose plugin). Uses `var(--font-mono)` font family.

### Fenced code blocks

Rendered by a custom `CodeBlock` React component. Syntax highlighting via Lowlight produces DOM with `hljs-*` class names.

**35 highlight.js token classes in CSS:**

```
.hljs                    — base container
.hljs-keyword            — language keywords
.hljs-string             — string literals
.hljs-number             — numeric literals
.hljs-comment            — comments
.hljs-title              — function/class names
.hljs-type               — type names
.hljs-built_in           — built-in functions
.hljs-attr               — attributes
.hljs-variable           — variables
.hljs-template-variable  — template interpolation
.hljs-regexp             — regular expressions
.hljs-literal            — true/false/null
.hljs-meta               — preprocessor directives
.hljs-addition           — diff additions
.hljs-deletion           — diff deletions
.hljs-section            — headings/sections
.hljs-link               — URLs
.hljs-symbol             — symbols
.hljs-bullet             — list bullets
.hljs-quote              — blockquotes
.hljs-emphasis           — italic
.hljs-strong             — bold
.hljs-formula            — math formulas
.hljs-doctag             — doc comment tags
.hljs-name               — tag names
.hljs-selector-tag       — CSS tag selectors
.hljs-selector-class     — CSS class selectors
.hljs-selector-id        — CSS ID selectors
.hljs-selector-attr      — CSS attribute selectors
.hljs-selector-pseudo    — CSS pseudo selectors
.hljs-attribute          — HTML attributes
.hljs-subst              — substitution
.hljs-class              — class definitions
.hljs-container          — wrapper class
```

Each token class has separate light/dark theme color values defined via CSS custom properties.

### Diff viewer

Uses **CodeMirror 5** (not CodeMirror 6) with merge view for side-by-side diffs. Separate from the markdown code block rendering. Styled under `.codemirror-diff-viewer` namespace.

---

## Typography (Tailwind Prose)

Uses Tailwind's `@tailwindcss/typography` plugin with the `.prose` class. Custom overrides for markdown-specific elements:

**18 prose classes found:**

| Class | Element |
|-------|---------|
| `.prose` | Base container |
| `.prose-sm` | Smaller variant |
| `.prose-invert` | Dark mode inversion |
| `.prose-p` | Paragraphs |
| `.prose-headings` | h1–h6 |
| `.prose-a` | Links |
| `.prose-blockquote` | Blockquotes |
| `.prose-code` | Inline code |
| `.prose-pre` | Code blocks |
| `.prose-em` | Emphasis |
| `.prose-strong` | Bold |
| `.prose-ol` | Ordered lists |
| `.prose-ul` | Unordered lists |
| `.prose-li` | List items |
| `.prose-hr` | Horizontal rules |
| `.prose-table` | Tables |
| `.prose-th` | Table headers |
| `.prose-td` | Table cells |

---

## Spacing System

Uses a numeric spacing scale as CSS custom properties:

```
--spacing-0 through --spacing-12  (steps of 1)
--spacing-14, --spacing-16, --spacing-20, --spacing-24, --spacing-28
--spacing-32, --spacing-36, --spacing-40, --spacing-44, --spacing-48
--spacing-52, --spacing-56, --spacing-60, --spacing-64
--spacing-72, --spacing-80, --spacing-96
```

30 spacing values total — follows Tailwind's default spacing scale.

---

## Additional Features

### Admonitions

Custom admonition/callout blocks with 5 variants, each with distinct bg/border colors:

| Type | Background | Border |
|------|-----------|--------|
| Note | `slate-4` | `slate-8` |
| Tip | `cyan-4` | `cyan-8` |
| Info | `grass-4` | `grass-8` |
| Caution | `amber-4` | `amber-8` |
| Danger | `red-4` | `red-8` |

### KaTeX Math Rendering

Full KaTeX integration with 8 custom font families bundled:
- KaTeX_Main, KaTeX_Math, KaTeX_AMS, KaTeX_Caligraphic
- KaTeX_Fraktur, KaTeX_SansSerif, KaTeX_Script, KaTeX_Typewriter
- 4 size variants (KaTeX_Size1 through KaTeX_Size4)

### React Component Architecture

Key message rendering components:
- `UserMessage` — user input display
- `AssistantMessage` — AI response with markdown rendering
- `ContentBlock` — generic content wrapper
- `CodeBlock` — syntax-highlighted code with copy button

### Streaming Support

The markdown pipeline supports incremental/streaming rendering — partial markdown is parsed and displayed as tokens arrive, with the HAST tree updated incrementally.

---

## Comparison with mrkd

| Aspect | Conductor | mrkd |
|--------|-----------|------|
| **Runtime** | Tauri (WebKit) | Native AppKit (NSTextView) |
| **Parser** | remark-parse (JS) | cmark-gfm (C) |
| **Rendering** | React virtual DOM → HTML | NSAttributedString → TextKit 2 |
| **Syntax highlighting** | Lowlight/highlight.js (35 token types) | Highlightr (highlight.js via JS bridge) |
| **Fonts** | Geist + Geist Mono (web fonts) | User-selectable (bundled TTFs) |
| **Theming** | CSS custom properties, Radix Colors | Swift Theme protocol, 5 themes |
| **Math** | KaTeX | Not supported |
| **Code blocks** | HTML `<pre><code>` with hljs classes | NSTextBlock with attributed string styling |
| **Typography** | Tailwind prose plugin | Manual NSParagraphStyle |
| **Admonitions** | 5 types with color-coded callouts | Not supported (could add) |

### Takeaways for mrkd

1. **Admonition blocks** — Conductor's note/tip/info/caution/danger callouts are useful. Could implement via `> [!NOTE]` GitHub-flavored syntax in cmark-gfm custom extensions.
2. **Token granularity** — 35 hljs token classes provide fine-grained syntax coloring. mrkd already uses Highlightr which maps to the same token set.
3. **Radix-style color scales** — The 12-step perceptual scale approach is systematic. mrkd's theme system could adopt a similar scale for consistent color relationships.
4. **iA Writer Mono** — Conductor offers this as an alternative code font. Could consider adding to mrkd's font options.
