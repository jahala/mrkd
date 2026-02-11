import AppKit

final class TextInteractionHandler: NSObject, NSTextViewDelegate {

    // MARK: - Link Handling

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
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

    // MARK: - Context Menu

    func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        // The `menu` parameter is the default context menu already built by NSTextView.
        // Do NOT call textView.menu(for:) again — that creates duplicate submenus
        // with broken parent references ("Internal inconsistency in menus" warnings).

        // Check if there's a link at the click location
        if let linkURL = linkAtCharIndex(charIndex, in: textView) {
            menu.addItem(NSMenuItem.separator())

            let openLinkItem = NSMenuItem(title: "Open Link", action: #selector(openContextLink(_:)), keyEquivalent: "")
            openLinkItem.target = self
            openLinkItem.representedObject = linkURL
            menu.addItem(openLinkItem)

            let copyLinkItem = NSMenuItem(title: "Copy Link", action: #selector(copyLink(_:)), keyEquivalent: "")
            copyLinkItem.target = self
            copyLinkItem.representedObject = linkURL
            menu.addItem(copyLinkItem)
        }

        // Add "Search with Google" for selected text
        if let selectedText = textView.selectedText(), !selectedText.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let searchItem = NSMenuItem(title: "Search with Google", action: #selector(searchWithGoogle(_:)), keyEquivalent: "")
            searchItem.target = self
            searchItem.representedObject = selectedText
            menu.addItem(searchItem)
        }

        // Add Share menu - using NSSharingServicePicker's standard menu item
        if let selectedText = textView.selectedText(), !selectedText.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let sharingPicker = NSSharingServicePicker(items: [selectedText])
            let shareMenuItem = sharingPicker.standardShareMenuItem
            menu.addItem(shareMenuItem)
        }

        return menu
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
