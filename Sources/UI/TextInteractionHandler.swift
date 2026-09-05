import AppKit

final class TextInteractionHandler: NSObject, NSTextViewDelegate {

    // Back-reference to the owning view controller — weak to avoid a retain cycle.
    // Set by MarkdownViewController after it creates this handler.
    weak var owner: MarkdownViewController?

    // MARK: - Link Handling

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        // Normalise the link value to a string so both String and URL attributes
        // are handled uniformly for the fragment check below.
        let urlString: String?
        if let s = link as? String { urlString = s }
        else if let u = link as? URL { urlString = u.absoluteString }
        else { urlString = nil }

        // Fragment-only links (#some-heading) have no scheme and no host —
        // detect that first so they never reach NSWorkspace.open.
        if let urlString,
           let components = URLComponents(string: urlString),
           components.scheme == nil,
           let fragment = components.fragment,
           !fragment.isEmpty {
            if let owner = owner,
               let entry = FragmentLinkHandler.resolve(fragment: fragment, in: owner.tocEntries) {
                owner.scrollToHeading(entry)
                return true  // consumed — NSTextView must not attempt default handling
            }
            return false  // fragment present but no matching heading; fall through
        }

        // Not a fragment link — hand off to the external-URL handler.
        guard let url = link as? URL else {
            if let urlString = link as? String, let url = URL(string: urlString) {
                return openLink(url)
            }
            return false
        }
        return openLink(url)
    }

    private func openLink(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
        return true
    }

    // MARK: - Selection

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        // The owner decides what the change means: an empty selection
        // releases a live reload that was held back because it would have
        // destroyed the old one, and any change hands ownership of the
        // selection back to the reader until a find action claims it.
        owner?.selectionDidChange(isEmpty: textView.selectedRange().length == 0)
    }

    // MARK: - Context Menu

    func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        // Build the context menu from scratch. NSTextView's default `menu` carries
        // orphaned submenus (Font, Spelling, Substitutions, etc.) with broken
        // parent references, causing "Internal inconsistency in menus" warnings.
        // Since this is a read-only viewer, none of those submenus are needed.
        let contextMenu = NSMenu()

        let hasSelection = textView.selectedRange().length > 0

        // Copy
        if hasSelection {
            contextMenu.addItem(NSMenuItem(
                title: "Copy",
                action: #selector(NSText.copy(_:)),
                keyEquivalent: ""
            ))
        }

        // Select All
        contextMenu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: ""
        ))

        // Link actions
        if let linkURL = linkAtCharIndex(charIndex, in: textView) {
            contextMenu.addItem(.separator())

            let openLinkItem = NSMenuItem(title: "Open Link", action: #selector(openContextLink(_:)), keyEquivalent: "")
            openLinkItem.target = self
            openLinkItem.representedObject = linkURL
            contextMenu.addItem(openLinkItem)

            let copyLinkItem = NSMenuItem(title: "Copy Link", action: #selector(copyLink(_:)), keyEquivalent: "")
            copyLinkItem.target = self
            copyLinkItem.representedObject = linkURL
            contextMenu.addItem(copyLinkItem)
        }

        // Search with Google
        if let selectedText = textView.selectedText(), !selectedText.isEmpty {
            contextMenu.addItem(.separator())

            let searchItem = NSMenuItem(title: "Search with Google", action: #selector(searchWithGoogle(_:)), keyEquivalent: "")
            searchItem.target = self
            searchItem.representedObject = selectedText
            contextMenu.addItem(searchItem)
        }

        // Share
        if let selectedText = textView.selectedText(), !selectedText.isEmpty {
            contextMenu.addItem(.separator())

            let sharingPicker = NSSharingServicePicker(items: [selectedText])
            contextMenu.addItem(sharingPicker.standardShareMenuItem)
        }

        return contextMenu
    }

    // MARK: - Context Menu Actions

    @objc private func openContextLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    @objc private func searchWithGoogle(_ sender: NSMenuItem) {
        guard let searchText = sender.representedObject as? String else { return }
        let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchText
        if let url = URL(string: "https://www.google.com/search?q=\(query)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helper Methods

    private func linkAtCharIndex(_ charIndex: Int, in textView: NSTextView) -> URL? {
        guard let textStorage = textView.textStorage else { return nil }
        guard charIndex < textStorage.length else { return nil }

        var effectiveRange = NSRange()
        if let link = textStorage.attribute(.link, at: charIndex, effectiveRange: &effectiveRange) {
            if let url = link as? URL {
                return url
            } else if let urlString = link as? String, let url = URL(string: urlString) {
                return url
            }
        }
        return nil
    }
}

// MARK: - NSTextView Extension

private extension NSTextView {
    func selectedText() -> String? {
        guard let selectedRange = self.selectedRanges.first as? NSRange,
              selectedRange.length > 0,
              let textStorage = self.textStorage else {
            return nil
        }
        return textStorage.attributedSubstring(from: selectedRange).string
    }
}
