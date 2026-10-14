import AppKit
import SwiftUI
import TrophyPlateCore

enum PlateAction { case engrave, frame, markOutline, testX, testX10, testY }

@MainActor
final class AppModel: ObservableObject {
    @Published var design = PlateDesign() {
        didSet {
            guard design != oldValue else { return }
            job = nil
            if design.offsetX != oldValue.offsetX || design.offsetY != oldValue.offsetY { originConfirmed = false }
            if design.powerPercent != oldValue.powerPercent || design.speed != oldValue.speed || design.passes != oldValue.passes || design.scanInterval != oldValue.scanInterval { materialConfirmed = false }
        }
    }
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
    @Published var showOutline = false
    @Published var message = "Simulation mode — connect the simulator to begin."
    @Published var console = ""
    @Published var phase: JobPhase = .ready
    @Published var accepted = 0
    @Published var total = 0
    @Published var info: ControllerInfo?
    private let makeTransport: (Bool, String) throws -> any LaserTransport
    init(makeTransport: @escaping (Bool, String) throws -> any LaserTransport = { simulation, port in
        if simulation { return SimulatedTransport() }
        return try SerialTransport(path:port)
    }) { self.makeTransport = makeTransport }
    private var runner: JobRunner?
    private var task: Task<Void,Never>?
    private var connectionID = UUID()
    private var lastProgress = Date.distantPast
    var layoutError: String? {
        do { _ = try TextLayout.make(design); return nil } catch { return error.localizedDescription }
    }
    var coordinatesAvailable: Bool { info?.workOffset?.count == 3 && info?.workOffset?.allSatisfy(\.isFinite) == true && info?.machinePosition?.count == 3 && info?.machinePosition?.allSatisfy(\.isFinite) == true }
    var canTestMovement: Bool { connected && !connecting && !busy && !generating && coordinatesAvailable && info?.machinePosition?.count == 3 && info?.machinePosition?.allSatisfy(\.isFinite) == true }
    var canStart: Bool { connected && !connecting && !busy && !generating && job != nil && (simulation || (coordinatesAvailable && originConfirmed && materialConfirmed)) }
    var placementError: String? {
        do { try design.validatePlacement(); return nil } catch { return error.localizedDescription }
    }
    var outlineError: String? {
        do { try design.validatePlacement(); try design.outline.validate(); return nil } catch { return error.localizedDescription }
    }
    var canFrame: Bool { connected && !connecting && !busy && !generating && placementError == nil && (simulation || (coordinatesAvailable && originConfirmed)) }
    var canMarkOutline: Bool { canFrame && outlineError == nil }
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
                let transport = try makeTransport(simulation,selectedPort)
                let session = JobRunner(transport:transport)
                runner = session
                if !simulation { try await Task.sleep(nanoseconds:1_000_000_000) }
                let detected = try await session.inspect()
                guard id == connectionID else { await session.disconnect(); return }
                info = detected; connected = true; phase = .ready
                message = simulation ? "Simulator connected. No physical laser is controlled.":"USB controller ready. Verify coordinates before motion."
                if !simulation && !coordinatesAvailable { message = "Connected, but no valid machine position and work offset were reported. Reconnect before commissioning motion." }
                log("\(detected.identity)\n$30=\(detected.powerMaximum ?? 0), $32=\(detected.laserMode ? 1:0), status=\(detected.status)")
                log("Position reports: \(detected.reportsInches == false ? "millimeters ($13=0)":"unverified")")
                log("Machine position (MPos): \(detected.machinePosition.map { String(describing:$0) } ?? "not reported")")
                log("Work offset (WCO): \(detected.workOffset.map { String(describing:$0) } ?? "not reported")")
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
    func start(_ action: PlateAction = .engrave) {
        let allowed: Bool
        switch action {
        case .engrave: allowed = canStart
        case .frame: allowed = canFrame
        case .markOutline: allowed = canMarkOutline
        case .testX, .testX10, .testY: allowed = canTestMovement
        }
        guard let runner, allowed else { return }
        let selectedJob: EngravingJob
        do {
            switch action {
            case .engrave:
                guard let job else { return }; selectedJob = job
            case .testX, .testX10, .testY:
                guard let position = info?.machinePosition, let offset = info?.workOffset else { return }
                selectedJob = try MovementJob.generate(axis:action == .testY ? .y:.x,machinePosition:position,workOffset:offset,powerMaximum:info?.powerMaximum ?? 1000,distance:action == .testX10 ? 10:2)
            case .frame, .markOutline:
                selectedJob = try PlacementJob.generate(design:design,mode:action == .frame ? .laserOff:.mark,powerMaximum:info?.powerMaximum ?? 1000)
                showOutline = true
            }
        } catch { message = error.localizedDescription; return }
        let lines = selectedJob.lines
        let seconds = max(300,selectedJob.estimatedSeconds*4+120)
        busy = true; phase = .ready; accepted = 0; total = lines.count
        switch action {
        case .testX10: message = "Moving X +10 mm at 120 mm/min — laser off…"
        case .testX: message = "Moving X +2 mm at 120 mm/min — laser off…"
        case .testY: message = "Moving Y +2 mm at 120 mm/min — laser off…"
        case .frame: message = "Tracing plate boundary with laser off…"
        case .markOutline: message = simulation ? "Simulating board outline…":"Marking plate outline on board…"
        case .engrave: message = simulation ? "Simulating engraving…":"Engraving…"
        }
        let id = connectionID
        let expectedPower = selectedJob.powerMaximum
        let expectedOffset = simulation ? nil:info?.workOffset
        let expectedPosition = simulation ? nil:info?.machinePosition
        task = Task {
            do {
                try await runner.run(lines:lines,expectedPowerMaximum:expectedPower,expectedWorkOffset:expectedOffset,expectedMachinePosition:expectedPosition,completionTimeout:seconds) { [weak self] event in
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
                    if state.phase == .completed {
                        if simulation { message = "Simulation complete." }
                        else if action == .markOutline { message = "Outline job complete. Keep the board and coordinate origin fixed when placing plates." }
                        else if action == .testX || action == .testX10 || action == .testY { message = "Movement check complete — laser off. Confirm the physical direction before continuing." }
                        else { message = "Controller reports Idle — job complete." }
                        let refreshed = try await runner.inspect()
                        guard id == connectionID else { return }
                        info = refreshed
                        log("After job — MPos: \(refreshed.machinePosition.map { String(describing:$0) } ?? "not reported"), WCO: \(refreshed.workOffset.map { String(describing:$0) } ?? "not reported")")
                    } else { message = "Job stopped." }
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
            design = try PlateDesign.decode(Data(contentsOf:url)); job = nil; originConfirmed = false; materialConfirmed = false; message = "Design opened."
        } catch { message = error.localizedDescription }
    }
}
