## MODIFIED Requirements

### Requirement: Walk preview and confirmation

In Walk mode, the app SHALL show the OSRM (or fallback) polyline plus distance and ETA before any `/walk` call, and SHALL only dispatch the walk after the user clicks Confirm. The preview UI SHALL be docked to the bottom edge of the window above the controls panel and SHALL NOT occlude the polyline at default window sizes.

#### Scenario: Preview shown before walk

- **WHEN** the user taps a destination in Walk mode and OSRM (or the fallback) returns a route
- **THEN** the app SHALL display the polyline overlay, distance in meters, and ETA at the current speed setting, with Confirm and Cancel buttons, and the preview panel SHALL be anchored to the bottom of the window so the polyline's bounding box (at default zoom) is fully visible above it

#### Scenario: Cancel preview

- **WHEN** the user clicks Cancel on the preview
- **THEN** the app SHALL remove the polyline overlay and the destination marker, returning to the idle map view, and SHALL NOT call `POST /walk`

#### Scenario: Re-plan keeps preview open

- **WHEN** a route is being re-planned (e.g., the start point changed) while a previous plan is on screen
- **THEN** the preview panel SHALL stay visible with an inline "Re-planning…" indicator, the previous polyline SHALL remain rendered at reduced opacity until the new plan arrives, and Confirm SHALL be disabled until re-planning completes

## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Persistent UI state

The app SHALL persist last map center, last zoom level, last speed value, and the `seenStartHint` flag to `~/Library/Application Support/GPSMock/state.json` and SHALL restore them on next launch. The persisted file format SHALL remain backward-compatible such that older `state.json` files without the new field decode without error.

#### Scenario: First launch

- **WHEN** the app launches and `state.json` does not exist
- **THEN** the app SHALL center on a sensible default (e.g., the user's last-known macOS location, or a hard-coded fallback) and the file SHALL be created on first state change

#### Scenario: Subsequent launch

- **WHEN** the app launches and a valid `state.json` exists
- **THEN** the map SHALL initialize at the saved center and zoom and the speed slider SHALL initialize to the saved value

#### Scenario: Old state.json without seenStartHint

- **WHEN** the app launches with a `state.json` written by a previous version that lacks the `seenStartHint` field
- **THEN** the app SHALL decode the file successfully, treat `seenStartHint` as false (hint not yet shown), and SHALL persist `seenStartHint: true` only after the user has seen the hint once
