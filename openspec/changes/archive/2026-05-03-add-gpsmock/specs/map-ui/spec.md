## ADDED Requirements

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

The app SHALL persist last map center, last zoom level, and last speed value to `~/Library/Application Support/GPSMock/state.json` and SHALL restore them on next launch.

#### Scenario: First launch

- **WHEN** the app launches and `state.json` does not exist
- **THEN** the app SHALL center on a sensible default (e.g., the user's last-known macOS location, or a hard-coded fallback) and the file SHALL be created on first state change

#### Scenario: Subsequent launch

- **WHEN** the app launches and a valid `state.json` exists
- **THEN** the map SHALL initialize at the saved center and zoom and the speed slider SHALL initialize to the saved value
