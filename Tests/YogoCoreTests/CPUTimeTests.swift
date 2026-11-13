import XCTest
@testable import YogoCore

final class CPUTimeTests: XCTestCase {
    func testCPUConsumptionUsesCumulativeProcessTimeAndElapsedWallTime() {
        let start = CPUTimeSample(wall: 100, cpu: 5.2)
        let end = CPUTimeSample(wall: 175, cpu: 5.55)
        let result = end.since(start)
        XCTAssertEqual(result?.wall ?? 0, 75, accuracy: 0.001)
        XCTAssertEqual(result?.cpu ?? 0, 0.35, accuracy: 0.001)
        XCTAssertNil(start.since(end))
    }
}
