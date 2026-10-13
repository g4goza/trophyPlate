import XCTest
@testable import TrophyPlateCore
final class ProtocolTests: XCTestCase {
    func testFragmentedReplies() {
        var parser = GRBLParser()
        XCTAssertEqual(parser.append("o"),[])
        XCTAssertEqual(parser.append("k\r\n<Id"),["ok"])
        XCTAssertEqual(parser.append("le|MPos:0,0,0>\n"),["<Idle|MPos:0,0,0>"])
    }
    func testControllerValidation() throws {
        var info = ControllerInfo()
        info.consume("[VER:1.1h:Kiosk]"); info.consume("$30=1000"); info.consume("$32=1"); info.consume("<Idle|MPos:0,0,0|WCO:0,0,0>")
        XCTAssertEqual(try info.validatedPowerMaximum(),1000)
        info.consume("$32=0")
        XCTAssertThrowsError(try info.validatedPowerMaximum())
    }
    func testFinalAcknowledgmentIsNotCompletion() {
        var state = JobStateMachine(lineCount:1)
        state.start(); XCTAssertTrue(state.canSendNextLine)
        state.sent(); XCTAssertFalse(state.canSendNextLine)
        state.acknowledge(); XCTAssertEqual(state.phase,.draining)
        state.status("Run"); XCTAssertEqual(state.phase,.draining)
        state.status("Idle"); XCTAssertEqual(state.phase,.completed)
    }
    func testPauseDisconnectAndErrorNeverReplay() {
        var s = JobStateMachine(lineCount:10)
        s.start(); s.sent(); s.pause(); s.acknowledge()
        XCTAssertFalse(s.canSendNextLine)
        s.resume(); XCTAssertTrue(s.canSendNextLine)
        s.disconnect(); s.resume(); XCTAssertFalse(s.canSendNextLine)
        XCTAssertEqual(s.phase,.failed)
        s = JobStateMachine(lineCount:10); s.start(); s.fail("error:1"); s.resume()
        XCTAssertFalse(s.canSendNextLine)
    }
    func testStopAndTimeout() {
        var s = JobStateMachine(lineCount:10); s.start(); s.stop(); s.acknowledge(); s.resume()
        XCTAssertEqual(s.phase,.stopped); XCTAssertFalse(s.canSendNextLine)
        s = JobStateMachine(lineCount:10); s.start(); s.fail("Timed out")
        XCTAssertEqual(s.phase,.failed)
    }
}
