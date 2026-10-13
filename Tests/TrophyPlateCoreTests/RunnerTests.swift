import XCTest
@testable import TrophyPlateCore
final class RunnerTests: XCTestCase {
    func testSimulationCommissionAndJob() async throws {
        let runner = JobRunner(transport:SimulatedTransport())
        let info = try await runner.inspect()
        XCTAssertEqual(try info.validatedPowerMaximum(),1000)
        try await runner.run(lines:["G21","G90","M5"],event:{ _ in })
        let state = await runner.snapshot()
        XCTAssertEqual(state.phase,.completed)
        XCTAssertEqual(state.acknowledged,3)
    }
    func testControllerErrorFailsJob() async throws {
        let transport = SimulatedTransport()
        let runner = JobRunner(transport:transport)
        _ = try await runner.inspect()
        await transport.injectError()
        do { try await runner.run(lines:["G21","M5"],event:{ _ in }); XCTFail("Expected failure") } catch {}
        let state = await runner.snapshot()
        XCTAssertEqual(state.phase,.failed)
        XCTAssertEqual(state.acknowledged,0)
    }
    func testInvalidPort() {
        XCTAssertThrowsError(try SerialTransport(path:"/dev/not-a-laser"))
    }
}
extension RunnerTests {
    func testChangedPowerScalePreventsSendingJob() async throws {
        let runner = JobRunner(transport:SimulatedTransport())
        do {
            try await runner.run(lines:["M4 S100"],expectedPowerMaximum:255,event:{ _ in })
            XCTFail("Must reject stale job power scale")
        } catch { XCTAssertTrue(error.localizedDescription.contains("power scale changed")) }
        let state = await runner.snapshot(); XCTAssertEqual(state.acknowledged,0)
    }
    func testChangedWorkOffsetRequiresNewCommissioning() async throws {
        let runner = JobRunner(transport:SimulatedTransport())
        do {
            try await runner.run(lines:["G0 X10 Y30 S0"],expectedWorkOffset:[1,0,0],event:{ _ in })
            XCTFail("Must reject changed coordinates")
        } catch { XCTAssertTrue(error.localizedDescription.contains("work offset changed")) }
        let state = await runner.snapshot(); XCTAssertEqual(state.acknowledged,0)
    }
}
