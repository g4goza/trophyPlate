import Foundation
import CoreGraphics

/// The same rectangle drives laser-off framing and board marking.
public enum PlacementMode: Sendable { case laserOff, mark }
public enum PlacementJob {
    public static func generate(design: PlateDesign, mode: PlacementMode, powerMaximum: Double) throws -> EngravingJob {
        try design.validatePlacement()
        guard powerMaximum.isFinite, powerMaximum > 0, powerMaximum <= 100000 else { throw PlateError("Invalid controller power maximum.") }
        if mode == .mark { try design.outline.validate() }
        let x = design.offsetX, y = design.offsetY
        let corners = [CGPoint(x:x,y:y),CGPoint(x:x+80,y:y),CGPoint(x:x+80,y:y+40),CGPoint(x:x,y:y+40),CGPoint(x:x,y:y)]
        func n(_ value: Double) -> String { String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value) }
        var lines = ["G21","G90","G94","M5","G0 S0","G0 X\(n(x)) Y\(n(y)) S0"]
        var strokes: [Stroke] = []
        if mode == .mark { lines.append("M4 S0") }
        for index in 1..<corners.count {
            let point = corners[index]
            if mode == .mark {
                lines.append("G1 X\(n(point.x)) Y\(n(point.y)) F\(n(design.outline.speed)) S\(n(design.outline.powerPercent/100*powerMaximum))")
            } else {
                lines.append("G0 X\(n(point.x)) Y\(n(point.y)) S0")
            }
            strokes.append(Stroke(start:corners[index-1],end:point))
        }
        lines.append("M5")
        return EngravingJob(strokes:strokes,lines:lines,estimatedSeconds:240/(mode == .mark ? design.outline.speed:2000)*60,powerMaximum:powerMaximum)
    }
}
