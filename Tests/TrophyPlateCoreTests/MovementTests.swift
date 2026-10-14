import XCTest
@testable import TrophyPlateCore
final class MovementTests: XCTestCase {
    func testXStepIsSlowAndLaserOff() throws {
        let job = try MovementJob.generate(axis:.x,machinePosition:[0,0,0],workOffset:[0,0,0],powerMaximum:1000)
        XCTAssertEqual(job.lines.filter { $0.hasPrefix("G1 ") },["G1 X2.000 Y0.000 F120.000 S0"])
        XCTAssertFalse(job.lines.contains { $0.hasPrefix("M3") || $0.hasPrefix("M4") })
        XCTAssertEqual(job.lines.first,"G21"); XCTAssertEqual(job.lines.last,"M5")
    }
    func testYStepUsesCurrentWorkPosition() throws {
        let job = try MovementJob.generate(axis:.y,machinePosition:[12,20,0],workOffset:[10,20,0],powerMaximum:1000)
        XCTAssertTrue(job.lines.contains("G1 X2.000 Y2.000 F120.000 S0"))
    }
    func testInvalidOrOutOfRangeCoordinatesRejected() {
        XCTAssertThrowsError(try MovementJob.generate(axis:.x,machinePosition:[99,0,0],workOffset:[0,0,0],powerMaximum:1000))
        XCTAssertThrowsError(try MovementJob.generate(axis:.y,machinePosition:[0,99,0],workOffset:[0,0,0],powerMaximum:1000))
        XCTAssertThrowsError(try MovementJob.generate(axis:.x,machinePosition:[.nan,0,0],workOffset:[0,0,0],powerMaximum:1000))
        XCTAssertThrowsError(try MovementJob.generate(axis:.x,machinePosition:[],workOffset:[0,0,0],powerMaximum:1000))
    }
}
extension RunnerTests {
    func testChangedMachinePositionPreventsDiagnosticMove() async throws {
        let runner = JobRunner(transport:SimulatedTransport())
        do {
            try await runner.run(lines:["G1 X2 Y0 F120 S0"],expectedMachinePosition:[1,0,0],event:{ _ in })
            XCTFail("Must reject stale position")
        } catch { XCTAssertTrue(error.localizedDescription.contains("position changed")) }
    }
}
