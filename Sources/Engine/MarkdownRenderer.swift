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

    /// Border color for inline code spans, drawn by CodeBorderLayoutManager.
    static let inlineCodeBorderColor = NSAttributedString.Key("MrkdInlineCodeBorder")
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

    private static let staticStateLock = DispatchQueue(label: "com.mrkd.renderer.static")
    private static var extensionsRegistered = false

    private static func registerGFMExtensions() {
        staticStateLock.sync {
            guard !extensionsRegistered else { return }
            extensionsRegistered = true
            cmark_gfm_core_extensions_ensure_registered()
        }
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

    /// Release the Highlightr JavaScriptCore context to reclaim memory.
    /// It will be lazily re-created on the next syntax highlight call.
    static func clearHighlightrCache() {
        staticStateLock.sync {
            _highlightr = nil
            _highlightrThemeName = ""
        }
    }

    private static func syntaxHighlight(_ code: String, language: String, theme: Theme) -> NSAttributedString? {
        return staticStateLock.sync {
            let highlightr: Highlightr
            if let existing = _highlightr {
                highlightr = existing
            } else {
                guard let h = Highlightr() else { return nil }
                _highlightr = h
                highlightr = h
            }

            let themeName = theme.highlightrTheme
            if _highlightrThemeName != themeName {
                highlightr.setTheme(to: themeName)
                _highlightrThemeName = themeName
            }

            let codeFont = NSFont(name: theme.codeFontFamily, size: theme.codeFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: theme.codeFontSize, weight: .regular)
            highlightr.theme.codeFont = codeFont

            return highlightr.highlight(code, as: language)
        }
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
            // Bump weight by one level: body (~450) → medium (500), heading (semibold) → bold
            strongResult.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                if let currentFont = value as? NSFont {
                    strongResult.addAttribute(.font, value: theme.fontByBumpingWeight(currentFont), range: subRange)
                }
            }
            result.append(strongResult)

        case CMARK_NODE_CODE:
            if let literal = cmark_node_get_literal(node) {
                let code = String(cString: literal)
                // Thin spaces outside the code span create real outer margin around the border.
                // These carry no .inlineCodeBorderColor so the layout manager won't draw
                // a border over them — they're just spacer characters in the text layout.
                let spacerAttrs: [NSAttributedString.Key: Any] = [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.textColor,
                ]
                let spacer = NSAttributedString(string: "\u{2009}", attributes: spacerAttrs)
                result.append(spacer)
                result.append(NSAttributedString(string: code, attributes: theme.inlineCodeAttributes))
                result.append(spacer)
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
            // Check if this is a task list item
            var isTaskList = false
            var isChecked = false

            if let parent = cmark_node_parent(node),
               let typeName = cmark_node_get_type_string(parent) {
                let parentType = String(cString: typeName)
                if parentType.contains("list") {
                    isChecked = cmark_gfm_extensions_get_tasklist_item_checked(node)
                    // Check if this node has the tasklist extension data
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
                bullet = isChecked ? "\u{2611}\t" : "\u{2610}\t" // ☑ or ☐
            } else if isOrdered {
                let start = max(1, Int(cmark_node_get_list_start(cmark_node_parent(node))))
                bullet = "\(start + listIndex).\t"
            } else {
                bullet = "\u{2022}\t" // bullet character + tab
            }

            // Tab-stop based indentation for consistent bullet-to-text spacing.
            let indentPerLevel: CGFloat = 24
            let depthIndent = CGFloat(listDepth) * indentPerLevel
            let bulletColumnWidth: CGFloat = 18
            let textIndent = depthIndent + bulletColumnWidth

            let listStyle = NSMutableParagraphStyle()
            listStyle.lineSpacing = 2
            listStyle.paragraphSpacing = 2
            listStyle.tabStops = [NSTextTab(textAlignment: .left, location: textIndent, options: [:])]
            listStyle.defaultTabInterval = 36
            listStyle.firstLineHeadIndent = depthIndent
            listStyle.headIndent = textIndent

            // Append bullet — render unordered bullets slightly larger for visibility.
            var bulletAttrs = theme.bodyAttributes
            bulletAttrs[.paragraphStyle] = listStyle
            if !isTaskList && !isOrdered {
                let bulletSize = theme.baseFontSize * 1.15
                bulletAttrs[.font] = theme.font(size: bulletSize, weight: .regular)
                // Nudge down to visually center with text baseline
                bulletAttrs[.baselineOffset] = -0.5
            }
            result.append(NSAttributedString(string: bullet, attributes: bulletAttrs))

            // Handle task list special case
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
                            let rangeStart = result.length
                            let cleaned = String(text.dropFirst(4))
                            // Render the cleaned text
                            result.append(NSAttributedString(string: cleaned, attributes: theme.bodyAttributes))
                            // Render the rest of the paragraph children
                            var sibling = cmark_node_next(firstText)
                            while let siblingNode = sibling {
                                renderNode(siblingNode, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                                sibling = cmark_node_next(siblingNode)
                            }
                            // Apply list style to rendered text
                            let rangeLen = result.length - rangeStart
                            if rangeLen > 0 {
                                result.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: rangeStart, length: rangeLen))
                            }
                            // Render remaining children (e.g. nested lists)
                            child = cmark_node_next(childNode)
                            while let nextChild = child {
                                let nextType = cmark_node_get_type(nextChild)
                                if nextType == CMARK_NODE_LIST {
                                    // Nested list handles its own indentation
                                    renderNode(nextChild, into: result, theme: theme, listDepth: listDepth, listIndex: 0, isOrdered: false)
                                } else {
                                    let childRangeStart = result.length
                                    renderNode(nextChild, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                                    let childRangeLen = result.length - childRangeStart
                                    if childRangeLen > 0 {
                                        result.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: childRangeStart, length: childRangeLen))
                                    }
                                }
                                child = cmark_node_next(nextChild)
                            }
                            // Single newline to separate from the next list item
                            result.append(NSAttributedString(string: "\n"))
                            return
                        }
                    }
                    child = cmark_node_next(childNode)
                }
            }

            // Render children manually to handle nested lists correctly
            var child = cmark_node_first_child(node)
            while let childNode = child {
                let childType = cmark_node_get_type(childNode)
                if childType == CMARK_NODE_LIST {
                    // Nested list handles its own indentation
                    renderNode(childNode, into: result, theme: theme, listDepth: listDepth, listIndex: 0, isOrdered: false)
                } else {
                    // Paragraph or other content — render then apply list style
                    let rangeStart = result.length
                    if childType == CMARK_NODE_PARAGRAPH {
                        renderChildren(of: childNode, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                        // Single newline for tight list items (not appendNewlines which adds \n\n)
                        result.append(NSAttributedString(string: "\n"))
                    } else {
                        renderNode(childNode, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)
                    }
                    let rangeLen = result.length - rangeStart
                    if rangeLen > 0 {
                        result.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: rangeStart, length: rangeLen))
                    }
                }
                child = cmark_node_next(childNode)
            }

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
        // cmark includes a trailing newline in code block literals;
        // strip it so the NSTextBlock background doesn't show a blank row.
        var code = String(cString: literal)
        while code.hasSuffix("\n") { code.removeLast() }

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
            // Links at medium weight for subtle visual distinction
            linkResult.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                if let currentFont = value as? NSFont {
                    let mediumFont = theme.font(size: currentFont.pointSize, weight: .medium)
                    linkResult.addAttribute(.font, value: mediumFont, range: subRange)
                }
            }
        }

        result.append(linkResult)
    }

    private static func detectAdmonition(in blockquoteNode: CMarkNode) -> AdmonitionType? {
        // Get first child (should be a paragraph)
        guard let firstChild = cmark_node_first_child(blockquoteNode),
              cmark_node_get_type(firstChild) == CMARK_NODE_PARAGRAPH else { return nil }

        // Get first text node of that paragraph
        guard let textNode = cmark_node_first_child(firstChild),
              cmark_node_get_type(textNode) == CMARK_NODE_TEXT,
              let literal = cmark_node_get_literal(textNode) else { return nil }

        let text = String(cString: literal)

        // Check for [!TYPE] pattern at start
        for type in AdmonitionType.allCases {
            let marker = "[!\(type.rawValue.uppercased())]"
            if text.hasPrefix(marker) {
                return type
            }
        }
        return nil
    }

    private static func renderAdmonition(
        _ node: CMarkNode,
        type: AdmonitionType,
        into result: NSMutableAttributedString,
        theme: Theme,
        listDepth: Int
    ) {
        // Render all children
        let admonitionResult = NSMutableAttributedString()
        renderChildren(of: node, into: admonitionResult, theme: theme, listDepth: listDepth, listIndex: 0, isOrdered: false)

        // Strip the [!TYPE] marker from the beginning
        let marker = "[!\(type.rawValue.uppercased())]"
        let text = admonitionResult.string
        if text.hasPrefix(marker) {
            var charsToRemove = marker.count
            // Strip trailing whitespace/newline left by the soft break or hard break after the marker
            if text.count > marker.count {
                let nextChar = text[text.index(text.startIndex, offsetBy: marker.count)]
                if nextChar == "\n" || nextChar == " " {
                    charsToRemove += 1
                }
            }
            admonitionResult.deleteCharacters(in: NSRange(location: 0, length: charsToRemove))
        }

        // Get icon and label for this type
        let icon: String
        let label: String
        switch type {
        case .note:
            icon = "\u{270F}"  // Pencil
            label = "Note"
        case .tip:
            icon = "\u{1F4A1}"  // Light bulb
            label = "Tip"
        case .important:
            icon = "\u{2757}"  // Exclamation mark
            label = "Important"
        case .warning:
            icon = "\u{26A0}\u{FE0F}"  // Warning sign
            label = "Warning"
        case .caution:
            icon = "\u{1F6D1}"  // Stop sign
            label = "Caution"
        }

        // Create label line with icon and type name
        let labelText = "\(icon) \(label)\n"
        let labelFont = theme.font(size: theme.baseFontSize, weight: .semibold)
        let labelColor = theme.admonitionColor(type: type)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: labelColor
        ]
        let labelString = NSAttributedString(string: labelText, attributes: labelAttrs)

        // Prepend label to content
        admonitionResult.insert(labelString, at: 0)

        // Create text block with admonition styling
        let range = NSRange(location: 0, length: admonitionResult.length)
        let block = NSTextBlock()
        block.backgroundColor = theme.admonitionBackgroundColor(type: type)
        block.setBorderColor(theme.admonitionColor(type: type), for: .minX)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxY)
        block.setValue(100, type: .percentageValueType, for: .width)

        // Apply the text block to all paragraphs
        admonitionResult.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
            let existing = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let style = existing.mutableCopy() as! NSMutableParagraphStyle
            style.textBlocks = [block] + existing.textBlocks
            admonitionResult.addAttribute(.paragraphStyle, value: style, range: subRange)
        }

        result.append(admonitionResult)
    }

    private static func renderBlockquote(
        _ node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme,
        listDepth: Int
    ) {
        // Check for GitHub-style admonition
        if let admonitionType = detectAdmonition(in: node) {
            renderAdmonition(node, type: admonitionType, into: result, theme: theme, listDepth: listDepth)
            return
        }

        // Standard blockquote rendering
        let quoteResult = NSMutableAttributedString()
        renderChildren(of: node, into: quoteResult, theme: theme, listDepth: listDepth, listIndex: 0, isOrdered: false)

        let range = NSRange(location: 0, length: quoteResult.length)

        // Single text block shared by all paragraphs — TextKit draws one
        // continuous left border spanning the full blockquote height.
        let block = NSTextBlock()
        block.backgroundColor = .clear
        block.setBorderColor(theme.blockquoteBarColor, for: .minX)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setValue(100, type: .percentageValueType, for: .width)

        quoteResult.addAttribute(.foregroundColor, value: theme.blockquoteColor, range: range)

        // Add the text block to every paragraph style, preserving existing formatting.
        // Prepend (outermost first) so nested blockquotes keep their inner bars.
        quoteResult.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
            let existing = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let style = existing.mutableCopy() as! NSMutableParagraphStyle
            style.textBlocks = [block] + existing.textBlocks
            quoteResult.addAttribute(.paragraphStyle, value: style, range: subRange)
        }

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

    /// Check if a node type is a block-level element (for spacing purposes)
    private static func isBlockLevelNode(_ type: cmark_node_type) -> Bool {
        switch type {
        case CMARK_NODE_PARAGRAPH,
             CMARK_NODE_HEADING,
             CMARK_NODE_CODE_BLOCK,
             CMARK_NODE_BLOCK_QUOTE,
             CMARK_NODE_LIST,
             CMARK_NODE_THEMATIC_BREAK,
             CMARK_NODE_HTML_BLOCK:
            return true
        default:
            return false
        }
    }

    /// Check if a GFM extension type string represents a block-level element
    private static func isBlockLevelExtension(_ typeName: String) -> Bool {
        return typeName == "table"
    }

    /// Apply contextual spacing before a block element based on its predecessor
    private static func applyContextualSpacing(
        to result: NSMutableAttributedString,
        startPosition: Int,
        currentNodeType: cmark_node_type,
        currentExtensionType: String?,
        previousNodeType: cmark_node_type?,
        previousExtensionType: String?,
        theme: Theme
    ) {
        // Skip if current node is heading (headings manage their own spacing)
        if currentNodeType == CMARK_NODE_HEADING {
            return
        }

        // Skip if we're at the document start
        guard let prevType = previousNodeType else {
            return
        }

        let baseFontSize = theme.baseFontSize

        // Determine spacing based on predecessor and current node types
        let spacing: CGFloat

        // Helper to check if extension type is table
        let currentIsTable = currentExtensionType.map { isBlockLevelExtension($0) } ?? false
        let prevIsTable = previousExtensionType.map { isBlockLevelExtension($0) } ?? false

        // After HEADING → any block element: 0 (heading's own spacing is enough)
        if prevType == CMARK_NODE_HEADING {
            spacing = 0
        }
        // After PARAGRAPH → PARAGRAPH: baseFontSize * 0.4 (~5pt extra)
        else if prevType == CMARK_NODE_PARAGRAPH && currentNodeType == CMARK_NODE_PARAGRAPH {
            spacing = baseFontSize * 0.4
        }
        // After PARAGRAPH → LIST: 0 (tight coupling)
        else if prevType == CMARK_NODE_PARAGRAPH && currentNodeType == CMARK_NODE_LIST {
            spacing = 0
        }
        // After PARAGRAPH → CODE_BLOCK/BLOCK_QUOTE/table: baseFontSize * 0.8
        else if prevType == CMARK_NODE_PARAGRAPH &&
                (currentNodeType == CMARK_NODE_CODE_BLOCK ||
                 currentNodeType == CMARK_NODE_BLOCK_QUOTE ||
                 currentIsTable) {
            spacing = baseFontSize * 0.8
        }
        // After CODE_BLOCK/BLOCK_QUOTE/table → any block element: baseFontSize * 0.8
        else if prevType == CMARK_NODE_CODE_BLOCK ||
                prevType == CMARK_NODE_BLOCK_QUOTE ||
                prevIsTable {
            spacing = baseFontSize * 0.8
        }
        // After LIST → any block element: baseFontSize * 0.8
        else if prevType == CMARK_NODE_LIST {
            spacing = baseFontSize * 0.8
        }
        // After THEMATIC_BREAK → any block element: 0
        else if prevType == CMARK_NODE_THEMATIC_BREAK {
            spacing = 0
        }
        // Default: no extra spacing
        else {
            spacing = 0
        }

        // Apply the spacing to the first paragraph in the range
        guard spacing > 0 && result.length > startPosition else {
            return
        }

        let text = result.string
        let startIdx = text.index(text.startIndex, offsetBy: startPosition)
        guard startIdx < text.endIndex else { return }

        // Find the first newline to determine the first paragraph's range
        let endIdx = text[startIdx...].firstIndex(of: "\n") ?? text.endIndex
        let firstParaLength = text.distance(from: startIdx, to: endIdx)

        guard firstParaLength > 0 else { return }

        // Get existing paragraph style or create one
        let existingStyle: NSParagraphStyle
        if let ps = result.attribute(.paragraphStyle, at: startPosition, effectiveRange: nil) as? NSParagraphStyle {
            existingStyle = ps
        } else {
            existingStyle = NSParagraphStyle.default
        }

        // Create mutable copy and set paragraphSpacingBefore
        let mutableStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
        mutableStyle.paragraphSpacingBefore = spacing

        // Apply to the first paragraph only
        result.addAttribute(.paragraphStyle, value: mutableStyle, range: NSRange(location: startPosition, length: firstParaLength))
    }

    private static func renderChildren(
        of node: CMarkNode,
        into result: NSMutableAttributedString,
        theme: Theme,
        listDepth: Int,
        listIndex: Int,
        isOrdered: Bool
    ) {
        var child = cmark_node_first_child(node)
        var previousType: cmark_node_type? = nil
        var previousExtensionType: String? = nil

        while let childNode = child {
            let childType = cmark_node_get_type(childNode)
            let startPosition = result.length

            // Check if this is a GFM extension node
            var extensionType: String? = nil
            if let typeName = cmark_node_get_type_string(childNode) {
                extensionType = String(cString: typeName)
            }

            // Render the child
            renderNode(childNode, into: result, theme: theme, listDepth: listDepth, listIndex: listIndex, isOrdered: isOrdered)

            // Apply contextual spacing if this is a block-level node
            if isBlockLevelNode(childType) || (extensionType.map { isBlockLevelExtension($0) } ?? false) {
                applyContextualSpacing(
                    to: result,
                    startPosition: startPosition,
                    currentNodeType: childType,
                    currentExtensionType: extensionType,
                    previousNodeType: previousType,
                    previousExtensionType: previousExtensionType,
                    theme: theme
                )

                // Update previous type for next iteration
                previousType = childType
                previousExtensionType = extensionType
            }

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
        var previousType: cmark_node_type? = nil
        var previousExtensionType: String? = nil

        while let block = child {
            let blockType = cmark_node_get_type(block)
            let startPosition = result.length

            // Check if this is a GFM extension node
            var extensionType: String? = nil
            if let typeName = cmark_node_get_type_string(block) {
                extensionType = String(cString: typeName)
            }

            renderNode(block, into: result, theme: theme, listDepth: 0, listIndex: 0, isOrdered: false)

            // Apply contextual spacing for top-level blocks
            if isBlockLevelNode(blockType) || (extensionType.map { isBlockLevelExtension($0) } ?? false) {
                applyContextualSpacing(
                    to: result,
                    startPosition: startPosition,
                    currentNodeType: blockType,
                    currentExtensionType: extensionType,
                    previousNodeType: previousType,
                    previousExtensionType: previousExtensionType,
                    theme: theme
                )

                // Update previous type for next iteration
                previousType = blockType
                previousExtensionType = extensionType
            }

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
