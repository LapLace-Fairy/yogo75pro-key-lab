import XCTest
@testable import YogoCore

final class AlertPolicyTests: XCTestCase {
    func testBatteryCrossingsAreStrictAndRearmAfterCharging() {
        var tracker = BatteryThresholdTracker()
        XCTAssertEqual(tracker.observe(50), [])
        XCTAssertEqual(tracker.observe(49), [.yellow])
        XCTAssertEqual(tracker.observe(49), [])
        XCTAssertEqual(tracker.observe(20), [])
        XCTAssertEqual(tracker.observe(19), [.orange])
        XCTAssertEqual(tracker.observe(10), [])
        XCTAssertEqual(tracker.observe(9), [.red])
        XCTAssertEqual(tracker.observe(nil), [])
        XCTAssertEqual(tracker.observe(10), [])
        XCTAssertEqual(tracker.observe(9), [.red])
    }

    func testFirstLowReadingWarnsMostUrgentAndJumpQueuesEachCrossing() {
        var first = BatteryThresholdTracker()
        XCTAssertEqual(first.observe(8), [.red])
        var jump = BatteryThresholdTracker()
        XCTAssertEqual(jump.observe(55), [])
        XCTAssertEqual(jump.observe(5), [.yellow, .orange, .red])
    }

    func testAgentWaitingPreemptsAndBatteryBlinksExactlyTenTimes() {
        var policy = AlertPolicy()
        policy.observeBattery(60)
        policy.observeBattery(49)
        XCTAssertEqual(policy.frame, .batteryWarning(.yellow))
        policy.setWaiting(codex: true, zcode: false)
        XCTAssertEqual(policy.frame, .agent(.codex))
        policy.advance()
        XCTAssertEqual(policy.frame, .agent(.codex))
        policy.setWaiting(codex: false, zcode: false)
        for phase in 0..<20 {
            XCTAssertEqual(policy.frame, phase.isMultiple(of: 2) ? .batteryWarning(.yellow) : .off)
            policy.advance()
        }
        XCTAssertEqual(policy.frame, .off)
    }

    func testTwoWaitingAgentsAlternate() {
        var policy = AlertPolicy()
        policy.setWaiting(codex: true, zcode: true)
        XCTAssertEqual(policy.frame, .agent(.codex))
        policy.advance()
        XCTAssertEqual(policy.frame, .agent(.zcode))
        policy.setWaiting(codex: false, zcode: true)
        XCTAssertEqual(policy.frame, .agent(.zcode))
    }

    func testQueuedBatteryAlertIsRemovedAfterChargeRecovers() {
        var policy = AlertPolicy()
        policy.observeBattery(60)
        policy.setWaiting(codex: true, zcode: false)
        policy.observeBattery(49)
        policy.observeBattery(55)
        policy.setWaiting(codex: false, zcode: false)
        XCTAssertEqual(policy.frame, .off)
        XCTAssertFalse(policy.needsTick)
    }

    func testAlertFramesUseEntireGridAndRequestedColors() {
        XCTAssertTrue(MatrixFrame.alert(.off).pixels.allSatisfy { $0 == .black })
        XCTAssertEqual(Set(MatrixFrame.alert(.agent(.codex)).pixels.filter { $0 != .black }), [Pixel(120, 200, 255)])
        XCTAssertEqual(Set(MatrixFrame.alert(.agent(.zcode)).pixels.filter { $0 != .black }), [Pixel(255, 230, 140)])
        XCTAssertEqual(Set(MatrixFrame.alert(.batteryWarning(.yellow)).pixels.filter { $0 != .black }), [Pixel(255, 220, 0)])
    }

    func testWaitingStateDoesNotExpireBeforeBeingHandled() {
        let start = Date(timeIntervalSince1970: 1_000)
        var registry = SessionRegistry()
        registry.update(agent: .codex, sessionID: "waiting", status: .waiting, at: start)
        XCTAssertEqual(registry.status(for: .codex, at: start.addingTimeInterval(7200), maxAge: 1800), .waiting)
        registry.update(agent: .codex, sessionID: "waiting", status: .running, at: start.addingTimeInterval(7201))
        XCTAssertEqual(registry.status(for: .codex, at: start.addingTimeInterval(7201), maxAge: 1800), .running)
    }
}
