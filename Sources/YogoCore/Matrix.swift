import Foundation

public struct Pixel: Hashable, Sendable {
    public let red: UInt8, green: UInt8, blue: UInt8
    public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }
    public static let black = Pixel(0, 0, 0)
}

public enum BatteryLevel: Int, Sendable {
    case empty = 0, twenty = 1, forty, sixty, eighty, full

    public init?(percent: Int?) {
        guard let percent, (0...100).contains(percent) else { return nil }
        self.init(rawValue: (percent + 19) / 20)
    }
}

public struct MatrixFrame: Hashable, Sendable {
    public let pixels: [Pixel]
    public init(pixels: [Pixel]) {
        precondition(pixels.count == 36)
        self.pixels = pixels
    }
    public var bytes: [UInt8] { pixels.flatMap { [$0.red, $0.green, $0.blue] } }
    public var isBlank: Bool { pixels.allSatisfy { $0 == .black } }

    public static func alert(_ alert: AlertFrame) -> MatrixFrame {
        let rows: [String]
        let color: Pixel
        switch alert {
        case .off: return MatrixFrame(pixels: Array(repeating: .black, count: 36))
        case .agent(.codex):
            rows = ["100001", "010010", "001100", "001100", "010010", "100001"]
            color = Pixel(120, 200, 255)
        case .agent(.zcode):
            rows = ["111111", "000010", "000100", "001000", "010000", "111111"]
            color = Pixel(255, 230, 140)
        case .batteryWarning(let warning):
            rows = ["001100", "001100", "001100", "001100", "000000", "001100"]
            switch warning {
            case .yellow: color = Pixel(255, 220, 0)
            case .orange: color = Pixel(255, 100, 0)
            case .red: color = Pixel(255, 0, 0)
            }
        }
        var pixels = Array(repeating: Pixel.black, count: 36)
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character == "1" {
                pixels[row * 6 + column] = color
            }
        }
        return MatrixFrame(pixels: pixels)
    }

    /// Volatile RGB565 stream; reports do not include an HID report ID byte.
    public func streamReports(payloadSize: Int, startingSequence: UInt8) -> [[UInt8]] {
        precondition(payloadSize == 24 || payloadSize == 56)
        precondition((1...250).contains(startingSequence))
        let data = pixels.flatMap { pixel -> [UInt8] in
            let value = (UInt16(pixel.red >> 3) << 11)
                | (UInt16(pixel.green >> 2) << 5) | UInt16(pixel.blue >> 3)
            return [UInt8(value & 0xff), UInt8(value >> 8)]
        }
        return stride(from: 0, to: data.count, by: payloadSize).enumerated().map { index, offset in
            var report = [UInt8](repeating: 0, count: payloadSize + 8)
            report[0] = 0xaa; report[1] = 0x3c
            report[2] = UInt8(offset)
            report[5] = UInt8((Int(startingSequence) - 1 + index) % 250 + 1)
            let chunk = data[offset..<min(offset + payloadSize, data.count)]
            report[4] = UInt8(chunk.count)
            report.replaceSubrange(8..<(8 + chunk.count), with: chunk)
            return report
        }
    }

    public static func battery(percent: Int?) -> MatrixFrame {
        guard let level = BatteryLevel(percent: percent) else {
            return MatrixFrame(pixels: Array(repeating: .black, count: 36))
        }
        let colors = [Pixel(100, 0, 0), Pixel(220, 0, 0), Pixel(220, 80, 0),
                      Pixel(210, 180, 0), Pixel(100, 190, 0), Pixel(0, 190, 40)]
        var pixels = Array(repeating: Pixel.black, count: 36)
        let color = colors[level.rawValue]
        // Four columns by five rows; each row represents one fifth.
        for row in 0..<5 {
            for column in 1...4 where row >= 5 - level.rawValue {
                if row == 0 && (column == 1 || column == 4) { continue }
                pixels[row * 6 + column] = color
            }
        }
        if level == .empty { pixels[4 * 6 + 2] = color; pixels[4 * 6 + 3] = color }
        return MatrixFrame(pixels: pixels)
    }

    /// Codex occupies the left three columns and ZCode the right three.
    public static func coding(codex: AgentStatus, zcode: AgentStatus) -> MatrixFrame {
        var pixels = Array(repeating: Pixel.black, count: 36)
        for (side, status) in [codex, zcode].enumerated() {
            let pattern: [String]
            let color: Pixel
            switch status {
            case .waiting:
                pattern = ["010", "010", "010", "000", "010", "000"]
                color = Pixel(220, 100, 0)
            case .running:
                pattern = ["010", "101", "010", "101", "010", "000"]
                color = Pixel(0, 130, 200)
            case .completed:
                pattern = ["000", "001", "001", "101", "010", "000"]
                color = Pixel(0, 180, 40)
            case .unknown:
                pattern = ["111", "001", "010", "000", "010", "000"]
                color = Pixel(55, 55, 55)
            }
            for (row, line) in pattern.enumerated() {
                for (column, character) in line.enumerated() where character == "1" {
                    pixels[row * 6 + side * 3 + column] = color
                }
            }
        }
        return MatrixFrame(pixels: pixels)
    }
}

public enum AgentStatus: Int, Codable, Sendable {
    case completed = 0, unknown = 1, running = 2, waiting = 3
    public static func aggregate(_ statuses: [AgentStatus]) -> AgentStatus {
        statuses.max(by: { $0.rawValue < $1.rawValue }) ?? .unknown
    }
}
