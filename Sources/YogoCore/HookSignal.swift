import Foundation

public struct HookSignal: Codable, Sendable {
    public let agent: Agent
    public let sessionID: String
    public let status: AgentStatus
    public let updatedAt: Date

    public init(agent: Agent, sessionID: String, status: AgentStatus, updatedAt: Date) {
        self.agent = agent
        self.sessionID = sessionID
        self.status = status
        self.updatedAt = updatedAt
    }

    public static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["YOGO_SIGNAL_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/YogoKeyLab/signals", isDirectory: true)
    }

    /// Observation only. Hook output never contains an approval decision.
    public static func status(event: String, toolName: String?) -> AgentStatus? {
        switch event {
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure": return .running
        case "PermissionRequest": return .waiting
        case "PreToolUse":
            let tool = (toolName ?? "").lowercased()
            if tool == "request_user_input" || tool == "askuserquestion" { return .waiting }
            return .running
        case "Stop": return .completed
        default: return nil
        }
    }
}
