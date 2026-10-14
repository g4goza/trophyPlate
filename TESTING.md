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

## Physical commissioning — October 13, 2026

- USB connected to firmware 1.3a.20211103 with $30=1000, $32=1, $13=0 and Idle status.
- Owner confirmed X+ moves right and Y+ moves toward the back. The 80 × 40 mm laser-off frame returned to its plate corner.
- Power cycling left the head physically in place but reset MPos to zero. We reconnected, cleared prior confirmation, used the current head position as the new plate corner (X/Y plate offsets both zero), and re-framed before laser operation. Always re-establish placement after a power cycle.
- Pine placement guide became usable after cumulative retraces at 10%, 20% and 30%, all 2,000 mm/min. This is not evidence for a single-pass pine preset.
- Three-line coated-metal tests at 30% and 40%, 2,000 mm/min, one pass and 0.10 mm interval completed without reported errors. The owner chose 40% for subsequent plates. A subsequent production plate completed with the same settings; physical finish inspection remains the owner's check.
- The default for new designs is now 40%; existing saved settings remain unchanged.

## Remaining hardware acceptance

Physical pause/stop behavior, cable-loss handling and serial short writes under load still require controlled testing. Material results apply to the owner's tested blanks and focus setup; simulation does not model laser physics or driver timing.
