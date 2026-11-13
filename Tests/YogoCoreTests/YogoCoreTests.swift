import XCTest
@testable import YogoCore

final class YogoCoreTests: XCTestCase {
    func testBatteryBoundariesAndUnknown() {
        XCTAssertNil(BatteryLevel(percent: nil))
        XCTAssertNil(BatteryLevel(percent: -1))
        XCTAssertNil(BatteryLevel(percent: 101))
        XCTAssertEqual(BatteryLevel(percent: 0), .empty)
        XCTAssertEqual(BatteryLevel(percent: 1), .twenty)
        XCTAssertEqual(BatteryLevel(percent: 20), .twenty)
        XCTAssertEqual(BatteryLevel(percent: 21), .forty)
        XCTAssertEqual(BatteryLevel(percent: 40), .forty)
        XCTAssertEqual(BatteryLevel(percent: 41), .sixty)
        XCTAssertEqual(BatteryLevel(percent: 61), .eighty)
        XCTAssertEqual(BatteryLevel(percent: 81), .full)
        XCTAssertEqual(BatteryLevel(percent: 100), .full)
    }

    func testBatteryFrameFitsAndHasFiveDifferentLevels() {
        let frames = [0, 20, 40, 60, 80, 100].map { MatrixFrame.battery(percent: $0) }
        XCTAssertEqual(Set(frames).count, 6)
        for frame in frames {
            XCTAssertEqual(frame.pixels.count, 36)
            XCTAssertTrue(frame.pixels.enumerated().allSatisfy { $0.offset % 6 != 0 && $0.offset % 6 != 5 || $0.element == .black })
        }
    }

    func testAggregationPrioritizesWaitingOverRunningAndDone() {
        XCTAssertEqual(AgentStatus.aggregate([.completed, .running, .waiting]), .waiting)
        XCTAssertEqual(AgentStatus.aggregate([.completed, .running]), .running)
        XCTAssertEqual(AgentStatus.aggregate([]), .unknown)
        XCTAssertEqual(AgentStatus.aggregate([.completed, .unknown]), .unknown)
    }

    func testMatrixPacketsPreserveAllBytesAndForbidOtherCommands() throws {
        let bytes = (0..<108).map(UInt8.init)
        let packets = try DevicePacket.matrix(bytes)
        XCTAssertEqual(packets.count, 5)
        XCTAssertEqual(packets.map(\.offset), [0, 24, 48, 72, 96])
        XCTAssertEqual(packets.map(\.length), [24, 24, 24, 24, 24])
        XCTAssertEqual(packets.flatMap(\.payload), bytes)
        XCTAssertThrowsError(try DevicePacket.matrix([0]))
        let report = packets[4].report(sequence: 1)
        XCTAssertEqual(report.count, 32)
        XCTAssertEqual(Array(report.prefix(6)), [0xaa, 59, 96, 0, 24, 1])
        XCTAssertEqual(Array(report.suffix(12)), Array(repeating: 0, count: 12))
    }

    func testVolatileFrameUsesRGB565AndTransportPayloadSize() throws {
        var pixels = Array(repeating: Pixel.black, count: 36)
        pixels[0] = Pixel(255, 0, 0)
        pixels[1] = Pixel(0, 255, 0)
        pixels[2] = Pixel(0, 0, 255)
        let frame = MatrixFrame(pixels: pixels)
        let wireless = frame.streamReports(payloadSize: 24, startingSequence: 1)
        XCTAssertEqual(wireless.count, 3)
        XCTAssertEqual(Array(wireless[0].prefix(8)), [0xaa, 60, 0, 0, 24, 1, 0, 0])
        XCTAssertEqual(Array(wireless[0][8..<14]), [0x00, 0xf8, 0xe0, 0x07, 0x1f, 0x00])
        let wired = frame.streamReports(payloadSize: 56, startingSequence: 250)
        XCTAssertEqual(wired.count, 2)
        XCTAssertEqual(wired[1][2], 56)
        XCTAssertEqual(wired[1][5], 1)
        XCTAssertEqual(wired[1][4], 16)
    }

    func testBatteryUsesFiveDistinctRedToGreenColors() {
        let expected: [Pixel] = [Pixel(220, 0, 0), Pixel(220, 80, 0), Pixel(210, 180, 0), Pixel(100, 190, 0), Pixel(0, 190, 40)]
        for (level, color) in zip([20, 40, 60, 80, 100], expected) {
            let colors = Set(MatrixFrame.battery(percent: level).pixels.filter { $0 != .black })
            XCTAssertEqual(colors, [color])
        }
    }

    func testDisplayReplyRequiresMatchingCommandSequenceAndSuccessStatus() {
        XCTAssertEqual(DeviceReply.match([0xaa, 0x3c, 0, 0, 0, 7, 0, 0x55], command: 0x3c, sequence: 7), .accepted)
        XCTAssertEqual(DeviceReply.match([0xaa, 0x3c, 0, 0, 0, 7, 0, 0x0f], command: 0x3c, sequence: 7), .rejected(0x0f))
        XCTAssertEqual(DeviceReply.match([0xaa, 0x30, 0, 0, 0, 7, 0, 0x55], command: 0x3c, sequence: 7), .unrelated)
        XCTAssertEqual(DeviceReply.match([0xaa, 0x3c], command: 0x3c, sequence: 7), .unrelated)
    }

    func testSessionAggregationAndExpiry() {
        var state = SessionRegistry()
        let now = Date(timeIntervalSince1970: 1_000)
        state.update(agent: .codex, sessionID: "a", status: .running, at: now)
        state.update(agent: .codex, sessionID: "b", status: .waiting, at: now)
        state.update(agent: .zcode, sessionID: "c", status: .completed, at: now)
        XCTAssertEqual(state.status(for: .codex, at: now, maxAge: 60), .waiting)
        XCTAssertEqual(state.status(for: .zcode, at: now, maxAge: 60), .completed)
        state.update(agent: .codex, sessionID: "b", status: .running, at: now.addingTimeInterval(2))
        XCTAssertEqual(state.status(for: .codex, at: now.addingTimeInterval(2), maxAge: 60), .running)
        XCTAssertEqual(state.status(for: .codex, at: now.addingTimeInterval(100), maxAge: 60), .unknown)
        state.remove(agent: .codex, sessionID: "b")
        XCTAssertEqual(state.status(for: .codex, at: now, maxAge: 60), .running)
    }

    func testCodingFrameSeparatesAgents() {
        let frame = MatrixFrame.coding(codex: .waiting, zcode: .completed)
        XCTAssertEqual(frame.pixels.count, 36)
        let left = stride(from: 0, to: 36, by: 6).flatMap { frame.pixels[$0..<($0 + 3)] }
        let right = stride(from: 0, to: 36, by: 6).flatMap { frame.pixels[($0 + 3)..<($0 + 6)] }
        XCTAssertTrue(left.contains(Pixel(220, 100, 0)))
        XCTAssertTrue(right.contains(Pixel(0, 180, 40)))
        XCTAssertFalse(left.contains(Pixel(0, 180, 40)))
        XCTAssertFalse(right.contains(Pixel(220, 100, 0)))
    }

    func testHookEventsNeverTreatPermissionAsDecision() {
        XCTAssertEqual(HookSignal.status(event: "UserPromptSubmit", toolName: nil), .running)
        XCTAssertEqual(HookSignal.status(event: "PermissionRequest", toolName: "Bash"), .waiting)
        XCTAssertEqual(HookSignal.status(event: "PreToolUse", toolName: "request_user_input"), .waiting)
        XCTAssertEqual(HookSignal.status(event: "PostToolUse", toolName: "request_user_input"), .running)
        XCTAssertEqual(HookSignal.status(event: "Stop", toolName: nil), .completed)
        XCTAssertNil(HookSignal.status(event: "SessionStart", toolName: nil))
    }
}
