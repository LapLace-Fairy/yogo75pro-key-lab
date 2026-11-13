import Foundation

public enum DeviceReply: Equatable, Sendable {
    case unrelated, accepted, rejected(UInt8)

    public static func match(_ report: [UInt8], command: UInt8, sequence: UInt8) -> DeviceReply {
        guard report.count >= 8, report[0] == 0xaa, report[1] == command, report[5] == sequence else { return .unrelated }
        return report[7] == 0x55 ? .accepted : .rejected(report[7])
    }
}

/// Matrix protocol derived from YogoDot (MIT), see THIRD_PARTY.md.
public struct DevicePacket: Sendable {
    public let offset: Int
    public let length: Int
    public let payload: [UInt8]
    public enum PacketError: Error { case invalidFrame }

    public static func matrix(_ bytes: [UInt8]) throws -> [DevicePacket] {
        guard bytes.count == 108 else { throw PacketError.invalidFrame }
        return stride(from: 0, to: 108, by: 24).map { offset in
            let payload = Array(bytes[offset..<min(offset + 24, bytes.count)])
            return DevicePacket(offset: offset, length: 24, payload: payload)
        }
    }

    /// The report ID is supplied separately by IOHIDDeviceSetReport.
    public func report(sequence: UInt8) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 32)
        report[0] = 0xaa; report[1] = 59
        report[2] = UInt8(offset & 255); report[3] = UInt8(offset >> 8)
        report[4] = UInt8(length); report[5] = sequence
        report.replaceSubrange(8..<(8 + payload.count), with: payload)
        return report
    }
}
