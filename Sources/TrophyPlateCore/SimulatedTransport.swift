import Foundation
public actor SimulatedTransport: LaserTransport {
    private var buffer = ""
    private var connected = true
    private var held = false
    private var fault = false
    public init() {}
    public func injectError() { fault = true }
    public func write(_ command: String) async throws {
        guard connected else { throw PlateError("Simulated disconnect.") }
        if command == "?" { buffer += held ? "<Hold:0|MPos:0,0,0|WCO:0,0,0>\n":"<Idle|MPos:0,0,0|WCO:0,0,0>\n"; return }
        if command == "!" { held = true; return }
        if command == "~" { held = false; return }
        if command == "\u{18}" { buffer = "Grbl 1.1h ['$' for help]\n"; held = false; return }
        if command.trimmingCharacters(in:.whitespacesAndNewlines) == "$I" { buffer += "[VER:1.1h:SIMULATOR]\nok\n"; return }
        if command.trimmingCharacters(in:.whitespacesAndNewlines) == "$$" { buffer += "$13=0\n$30=1000\n$32=1\nok\n"; return }
        if fault { buffer += "error:1\n"; fault = false } else { buffer += "ok\n" }
    }
    public func read() async throws -> String {
        guard connected else { throw PlateError("Simulated disconnect.") }
        let result = buffer; buffer = ""; return result
    }
    public func close() async { connected = false; buffer = "" }
}
