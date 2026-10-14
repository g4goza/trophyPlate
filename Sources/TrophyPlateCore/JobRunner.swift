import Foundation

public enum RunnerEvent: Sendable {
    case log(String)
    case progress(JobStateMachine)
}
public actor JobRunner {
    private let transport: any LaserTransport
    private var state = JobStateMachine(lineCount:0)
    private var parser = GRBLParser()
    private var connected = true
    public init(transport: any LaserTransport) { self.transport = transport }
    public func snapshot() -> JobStateMachine { state }
    private func query(_ command: String, timeout: TimeInterval = 5) async throws -> [String] {
        try await transport.write(command)
        let deadline = Date().addingTimeInterval(timeout)
        var replies: [String] = []
        while Date() < deadline {
            try Task.checkCancellation()
            for line in parser.append(try await transport.read()) {
                replies.append(line)
                if line.hasPrefix("error:") || line.hasPrefix("ALARM:") { throw PlateError(line) }
                if command == "?" && line.hasPrefix("<") { return replies }
                if command != "?" && line == "ok" { return replies }
            }
            try await Task.sleep(nanoseconds:10_000_000)
        }
        throw PlateError("Controller did not reply to \(command.trimmingCharacters(in:.whitespacesAndNewlines)).")
    }
    public func inspect() async throws -> ControllerInfo {
        guard connected, !state.isActive else { throw PlateError("Cannot inspect while a job is active or disconnected.") }
        // Discard stale acknowledgments before sending new queries.
        parser = GRBLParser()
        _ = try await transport.read()
        var info = ControllerInfo()
        for command in ["$I\n","$$\n","?"] {
            for line in try await query(command) { info.consume(line) }
        }
        // WCO is emitted periodically by GRBL; obtain a fresh value for commissioning.
        let offsetDeadline = Date().addingTimeInterval(3)
        while info.workOffset == nil && Date() < offsetDeadline {
            try await Task.sleep(nanoseconds:50_000_000)
            for line in try await query("?") { info.consume(line) }
        }
        _ = try info.validatedPowerMaximum()
        return info
    }
    public func run(lines: [String], expectedPowerMaximum: Double? = nil, expectedWorkOffset: [Double]? = nil, expectedMachinePosition: [Double]? = nil, acknowledgmentTimeout: TimeInterval = 120, completionTimeout: TimeInterval = 3600, event: @escaping @Sendable (RunnerEvent) -> Void) async throws {
        guard connected, !state.isActive, !lines.isEmpty else { throw PlateError("Cannot start this job.") }
        // Every run verifies fresh status and settings before issuing motion.
        let current = try await inspect()
        guard connected else { throw PlateError("Controller disconnected before job start.") }
        if let expectedPowerMaximum, current.powerMaximum != expectedPowerMaximum {
            throw PlateError("Controller power scale changed. Reconnect and regenerate the preview.")
        }
        if let expectedWorkOffset {
            guard expectedWorkOffset.count == 3, let actual = current.workOffset, actual.count == 3,
                  zip(actual,expectedWorkOffset).allSatisfy({ $0.0.isFinite && $0.1.isFinite && abs($0.0-$0.1) < 0.000001 }) else {
                throw PlateError("Controller work offset changed. Reconnect and verify plate coordinates again.")
            }
        }
        if let expectedMachinePosition {
            guard expectedMachinePosition.count == 3, let actual = current.machinePosition, actual.count == 3,
                  zip(actual,expectedMachinePosition).allSatisfy({ $0.0.isFinite && $0.1.isFinite && abs($0.0-$0.1) < 0.001 }) else {
                throw PlateError("Controller position changed. Reconnect before the movement check.")
            }
        }
        state = JobStateMachine(lineCount:lines.count); state.start()
        event(.progress(state))
        var lastAck = Date(); var lastPoll = Date.distantPast
        var drainStart: Date?
        var awaitingStatus = false
        var statusCanComplete = false
        var statusSentAt = Date.distantPast
        do {
            while state.isActive {
                try Task.checkCancellation()
                if state.canSendNextLine {
                    let command = lines[state.acknowledged]
                    state.sent(); lastAck = Date()
                    try await transport.write(command+"\n")
                }
                if !awaitingStatus && Date().timeIntervalSince(lastPoll) > 0.25 {
                    lastPoll = Date(); statusSentAt = Date()
                    awaitingStatus = true; statusCanComplete = state.phase == .draining
                    try await transport.write("?")
                }
                if awaitingStatus && Date().timeIntervalSince(statusSentAt) > 5 {
                    throw PlateError("Controller status reply timed out.")
                }
                let replies = parser.append(try await transport.read())
                for line in replies {
                    if line == "ok" { state.acknowledge(); lastAck = Date() }
                    else if line.hasPrefix("error:") || line.hasPrefix("ALARM:") || line.hasPrefix("Grbl ") { throw PlateError("Controller interrupted the job: \(line)") }
                    else if line.hasPrefix("<") {
                        let status = String(line.dropFirst().split(separator:"|").first ?? "").replacingOccurrences(of:">",with:"")
                        if status.hasPrefix("Alarm") || status.hasPrefix("Door") || status.hasPrefix("Check") { throw PlateError("Controller entered \(status).") }
                        // Match one outstanding query, and only a post-ack query can complete.
                        if awaitingStatus && statusCanComplete { state.status(status) }
                        awaitingStatus = false; statusCanComplete = false
                    }
                }
                if state.phase == .paused { lastAck = Date(); drainStart = nil }
                if state.phase == .draining && drainStart == nil { drainStart = Date(); lastPoll = Date() }
                if state.awaitingAcknowledgment && state.phase != .paused && Date().timeIntervalSince(lastAck) > acknowledgmentTimeout { throw PlateError("Acknowledgment timed out. The job will not resume automatically.") }
                if let began = drainStart, Date().timeIntervalSince(began) > completionTimeout { throw PlateError("Controller did not report Idle before the completion timeout.") }
                event(.progress(state))
                if !replies.isEmpty && !replies.allSatisfy({ $0 == "ok" || $0.hasPrefix("<") }) { replies.forEach { event(.log($0)) } }
                try await Task.sleep(nanoseconds:2_000_000)
            }
            event(.progress(state))
            if state.phase == .failed { throw PlateError(state.failure ?? "Job failed.") }
        } catch {
            state.fail(error.localizedDescription)
            event(.log(error.localizedDescription)); event(.progress(state))
            // Halt motion first; do not enqueue M5 behind buffered movement.
            try? await transport.write("!")
            throw error
        }
    }
    public func pause() async throws {
        guard state.isActive else { return }
        state.pause(); try await transport.write("!")
    }
    public func resume() async throws {
        guard state.phase == .paused else { return }
        try await transport.write("~"); state.resume()
    }
    public func stop() async {
        state.stop()
        try? await transport.write("!")
        try? await transport.write("\u{18}")
        // A reset clears the GRBL planner; reconnect/inspect before any new job.
        connected = false
        await transport.close()
    }
    public func disconnect() async {
        if state.isActive { try? await transport.write("!") }
        state.disconnect(); connected = false
        await transport.close()
    }
}
