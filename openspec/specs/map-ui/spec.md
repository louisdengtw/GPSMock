# map-ui Specification

## Purpose

Defines the macOS SwiftUI map surface, mode toggle, markers, speed controls, status pill, and persisted UI state that the user interacts with to drive iPhone GPS simulation.
## Requirements
### Requirement: MapKit-based map surface

The app SHALL render the primary view using SwiftUI MapKit with Apple default tiles, support pan and zoom via standard gestures, and capture single-tap to set the destination point.

#### Scenario: Tap to set destination

- **WHEN** the user single-taps anywhere on the map
- **THEN** the app SHALL place a destination marker at the tapped coordinate and update the action button label to reflect the active mode (Teleport or Walk)

#### Scenario: Pan and zoom unaffected

- **WHEN** the user pans or pinch-zooms the map
- **THEN** no destination marker SHALL be created from the gesture and existing markers SHALL retain their geographic positions

### Requirement: Mode toggle (Teleport vs Walk)

The app SHALL present a binary mode toggle that controls the action taken when the user confirms a destination, defaulting to Teleport on first launch.

#### Scenario: Teleport mode

- **WHEN** the toggle is set to Teleport and the user confirms a destination
- **THEN** the app SHALL call `POST /teleport` with the destination coordinates and SHALL NOT call OSRM

#### Scenario: Walk mode

- **WHEN** the toggle is set to Walk and the user confirms a destination
- **THEN** the app SHALL request a route from OSRM, render the polyline preview, and require a second explicit confirmation before calling `POST /walk`

### Requirement: Walk preview and confirmation

In Walk mode, the app SHALL show the OSRM (or fallback) polyline plus distance and ETA before any `/walk` call, and SHALL only dispatch the walk after the user clicks Confirm.

#### Scenario: Preview shown before walk

- **WHEN** the user taps a destination in Walk mode and OSRM (or the fallback) returns a route
- **THEN** the app SHALL display the polyline overlay, distance in meters, and ETA at the current speed setting, with Confirm and Cancel buttons

#### Scenario: Cancel preview

- **WHEN** the user clicks Cancel on the preview
- **THEN** the app SHALL remove the polyline overlay and the destination marker, returning to the idle map view, and SHALL NOT call `POST /walk`

### Requirement: Distinct markers for target and current

The app SHALL render the user-selected target point and the iPhone's current simulated location as visually distinct markers (different color or shape) so they can be distinguished when overlapping.

#### Scenario: Both markers visible

- **WHEN** a teleport or walk has occurred and a target has been set
- **THEN** the map SHALL show two markers: the target marker (user pick) and the current marker (from `/status`), each labeled in the legend

#### Scenario: Only current marker

- **WHEN** the user has just opened the app and no target is set, but `/status` reports a non-null `current`
- **THEN** the map SHALL show only the current marker

### Requirement: Speed presets and slider

The app SHALL expose three speed presets — Walk (1.3 m/s), Jog (2.7 m/s), Bike (5.0 m/s) — plus a slider in `[0.1, 10] m/s`, and SHALL persist the most recently used value across launches.

#### Scenario: Preset selection

- **WHEN** the user clicks a preset
- **THEN** the slider SHALL snap to the preset's value and that value SHALL be used as `speed_mps` for the next `/walk`

#### Scenario: Slider override

- **WHEN** the user moves the slider away from a preset
- **THEN** the preset selection SHALL deselect and the slider's current value SHALL be used as `speed_mps`

#### Scenario: Speed persisted

- **WHEN** the app exits and is relaunched
- **THEN** the speed slider SHALL load the most recently used value from `~/Library/Application Support/GPSMock/state.json`

### Requirement: Clear button

The app SHALL expose a Clear button that calls `POST /clear` and returns the iPhone to real GPS, available whenever the connection state is `sidecarUp/iPhonePresent`.

#### Scenario: Clear after teleport

- **WHEN** the user clicks Clear after a teleport
- **THEN** the app SHALL call `POST /clear`, remove the current-location marker, and the status pill SHALL show "Real GPS"

#### Scenario: Clear during walk

- **WHEN** the user clicks Clear during an active walk
- **THEN** the walk SHALL stop, `POST /clear` SHALL be called, and the current-location marker SHALL disappear within 1 second

### Requirement: Connection status pill

The app SHALL display a persistent status pill that names the current connection state (`sidecarDown`, `sidecarUp/iPhoneAbsent`, `sidecarUp/iPhonePresent`) and the next concrete remediation step when not ready.

#### Scenario: Sidecar down

- **WHEN** the connection state is `sidecarDown`
- **THEN** the pill SHALL display "Sidecar not running" and the remediation card SHALL show the literal command `python sidecar/main.py`

#### Scenario: iPhone missing

- **WHEN** the connection state is `sidecarUp/iPhoneAbsent`
- **THEN** the pill SHALL display "No iPhone detected" and the card SHALL instruct the user to connect via USB and (if not already running) run `sudo pymobiledevice3 remote tunneld`

#### Scenario: Ready state

- **WHEN** the connection state is `sidecarUp/iPhonePresent`
- **THEN** the pill SHALL display the iPhone's name (e.g., "Connected: Louis's iPhone") and no remediation card SHALL be shown

### Requirement: Status polling cadence

While the app is foregrounded, it SHALL poll `GET /status` at 1 Hz to update the current-location marker, and SHALL pause polling when the app is backgrounded.

#### Scenario: Foreground polling

- **WHEN** the app is foregrounded and `sidecarUp/iPhonePresent`
- **THEN** the app SHALL issue `GET /status` once per second and the current-location marker SHALL reflect the response within 1 second of receipt

#### Scenario: Background pause

- **WHEN** the app is sent to the background or hidden
- **THEN** `/status` polling SHALL stop until the app returns to the foreground

### Requirement: Persistent UI state

The app SHALL persist last map center, last zoom level, last speed value, and the prevent-sleep toggle value to `~/Library/Application Support/GPSMock/state.json` and SHALL restore them on next launch.

#### Scenario: First launch

- **WHEN** the app launches and `state.json` does not exist
- **THEN** the app SHALL center on a sensible default (e.g., the user's last-known macOS location, or a hard-coded fallback), the prevent-sleep toggle SHALL default to off, and the file SHALL be created on first state change

#### Scenario: Subsequent launch

- **WHEN** the app launches and a valid `state.json` exists
- **THEN** the map SHALL initialize at the saved center and zoom, the speed slider SHALL initialize to the saved value, and the prevent-sleep toggle SHALL initialize to the saved value (treating an absent `preventSleep` field as off for backward compatibility)

### Requirement: Loop-area selection in Walk mode

In Walk mode the app SHALL provide a loop-area sub-flow in which the user outlines an area by tapping an ordered sequence of waypoints on the map; while this sub-flow is active a single map tap SHALL append a waypoint to the outline instead of setting a destination. The app SHALL require at least three waypoints before a loop can be planned.

#### Scenario: Enter loop-area drawing

- **WHEN** the user activates the loop-area control in Walk mode
- **THEN** the app SHALL enter a loop-draw state, and subsequent single map taps SHALL each append a waypoint rendered as a numbered/ordered marker, with the polygon outline drawn between consecutive waypoints

#### Scenario: Append waypoints

- **WHEN** the user taps the map three or more times while in the loop-draw state
- **THEN** the app SHALL show all waypoints in tap order connected by an outline that visually closes back to the first waypoint, and SHALL enable loop planning

#### Scenario: Waypoint soft cap

- **WHEN** the user has placed the maximum supported number of loop waypoints (25) and taps the map again
- **THEN** the app SHALL NOT append a further waypoint, SHALL keep the existing outline, and SHALL surface a message that the loop area is limited to 25 points

#### Scenario: Remove the last waypoint

- **WHEN** the user invokes "remove last" (or equivalent) while waypoints exist
- **THEN** the app SHALL drop the most recently added waypoint and redraw the outline

#### Scenario: Exit loop-area drawing

- **WHEN** the user presses Esc, switches mode away from Walk, or invokes Cancel while in the loop-draw state
- **THEN** the app SHALL discard the in-progress waypoints and any loop preview and return to the idle Walk view, without calling `POST /walk`

### Requirement: Loop preview and continuous walking

In loop-area mode, before any `/walk` call the app SHALL show the planned closed-loop polyline with per-lap distance and ETA, and SHALL only start looping after the user clicks Confirm. Once confirmed the app SHALL dispatch `POST /walk` with `loop: true` and SHALL surface a Stop control that halts the loop.

#### Scenario: Loop preview before confirm

- **WHEN** the user has three or more waypoints and loop planning succeeds (via OSRM round-trip or the closed-polygon fallback)
- **THEN** the app SHALL render the closed-loop polyline, display per-lap distance and ETA at the current speed, and present Confirm and Cancel buttons, with the preview panel docked so it does not occlude the loop

#### Scenario: Confirm starts continuous loop

- **WHEN** the user clicks Confirm on the loop preview
- **THEN** the app SHALL call `POST /walk` with the closed-loop points and `loop: true`, and the status pill SHALL reflect an ongoing walk for as long as the loop runs

#### Scenario: Stop the loop

- **WHEN** the user clicks Stop while a loop is running
- **THEN** the app SHALL cancel the loop (via `POST /clear`), the iPhone SHALL stop moving, and the app SHALL return to the idle Walk view

#### Scenario: Single-walk flow unaffected

- **WHEN** the user plans an ordinary single-destination walk (does not enter loop-area drawing)
- **THEN** the existing tap-destination → preview → Confirm flow SHALL behave exactly as before and SHALL dispatch `POST /walk` without `loop: true`

### Requirement: Editable walk start point

In Walk mode, while a route preview is shown, the app SHALL expose the start point as an explicitly labeled, draggable map handle, and SHALL provide preview-panel actions to (a) pick a new start by tapping the map and (b) reset the start to the default origin chain.

#### Scenario: Start handle is labeled

- **WHEN** a walk route preview is on screen
- **THEN** the start point SHALL be rendered as a green map annotation with the title "Start", visually distinct from the destination marker

#### Scenario: First-time drag hint

- **WHEN** the user sees a walk route preview for the first time on this Mac (no `seenStartHint` flag in `state.json`)
- **THEN** the app SHALL display a one-time tooltip near the start handle reading "Drag to change start" and SHALL persist `seenStartHint: true` so the hint does not appear on subsequent previews

#### Scenario: Drag start to new coordinate

- **WHEN** the user drags the start handle to a new map coordinate
- **THEN** the app SHALL set `customOrigin` to that coordinate and SHALL re-plan the route from the new origin to the existing destination

#### Scenario: "Set start here" picker

- **WHEN** the user clicks "Set start here" in the preview panel
- **THEN** the app SHALL enter a `pickingStart` state in which the next single tap on the map sets `customOrigin` to the tapped coordinate (instead of replacing the destination), re-plans the route, and exits the picking state

#### Scenario: Cancel picker

- **WHEN** the user is in the `pickingStart` state and either clicks the same button again, presses Esc, or switches mode away from Walk
- **THEN** the app SHALL exit the `pickingStart` state without changing `customOrigin`, and the next map tap SHALL revert to setting the destination

#### Scenario: Reset start to default

- **WHEN** the user clicks "Reset start to GPS" in the preview panel and `customOrigin` is currently set
- **THEN** the app SHALL clear `customOrigin`, re-plan using the default origin chain (iPhone simulated GPS → Mac CoreLocation → map center), and the button SHALL be hidden when `customOrigin` is nil

### Requirement: Prevent computer sleep toggle

The app SHALL expose a user-controllable setting that, when enabled, prevents the Mac from entering user-idle system sleep for as long as the GPSMock process is running. The setting SHALL default to off on first launch and SHALL persist across launches in `~/Library/Application Support/GPSMock/state.json` under the key `preventSleep`.

#### Scenario: Toggle on while app is open

- **WHEN** the user enables the "Prevent computer from sleeping while GPSMock is open" toggle
- **THEN** the app SHALL acquire a system-sleep-prevention assertion (equivalent to `kIOPMAssertPreventUserIdleSystemSleep`) and SHALL hold it until the toggle is turned off or the app exits

#### Scenario: Toggle off

- **WHEN** the user disables the toggle while the assertion is held
- **THEN** the app SHALL release the assertion within one second and the Mac SHALL be free to follow its normal idle-sleep policy

#### Scenario: App exit releases assertion

- **WHEN** the GPSMock process terminates (normal quit, window close, or crash)
- **THEN** any held sleep-prevention assertion SHALL be released so the system is not kept awake by a non-running app

#### Scenario: Setting persisted

- **WHEN** the user enables the toggle, quits, and relaunches the app
- **THEN** the toggle SHALL be on after relaunch and the assertion SHALL be re-acquired before the first user interaction

#### Scenario: Display sleep unaffected

- **WHEN** the toggle is enabled and the user does not touch the Mac for the system's display-sleep timeout
- **THEN** the display MAY still sleep, but the system SHALL NOT enter idle sleep and the simulated walk SHALL continue running

