import XCTest
@testable import TrophyPlateCore

private actor ControlledTransport: LaserTransport {
    var buffer = ""
    var commands: [String] = []
    var closed = false
    var allowIdle = false
    func write(_ command: String) async throws {
        if closed { throw PlateError("Disconnected") }
        commands.append(command)
        switch command {
        case "$I\n": buffer += "[VER:1.1h:TEST]\nok\n"
        case "$$\n": buffer += "$13=0\n$30=1000\n$32=1\nok\n"
        case "?": buffer += commands.contains("G21\n") && !allowIdle ? "<Run|MPos:0,0,0|WCO:0,0,0>\n":"<Idle|MPos:0,0,0|WCO:0,0,0>\n"
        default: break
        }
    }
    func read() async throws -> String {
        if closed { throw PlateError("Disconnected") }
        let out = buffer; buffer = ""; return out
    }
    func close() { closed = true }
    func ack() { buffer += "ok\n" }
    func finish() { allowIdle = true }
    func count(_ command: String) -> Int { commands.filter { $0 == command }.count }
}
final class JobIntegrationTests: XCTestCase {
    func testPauseAcknowledgmentAndStopDoNotLeakNextLine() async throws {
        let transport = ControlledTransport()
        let session = JobRunner(transport:transport)
        let run = Task { try await session.run(lines:["G21","G90","M5"],event:{ _ in }) }
        try await wait { await transport.count("G21\n") == 1 }
        try await session.pause()
        await transport.ack()
        try await wait { await session.snapshot().acknowledged == 1 }
        let before = await transport.count("G90\n"); XCTAssertEqual(before,0)
        try await session.resume()
        try await wait { await transport.count("G90\n") == 1 }
        await session.stop()
        _ = try? await run.value
        let last = await transport.count("M5\n"); XCTAssertEqual(last,0)
        let state = await session.snapshot(); XCTAssertEqual(state.phase,.stopped)
    }
    func testRealRunnerAcknowledgmentTimeout() async throws {
        let t = ControlledTransport()
        let session = JobRunner(transport:t)
        do {
            try await session.run(lines:["G21","M5"],acknowledgmentTimeout:0.05,event:{ _ in })
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        let count = await t.count("M5\n"); XCTAssertEqual(count,0)
        let state = await session.snapshot(); XCTAssertEqual(state.phase,.failed)
    }
    func testDrainingWaitsForIdle() async throws {
        let t = ControlledTransport()
        let runner = JobRunner(transport:t)
        let run = Task { try await runner.run(lines:["G21"],event:{ _ in }) }
        try await wait { await t.count("G21\n") == 1 }
        await t.ack()
        try await wait { await runner.snapshot().phase == .draining }
        try await Task.sleep(nanoseconds:300_000_000)
        let draining = await runner.snapshot(); XCTAssertEqual(draining.phase,.draining)
        await t.finish()
        try await run.value
        let completed = await runner.snapshot(); XCTAssertEqual(completed.phase,.completed)
    }
    private func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds:10_000_000)
        }
        throw PlateError("Test condition timed out")
    }
}

private actor StaleIdleTransport: LaserTransport {
    var buffer = ""
    var delayedIdle = false
    var jobSent = false
    var polls = 0
    func write(_ command: String) async throws {
        switch command {
        case "$I\n": buffer += "[VER:1.1h:TEST]\nok\n"
        case "$$\n": buffer += "$13=0\n$30=1000\n$32=1\nok\n"
        case "G21\n": jobSent = true; buffer += "ok\n"
        case "?":
            if jobSent {
                polls += 1
                if polls == 1 { delayedIdle = true }
                else { buffer += "<Run|WCO:0,0,0>\n" }
            } else { buffer += "<Idle|WCO:0,0,0>\n" }
        default: break
        }
    }
    func read() async throws -> String {
        if !buffer.isEmpty { let out = buffer; buffer = ""; return out }
        if delayedIdle { delayedIdle = false; return "<Idle|WCO:0,0,0>\n" }
        return ""
    }
    func close() {}
}
extension JobIntegrationTests {
    func testDelayedPreAcknowledgmentIdleCannotComplete() async throws {
        let runner = JobRunner(transport:StaleIdleTransport())
        do {
            try await runner.run(lines:["G21"],completionTimeout:0.1,event:{ _ in })
            XCTFail("Old Idle must not complete the job")
        } catch { XCTAssertTrue(error.localizedDescription.contains("completion timeout")) }
    }
}
