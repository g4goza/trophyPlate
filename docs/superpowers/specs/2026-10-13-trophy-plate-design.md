# TrophyPlate Mac app design

## Purpose and agreed scope
Create a native Apple Silicon macOS app for engraving presenter trophy plates on the user's Genmitsu Kiosk 5 W, 455 nm laser. Plates measure 80 × 40 mm within the machine's 100 × 100 mm work area. Enter a presenter name, one or two talk-title lines, and a date. Center each line horizontally and center the full text block vertically. Develop with simulated communication while the machine is unavailable; determine painted-metal power and speed through later physical tests.

The user approved this scope on October 13, 2026. USB is the initial transport. Wi-Fi is deferred until the Kiosk network protocol is verified. Previous USB detection succeeded at /dev/cu.usbserial-210, but controller identity and command responses remain unverified because sandbox restrictions blocked serial configuration.

## Application and packaging
Use Swift and SwiftUI, AppKit/CoreText/CoreGraphics for text rendering, and Darwin serial APIs. Target macOS 14 or later. Deliver a Swift package with an executable, unit tests, and a script to build a local .app bundle. Avoid external dependencies. Signing and distribution outside the user's Mac are outside this initial scope.

## Editing and layout
The editor has presenter, title line 1, optional title line 2, and date text fields. The date is editable text to permit the user's preferred format. An empty second title line yields three lines. Required empty fields prevent job generation.

Use an installed Mac font, separate name/title/date font sizes, adjustable line spacing, and default 4 mm margins. Keep plate dimensions fixed at 80 × 40 mm for this version. Measure actual font bounds; center each line's visible bounds and the combined visible block. Do not silently shrink or wrap text. Show overflow errors and disable job generation when content exceeds the margins. Convert typography from points to millimeters consistently at 72 points per inch.

Show a scaled plate preview with margin guides and a separate generated engraving-path preview. Save and open versioned JSON design files containing text, typography, margins, placement, and engraving settings. Reject malformed or unsupported files with a clear message.

## Engraving conversion
Render monochrome text into a CoreGraphics bitmap at a configurable scan interval, initially 0.10 mm. Convert marked pixel runs into horizontal filled engraving strokes. Use alternating scan direction to reduce travel, with the laser off between separate runs. Keep rasterization, layout, and G-code generation independent from transport. This initial version supports text only.

Generate metric absolute-coordinate G-code with explicit laser-off initialization and completion. Use GRBL dynamic power (M4), motion feed rates in mm/min, and explicit S0 for travel. Map power percentage to a verified controller maximum; do not assume the machine's maximum S value. Unsupported controller behavior blocks sending instead of falling back to a different laser mode automatically.

Place the plate with an editable lower-left offset in the 100 × 100 mm machine workspace, initially 10 × 30 mm. Validate all generated motion, including travel, against the work area. Machine coordinates, homing support, and actual origin must be confirmed during hardware commissioning. Never home automatically when connecting. Outline positioning uses laser-off motion only and is unavailable until coordinate setup is confirmed.

Power, speed, and pass count are editable. Initial settings are clearly labeled untested and never represented as a validated painted-metal preset. Require explicit acknowledgment of test settings before a physical job. Preview and simulation remain available without hardware.

## Connection and job lifecycle
Define a transport interface used by a simulated controller and a POSIX USB serial implementation. Enumerate USB serial callout ports without hardcoding the prior port number. Start with 115200 baud; show connection errors and controller replies in a console. Connect explicitly, then query identity, settings, and status without changing firmware settings or sending reset, homing, motion, or laser-on commands.

Validate GRBL identity, laser-mode configuration, power scale, and machine status before physical engraving. Show detected settings; do not automatically rewrite them. Keep serial I/O away from the UI thread and own the file descriptor in one component. Handle partial writes, fragmented responses, timeouts, controller errors, and disconnections.

Stream one G-code line at a time, advancing only after its acknowledgment. Progress distinguishes accepted lines from completed physical work. Continue polling status after the final acknowledgment and report completion only when the controller reports Idle. Start requires a connected validated controller, a valid generated job, confirmed coordinate setup, and an explicit user action.

Pause uses GRBL feed hold; resume requires an explicit action. Stop is best effort: request hold, stop the queue, then reset and request laser off as supported by the confirmed controller. A disconnect must never cause automatic resume or replay. Explain that software stop and disconnect cannot guarantee an immediate physical stop; the machine's physical controls remain necessary.

## Simulation
Simulation implements identity, settings, acknowledgments, status, pause, resume, stop, errors, and disconnects. Label simulated mode visibly. Never route simulated jobs to a physical port. Permit preview, generation, and simulated job execution without hardware.

## Validation
Use Swift tests for centering, three/four-line layouts, overflow, document round trips, bounds checks, power/feed validation, laser-off travel and completion, pixel-run generation, acknowledgment ordering, controller errors, timeouts, and no automatic replay. Build the executable and .app bundle on this Mac. Inspect the editor and preview when a UI surface is available; report any unperformed UI verification.

Hardware acceptance is deferred: verify controller identity/settings and origin, test laser-off positioning, then use a scrap plate to establish power/speed and confirm alignment and text quality. Verify pause/stop behavior and connection-loss handling before relying on physical engraving. Do not claim hardware compatibility or engraving quality from simulation results.

## Implementation sequence
1. Project structure, document model, typography layout, and meaningful unit tests.
2. Raster scan conversion, job validation, and path preview.
3. Simulation and job state machine.
4. Native editor, persistence, and build packaging.
5. USB transport and controller commissioning checks.
6. Build/test verification and user instructions for running and later hardware testing.

## Deferred scope
Wi-Fi, logos, arbitrary plate sizes, CSV batch jobs, camera positioning, rotary accessories, firmware updates, distribution signing, and calibrated material presets.
