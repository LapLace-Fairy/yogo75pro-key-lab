import Darwin
import Foundation
import YogoCore

@MainActor
final class PerformanceMonitor: ObservableObject {
    @Published private(set) var message = "可测量 75 秒内的空闲 CPU 时间"
    @Published private(set) var measuring = false
    private var timer: Timer?

    func start() {
        guard !measuring, let initial = sample() else { return }
        measuring = true
        message = "测量中，请保持应用空闲 75 秒"
        timer = Timer.scheduledTimer(withTimeInterval: 75, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.measuring = false
                guard let end = self.sample(), let result = end.since(initial) else {
                    self.message = "CPU 时间读取失败"; return
                }
                let verdict = result.cpu < 0.5 ? "达标" : "未达标"
                self.message = String(format: "%.1f 秒内 CPU %.3f 秒（%@）", result.wall, result.cpu, verdict)
            }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; measuring = false }

    private func sample() -> CPUTimeSample? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return CPUTimeSample(wall: ProcessInfo.processInfo.systemUptime, cpu: user + system)
    }
}
