import Foundation
public protocol LaserTransport: Sendable {
    func write(_ command: String) async throws
    func read() async throws -> String
    func close() async
}
