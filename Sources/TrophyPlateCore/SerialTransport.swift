import Foundation
import Darwin
public actor SerialTransport: LaserTransport {
    private var descriptor: Int32
    private var original: termios
    public static func availablePorts() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath:"/dev")) ?? [])
            .filter { $0.hasPrefix("cu.usb") || $0.hasPrefix("cu.wch") || $0.hasPrefix("cu.SLAB") }
            .sorted().map { "/dev/"+$0 }
    }
    public init(path: String) throws {
        guard Self.availablePorts().contains(path) else { throw PlateError("Select an available USB serial port.") }
        let fd = Darwin.open(path,O_RDWR|O_NOCTTY|O_NONBLOCK)
        guard fd >= 0 else { throw PlateError("Cannot open \(path): \(String(cString:strerror(errno)))") }
        var old = termios()
        guard tcgetattr(fd,&old) == 0 else { Darwin.close(fd); throw PlateError("Cannot read serial configuration.") }
        var settings = old
        cfmakeraw(&settings)
        settings.c_cflag |= tcflag_t(CLOCAL|CREAD)
        settings.c_cflag &= ~tcflag_t(CRTSCTS)
        cfsetispeed(&settings,speed_t(B115200)); cfsetospeed(&settings,speed_t(B115200))
        guard ioctl(fd,TIOCEXCL) == 0, tcsetattr(fd,TCSANOW,&settings) == 0 else {
            Darwin.close(fd); throw PlateError("Cannot configure serial port. Close LightBurn or other controller apps and check macOS permissions.")
        }
        descriptor = fd; original = old
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
    public func write(_ command: String) async throws {
        guard descriptor >= 0 else { throw PlateError("USB port is closed.") }
        let bytes = Array(command.utf8); var offset = 0
        let deadline = Date().addingTimeInterval(2)
        while offset < bytes.count {
            try Task.checkCancellation()
            let count = bytes.withUnsafeBytes { Darwin.write(descriptor,$0.baseAddress!.advanced(by:offset),bytes.count-offset) }
            if count > 0 { offset += count }
            else if count < 0 && errno != EAGAIN && errno != EINTR { throw PlateError("USB write failed: \(String(cString:strerror(errno)))") }
            else {
                guard Date() < deadline else { throw PlateError("USB write timed out.") }
                try await Task.sleep(nanoseconds:5_000_000)
                guard descriptor >= 0 else { throw PlateError("USB port is closed.") }
            }
        }
    }
    public func read() async throws -> String {
        guard descriptor >= 0 else { throw PlateError("USB port is closed.") }
        var bytes = [UInt8](repeating:0,count:8192)
        let count = Darwin.read(descriptor,&bytes,bytes.count)
        if count > 0 { return String(decoding:bytes.prefix(count),as:UTF8.self) }
        if count == 0 { throw PlateError("USB device disconnected.") }
        if errno == EAGAIN || errno == EINTR { return "" }
        throw PlateError("USB read failed: \(String(cString:strerror(errno)))")
    }
    public func close() async {
        if descriptor >= 0 {
            _ = tcsetattr(descriptor,TCSANOW,&original)
            Darwin.close(descriptor); descriptor = -1
        }
    }
}
