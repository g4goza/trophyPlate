import XCTest
@testable import TrophyPlateCore
final class LayoutTests: XCTestCase {
    func testThreeAndFourLinesCentered() throws {
        for second in ["", "A Shared Future"] {
            var d = PlateDesign(); d.title2 = second
            let l = try TextLayout.make(d)
            XCTAssertEqual(l.lines.count, second.isEmpty ? 3 : 4)
            XCTAssertEqual(l.bounds.midY, 20, accuracy: 0.001)
            for line in l.lines { XCTAssertEqual(line.bounds.midX, 40, accuracy: 0.001) }
        }
    }
    func testUnicodeAndRoundTrip() throws {
        var d = PlateDesign(); d.presenter = "José García"
        _ = try TextLayout.make(d)
        let data = try JSONEncoder().encode(d)
        XCTAssertEqual(try PlateDesign.decode(data), d)
    }
    func testUnsupportedVisibleGlyphRejected() {
        var d = PlateDesign(); d.presenter = "Test 🏆"
        XCTAssertThrowsError(try TextLayout.make(d))
    }
    func testOverflow() {
        var d = PlateDesign(); d.presenter = String(repeating: "W", count: 200)
        XCTAssertThrowsError(try TextLayout.make(d))
    }
    func testInvalidNumbersAndSchema() throws {
        var d = PlateDesign(); d.margin = .nan
        XCTAssertThrowsError(try d.validate())
        d = PlateDesign(); d.version = 99
        XCTAssertThrowsError(try PlateDesign.decode(JSONEncoder().encode(d)))
        d = PlateDesign(); d.presenter = "  "
        XCTAssertThrowsError(try d.validate())
    }
}
