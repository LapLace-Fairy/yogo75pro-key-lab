import AppKit
import Carbon

@MainActor
final class GlobalHotkeys: ObservableObject {
    @Published private(set) var message = "快捷键尚未注册"
    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private let signature: OSType = 0x594F474F // YOGO

    func start() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard result == noErr else { return result }
            return MainActor.assumeIsolated {
                Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue().handle(hotKeyID)
            }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr, handler != nil else {
            message = "快捷键监听启动失败（\(status)）"
            return
        }

        let modifiers = UInt32(shiftKey | controlKey | optionKey | cmdKey)
        let keys: [(UInt32, UInt32, String)] = [
            (UInt32(kVK_ANSI_X), 1, "ChatGPT"),
            (UInt32(kVK_ANSI_Z), 2, "ZCode")
        ]
        var failed: [String] = []
        for (key, id, name) in keys {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: signature, id: id),
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { registered.append(reference) }
            else { failed.append("\(name)（\(result)）") }
        }
        message = failed.isEmpty ? "全局快捷键已启用" : "注册失败：\(failed.joined(separator: "、"))；请检查快捷键冲突"
    }

    private func handle(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == signature else { return OSStatus(eventNotHandledErr) }
        let bundleID: String
        switch hotKeyID.id {
        case 1: bundleID = "com.openai.codex"
        case 2: bundleID = "dev.zcode.app"
        default: return OSStatus(eventNotHandledErr)
        }
        let name = hotKeyID.id == 1 ? "ChatGPT" : "ZCode"
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = false
            workspace.openApplication(at: url, configuration: config) { [weak self] _, error in
                Task { @MainActor in
                    guard error == nil else {
                        self?.message = "无法打开 \(name)，请检查安装状态"
                        return
                    }
                    self?.message = "已请求打开或切换至 \(name)"
                }
            }
        } else {
            message = "未找到 \(name) 应用"
        }
        return noErr
    }
}
