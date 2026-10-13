import XCTest
@testable import TrophyPlateCore
final class EngravingTests: XCTestCase {
    func testJobBoundsAndOffTravel() throws {
        let job = try EngravingJob.generate(design:PlateDesign(),powerMaximum:1000)
        XCTAssertFalse(job.strokes.isEmpty)
        for s in job.strokes {
            for p in [s.start,s.end] {
                XCTAssertTrue((0...100).contains(p.x)); XCTAssertTrue((0...100).contains(p.y))
            }
        }
        XCTAssertEqual(job.lines.last,"M5")
        // Starting in inverse-time mode must not change the meaning of feed settings.
        var mode = "G93"
        for command in job.lines {
            if ["G93","G94"].contains(command) { mode = command }
            if command.hasPrefix("G1 ") { XCTAssertEqual(mode,"G94"); break }
        }
        XCTAssertTrue(job.lines.filter { $0.hasPrefix("G0 ") }.allSatisfy { $0.hasSuffix("S0") })
        XCTAssertTrue(job.lines.contains { $0.hasPrefix("G1 ") && $0.contains("S300.000") })
    }
    func testRasterMatchesVisibleGlyphPositions() throws {
        var d = PlateDesign(); d.title2 = "A Shared Future"
        let layout = try TextLayout.make(d)
        let job = try EngravingJob.generate(design:d,powerMaximum:1000)
        let matching = job.strokes.filter { stroke in
            let midX = (Double(stroke.start.x)+Double(stroke.end.x))/2-d.offsetX
            let midpoint = CGPoint(x:midX,y:Double(stroke.start.y)-d.offsetY)
            return layout.lines.contains { $0.path.contains(midpoint) }
        }.count
        // Pixel quantization can place very thin edge runs just outside the outline.
        XCTAssertGreaterThan(Double(matching)/Double(job.strokes.count),0.90)
    }
    func testInvalidPowerAndPlacement() {
        XCTAssertThrowsError(try EngravingJob.generate(design:PlateDesign(),powerMaximum:.nan))
        var d = PlateDesign(); d.offsetX = 21
        XCTAssertThrowsError(try EngravingJob.generate(design:d,powerMaximum:1000))
        d = PlateDesign(); d.speed = 0
        XCTAssertThrowsError(try EngravingJob.generate(design:d,powerMaximum:1000))
    }
    func testPassesAndAlternatingRows() throws {
        let one = try EngravingJob.generate(design:PlateDesign(),powerMaximum:1000)
        var d = PlateDesign(); d.passes = 2
        let two = try EngravingJob.generate(design:d,powerMaximum:1000)
        XCTAssertEqual(two.strokes.count,one.strokes.count*2)
        XCTAssertTrue(one.strokes.contains { $0.start.x > $0.end.x })
        XCTAssertTrue(one.strokes.contains { $0.start.x < $0.end.x })
    }
}
