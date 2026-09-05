import XCTest
@testable import mrkd

/// Real timing, real dispatch queues — no injected clock. These tests take
/// about a second in total, which is the price of proving the coalescing
/// actually happens rather than proving a mock was called.
@MainActor
final class DebouncerTests: XCTestCase {

    /// A burst of writes — the agent case — must produce exactly one render.
    func testBurstOfSchedulesFiresExactlyOnce() {
        var fireCount = 0
        let fired = expectation(description: "debounced action fired")
        let debouncer = Debouncer(delay: 0.15) {
            fireCount += 1
            fired.fulfill()
        }

        for burstIndex in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(burstIndex) * 0.02) {
                debouncer.schedule()
            }
        }

        wait(for: [fired], timeout: 3)
        // Give any stray extra invocation time to arrive and be counted.
        let settle = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        wait(for: [settle], timeout: 3)

        XCTAssertEqual(fireCount, 1, "six writes in one burst must coalesce into one reload")
    }

    /// The action fires after the *last* event in the burst, not the first —
    /// a leading-edge implementation would fire early and re-read a
    /// half-written file.
    func testActionFiresAfterTheLastEventNotTheFirst() {
        let delay: TimeInterval = 0.2
        var firedAt: Date?
        var lastScheduledAt = Date()
        let fired = expectation(description: "debounced action fired")
        let debouncer = Debouncer(delay: delay) {
            firedAt = Date()
            fired.fulfill()
        }

        for burstIndex in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(burstIndex) * 0.03) {
                lastScheduledAt = Date()
                debouncer.schedule()
            }
        }

        wait(for: [fired], timeout: 3)
        guard let firedAt else { return XCTFail("action never fired") }
        XCTAssertGreaterThanOrEqual(
            firedAt.timeIntervalSince(lastScheduledAt), delay * 0.9,
            "action fired before the debounce interval elapsed after the last event"
        )
    }

    /// Two bursts far enough apart are two separate reloads.
    func testSeparatedBurstsFireSeparately() {
        var fireCount = 0
        let firedTwice = expectation(description: "two separate firings")
        firedTwice.expectedFulfillmentCount = 2
        let debouncer = Debouncer(delay: 0.1) {
            fireCount += 1
            firedTwice.fulfill()
        }

        debouncer.schedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { debouncer.schedule() }

        wait(for: [firedTwice], timeout: 3)
        XCTAssertEqual(fireCount, 2)
    }

    func testCancelDropsAPendingAction() {
        var fireCount = 0
        let debouncer = Debouncer(delay: 0.1) { fireCount += 1 }
        debouncer.schedule()
        debouncer.cancel()

        let settle = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        wait(for: [settle], timeout: 3)

        XCTAssertEqual(fireCount, 0, "a cancelled debouncer must not fire")
    }

    func testDeallocatedDebouncerDoesNotFire() {
        var fireCount = 0
        do {
            let debouncer = Debouncer(delay: 0.1) { fireCount += 1 }
            debouncer.schedule()
        }

        let settle = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        wait(for: [settle], timeout: 3)

        XCTAssertEqual(fireCount, 0, "a debouncer that went away must not fire into a dead controller")
    }
}
