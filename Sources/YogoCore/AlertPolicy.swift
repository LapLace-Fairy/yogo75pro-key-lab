import Foundation

public enum BatteryWarning: Equatable, Sendable {
    case yellow, orange, red

    fileprivate var threshold: Int {
        switch self { case .yellow: return 50; case .orange: return 20; case .red: return 10 }
    }
}

public enum AlertFrame: Equatable, Sendable {
    case off
    case batteryWarning(BatteryWarning)
    case agent(Agent)
}

public struct BatteryThresholdTracker: Sendable {
    private var previous: Int?
    public init() {}

    public mutating func observe(_ value: Int?) -> [BatteryWarning] {
        guard let value, (0...100).contains(value) else { return [] }
        defer { previous = value }
        guard let previous else {
            if value < 10 { return [.red] }
            if value < 20 { return [.orange] }
            if value < 50 { return [.yellow] }
            return []
        }
        return [(50, BatteryWarning.yellow), (20, .orange), (10, .red)]
            .compactMap { previous >= $0.0 && value < $0.0 ? $0.1 : nil }
    }
}

public struct AlertPolicy: Sendable {
    private var battery = BatteryThresholdTracker()
    private var queued: [BatteryWarning] = []
    private var active: BatteryWarning?
    private var phase = 0
    private var codexWaiting = false
    private var zcodeWaiting = false
    private var showZcode = false
    public init() {}

    public mutating func observeBattery(_ value: Int?) {
        if let value, (0...100).contains(value) {
            queued.removeAll { value >= $0.threshold }
            if let active, value >= active.threshold { self.active = nil; phase = 0 }
        }
        queued.append(contentsOf: battery.observe(value))
        startNext()
    }

    public mutating func testBatteryWarning(_ warning: BatteryWarning) {
        queued.append(warning)
        startNext()
    }

    public mutating func setWaiting(codex: Bool, zcode: Bool) {
        codexWaiting = codex
        zcodeWaiting = zcode
        if !codex { showZcode = true }
        if !zcode { showZcode = false }
        startNext()
    }

    public var frame: AlertFrame {
        if codexWaiting && zcodeWaiting { return .agent(showZcode ? .zcode : .codex) }
        if codexWaiting { return .agent(.codex) }
        if zcodeWaiting { return .agent(.zcode) }
        if let active, phase.isMultiple(of: 2) { return .batteryWarning(active) }
        return .off
    }

    public var needsTick: Bool {
        (codexWaiting && zcodeWaiting) || (!codexWaiting && !zcodeWaiting && active != nil)
    }

    public var tickInterval: TimeInterval { codexWaiting && zcodeWaiting ? 2 : 0.5 }

    /// One half-blink, or one alternation step when both agents need attention.
    public mutating func advance() {
        if codexWaiting && zcodeWaiting { showZcode.toggle(); return }
        guard !codexWaiting, !zcodeWaiting, active != nil else { return }
        phase += 1
        if phase == 20 { active = nil; phase = 0; startNext() }
    }

    private mutating func startNext() {
        guard !codexWaiting, !zcodeWaiting, active == nil, !queued.isEmpty else { return }
        active = queued.removeFirst()
        phase = 0
    }
}
