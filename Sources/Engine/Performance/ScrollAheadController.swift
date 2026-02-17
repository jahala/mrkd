import AppKit

/// Monitors scroll direction and leverages TextKit 2's built-in layout
/// prefetching. NSTextLayoutManager already performs viewport-aware lazy
/// layout; this controller tracks scroll state as a hook for future
/// optimizations (e.g. cancelling background work on direction change).
@MainActor
final class ScrollAheadController {

    private weak var scrollView: NSScrollView?
    private weak var textLayoutManager: NSTextLayoutManager?
    private var lastScrollOffset: CGFloat = 0
    private var boundsObserver: NSObjectProtocol?

    init(scrollView: NSScrollView, textLayoutManager: NSTextLayoutManager?) {
        self.scrollView = scrollView
        self.textLayoutManager = textLayoutManager

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.boundsDidChange()
            }
        }
    }

    deinit {
        if let observer = boundsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func boundsDidChange() {
        guard let scrollView else { return }
        let newOffset = scrollView.contentView.bounds.origin.y
        let direction: Direction = newOffset > lastScrollOffset ? .down : .up
        lastScrollOffset = newOffset

        prefetchIfNeeded(direction: direction)
    }

    private enum Direction { case up, down }

    /// Ask TextKit 2 to ensure layout 2 screenfuls ahead in scroll direction.
    /// NSTextLayoutManager already does viewport-based prefetching, but we
    /// can nudge it for smoother large-document scrolling.
    private func prefetchIfNeeded(direction: Direction) {
        guard let scrollView, let textLayoutManager else { return }

        let viewportHeight = scrollView.contentView.bounds.height
        let currentY = scrollView.contentView.bounds.origin.y
        let prefetchDistance = viewportHeight * 2

        // Find the text position at the current viewport edge (in scroll direction)
        let startY: CGFloat
        let targetY: CGFloat
        switch direction {
        case .down:
            startY = currentY + viewportHeight
            targetY = startY + prefetchDistance
        case .up:
            startY = currentY
            targetY = max(0, currentY - prefetchDistance)
        }

        // Find the layout fragment at the viewport edge to start from
        let startPoint = CGPoint(x: 0, y: startY)
        guard let startFragment = textLayoutManager.textLayoutFragment(for: startPoint) else { return }

        let targetPoint = CGPoint(x: 0, y: targetY)
        guard let targetLocation = textLayoutManager.textLayoutFragment(for: targetPoint)?
            .rangeInElement.location else { return }

        // Enumerate from viewport edge toward the target, not from document start
        let startLocation = startFragment.rangeInElement.location

        if direction == .down {
            textLayoutManager.enumerateTextLayoutFragments(
                from: startLocation,
                options: [.ensuresLayout]
            ) { fragment in
                fragment.rangeInElement.location.compare(targetLocation) == .orderedAscending
            }
        } else {
            textLayoutManager.enumerateTextLayoutFragments(
                from: startLocation,
                options: [.ensuresLayout, .reverse]
            ) { fragment in
                fragment.rangeInElement.location.compare(targetLocation) == .orderedDescending
            }
        }
    }
}
