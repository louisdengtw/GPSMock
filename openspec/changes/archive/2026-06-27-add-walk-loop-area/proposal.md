## Why

Walk mode today plays a single origin→destination route once and stops on the final point. Users who want to simulate sustained activity inside a fixed area — staying "alive and moving" within a neighborhood rather than travelling somewhere — have no way to do it: they must keep re-issuing walks by hand, and each new walk teleports back to a start point, producing visible jumps. There is no way to say "wander around this area and keep going until I stop you."

## What Changes

- Add a **Loop area** sub-mode to Walk: the user taps three or more points on the map to outline a polygon, the app routes a closed loop through those waypoints along real walking paths, and the iPhone walks that loop **continuously until the user explicitly stops it**.
- Extend OSRM routing from two-point only to an ordered **multi-waypoint round-trip**: the app SHALL request a route through `p0;p1;…;pN;p0` so the returned polyline returns to its own start, making each lap seamless. The existing two-point `route` path is unchanged.
- Extend the sidecar `/walk` endpoint and `Walker` with an additive `loop` flag. When `loop: true`, the walker replays the polyline indefinitely (lap after lap, no land-on-final-point stop) until cancelled by `/clear`, `/teleport`, or a new walk. When absent/false, behavior is exactly as today.
- Surface loop control in the UI: a way to enter loop-area drawing, add/clear waypoints, a preview of the closed-loop polyline with per-lap distance and ETA, a Confirm that starts the loop, and a Stop affordance while looping.
- Persisted state and teleport mode are untouched. A non-looping single walk keeps its current "stop on final point" behavior.

## Capabilities

### New Capabilities
<!-- None — this extends existing capabilities. -->

### Modified Capabilities
- `route-planning`: the "OSRM foot routing" requirement gains an ordered multi-waypoint round-trip request used by loop-area planning, with the same 3 s timeout and straight-line fallback (fallback connects the waypoints in order and closes back to the first).
- `gps-simulation`: the "Walk endpoint" requirement gains an optional `loop` flag; when set, the walker repeats the polyline indefinitely and only stops on cancel/teleport/replacement rather than on the final point.
- `map-ui`: a new loop-area selection and control flow is added to Walk mode — outline-by-tapping, closed-loop preview, Confirm to start continuous looping, and an explicit Stop.

## Impact

- **App code**:
  - `app/Sources/Models/OSRMClient.swift`: add a multi-waypoint round-trip route function (ordered waypoints, closes back to the first), reusing the existing GeoJSON parsing and straight-line fallback.
  - `app/Sources/Models/SidecarClient.swift`: `walk(points:speedMps:)` gains a `loop` parameter encoded into the `/walk` body.
  - `app/Sources/Models/AppViewModel.swift`: add loop-area interaction state (collecting waypoints), closed-loop planning, dispatch with `loop: true`, and a stop action.
  - `app/Sources/Views/MapSurface.swift`: render in-progress waypoints, the polygon outline, and the closed-loop polyline; tap appends a waypoint while in loop-draw state.
  - `app/Sources/Views/WalkPreviewSheet.swift` / `app/Sources/ContentView.swift`: loop-area entry, waypoint count / clear-last / per-lap distance + ETA, Confirm-to-loop, and Stop controls.
- **Sidecar (Python)**:
  - `sidecar/gpsmock_sidecar/main.py`: `WalkBody` gains `loop: bool = False`; `/walk` passes it to the walker.
  - `sidecar/gpsmock_sidecar/walker.py`: `Walker.start(...)` and `_run(...)` accept `loop`; when looping, wrap the segment traversal in a cancel-checked repeat and skip the no-jitter land-on-final-point step.
- **Persisted state**: none. Loop waypoints are transient interaction state, not persisted.
- **Tests**: extend `sidecar/tests/test_walker.py` and `sidecar/tests/test_endpoints.py` for the loop flag (repeats until cancelled, validation still requires ≥2 points). No automated UI tests exist; manual plan captured in `tasks.md`.
