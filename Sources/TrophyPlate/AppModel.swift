import AppKit
import SwiftUI
import TrophyPlateCore

@MainActor
final class AppModel: ObservableObject {
    @Published var design = PlateDesign() { didSet { job = nil; originConfirmed = false; materialConfirmed = false } }
    @Published var job: EngravingJob?
    @Published var simulation = true
    @Published var ports = SerialTransport.availablePorts()
    @Published var selectedPort = ""
    @Published var connected = false
    @Published var busy = false
    @Published var connecting = false
    @Published var generating = false
    @Published var originConfirmed = false
    @Published var materialConfirmed = false
    @Published var showPaths = false
    @Published var message = "Simulation mode — connect the simulator to begin."
    @Published var console = ""
    @Published var phase: JobPhase = .ready
    @Published var accepted = 0
    @Published var total = 0
    @Published var info: ControllerInfo?
    private var runner: JobRunner?
    private var task: Task<Void,Never>?
    private var connectionID = UUID()
    private var lastProgress = Date.distantPast
    var layoutError: String? {
        do { _ = try TextLayout.make(design); return nil } catch { return error.localizedDescription }
    }
    var coordinatesAvailable: Bool { info?.workOffset?.count == 3 && info?.workOffset?.allSatisfy(\.isFinite) == true }
    var canStart: Bool { connected && !connecting && !busy && !generating && job != nil && (simulation || (coordinatesAvailable && originConfirmed && materialConfirmed)) }
    var canFrame: Bool { connected && !busy && !generating && layoutError == nil && (simulation || (coordinatesAvailable && originConfirmed)) }
    func log(_ text: String) {
        console += text+"\n"
        if console.count > 20000 { console = String(console.suffix(15000)) }
    }
    func refreshPorts() {
        ports = SerialTransport.availablePorts()
        if !ports.contains(selectedPort) { selectedPort = ports.first ?? "" }
    }
    func connect() {
        guard !busy, !connecting, !generating else { return }
        connecting = true; info = nil; job = nil; originConfirmed = false; materialConfirmed = false
        let id = UUID(); connectionID = id
        Task {
            do {
                let transport: any LaserTransport
                if simulation { transport = SimulatedTransport() }
                else { transport = try SerialTransport(path:selectedPort) }
                let session = JobRunner(transport:transport)
                runner = session
                if !simulation { try await Task.sleep(nanoseconds:1_000_000_000) }
                let detected = try await session.inspect()
                guard id == connectionID else { await session.disconnect(); return }
                info = detected; connected = true; phase = .ready
                message = simulation ? "Simulator connected. No physical laser is controlled.":"USB controller ready. Verify coordinates before motion."
                if !simulation && !coordinatesAvailable { message = "Connected, but no valid work offset was reported. Reconnect before commissioning motion." }
                log("\(detected.identity)\n$30=\(detected.powerMaximum ?? 0), $32=\(detected.laserMode ? 1:0), status=\(detected.status)")
            } catch {
                if let runner { await runner.disconnect() }
                runner = nil; connected = false; message = error.localizedDescription; log(message)
            }
            connecting = false
        }
    }
    func disconnect() {
        guard !busy else { return }
        connectionID = UUID(); connected = false; info = nil; job = nil
        originConfirmed = false; materialConfirmed = false
        let old = runner; runner = nil
        Task { await old?.disconnect() }
        message = "Disconnected."
    }
    func generate() {
        guard !busy, !generating, !connecting else { return }
        generating = true
        let input = design
        let id = connectionID
        let maximum = info?.powerMaximum ?? 1000
        Task {
            do {
                let result = try await Task.detached(priority:.userInitiated) { try EngravingJob.generate(design:input,powerMaximum:maximum) }.value
                if design == input && connectionID == id { job = result; message = "Preview ready: \(result.strokes.count) engraving strokes. Timing estimate excludes acceleration." }
            } catch { message = error.localizedDescription }
            generating = false
        }
    }
    func start(frame: Bool = false) {
        guard let runner, frame ? canFrame:canStart else { return }
        let lines: [String]
        let seconds: Double
        if frame {
            let x = design.offsetX, y = design.offsetY
            func n(_ value: Double) -> String { String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value) }
            lines = ["G21","G90","M5","G0 S0","G0 X\(n(x)) Y\(n(y)) S0","G0 X\(n(x+80)) Y\(n(y)) S0","G0 X\(n(x+80)) Y\(n(y+40)) S0","G0 X\(n(x)) Y\(n(y+40)) S0","G0 X\(n(x)) Y\(n(y)) S0","M5"]
            seconds = 300
        } else {
            guard let job else { return }; lines = job.lines; seconds = max(300,job.estimatedSeconds*4+120)
        }
        busy = true; phase = .ready; accepted = 0; total = lines.count
        message = frame ? "Tracing plate boundary with laser off…":(simulation ? "Simulating engraving…":"Engraving…")
        let id = connectionID
        let expectedPower = frame ? info?.powerMaximum:job?.powerMaximum
        let expectedOffset = simulation ? nil:info?.workOffset
        task = Task {
            do {
                try await runner.run(lines:lines,expectedPowerMaximum:expectedPower,expectedWorkOffset:expectedOffset,completionTimeout:seconds) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self, self.connectionID == id else { return }
                        switch event {
                        case .log(let text): self.log(text)
                        case .progress(let state):
                            if Date().timeIntervalSince(self.lastProgress) > 0.05 || !state.isActive || self.phase != state.phase {
                                self.lastProgress = Date(); self.phase = state.phase; self.accepted = state.acknowledged
                            }
                        }
                    }
                }
                let state = await runner.snapshot()
                if id == connectionID {
                    phase = state.phase; accepted = state.acknowledged
                    message = state.phase == .completed ? (simulation ? "Simulation complete.":"Controller reports Idle — job complete."):"Job stopped."
                }
            } catch {
                if id == connectionID {
                    message = error.localizedDescription; phase = .failed
                    await runner.stop(); connected = false; info = nil
                    originConfirmed = false; materialConfirmed = false
                }
            }
            if id == connectionID { busy = false }
        }
    }
    func pauseOrResume() {
        guard let runner, busy else { return }
        Task {
            do {
                if phase == .paused { try await runner.resume() } else { try await runner.pause() }
                phase = await runner.snapshot().phase
            } catch { message = error.localizedDescription; stop() }
        }
    }
    func stop() {
        guard let runner else { return }
        // Invalidate callbacks before cancelling the old run.
        connectionID = UUID(); task?.cancel()
        connected = false; info = nil; originConfirmed = false; materialConfirmed = false
        Task {
            await runner.stop(); self.runner = nil; busy = false; phase = .stopped
            message = "Stopped. Reconnect before starting another job. Use physical controls if the machine does not stop."
        }
    }
    func save() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Trophy Plate.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try design.validate(); try JSONEncoder().encode(design).write(to:url,options:.atomic); message = "Design saved." }
        catch { message = error.localizedDescription }
    }
    func open() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json,.data]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size <= 1_000_000 else { throw PlateError("Design file is too large.") }
            design = try PlateDesign.decode(Data(contentsOf:url)); message = "Design opened."
        } catch { message = error.localizedDescription }
    }
}
