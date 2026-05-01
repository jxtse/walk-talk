import XCTest
@testable import LocalGravity

final class ProactiveQuotaTests: XCTestCase {
    func test_emptyQuota_canSpeak() {
        let q = ProactiveQuota(limit: 3, window: 600, clock: FakeClock())
        XCTAssertTrue(q.canSpeak())
    }

    func test_threeWithinWindow_thenBlocked() {
        let c = FakeClock()
        let q = ProactiveQuota(limit: 3, window: 600, clock: c)
        for _ in 0..<3 { q.recordSpoken(); c.advance(by: 60) }
        XCTAssertFalse(q.canSpeak())
    }

    func test_oldEntriesAge_outOfWindow() {
        let c = FakeClock()
        let q = ProactiveQuota(limit: 3, window: 600, clock: c)
        q.recordSpoken()
        c.advance(by: 700)        // > window
        XCTAssertTrue(q.canSpeak())
    }

    func test_recordSpokenCountsImmediately() {
        let c = FakeClock()
        let q = ProactiveQuota(limit: 1, window: 600, clock: c)
        q.recordSpoken()
        XCTAssertFalse(q.canSpeak())
    }
}
