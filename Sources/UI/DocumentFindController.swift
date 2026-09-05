import AppKit

/// Find-in-page for a rendered document: the standard find bar, its
/// theming, and putting an in-flight search back on its match when the
/// text storage is replaced underneath it.
///
/// The finder is the text view's own. `NSTextView` does not conform to
/// `NSTextFinderClient` in Swift, so a free-standing `NSTextFinder` cannot
/// be pointed at it; `usesFindBar` is the supported wiring and produces the
/// same standard `NSTextFinderBarView` in the enclosing scroll view.
///
/// Compiled into the sandboxed Quick Look extension as well as the app, so
/// nothing here may reach outside the process.
@MainActor
final class DocumentFindController {

    private let textView: NSTextView
    private let scrollView: NSScrollView

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
    }

    /// True while the find bar is on screen. What is selected then belongs
    /// to the search — incremental searching moves the selection with every
    /// keystroke — rather than to the reader.
    var isFindBarVisible: Bool { scrollView.isFindBarVisible }

    /// The standard find bar, once it has been shown.
    var findBarView: NSView? { scrollView.findBarView }

    /// `NSTextView` reads the requested action off the sender's tag, the
    /// way a menu item carries it.
    func perform(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        textView.performTextFinderAction(sender)
    }

    /// The find bar is Apple's view and its subviews are not ours to
    /// repaint, but its polarity is: a dark document must not get a white
    /// slab across the top of it.
    func applyTheme(_ theme: Theme) {
        findBarView?.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }

    /// The match the reader is on, as a value that survives the text
    /// storage being replaced. Nil when nothing is selected.
    func currentMatch() -> FindMatch? {
        let range = textView.selectedRange()
        guard range.length > 0,
              let storage = textView.textStorage,
              NSMaxRange(range) <= storage.length else { return nil }
        return FindMatch(
            text: storage.attributedSubstring(from: range).string,
            location: range.location
        )
    }

    /// Put the search back on its match after the document was replaced.
    ///
    /// Scrolling is deliberately `scrollRangeToVisible`, not a jump: the
    /// reading position has already been restored by the caller, so a match
    /// that is still on screen leaves the view exactly where it was and
    /// only a match that moved out of sight pulls the view to it.
    @discardableResult
    func restore(_ match: FindMatch) -> NSRange? {
        guard let restored = FindRestoration.restoredMatch(for: match, in: textView.string) else {
            // The text the reader was on is gone. Leaving the old range
            // selected would highlight whatever moved into its place.
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            return nil
        }
        textView.setSelectedRange(restored)
        textView.scrollRangeToVisible(restored)
        return restored
    }
}
