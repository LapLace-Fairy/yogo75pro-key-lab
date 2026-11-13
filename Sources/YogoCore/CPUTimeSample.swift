import Foundation

public struct CPUTimeSample: Sendable {
    public let wall: TimeInterval
    public let cpu: TimeInterval

    public init(wall: TimeInterval, cpu: TimeInterval) {
        self.wall = wall; self.cpu = cpu
    }

    public func since(_ previous: CPUTimeSample) -> CPUTimeSample? {
        guard wall > previous.wall, cpu >= previous.cpu else { return nil }
        return CPUTimeSample(wall: wall - previous.wall, cpu: cpu - previous.cpu)
    }
}
