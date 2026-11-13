import Foundation
import IOKit.hid
import YogoCore

@MainActor
final class KeyboardMonitor: ObservableObject {
    @Published private(set) var connection = "未检测"
    @Published private(set) var battery: Int?
    @Published private(set) var displayStatus = "未发送画面"
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var timer: Timer?
    private var timeout: Timer?
    private var displayTimer: Timer?
    private var desiredFrame = MatrixFrame.alert(.off)
    private var lastHandshake = Date.distantPast
    private var pendingSequence: UInt8?
    private var sequence: UInt8 = 0
    private var candidates: [IOHIDDevice] = []
    private var framePackets: [[UInt8]] = []
    private var frameSequence: UInt8?
    private var frameTimeout: Timer?
    private var frameInFlight: MatrixFrame?
    private var retryTimer: Timer?

    init() {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x373b,
            kIOHIDPrimaryUsagePageKey: 0xff60,
            kIOHIDPrimaryUsageKey: 0x61,
        ] as CFDictionary)
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBattery() }
        }
        scheduleDisplayRefresh()
    }

    func setFrame(_ frame: MatrixFrame) {
        guard desiredFrame != frame else { return }
        desiredFrame = frame
        scheduleDisplayRefresh()
        drawCurrentFrame()
    }

    func stop() {
        timer?.invalidate()
        displayTimer?.invalidate()
        retryTimer?.invalidate()
        timer = nil
        displayTimer = nil
        disconnect()
        connection = "已停止"
    }

    func refresh() {
        disconnect()
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            connection = "未找到键盘接口"; return
        }
        candidates = devices.filter {
            let pid = (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
            return pid == 0x119b || pid == 0x11ff
        }.sorted {
            let left = (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let right = (IOHIDDeviceGetProperty($1, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            return left < right
        }
        guard !candidates.isEmpty else { connection = "未找到键盘接口"; return }
        tryCandidate(at: 0)
    }

    private func pollBattery() {
        guard device != nil else { refresh(); return }
        guard pendingSequence == nil, frameSequence == nil else { return }
        if Date().timeIntervalSince(lastHandshake) > 4, !send(command: 0x10) {
            disconnect(); connection = "握手失败"; return
        }
        guard send(command: 0x30) else { disconnect(); connection = "电量查询失败"; return }
        pendingSequence = sequence
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pendingSequence != nil else { return }
                self.disconnect(); self.connection = "键盘未应答，稍后重试"
            }
        }
    }

    private func tryCandidate(at index: Int) {
        disconnect()
        guard index < candidates.count else {
            connection = "键盘未应答，请检查连接、权限或其他驱动"; return
        }
        let candidate = candidates[index]
        guard IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess else {
            tryCandidate(at: index + 1); return
        }
        device = candidate
        let size = max(64, (IOHIDDeviceGetProperty(candidate, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        inputBuffer = buffer
        IOHIDDeviceRegisterInputReportCallback(candidate, buffer, size, { context, result, _, _, _, report, length in
            guard result == kIOReturnSuccess, let context else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated {
                Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue().receive(bytes)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        connection = "正在查询键盘…"
        guard send(command: 0x10), send(command: 0x30) else {
            tryCandidate(at: index + 1); return
        }
        pendingSequence = sequence
        timeout = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pendingSequence != nil else { return }
                self.tryCandidate(at: index + 1)
            }
        }
    }

    private func send(command: UInt8) -> Bool {
        guard let device else { return false }
        sequence = sequence % 250 + 1
        let reportSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
        guard reportSize == 32 || reportSize == 64 else { return false }
        var report = [UInt8](repeating: 0, count: reportSize)
        report[0] = 0xaa; report[1] = command; report[5] = sequence
        let success = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count) == kIOReturnSuccess
        }
        if success && command == 0x10 { lastHandshake = Date() }
        return success
    }

    private func drawCurrentFrame() {
        guard let device, frameSequence == nil, pendingSequence == nil, retryTimer?.isValid != true else { return }
        if Date().timeIntervalSince(lastHandshake) > 4, !send(command: 0x10) {
            displayStatus = "握手失败"; return
        }
        let size = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
        guard size == 32 || size == 64 else { displayStatus = "报告长度不支持"; return }
        let firstSequence = sequence % 250 + 1
        frameInFlight = desiredFrame
        framePackets = desiredFrame.streamReports(payloadSize: size - 8, startingSequence: firstSequence)
        sendNextFramePacket()
    }

    private func scheduleDisplayRefresh() {
        displayTimer?.invalidate()
        displayTimer = nil
        guard !desiredFrame.isBlank else { return }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drawCurrentFrame() }
        }
    }

    private func retryFrameLater() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryTimer = nil; self?.drawCurrentFrame() }
        }
    }

    private func sendNextFramePacket() {
        guard let device, !framePackets.isEmpty else {
            frameSequence = nil
            if displayStatus != "键盘已确认接收画面" { displayStatus = "键盘已确认接收画面" }
            let sent = frameInFlight
            frameInFlight = nil
            if sent != desiredFrame { drawCurrentFrame() }
            return
        }
        let report = framePackets.removeFirst()
        sequence = report[5]
        frameSequence = sequence
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else {
            frameSequence = nil; framePackets.removeAll(); frameInFlight = nil
            displayStatus = "画面发送失败"; retryFrameLater(); return
        }
        frameTimeout?.invalidate()
        frameTimeout = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.frameSequence != nil else { return }
                self.frameSequence = nil; self.framePackets.removeAll(); self.frameInFlight = nil
                self.displayStatus = "点阵画面未收到键盘确认"
                self.retryFrameLater()
            }
        }
    }

    private func receive(_ report: [UInt8]) {
        if let frameSequence {
            switch DeviceReply.match(report, command: 0x3c, sequence: frameSequence) {
            case .accepted:
                frameTimeout?.invalidate()
                self.frameSequence = nil
                sendNextFramePacket()
                return
            case .rejected(let code):
                frameTimeout?.invalidate()
                self.frameSequence = nil
                framePackets.removeAll()
                frameInFlight = nil
                displayStatus = String(format: "键盘拒绝点阵画面（0x%02X）", code)
                retryFrameLater()
                return
            case .unrelated: break
            }
        }
        guard report.count >= 10, report[0] == 0xaa, report[1] == 0x30,
              report[5] == pendingSequence, report[7] == 0x55, report[8] <= 100 else { return }
        timeout?.invalidate()
        pendingSequence = nil
        let newBattery = Int(report[8])
        if battery != newBattery { battery = newBattery }
        if connection != "键盘已响应" { connection = "键盘已响应" }
        drawCurrentFrame()
    }

    private func disconnect() {
        timeout?.invalidate()
        frameTimeout?.invalidate()
        retryTimer?.invalidate()
        frameSequence = nil
        frameInFlight = nil
        framePackets.removeAll()
        pendingSequence = nil
        battery = nil
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, 0)
        }
        device = nil
        inputBuffer?.deallocate()
        inputBuffer = nil
    }
}
