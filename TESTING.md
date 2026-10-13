# Validation

Run `swift test --disable-sandbox` on macOS. Current suite: **23 tests**.

| Test group | Count | Coverage |
| --- | ---: | --- |
| LayoutTests | 5 | 3/4 lines, visible centering, Unicode, unsupported glyph rejection, overflow, JSON round trip, invalid settings/schema |
| EngravingTests | 4 | Workspace bounds, laser-off travel/completion, explicit G94, raster orientation, power/feed validation, alternating scan rows and passes |
| ProtocolTests | 5 | Fragmented CRLF/status parsing, settings validation, acknowledgment flow, pause/resume, disconnect/stop/error state |
| RunnerTests | 5 | Simulated commissioning/execution, controller error, invalid port, changed power scale and changed work offset |
| JobIntegrationTests | 4 | Controlled pause with outstanding acknowledgment, stop queue suppression, acknowledgment timeout, draining until fresh Idle, delayed stale Idle rejection |

Build/package: `./scripts/build-app.sh`. Validate metadata with `plutil -lint build/TrophyPlate.app/Contents/Info.plist`.

UI inspection on the development Mac exercised four-line editing, preview generation, simulator connection, pause, stop and save/open dialogs. A flipped raster preview was caught visually and fixed with a geometric regression test. Save/open restored the original presenter and four-line text after editing. The GitHub workflow builds/tests on macOS.

## Pending hardware acceptance

- USB serial configuration and controller firmware compatibility.
- Machine origin, axis directions, work coordinate offsets and laser-off boundary framing.
- Actual engraving orientation/alignment and coating removal on 80 × 40 mm blanks.
- Speed/power calibration and physical pause/stop behavior.
- Physical cable disconnect behavior, short writes and suspended serial I/O under load.

Simulation does not model the physics, real serial driver or hardware timing.
