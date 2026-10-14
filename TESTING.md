# Validation

Run `swift test --disable-sandbox` on macOS. Current suite: **34 tests**.

| Test group | Count | Coverage |
| --- | ---: | --- |
| LayoutTests | 5 | 3/4 lines, visible centering, Unicode, unsupported glyph rejection, overflow, JSON round trip, invalid settings/schema |
| EngravingTests | 4 | Workspace bounds, laser-off travel/completion, explicit G94, raster orientation, power/feed validation, alternating scan rows and passes |
| PlacementTests | 5 | Approved text defaults, closed 80 × 40 mm rectangle, independent outline power, laser-off framing, bounds/numeric rejection, old-file compatibility |
| MovementTests | 4 | Slow 2 mm X/Y and 10 mm X laser-off commands, work-position conversion, invalid/out-of-bounds rejection |
| ProtocolTests | 6 | Fragmented CRLF/status parsing, settings and position-report unit validation, acknowledgment flow, pause/resume, disconnect/stop/error state |
| RunnerTests | 6 | Simulated commissioning/execution, controller error, invalid port, changed power scale, changed work offset and changed machine position |
| JobIntegrationTests | 4 | Controlled pause with outstanding acknowledgment, stop queue suppression, acknowledgment timeout, draining until fresh Idle, delayed stale Idle rejection |

Build/package: `./scripts/build-app.sh`. Validate metadata with `plutil -lint build/TrophyPlate.app/Contents/Info.plist`.

UI inspection on the development Mac exercised four-line editing, preview generation, simulator connection, pause, stop and save/open dialogs. A flipped raster preview was caught visually and fixed with a geometric regression test. Save/open restored the original presenter and four-line text after editing. The new Mark Plate Outline button and orange boundary preview were exercised through a completed simulator job; the fresh editor showed the approved 30% / 2,000 mm/min / one-pass defaults. USB-mode marking confirmation was reviewed statically; no physical marking was performed. The GitHub workflow builds/tests on macOS.

## Pending hardware acceptance

- Further USB/firmware validation beyond initial read-only commissioning.

Initial physical USB commissioning on October 13, 2026 succeeded: firmware 1.3a.20211103, $30=1000, $32=1, Idle, initial MPos/WCO both zero. A laser-off X+2 mm command completed with controller-reported MPos [2,0,0] and Idle; physical direction confirmation is pending. $13=0 was read and verified. No laser-on engraving has been tested.

- Machine origin, axis directions, work coordinate offsets and laser-off boundary framing.
- Actual engraving orientation/alignment and coating removal on 80 × 40 mm blanks.
- Speed/power calibration and physical pause/stop behavior.
- Physical cable disconnect behavior, short writes and suspended serial I/O under load.

Simulation does not model the physics, real serial driver or hardware timing.
