import Foundation
import YogoCore

@MainActor
final class DisplayCoordinator: ObservableObject {
    @Published private(set) var alert: AlertFrame = .off
    private var policy = AlertPolicy()
    private var timer: Timer?
    private var scheduledInterval: TimeInterval?

    func batteryChanged(_ value: Int?) { policy.observeBattery(value); synchronize() }
    func waitingChanged(codex: Bool, zcode: Bool) {
        policy.setWaiting(codex: codex, zcode: zcode)
        synchronize()
    }
    func testWarning(_ warning: BatteryWarning) { policy.testBatteryWarning(warning); synchronize() }
    func stop() { timer?.invalidate(); timer = nil; scheduledInterval = nil }

    private func synchronize() {
        if alert != policy.frame { alert = policy.frame }
        guard policy.needsTick else { stop(); return }
        let interval = policy.tickInterval
        guard timer == nil || scheduledInterval != interval else { return }
        stop()
        scheduledInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.policy.advance()
                self.synchronize()
            }
        }
    }
}
