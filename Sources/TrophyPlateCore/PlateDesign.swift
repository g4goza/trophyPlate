import Foundation

public struct PlateError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct PlateDesign: Codable, Equatable, Sendable {
    public var version = 1
    public var presenter = "Presenter Name"
    public var title1 = "An Inspiring Talk"
    public var title2 = ""
    public var date = "October 13, 2026"
    public var fontName = "Helvetica"
    public var nameSize = 19.0
    public var titleSize = 15.0
    public var dateSize = 12.0
    public var lineSpacing = 2.5
    public var margin = 4.0
    public var offsetX = 10.0
    public var offsetY = 30.0
    public var powerPercent = 40.0
    public var speed = 2000.0
    public var passes = 1
    public var scanInterval = 0.1
    // Optional encoded field keeps existing version-1 design files readable.
    public var outlineSettings: OutlineSettings? = OutlineSettings()
    public var outline: OutlineSettings {
        get { outlineSettings ?? OutlineSettings() }
        set { outlineSettings = newValue }
    }
    public var usesOwnerTestedSettings: Bool {
        powerPercent == 40 && speed == 2000 && passes == 1 && scanInterval == 0.1
    }
    public init() {}
    public func validatePlacement() throws {
        guard offsetX.isFinite, offsetY.isFinite, (0...20).contains(offsetX), (0...60).contains(offsetY) else {
            throw PlateError("The 80 × 40 mm plate must fit inside the 100 × 100 mm workspace.")
        }
    }
    public func validate() throws {
        guard version == 1 else { throw PlateError("Unsupported design version.") }
        try validatePlacement()
        try outline.validate()
        for text in [presenter, title1, date] {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlateError("Enter a presenter, title and date.") }
        }
        guard [presenter,title1,title2,date].allSatisfy({ $0.count <= 500 && !$0.contains("\n") && !$0.contains("\r") }) else { throw PlateError("Each field must be a single line of at most 500 characters.") }
        guard !fontName.isEmpty, fontName.count <= 200 else { throw PlateError("Choose a font.") }
        let checks: [(Double, ClosedRange<Double>)] = [(nameSize,4...72),(titleSize,4...72),(dateSize,4...72),(lineSpacing,0...10),(margin,1...15),(offsetX,0...20),(offsetY,0...60),(powerPercent,0.1...100),(speed,50...12000),(scanInterval,0.05...0.5)]
        guard checks.allSatisfy({ $0.0.isFinite && $0.1.contains($0.0) }), (1...10).contains(passes) else { throw PlateError("Settings are outside the supported ranges.") }
    }
    public static func decode(_ data: Data) throws -> PlateDesign {
        let design = try JSONDecoder().decode(PlateDesign.self, from: data)
        try design.validate()
        return design
    }
}

public struct OutlineSettings: Codable, Equatable, Sendable {
    public var powerPercent = 10.0
    public var speed = 2000.0
    public init() {}
    public func validate() throws {
        guard powerPercent.isFinite, (0.1...100).contains(powerPercent), speed.isFinite, (50...12000).contains(speed) else {
            throw PlateError("Outline power must be 0.1–100% and speed 50–12,000 mm/min.")
        }
    }
}
