import XCTest
@testable import TrophyPlateCore
final class PlacementTests: XCTestCase {
    func testApprovedTextDefaults() {
        let d = PlateDesign()
        XCTAssertEqual(d.powerPercent,40)
        XCTAssertEqual(d.speed,2000)
        XCTAssertEqual(d.passes,1)
        XCTAssertEqual(d.scanInterval,0.1)
    }
    func testMarkingRectangleMatchesPlateLocationAndHasSeparatePower() throws {
        var d = PlateDesign(); d.offsetX = 5; d.offsetY = 12
        d.outline.powerPercent = 12; d.outline.speed = 1800
        let job = try PlacementJob.generate(design:d,mode:.mark,powerMaximum:1000)
        XCTAssertEqual(job.strokes.count,4)
        XCTAssertEqual(job.strokes.first?.start,CGPoint(x:5,y:12))
        XCTAssertEqual(job.strokes[0].end,CGPoint(x:85,y:12))
        XCTAssertEqual(job.strokes[1].end,CGPoint(x:85,y:52))
        XCTAssertEqual(job.strokes[2].end,CGPoint(x:5,y:52))
        XCTAssertEqual(job.strokes.last?.end,CGPoint(x:5,y:12))
        let feed = job.lines.filter { $0.hasPrefix("G1 ") }
        XCTAssertEqual(feed.count,4)
        XCTAssertTrue(feed.allSatisfy { $0.contains("F1800.000 S120.000") })
        XCTAssertTrue(job.lines.contains("G94"))
        XCTAssertEqual(job.lines.last,"M5")
        XCTAssertTrue(job.lines.filter { $0.hasPrefix("G0 ") }.allSatisfy { $0.hasSuffix("S0") })
    }
    func testLaserOffFrameNeverEnablesLaser() throws {
        let job = try PlacementJob.generate(design:PlateDesign(),mode:.laserOff,powerMaximum:1000)
        XCTAssertFalse(job.lines.contains { $0.hasPrefix("M4") || $0.hasPrefix("M3") || $0.hasPrefix("G1 ") })
        XCTAssertTrue(job.lines.filter { $0.hasPrefix("G0 ") }.allSatisfy { $0.hasSuffix("S0") })
    }
    func testOutlineDoesNotDependOnTextAndRejectsInvalidPlacement() throws {
        var d = PlateDesign(); d.presenter = ""; d.title1 = ""
        XCTAssertNoThrow(try PlacementJob.generate(design:d,mode:.mark,powerMaximum:1000))
        d.offsetX = 21
        XCTAssertThrowsError(try PlacementJob.generate(design:d,mode:.mark,powerMaximum:1000))
        d.offsetX = 0; d.outline.powerPercent = .nan
        XCTAssertThrowsError(try PlacementJob.generate(design:d,mode:.mark,powerMaximum:1000))
    }
    func testOldDesignLoadsWithOutlineDefaultsAndKeepsTextSettings() throws {
        var d = PlateDesign(); d.powerPercent = 10; d.speed = 1500
        let encoded = try JSONEncoder().encode(d)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        object.removeValue(forKey:"outlineSettings")
        let loaded = try PlateDesign.decode(JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(loaded.powerPercent,10); XCTAssertEqual(loaded.speed,1500)
        XCTAssertEqual(loaded.outline,OutlineSettings())
        XCTAssertEqual(try PlateDesign.decode(JSONEncoder().encode(d)),d)
    }
}
