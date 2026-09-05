import Foundation

/// Collapses a burst of calls into a single trailing invocation.
///
/// A save from an editor or a coding agent lands as several filesystem
/// events in quick succession; re-rendering on each one would render a
/// half-written file and throw away the result milliseconds later.
/// `schedule()` restarts the countdown, so the action runs once, `delay`
/// after the last event.
///
/// Trailing-edge only, and deliberately so: firing on the leading edge would
/// read the file mid-write.
final class Debouncer {

    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let action: () -> Void
    private var pending: DispatchWorkItem?

    init(delay: TimeInterval, queue: DispatchQueue = .main, action: @escaping () -> Void) {
        self.delay = delay
        self.queue = queue
        self.action = action
    }

    /// Restart the countdown. The action fires `delay` from now unless
    /// another call arrives first.
    func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.action()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Drop any queued invocation.
    func cancel() {
        pending?.cancel()
        pending = nil
    }

    deinit {
        pending?.cancel()
    }
}
