## ADDED Requirements

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
