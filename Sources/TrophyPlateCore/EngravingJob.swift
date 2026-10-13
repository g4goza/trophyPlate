import Foundation
import CoreGraphics

public struct Stroke: Sendable {
    public let start: CGPoint
    public let end: CGPoint
}
public struct EngravingJob: Sendable {
    public let strokes: [Stroke]
    public let lines: [String]
    public let estimatedSeconds: Double
    public let powerMaximum: Double
    public static func generate(design: PlateDesign, powerMaximum: Double) throws -> EngravingJob {
        let layout = try TextLayout.make(design)
        guard powerMaximum.isFinite, powerMaximum > 0, powerMaximum <= 100000 else { throw PlateError("Invalid controller power maximum.") }
        let interval = design.scanInterval
        let width = Int(ceil(80/interval)), height = Int(ceil(40/interval))
        var pixels = [UInt8](repeating:0,count:width*height)
        let strokes: [Stroke] = try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { throw PlateError("Unable to render engraving bitmap.") }
            context.setShouldAntialias(false)
            context.scaleBy(x:1/interval,y:1/interval)
            context.setFillColor(gray:1,alpha:1)
            for line in layout.lines { context.addPath(line.path); context.fillPath() }
            let bytes = buffer.bindMemory(to:UInt8.self)
            var result: [Stroke] = []
            for row in 0..<height {
                var runs: [(Int,Int)] = []; var column = 0
                while column < width {
                    if bytes[(height-1-row)*width+column] < 128 { column += 1; continue }
                    let start = column
                    while column < width && bytes[(height-1-row)*width+column] >= 128 { column += 1 }
                    runs.append((start,column))
                }
                if row % 2 == 1 { runs.reverse() }
                for (left,right) in runs {
                    let y = (Double(row)+0.5)*interval + design.offsetY
                    let a = CGPoint(x:Double(left)*interval+design.offsetX,y:y)
                    let b = CGPoint(x:min(80,Double(right)*interval)+design.offsetX,y:y)
                    result.append(Stroke(start:row % 2 == 0 ? a:b,end:row % 2 == 0 ? b:a))
                }
            }
            return result
        }
        guard !strokes.isEmpty else { throw PlateError("No engraving strokes were generated.") }
        var lines = ["G21","G90","G94","M5","G0 S0","M4 S0"]
        var all: [Stroke] = []; var distance = 0.0; var travel = 0.0; var previous: CGPoint?
        let power = design.powerPercent/100*powerMaximum
        func number(_ n: Double) -> String { String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),n) }
        for _ in 0..<design.passes {
            for stroke in strokes {
                for p in [stroke.start,stroke.end] {
                    guard p.x.isFinite, p.y.isFinite, (0...100).contains(p.x), (0...100).contains(p.y) else { throw PlateError("Generated motion exceeds the workspace.") }
                }
                if let p = previous { travel += hypot(stroke.start.x-p.x,stroke.start.y-p.y) }
                distance += hypot(stroke.end.x-stroke.start.x,stroke.end.y-stroke.start.y)
                lines.append("G0 X\(number(stroke.start.x)) Y\(number(stroke.start.y)) S0")
                lines.append("G1 X\(number(stroke.end.x)) Y\(number(stroke.end.y)) F\(number(design.speed)) S\(number(power))")
                previous = stroke.end; all.append(stroke)
            }
        }
        lines.append("M5")
        return EngravingJob(strokes:all,lines:lines,estimatedSeconds:(distance+travel)/design.speed*60,powerMaximum:powerMaximum)
    }
}
