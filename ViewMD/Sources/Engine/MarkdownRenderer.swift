import AppKit
import cmark_gfm
import cmark_gfm_extensions
import Highlightr

extension NSAttributedString.Key {
    /// Stores the source URL string for an image attachment, used by the
    /// view controller to trigger async loading via ImageAttachmentProvider.
    static let imageSourceURL = NSAttributedString.Key("MrkdImageSource")

    /// Heading level (1–6) for VoiceOver rotor navigation.
    static let accessibilityHeadingLevel = NSAttributedString.Key("MrkdHeadingLevel")
}

enum MarkdownRenderer {

    // MARK: - Public API

    /// Render a full markdown document in one pass.
    static func render(_ markdown: String, theme: Theme = DefaultTheme()) -> NSMutableAttributedString {
        registerGFMExtensions()

        let options = CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE
        guard let parser = cmark_parser_new(options) else {
            return NSMutableAttributedString(string: markdown, attributes: theme.bodyAttributes)
        }
        defer { cmark_parser_free(parser) }

        // Attach GFM extensions
        let extensionNames = ["table", "autolink", "strikethrough", "tasklist", "tagfilter"]
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let doc = cmark_parser_finish(parser) else {
            return NSMutableAttributedString(string: markdown, attributes: theme.bodyAttributes)
        }
        defer { cmark_node_free(doc) }

        let result = NSMutableAttributedString()
        renderNode(doc, into: result, theme: theme, listDepth: 0, listIndex: 0, isOrdered: false)
        trimTrailingNewlines(result)

        return result
    }

    // MARK: - GFM Extensions

    private static var extensionsRegistered = false

    private static func registerGFMExtensions() {
        guard !extensionsRegistered else { return }
        extensionsRegistered = true
        cmark_gfm_core_extensions_ensure_registered()
    }

    private typealias CMarkNode = UnsafeMutablePointer<cmark_node>

    // MARK: - Image Placeholder

    private static let placeholderImage: NSImage = {
        let size = NSSize(width: 300, height: 150)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.separatorColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).stroke()
            return true
        }
    }()

    // MARK: - Syntax Highlighting

    private static var _highlightr: Highlightr?
    private static var _highlightrThemeName: String = ""

    private static func syntaxHighlight(_ code: String, language: String, theme: Theme) -> NSAttributedString? {
        let highlightr: Highlightr
        if let existing = _highlightr {
            highlightr = existing
        } else {
            guard let h = Highlightr() else { return nil }
            _highlightr = h
            highlightr = h
        }

        let isDark = (theme.backgroundColor.usingColorSpace(.sRGB)?.brightnessComponent ?? 0.5) < 0.5
        let themeName = isDark ? "atom-one-dark" : "atom-one-light"
        if _highlightrThemeName != themeName {
            highlightr.setTheme(to: themeName)
            _highlightrThemeName = themeName
        }

        let codeFont = NSFont(name: theme.fontFamily, size: theme.codeFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: theme.codeFontSize, weight: .regular)
        highlightr.theme.codeFont = codeFont

        return highlightr.highlight(code, as: language)
    }

    // MARK: - AST Traversal

    private static func renderNode(
        _ node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme,
        listDepth: Int,
        listIndex: Int,
        isOrdered: Bool
    ) {
        let nodeType = cmark_node_get_type(node)

        switch nodeType {
        case CMARK_NODE_DOCUMENT:
            renderChildren(of: node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)

        case CMARK_NODE_PARAGRAPH:
            renderChildren(of: node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
            appendNewlines(result, count: 1)

        case CMARK_NODE_HEADING:
            let level = Int(cmark_node_get_heading_level(node))

            // Add extra spacing before h1 (unless at the start of document)
            if level == 1 && result.length > 0 {
                // Ensure we have a blank line before h1
                let str = result.string
                if !str.hasSuffix("\n\n") && !str.isEmpty {
                    appendNewlines(result, count: 1)
                }
            }

            let headingResult = NSMutableAttributedString()
            renderChildren(of: node, into: headingResult, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
            let headingRange = NSRange(location: 0, length: headingResult.length)
            headingResult.addAttributes(
                theme.headingAttributes(level: level),
                range: headingRange
            )
            headingResult.addAttribute(.accessibilityHeadingLevel, value: level, range: headingRange)
            result.append(headingResult)
            appendNewlines(result, count: 1)

        case CMARK_NODE_TEXT:
            if let literal = cmark_node_get_literal(node) {
                let text = String(cString: literal)
                result.append(NSAttributedString(string: text, attributes: theme.bodyAttributes))
            }

        case CMARK_NODE_SOFTBREAK:
            result.append(NSAttributedString(string: " ", attributes: theme.bodyAttributes))

        case CMARK_NODE_LINEBREAK:
            result.append(NSAttributedString(string: "\n", attributes: theme.bodyAttributes))

        case CMARK_NODE_THEMATIC_BREAK:
            let separator = String(repeating: "\u{2500}", count: 60) // Box-drawing horizontal line
            var attrs = theme.bodyAttributes
            attrs[.foregroundColor] = NSColor.separatorColor
            result.append(NSAttributedString(string: separator + "\n", attributes: attrs))
            appendNewlines(result, count: 1)

        case CMARK_NODE_EMPH:
            let emphResult = NSMutableAttributedString()
            renderChildren(of: node, into: emphResult, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
            let range = NSRange(location: 0, length: emphResult.length)
            if let currentFont = emphResult.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                emphResult.addAttribute(.font, value: italicFont, range: range)
            }
            result.append(emphResult)

        case CMARK_NODE_STRONG:
            let strongResult = NSMutableAttributedString()
            renderChildren(of: node, into: strongResult, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
            let range = NSRange(location: 0, length: strongResult.length)
            if let currentFont = strongResult.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                strongResult.addAttribute(.font, value: boldFont, range: range)
            }
            result.append(strongResult)

        case CMARK_NODE_CODE:
            if let literal = cmark_node_get_literal(node) {
                let code = String(cString: literal)
                result.append(NSAttributedString(string: code, attributes: theme.inlineCodeAttributes))
            }

        case CMARK_NODE_CODE_BLOCK:
            renderCodeBlock(node, into: result, theme: theme)

        case CMARK_NODE_LINK:
            renderLink(node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)

        case CMARK_NODE_IMAGE:
            let sourceURL: String
            if let url = cmark_node_get_url(node) {
                sourceURL = String(cString: url)
            } else {
                sourceURL = ""
            }

            var altText = ""
            if let firstChild = cmark_node_first_child(node),
               cmark_node_get_type(firstChild) == CMARK_NODE_TEXT,
               let literal = cmark_node_get_literal(firstChild) {
                altText = String(cString: literal)
            }
            if altText.isEmpty, let title = cmark_node_get_title(node) {
                let t = String(cString: title)
                if !t.isEmpty { altText = t }
            }

            let attachment = NSTextAttachment()
            attachment.image = placeholderImage

            let attachmentString = NSMutableAttributedString(
                attributedString: NSAttributedString(attachment: attachment)
            )
            if !sourceURL.isEmpty {
                attachmentString.addAttribute(
                    .imageSourceURL, value: sourceURL,
                    range: NSRange(location: 0, length: attachmentString.length)
                )
            }
            result.append(attachmentString)
            appendNewlines(result, count: 1)

        case CMARK_NODE_LIST:
            let listType = cmark_node_get_list_type(node)
            let ordered = listType == CMARK_ORDERED_LIST
            var itemIndex = 0
            var child = cmark_node_first_child(node)
            while let item = child {
                renderNode(item, into: result, theme: theme, listDepth: listDepth + 1, listIndex: itemIndex, isOrdered: ordered)
                itemIndex += 1
                child = cmark_node_next(item)
            }

        case CMARK_NODE_ITEM:
            let indent = String(repeating: "    ", count: listDepth)

            // Check if this is a task list item
            // The function returns true if the item is checked, and we need to check if it's a tasklist item first
            // by checking the parent list's type string
            var isTaskList = false
            var isChecked = false

            if let parent = cmark_node_parent(node),
               let typeName = cmark_node_get_type_string(parent) {
                let parentType = String(cString: typeName)
                if parentType.contains("list") {
                    // Try to get tasklist status - if this is a tasklist item, the function will return the checked state
                    isChecked = cmark_gfm_extensions_get_tasklist_item_checked(node)
                    // We need to check if this node has the tasklist extension data
                    // For now, we'll check the first child to see if it starts with [ ] or [x]
                    if let firstChild = cmark_node_first_child(node),
                       cmark_node_get_type(firstChild) == CMARK_NODE_PARAGRAPH,
                       let firstText = cmark_node_first_child(firstChild),
                       cmark_node_get_type(firstText) == CMARK_NODE_TEXT,
                       let literal = cmark_node_get_literal(firstText) {
                        let text = String(cString: literal)
                        if text.hasPrefix("[ ]") || text.hasPrefix("[x]") || text.hasPrefix("[X]") {
                            isTaskList = true
                        }
                    }
                }
            }

            let bullet: String
            if isTaskList {
                bullet = isChecked ? "\u{2611} " : "\u{2610} " // ☑ or ☐
            } else if isOrdered {
                let start = max(1, Int(cmark_node_get_list_start(cmark_node_parent(node))))
                bullet = "\(start + listIndex). "
            } else {
                bullet = "\u{2022} " // bullet character
            }

            var attrs = theme.bodyAttributes
            attrs[.foregroundColor] = (attrs[.foregroundColor] as? NSColor) ?? NSColor.labelColor
            result.append(NSAttributedString(string: indent + bullet, attributes: attrs))

            // If this is a task list, skip the checkbox markers from the text
            if isTaskList {
                var child = cmark_node_first_child(node)
                while let childNode = child {
                    if cmark_node_get_type(childNode) == CMARK_NODE_PARAGRAPH,
                       let firstText = cmark_node_first_child(childNode),
                       cmark_node_get_type(firstText) == CMARK_NODE_TEXT,
                       let literal = cmark_node_get_literal(firstText) {
                        let text = String(cString: literal)
                        // Remove the checkbox marker from the beginning
                        if text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                            let cleaned = String(text.dropFirst(4))
                            // Render the cleaned text
                            result.append(NSAttributedString(string: cleaned, attributes: theme.bodyAttributes))
                            // Render the rest of the paragraph children
                            var sibling = cmark_node_next(firstText)
                            while let siblingNode = sibling {
                                renderNode(siblingNode, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                                sibling = cmark_node_next(siblingNode)
                            }
                            // Skip the rest of the children since we've rendered them
                            child = cmark_node_next(childNode)
                            while let nextChild = child {
                                renderNode(nextChild, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                                child = cmark_node_next(nextChild)
                            }
                            return
                        }
                    }
                    child = cmark_node_next(childNode)
                }
            }

            renderChildren(of: node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)

        case CMARK_NODE_BLOCK_QUOTE:
            renderBlockquote(node, into: result, theme: theme, listDepth: listDepth)

        case CMARK_NODE_HTML_BLOCK:
            if let literal = cmark_node_get_literal(node) {
                let html = String(cString: literal)
                var attrs = theme.bodyAttributes
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
                result.append(NSAttributedString(string: html, attributes: attrs))
            }

        case CMARK_NODE_HTML_INLINE:
            if let literal = cmark_node_get_literal(node) {
                let html = String(cString: literal)
                result.append(NSAttributedString(string: html, attributes: theme.bodyAttributes))
            }

        default:
            // Handle GFM extension nodes
            if let typeName = cmark_node_get_type_string(node) {
                let name = String(cString: typeName)
                switch name {
                case "strikethrough":
                    renderStrikethrough(node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                case "table":
                    renderTable(node, into: result, theme: theme)
                case "table_header", "table_row":
                    renderChildren(of: node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                case "table_cell":
                    renderChildren(of: node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                case "tasklist":
                    renderChildren(of: node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                default:
                    renderChildren(of: node, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                }
            }
        }
    }

    // MARK: - Specialized Renderers

    private static func renderCodeBlock(
        _ node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme
    ) {
        guard let literal = cmark_node_get_literal(node) else { return }
        let code = String(cString: literal)

        var language: String? = nil
        if let fence = cmark_node_get_fence_info(node) {
            let lang = String(cString: fence)
            if !lang.isEmpty { language = lang }
        }

        let codeResult = NSMutableAttributedString()
        let baseAttrs = theme.codeBlockAttributes

        // Language label
        if let lang = language {
            var labelAttrs = baseAttrs
            labelAttrs[.foregroundColor] = NSColor.tertiaryLabelColor
            labelAttrs[.font] = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            codeResult.append(NSAttributedString(string: "\(lang)\n", attributes: labelAttrs))
        }

        // Try syntax highlighting via Highlightr
        if let lang = language, let highlighted = syntaxHighlight(code, language: lang, theme: theme) {
            let mutable = NSMutableAttributedString(attributedString: highlighted)
            let range = NSRange(location: 0, length: mutable.length)

            // Apply the code block paragraph style (with NSTextBlock background)
            if let paragraphStyle = baseAttrs[.paragraphStyle] {
                mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
            }

            codeResult.append(mutable)
        } else {
            // Fallback: plain monochrome code
            codeResult.append(NSAttributedString(string: code, attributes: baseAttrs))
        }

        result.append(codeResult)
        appendNewlines(result, count: 1)
    }

    private static func renderLink(
        _ node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme,
        listDepth: Int,
        listIndex: Int,
        isOrdered: Bool
    ) {
        let linkResult = NSMutableAttributedString()
        renderChildren(of: node, into: linkResult, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)

        if let url = cmark_node_get_url(node) {
            let urlString = String(cString: url)
            let range = NSRange(location: 0, length: linkResult.length)
            linkResult.addAttribute(.link, value: urlString, range: range)
            linkResult.addAttribute(.foregroundColor, value: theme.linkColor, range: range)
            linkResult.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            linkResult.addAttribute(.toolTip, value: urlString, range: range)
        }

        result.append(linkResult)
    }

    private static func renderBlockquote(
        _ node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme,
        listDepth: Int
    ) {
        let quoteResult = NSMutableAttributedString()
        renderChildren(of: node, into: quoteResult, theme: theme, listDepth: listDepth, listIndex: 0, isOrdered: false)

        let range = NSRange(location: 0, length: quoteResult.length)

        // Apply blockquote styling
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 20
        paragraphStyle.firstLineHeadIndent = 20
        quoteResult.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        quoteResult.addAttribute(.foregroundColor, value: theme.blockquoteColor, range: range)

        // Prefix with vertical bar
        let prefix = NSAttributedString(string: "\u{2502} ", attributes: [
            .foregroundColor: theme.blockquoteBarColor,
            .font: theme.bodyFont,
        ])
        quoteResult.insert(prefix, at: 0)

        result.append(quoteResult)
    }

    private static func renderStrikethrough(
        _ node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme,
        listDepth: Int,
        listIndex: Int,
        isOrdered: Bool
    ) {
        let strikeResult = NSMutableAttributedString()
        renderChildren(of: node, into: strikeResult, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
        let range = NSRange(location: 0, length: strikeResult.length)
        strikeResult.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        result.append(strikeResult)
    }

    private static func renderTable(
        _ node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme
    ) {
        // Collect rows and cells with type information
        var rows: [[(text: String, isHeader: Bool)]] = []
        var child = cmark_node_first_child(node)
        var isFirstRow = true
        while let row = child {
            var cells: [(text: String, isHeader: Bool)] = []

            // Check if this row is a table_header
            let isHeaderRow = isFirstRow || {
                if let typeName = cmark_node_get_type_string(row) {
                    return String(cString: typeName) == "table_header"
                }
                return false
            }()

            var cellNode = cmark_node_first_child(row)
            while let cell = cellNode {
                let cellText = NSMutableAttributedString()
                renderChildren(of: cell, into: cellText, theme: theme, listDepth: 0, listIndex: 0, isOrdered: false)
                cells.append((text: cellText.string, isHeader: isHeaderRow))
                cellNode = cmark_node_next(cell)
            }
            rows.append(cells)
            child = cmark_node_next(row)
            isFirstRow = false
        }

        guard !rows.isEmpty else { return }

        // Calculate column widths
        let colCount = rows.map(\.count).max() ?? 0
        var colWidths = [Int](repeating: 0, count: colCount)
        for row in rows {
            for (i, cell) in row.enumerated() where i < colCount {
                colWidths[i] = max(colWidths[i], cell.text.count)
            }
        }

        // Render table with box-drawing characters.
        // Call codeBlockAttributes ONCE so all rows share the same NSTextBlock
        // instance — consecutive paragraphs must share the same text block for
        // the layout engine to render them as one continuous background region.
        let codeAttrs = theme.codeBlockAttributes

        // Header
        if let header = rows.first {
            let headerTexts = header.map(\.text)
            let headerLine = formatTableRow(headerTexts, widths: colWidths)

            // Bold font for header — only override .font, keep shared paragraph style
            var headerAttrs = codeAttrs
            if header.first?.isHeader == true {
                if let currentFont = codeAttrs[.font] as? NSFont {
                    let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                    headerAttrs[.font] = boldFont
                }
            }
            result.append(NSAttributedString(string: headerLine + "\n", attributes: headerAttrs))

            // Separator
            let separator = colWidths.map { String(repeating: "\u{2500}", count: $0 + 2) }.joined(separator: "\u{253C}")
            result.append(NSAttributedString(string: "\u{251C}" + separator + "\u{2524}\n", attributes: codeAttrs))
        }

        // Data rows
        for row in rows.dropFirst() {
            let rowTexts = row.map(\.text)
            let line = formatTableRow(rowTexts, widths: colWidths)
            result.append(NSAttributedString(string: line + "\n", attributes: codeAttrs))
        }

        appendNewlines(result, count: 1)
    }

    private static func formatTableRow(_ cells: [String], widths: [Int]) -> String {
        var parts: [String] = []
        for (i, width) in widths.enumerated() {
            let cell = i < cells.count ? cells[i] : ""
            parts.append(" " + cell.padding(toLength: width, withPad: " ", startingAt: 0) + " ")
        }
        return "\u{2502}" + parts.joined(separator: "\u{2502}") + "\u{2502}"
    }

    // MARK: - Helpers

    private static func renderChildren(
        of node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme,
        listDepth: Int,
        listIndex: Int,
        isOrdered: Bool
    ) {
        var child = cmark_node_first_child(node)
        while let childNode = child {
            renderNode(childNode, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
            child = cmark_node_next(childNode)
        }
    }

    private static func appendNewlines(_ result: NSMutableAttributedString, count: Int) {
        if result.length > 0 {
            let str = result.string
            let existingNewlines = str.reversed().prefix(while: { $0 == "\n" }).count
            let needed = max(0, count + 1 - existingNewlines)
            if needed > 0 {
                result.append(NSAttributedString(string: String(repeating: "\n", count: needed)))
            }
        }
    }

    private static func trimTrailingNewlines(_ result: NSMutableAttributedString) {
        while result.length > 0 && result.string.hasSuffix("\n\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
    }

    // MARK: - Progressive Rendering

    /// Render markdown progressively: delivers a first-screen snapshot via
    /// `onFirstScreen` after rendering the first N top-level blocks, then
    /// returns the full attributed string. Both callbacks and the return
    /// happen synchronously on the caller's thread.
    static func renderProgressive(
        _ markdown: String,
        theme: Theme = DefaultTheme(),
        firstScreenBlocks: Int = 30,
        onFirstScreen: @escaping (NSMutableAttributedString) -> Void
    ) -> NSMutableAttributedString {
        registerGFMExtensions()

        let options = CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE
        guard let parser = cmark_parser_new(options) else {
            let fallback = NSMutableAttributedString(string: markdown, attributes: theme.bodyAttributes)
            onFirstScreen(fallback)
            return fallback
        }
        defer { cmark_parser_free(parser) }

        let extensionNames = ["table", "autolink", "strikethrough", "tasklist", "tagfilter"]
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let doc = cmark_parser_finish(parser) else {
            let fallback = NSMutableAttributedString(string: markdown, attributes: theme.bodyAttributes)
            onFirstScreen(fallback)
            return fallback
        }
        defer { cmark_node_free(doc) }

        let result = NSMutableAttributedString()
        var blockIndex = 0
        var deliveredFirstScreen = false
        var child = cmark_node_first_child(doc)

        while let block = child {
            renderNode(block, into: result, theme: theme, listDepth: 0, listIndex: 0, isOrdered: false)
            blockIndex += 1

            if !deliveredFirstScreen && blockIndex >= firstScreenBlocks {
                deliveredFirstScreen = true
                let snapshot = NSMutableAttributedString(attributedString: result)
                trimTrailingNewlines(snapshot)
                onFirstScreen(snapshot)
            }

            child = cmark_node_next(block)
        }

        // Document had fewer blocks than threshold — deliver now
        if !deliveredFirstScreen {
            let snapshot = NSMutableAttributedString(attributedString: result)
            trimTrailingNewlines(snapshot)
            onFirstScreen(snapshot)
        }

        trimTrailingNewlines(result)
        return result
    }
}
