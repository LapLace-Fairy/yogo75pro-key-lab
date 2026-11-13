import Foundation

public enum Agent: String, Codable, Sendable { case codex, zcode }

/// A stale session is unknown, never silently treated as completed.
public struct SessionRegistry: Sendable {
    private struct Session: Sendable {
        let status: AgentStatus
        let updatedAt: Date
    }
    private var sessions: [Agent: [String: Session]] = [:]

    public init() {}

    public mutating func update(agent: Agent, sessionID: String, status: AgentStatus, at time: Date) {
        guard !sessionID.isEmpty else { return }
        if let previous = sessions[agent]?[sessionID], previous.updatedAt > time { return }
        sessions[agent, default: [:]][sessionID] = Session(status: status, updatedAt: time)
    }

    public mutating func remove(agent: Agent, sessionID: String) {
        sessions[agent]?.removeValue(forKey: sessionID)
    }

    public func status(for agent: Agent, at time: Date, maxAge: TimeInterval) -> AgentStatus {
        let statuses = (sessions[agent] ?? [:]).values.map { session in
            session.status != .waiting && time.timeIntervalSince(session.updatedAt) > maxAge
                ? AgentStatus.unknown : session.status
        }
        return AgentStatus.aggregate(statuses)
    }
}
