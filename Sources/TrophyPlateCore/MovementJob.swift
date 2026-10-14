import Foundation
import CoreGraphics

public enum MovementAxis: Sendable { case x, y }
public enum MovementJob {
    /// One positive 0.1–10 mm step at 120 mm/min. No laser-enable commands are generated.
    public static func generate(axis: MovementAxis, machinePosition: [Double], workOffset: [Double], powerMaximum: Double, distance: Double = 2) throws -> EngravingJob {
        guard machinePosition.count == 3, workOffset.count == 3,
              (machinePosition+workOffset).allSatisfy(\.isFinite),
              distance.isFinite, (0.1...10).contains(distance), powerMaximum.isFinite, powerMaximum > 0, powerMaximum <= 100000 else {
            throw PlateError("A valid machine position, work offset and power scale are required for the movement check.")
        }
        let x = machinePosition[0]-workOffset[0], y = machinePosition[1]-workOffset[1]
        let targetX = x + (axis == .x ? distance:0), targetY = y + (axis == .y ? distance:0)
        guard [x,y,targetX,targetY].allSatisfy({ (0...100).contains($0) }) else {
            throw PlateError("The movement would leave the assumed 100 × 100 mm workspace.")
        }
        func n(_ value: Double) -> String { String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value) }
        return EngravingJob(strokes:[Stroke(start:CGPoint(x:x,y:y),end:CGPoint(x:targetX,y:targetY))],lines:["G21","G90","G94","M5","G0 S0","G1 X\(n(targetX)) Y\(n(targetY)) F120.000 S0","M5"],estimatedSeconds:distance/2,powerMaximum:powerMaximum)
    }
}
