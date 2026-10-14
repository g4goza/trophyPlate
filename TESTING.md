# Validation

Run `swift test --disable-sandbox` on macOS. Current suite: **43 tests**.

| Test group | Count | Coverage |
| --- | ---: | --- |
| LayoutTests | 5 | 3/4 lines, visible centering, Unicode, unsupported glyph rejection, overflow, JSON round trip, invalid settings/schema |
| EngravingTests | 4 | Workspace bounds, laser-off travel/completion, explicit G94, raster orientation, power/feed validation, alternating scan rows and passes |
| PlacementTests | 5 | Approved text defaults, closed 80 × 40 mm rectangle, independent outline power, laser-off framing, bounds/numeric rejection, old-file compatibility |
| MovementTests | 4 | Slow 2 mm X/Y and 10 mm X laser-off commands, work-position conversion, invalid/out-of-bounds rejection |
| ProtocolTests | 6 | Fragmented CRLF/status parsing, settings and position-report unit validation, acknowledgment flow, pause/resume, disconnect/stop/error state |
| RunnerTests | 6 | Simulated commissioning/execution, controller error, invalid port, changed power scale, changed work offset and changed machine position |
| AppModelTests | 9 | Text/typography confirmation persistence, placement/material invalidation, required valid MPos, all physical actions reject changed position before accepting job lines, tested/custom setting classification, boundary-newline cleanup and field-specific internal-line errors, automatic latest-edit preview, actionable blocked-job reasons |
| JobIntegrationTests | 4 | Controlled pause with outstanding acknowledgment, stop queue suppression, acknowledgment timeout, draining until fresh Idle, delayed stale Idle rejection |

Build/package: `./scripts/build-app.sh`. Validate metadata with `plutil -lint build/TrophyPlate.app/Contents/Info.plist`.

UI inspection on the development Mac exercised four-line editing, preview generation, simulator connection, pause, stop and save/open dialogs. A flipped raster preview was caught visually and fixed with a geometric regression test. Save/open restored the original presenter and four-line text after editing. The new Mark Plate Outline button and orange boundary preview were exercised through a completed simulator job; the initial editor showed the then-approved 30% / 2,000 mm/min / one-pass defaults. Those initial checks preceded the physical commissioning below. The GitHub workflow builds/tests on macOS.

## Physical commissioning — October 13, 2026

- USB connected to firmware 1.3a.20211103 with $30=1000, $32=1, $13=0 and Idle status.
- Owner confirmed X+ moves right and Y+ moves toward the back. The 80 × 40 mm laser-off frame returned to its plate corner.
- Power cycling left the head physically in place but reset MPos to zero. We reconnected, cleared prior confirmation, used the current head position as the new plate corner (X/Y plate offsets both zero), and re-framed before laser operation. Always re-establish placement after a power cycle.
- Pine placement guide became usable after cumulative retraces at 10%, 20% and 30%, all 2,000 mm/min. This is not evidence for a single-pass pine preset.
- Three-line coated-metal tests at 30% and 40%, 2,000 mm/min, one pass and 0.10 mm interval completed without reported errors. The owner chose 40% for subsequent plates. The owner approved the finish on a production plate; additional production jobs completed with the same settings. Physical finish inspection remains the owner’s check.
- The default for new designs is now 40%; existing saved settings remain unchanged.

## Remaining hardware acceptance

Physical pause/stop behavior, cable-loss handling and serial short writes under load still require controlled testing. Material results apply to the owner's tested blanks and focus setup; simulation does not model laser physics or driver timing.

## Commissioning UI update — October 14, 2026

The exact tested text settings are labeled separately from custom settings. Every physical action now checks fresh machine position against the displayed snapshot, including engraving, framing and board marking. App-level integration tests use the real runner with the simulator transport to reproduce a position reset; all three actions reject before accepting any job lines. Text edits preserve confirmations; coordinate edits, material-setting edits, loading and reconnection invalidate the relevant confirmation.

Version 0.4.0 UI verification: restored the completed plate JSON (including X/Y=0, outline30%, text40%), verified tested/custom labels switch with a power edit, reconnected USB read-only and confirmed the unchanged final MPos [22.1,28.65,0] and WCO [0,0,0]. A fresh preview generated; reconnection correctly left both confirmations cleared. No additional movement or laser job was started after the update.

## Editor usability update — October 14, 2026

Version 0.5.0 cleans pasted boundary newlines (including CRLF), trims whitespace when leaving a field, and preserves spaces while typing. Internal newlines identify the invalid field. The outline overlays text and paths. Preview paths regenerate after a 350 ms editing pause with design/connection snapshot checks; this never starts a hardware job. Blocked preview, engraving and placement actions show reasons. A missing port no longer prevents disconnecting an existing session.

UI checks used fictional sample text in Simulator mode: pasted CRLF cleanup, three/four-line auto-preview, simultaneous outline/text display, and field-specific validation. Actual screenshots are in docs/images and the illustrated user guide. No movement or laser commands were sent during these checks. Current user design was saved locally before restarting the app.
