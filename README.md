# TrophyPlate

A native macOS app for designing **80 × 40 mm trophy plates** with centered presenter, talk title and date text. Intended for the Genmitsu Kiosk 5 W laser and painted/coated metal blanks. Three lines, or four with an optional second title line.

**Status: initial implementation. Simulation is tested; USB controller compatibility, coordinate setup and physical engraving are not yet validated.** No calibrated painted-metal power/speed presets are included.

## Requirements and build

- macOS 14 or later; developed on an Apple Silicon Mac.
- Swift 5.9 or later through Xcode or the command line tools (`xcode-select --install`).
- No third-party packages.

```sh
git clone https://github.com/g4goza/trophyPlate.git
cd trophyPlate
swift test --disable-sandbox
./scripts/build-app.sh
open build/TrophyPlate.app
```

The script creates a locally ad-hoc-signed app. It is not notarized for distribution. `swift run TrophyPlate` is also available for development.

## Without the laser

1. Leave **Simulator** selected and click **Connect**.
2. Enter the presenter, title, optional second title line and date.
3. Choose a font and adjust sizes, margins and spacing. The preview uses actual glyph outlines; long text reports overflow rather than shrinking silently.
4. Click **Generate Preview** and toggle **Engraving paths** to see the filled scan strokes.
5. Click **Run Simulation**. Pause, resume and stop are available.
6. Use **Save** and **Open** for JSON design files. Files contain design/settings only, not connection permissions or commissioned origin state.

The simulation acknowledges commands; it does not model laser physics or actual motion timing. Its completion proves the software path, not real-world engraving quality. The displayed time estimate is rough and excludes acceleration and controller buffering.

## USB connection

1. Use the Kiosk's **USB-PC** port, power adapter, and a working data cable. On the development Mac, a USB-A–to–USB-C cable established detection where C-to-C attempts did not. Accept the macOS accessory prompt.
2. Close LightBurn, CutLabX and other controller applications.
3. Choose **USB**, refresh the port list, select the device and **Connect**. Port names vary; `/dev/cu.usbserial-210` was previously detected on the owner's Mac.
4. The app uses 115200 baud, reads `$I`, `$$` and `?`, and checks identity, `$30`, `$32` and Idle status. It does not automatically home or modify firmware settings. Inspect the console if connection fails.
5. Verify the machine's origin, positive axis directions, work offsets and usable 100 × 100 mm coordinate range. Enter the plate's lower-left X/Y position. The default is X=10, Y=30, placing the plate centrally in the assumed workspace.
6. Confirm coordinate setup, then use **Frame — Laser Off** to trace the plate boundary. This is real movement with the laser off.
7. Generate a new preview, select test settings, confirm the scrap-material test and explicitly choose **Engrave Plate**.

Coordinate commissioning is essential: generated moves use the controller's current work coordinate system. This first version does not provide homing, jogging, alarm unlocking or automatic coordinate setup. If the controller's coordinate range differs from the assumed positive workspace, do not start; establish a verified work origin using the manufacturer's supported workflow first.

## First physical test

With the machine attended and its normal protective measures in place:

- Verify identity, laser mode, power scale, coordinate origin and laser-off framing first.
- Use a scrap of the actual laser-suitable painted/coated metal; establish power and speed through small tests. Engraving generally removes coating rather than cutting metal.
- Check text orientation, size, centering, coating removal and finish before engraving final plates.
- Verify pause/resume and stop behavior on a controlled test. Software Stop requests feed hold and reset, closes USB and requires reconnection. It is best effort; use physical controls if motion or laser emission continues.
- Loss of connection never automatically resumes or replays a job. Assess the workpiece before starting again.

Acknowledged commands can still be executing. The app waits for a subsequent Idle status before reporting completion. A timeout or controller error halts the queue and requires reconnection.

## Architecture

- `TrophyPlateCore`: validated document model, CoreText layout, monochrome scan conversion, G-code generation, incremental GRBL parser, state machine, simulator and POSIX USB transport.
- `TrophyPlate`: SwiftUI editor and previews, document dialogs, commissioning checks and job controls.
- `Tests/TrophyPlateCoreTests`: layout, overflow, numeric validation, encoding, generated bounds/laser-off travel, protocol fragmentation and job lifecycle.

The generator uses metric absolute coordinates, GRBL dynamic power (`M4`), explicit mm/min feed mode (`G94`), explicit zero power for travel and `M5` at completion. Power is scaled to the controller's reported `$30`. Before each job the app compares fresh power scale and work offsets against the preview/commissioning snapshot; a change requires reconnection and a new preview. Unsupported visible symbols (including color emoji without outlines) produce an explicit error rather than disappearing. The scan interval defaults to 0.10 mm. Wi-Fi, logos, camera positioning, rotary operation and CSV batches are outside this version.
