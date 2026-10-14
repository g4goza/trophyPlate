import Foundation

public struct GRBLParser {
    private var buffer = ""
    public init() {}
    public mutating func append(_ chunk: String) -> [String] {
        buffer += chunk
        // Status reports may end at '>' without a newline.
        var output: [String] = []
        while let index = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" || $0 == ">" }) {
            let through = buffer.index(after:index)
            let line = String(buffer[..<through]).trimmingCharacters(in:.whitespacesAndNewlines)
            buffer.removeSubrange(..<through)
            if !line.isEmpty { output.append(line) }
        }
        if buffer.utf8.count > 65536 { buffer = ""; output.append("error:oversized controller reply") }
        return output
    }
}
public struct ControllerInfo: Sendable {
    public var identity = ""
    public var powerMaximum: Double?
    public var laserMode = false
    public var reportsInches: Bool?
    public var status = "Unknown"
    public var workOffset: [Double]?
    public var machinePosition: [Double]?
    public init() {}
    public mutating func consume(_ line: String) {
        if line.hasPrefix("Grbl ") || line.hasPrefix("[VER:") { identity = line }
        if line.hasPrefix("$30="), let value = Double(line.dropFirst(4).split(separator:" ").first ?? "") { powerMaximum = value }
        if line.hasPrefix("$13=") {
            let value = Double(line.dropFirst(4).split(separator:" ").first ?? "")
            reportsInches = value == 0 ? false:(value == 1 ? true:nil)
        }
        if line.hasPrefix("$32=") { laserMode = Double(line.dropFirst(4).split(separator:" ").first ?? "") == 1 }
        if line.hasPrefix("<") {
            let parts = line.dropFirst().replacingOccurrences(of:">",with:"").split(separator:"|")
            if let first = parts.first { status = String(first).components(separatedBy:":")[0] }
            for part in parts {
                if part.hasPrefix("WCO:") { workOffset = part.dropFirst(4).split(separator:",").compactMap { Double($0) } }
                if part.hasPrefix("MPos:") { machinePosition = part.dropFirst(5).split(separator:",").compactMap { Double($0) } }
            }
        }
    }
    public func validatedPowerMaximum() throws -> Double {
        guard !identity.isEmpty else { throw PlateError("Controller did not identify as GRBL. Check baud rate and USB connection.") }
        guard laserMode else { throw PlateError("Controller laser mode ($32) is not enabled. Configure and verify the machine before engraving.") }
        guard let maximum = powerMaximum, maximum.isFinite, maximum > 0, maximum <= 100000 else { throw PlateError("Controller power maximum ($30) is missing or invalid.") }
        guard reportsInches == false else { throw PlateError("Position reports must use millimeters ($13=0). Verify the controller setting before motion; the app does not change it automatically.") }
        guard status == "Idle" else { throw PlateError("Controller must be Idle; current status: \(status).") }
        return maximum
    }
}
