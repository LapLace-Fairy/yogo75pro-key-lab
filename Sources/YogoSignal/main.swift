import CryptoKit
import Foundation
import YogoCore

// Hooks are best-effort observers: no stdout, no decisions, and always exit 0.
func record() throws {
    guard CommandLine.arguments.count == 2,
          let agent = Agent(rawValue: CommandLine.arguments[1]),
          let input = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any],
          let session = input["session_id"] as? String, !session.isEmpty,
          let event = input["hook_event_name"] as? String else { return }
    let directory = HookSignal.directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let digest = SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
    let file = directory.appendingPathComponent("\(agent.rawValue)-\(digest).json")
    if event == "SessionEnd" {
        try? FileManager.default.removeItem(at: file)
        return
    }
    guard let status = HookSignal.status(event: event, toolName: input["tool_name"] as? String) else { return }
    let signal = HookSignal(agent: agent, sessionID: digest, status: status, updatedAt: Date())
    try JSONEncoder().encode(signal).write(to: file, options: .atomic)
}

try? record()
