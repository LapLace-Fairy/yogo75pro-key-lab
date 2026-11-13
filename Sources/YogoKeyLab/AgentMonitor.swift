import Darwin
import Foundation
import YogoCore

@MainActor
final class AgentMonitor: ObservableObject {
    @Published private(set) var codex: AgentStatus = .unknown
    @Published private(set) var zcode: AgentStatus = .unknown
    private var source: DispatchSourceFileSystemObject?
    private var expiryTimer: Timer?

    func start() {
        stop()
        let directory = HookSignal.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.path, O_EVTONLY)
        if descriptor >= 0 {
            let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                                     eventMask: [.write, .delete, .rename], queue: .main)
            watcher.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let event = self.source?.data, event.contains(.delete) || event.contains(.rename) {
                        self.start()
                    } else {
                        self.refresh()
                    }
                }
            }
            watcher.setCancelHandler { close(descriptor) }
            source = watcher
            watcher.resume()
        }
        refresh()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        source?.cancel(); source = nil
        expiryTimer?.invalidate(); expiryTimer = nil
    }

    private func refresh() {
        let directory = HookSignal.directory
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let now = Date()
        var registry = SessionRegistry()
        for url in urls where url.pathExtension == "json" {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
                  let data = try? Data(contentsOf: url),
                  let signal = try? JSONDecoder().decode(HookSignal.self, from: data),
                  signal.updatedAt.timeIntervalSince(now) <= 60 else { continue }
            registry.update(agent: signal.agent, sessionID: signal.sessionID, status: signal.status, at: signal.updatedAt)
        }
        let newCodex = registry.status(for: .codex, at: now, maxAge: 1800)
        let newZcode = registry.status(for: .zcode, at: now, maxAge: 1800)
        if codex != newCodex { codex = newCodex }
        if zcode != newZcode { zcode = newZcode }
    }
}
