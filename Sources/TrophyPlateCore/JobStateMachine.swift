import Foundation
public enum JobPhase: String, Sendable { case ready, running, paused, draining, completed, stopped, failed }
public struct JobStateMachine: Sendable {
    public private(set) var phase: JobPhase = .ready
    public private(set) var acknowledged = 0
    public private(set) var awaitingAcknowledgment = false
    public private(set) var failure: String?
    public let lineCount: Int
    public init(lineCount: Int) { self.lineCount = lineCount }
    public var canSendNextLine: Bool { phase == .running && !awaitingAcknowledgment && acknowledged < lineCount }
    public var isActive: Bool { [.running,.paused,.draining].contains(phase) }
    public mutating func start() { if phase == .ready && lineCount > 0 { phase = .running } }
    public mutating func sent() { if canSendNextLine { awaitingAcknowledgment = true } }
    public mutating func acknowledge() {
        guard isActive, awaitingAcknowledgment else { return }
        awaitingAcknowledgment = false; acknowledged += 1
        if acknowledged == lineCount && phase != .paused { phase = .draining }
    }
    public mutating func pause() { if phase == .running || phase == .draining { phase = .paused } }
    public mutating func resume() { if phase == .paused { phase = acknowledged == lineCount ? .draining:.running } }
    public mutating func status(_ status: String) {
        if phase == .draining && status == "Idle" { phase = .completed }
    }
    public mutating func stop() { if isActive { phase = .stopped; awaitingAcknowledgment = false } }
    public mutating func fail(_ reason: String) { if isActive { failure = reason; phase = .failed; awaitingAcknowledgment = false } }
    public mutating func disconnect() { fail("Controller disconnected. Reconnect and start a new job; no automatic replay.") }
}
