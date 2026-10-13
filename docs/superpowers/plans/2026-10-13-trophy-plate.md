# TrophyPlate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a native Mac editor and USB engraving controller for centered 80 × 40 mm trophy plates, usable in simulation before hardware testing.

**Architecture:** A dependency-free Swift package separates document/layout and G-code generation from transport and job execution. A SwiftUI executable uses the same job engine with either a simulated GRBL transport or a Darwin serial transport. Explicit commissioning gates prevent unverified hardware from starting engraving.

**Tech Stack:** Swift, SwiftUI, AppKit, CoreText, CoreGraphics, Darwin, XCTest; macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-13-trophy-plate-design.md`

## Global Constraints

- Plates measure 80 × 40 mm within the machine's 100 × 100 mm work area.
- Target macOS 14 or later.
- Avoid external dependencies.
- Never home automatically when connecting.
- A disconnect must never cause automatic resume or replay.
- Power, speed, and pass count are editable.
- Wi-Fi is deferred until the Kiosk network protocol is verified.
- Do not claim hardware compatibility or engraving quality from simulation results.

## Review Focus

- Long names, Unicode titles, and large fonts must produce correct visible bounds or an explicit overflow error.
- Nonfinite values in imported documents must never reach bitmap allocation or machine instructions.
- Fragmented serial replies and partial writes must preserve line boundaries and acknowledgment ordering.
- Final line acknowledgment must not be mistaken for completed physical motion.
- Pause, stop, timeout, or disconnect must never allow the next queued engraving line to escape unexpectedly.

## Files and interfaces

- `Package.swift`: library `TrophyPlateCore`, executable `TrophyPlate`, test target `TrophyPlateCoreTests`.
- `Sources/TrophyPlateCore/PlateDesign.swift`: Codable design and settings; `PlateDesign.validate() throws`.
- `Sources/TrophyPlateCore/TextLayout.swift`: `TextLayout.make(_ design: PlateDesign) throws -> PlateLayout`; visible line bounds in mm.
- `Sources/TrophyPlateCore/EngravingJob.swift`: `EngravingJob.generate(design: PlateDesign, powerMaximum: Double) throws -> EngravingJob`; strokes, G-code, bounds.
- `Sources/TrophyPlateCore/ControllerProtocol.swift`: incremental GRBL parsing and validated controller settings.
- `Sources/TrophyPlateCore/Transport.swift`: serial and simulator interface.
- `Sources/TrophyPlateCore/SerialTransport.swift`: isolated file descriptor, serial setup, bounded reads and complete writes.
- `Sources/TrophyPlateCore/SimulatedTransport.swift`: deterministic fake controller.
- `Sources/TrophyPlateCore/JobRunner.swift`: sequential acknowledgments and explicit state transitions.
- `Sources/TrophyPlate/AppModel.swift`: main-thread UI state, persistence, commissioning and job orchestration.
- `Sources/TrophyPlate/TrophyPlateApp.swift`: app entry and editor, plate/path previews, connection controls and console.
- `Tests/TrophyPlateCoreTests/`: layout, generation, parser and job lifecycle tests.
- `scripts/build-app.sh`: build and package `build/TrophyPlate.app`.
- `README.md`: running, simulation, USB setup and hardware acceptance checklist.

### Task 1: Document and text layout

- [x] Create the package and write tests before the core implementation. Required cases: three and four lines, visible centering, overflow, Unicode, invalid numeric values, JSON round trip and unsupported schema.

```swift
func testThreeLinesCentered() throws {
    let d = PlateDesign()
    let layout = try TextLayout.make(d)
    XCTAssertEqual(layout.lines.count, 3)
    for line in layout.lines {
        XCTAssertEqual(line.bounds.midX, 40, accuracy: 0.01)
    }
    XCTAssertEqual(layout.bounds.midY, 20, accuracy: 0.01)
}
func testOversizedTextRejected() {
    var d = PlateDesign()
    d.presenter = String(repeating: "W", count: 200)
    XCTAssertThrowsError(try TextLayout.make(d))
}
```

- [x] Run `swift test --filter LayoutTests`; confirm missing types fail compilation.
- [x] Implement Codable settings with finite/range checks, schema validation, and CoreText visible-bound layout. Use explicit title lines, no silent wrapping or shrinking. Empty optional title line yields three lines.
- [x] Run layout/document tests; fix until passing.

### Task 2: Raster conversion and job validation

- [x] Add tests for filled text, alternating scan runs, all laser-off travel, final M5, bounds, passes, controller power scale, invalid feeds and NaN inputs.

```swift
func testJobStaysInWorkspace() throws {
    let job = try EngravingJob.generate(design: PlateDesign(), powerMaximum: 1000)
    XCTAssertFalse(job.strokes.isEmpty)
    for stroke in job.strokes {
        XCTAssertTrue((0...100).contains(stroke.start.x))
        XCTAssertTrue((0...100).contains(stroke.start.y))
        XCTAssertTrue((0...100).contains(stroke.end.x))
        XCTAssertTrue((0...100).contains(stroke.end.y))
    }
    XCTAssertEqual(job.lines.last, "M5")
}
```

- [x] Run `swift test --filter EngravingTests`; confirm new tests fail before implementation.
- [x] Implement bounded CoreGraphics monochrome rasterization and horizontal runs at initially 0.10 mm spacing. Map design coordinates into machine offsets; produce G21/G90, explicit off initialization, M4 and feed moves, S0 travel and final M5. Reject invalid settings before memory allocation or formatting.
- [x] Run generation tests and inspect sample output for origin, power scale and laser-off transitions.

### Task 3: Protocol, simulation and job execution

- [x] Add tests for fragmented `ok`, `error`, settings and status replies; unexpected reset; one-line acknowledgment flow; pause/resume; timeout; stop; disconnect; and completion only after Idle.

```swift
func testFinalAcknowledgmentIsNotCompletion() {
    var state = JobStateMachine(lineCount: 1)
    state.start()
    state.acknowledge()
    XCTAssertEqual(state.phase, .draining)
    state.status("Idle")
    XCTAssertEqual(state.phase, .completed)
}
func testDisconnectNeverResumes() {
    var state = JobStateMachine(lineCount: 10)
    state.start()
    state.disconnect()
    XCTAssertFalse(state.canSendNextLine)
    XCTAssertEqual(state.phase, .failed)
}
```

- [x] Run `swift test --filter ProtocolTests` and `swift test --filter JobTests`; confirm failure.
- [x] Implement incremental line/status parsing, controller identity and $30/$32 validation, serializable transport commands, simulator and job state machine. Only acknowledged lines advance; retain a draining phase until Idle. Hold pauses queue advancement; resume is explicit. Stop clears the queue and never auto-replays. Mark connection loss and reset as failures requiring a fresh start.
- [x] Run the protocol and lifecycle tests, including delayed replies and injected errors.

### Task 4: Mac editor and persistence

- [x] Implement the SwiftUI app using the tested core: name, two title fields and date; font controls; margins and spacing; plate and path previews; settings; save/open; simulator controls; console and job status. Clearly distinguish simulated and USB modes.
- [x] Use the following model boundary to keep UI work on the main thread and expensive generation off it:

```swift
@MainActor
final class AppModel: ObservableObject {
    @Published var design = PlateDesign()
    @Published var message = "Simulation — hardware not connected"
    @Published var job: EngravingJob?
}
```

- [x] Disable generation on invalid designs and physical start until connection, settings, origin and untested-material acknowledgment are confirmed. Disable editing or mode changes while a job is active.
- [x] Run `swift build`; resolve compiler errors. Exercise save/open, overflow and simulated execution through the UI if UI access is available; otherwise document that UI inspection is pending.

### Task 5: USB transport and commissioning

- [x] Implement serial port enumeration, explicit 115200-baud connect, exclusive ownership, nonblocking read/write and descriptor cleanup. Use identity, settings and status queries only during connection; no automatic homing, firmware writes or reset.
- [x] Implement bounded writes preserving unwritten bytes, fragmented reply handling, read errors and timeouts. Log diagnostic replies without exposing unrelated system information.
- [x] Bind serial transport to the same tested runner. Validate GRBL laser mode, power maximum and Idle status; show controller replies and actionable failures. Confirm origin independently before enabling laser-off framing or engraving.
- [x] Test invalid port/open failures and simulator parity. Keep actual serial configuration, protocol compatibility and emergency behavior marked unverified until hardware acceptance.

### Task 6: Packaging, verification and handoff

- [x] Add a build script that runs `swift build -c release`, creates an .app bundle with an Info.plist and copies the executable. Keep build outputs ignored by Git.
- [x] Document `swift test`, `./scripts/build-app.sh`, and opening `build/TrophyPlate.app`, plus simulated and USB workflows in README.
- [x] Run `swift test` and `./scripts/build-app.sh`; confirm output exists and package metadata is valid. Review the final source for unintended laser-on motion, unbounded allocations and premature completion.
- [ ] Hardware session: read identity/settings, verify origin and laser-off plate outline, engrave a scrap plate with conservative user-selected settings, then verify pause/stop and power/speed results. Do not perform these steps without attached hardware and explicit job initiation.

## Execution choice

Recommend native execution in this chat: the layout, rasterization, protocol and UI share interfaces, and the project is small enough to review as a whole. Preserve the approved spec; do not add Wi-Fi or unrelated features.

## Repository limitation

Creating `.git` was blocked by the current sandbox. Do not repeatedly retry Git mutations; preserve all source and documentation in the requested folder. Request narrowly scoped repository access only if needed later. Building may require permission for Swift toolchain caches; prefer workspace-local build/cache paths first.
