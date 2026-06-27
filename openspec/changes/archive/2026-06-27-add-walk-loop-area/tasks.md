## 1. Sidecar walker loop support

- [x] 1.1 In `sidecar/gpsmock_sidecar/walker.py`, add a `loop: bool = False` parameter to `Walker.start(...)` and thread it into the worker thread args alongside `points` and `speed`
- [x] 1.2 In `Walker._run(...)`, when `loop` is true, wrap the segment-traversal loop in `while not cancel.is_set():` so the polyline replays lap after lap; check `cancel.is_set()` at the top of each lap
- [x] 1.3 When `loop` is true, skip the no-jitter "land on `points[-1]`" final publish and the `completed`/finished logging — the loop only ends via cancel; keep `_walking` true across laps and set it false only in the `finally`
- [x] 1.4 Keep validation unchanged (≥2 points, speed in (0, 10]); confirm a looped polyline whose last point ≈ first point flows into the next lap with no jump

## 2. Sidecar endpoint

- [x] 2.1 In `sidecar/gpsmock_sidecar/main.py`, add `loop: bool = False` to `WalkBody`
- [x] 2.2 In the `/walk` handler, pass `body.loop` to `w.start(body.points, body.speed_mps, loop=body.loop)`; log whether the walk is looping
- [x] 2.3 Confirm `/clear`, `/teleport`, and a replacing `/walk` all still cancel a looping walker (they call `w.cancel()` / `w.start()` which already cancel)

## 3. Sidecar tests

- [x] 3.1 In `sidecar/tests/test_walker.py`, add a test that `start(points, speed, loop=True)` keeps `state()` walking and re-publishes `points[0]` after reaching the end (use the injected fake `sleeper`/`rng` and assert ≥2 laps before `cancel()`)
- [x] 3.2 Add a test that `cancel()` stops a looping walker within one tick and `walking` becomes false
- [x] 3.3 In `sidecar/tests/test_endpoints.py`, add a test that `POST /walk` with `loop: true` returns 202 and reports `walking: true`, and that omitting `loop` defaults to a one-shot walk (existing behavior)

## 4. App — OSRM multi-waypoint routing

- [x] 4.1 In `app/Sources/Models/OSRMClient.swift`, add `static func loopRoute(through waypoints: [CLLocationCoordinate2D]) async -> RoutePlan` that builds a `;`-joined `lon,lat` path of the waypoints in order with the first appended at the end (`p0;…;pN;p0`)
- [x] 4.2 Reuse the existing GeoJSON decode and `RoutePlan` mapping; share the 3 s timeout `session`
- [x] 4.3 Add a closed-polygon fallback (waypoints in order, closed back to the first) computing distance via the existing `haversine`, setting `usedFallback = true` and a fallback reason consistent with the two-point path
- [x] 4.4 Leave `route(from:to:)` untouched

## 5. App — SidecarClient loop flag

- [x] 5.1 In `app/Sources/Models/SidecarClient.swift`, add a `loop: Bool = false` parameter to `walk(points:speedMps:)` and include `loop` in the encoded `Body` struct
- [x] 5.2 Verify the default `false` keeps existing single-walk call sites byte-compatible

## 6. App — AppViewModel loop-area flow

- [x] 6.1 Add loop-draw interaction state to `AppViewModel`: `var isDrawingLoop: Bool = false`, `var loopWaypoints: [CLLocationCoordinate2D] = []`, and a derived `var canPlanLoop: Bool { loopWaypoints.count >= 3 }`
- [x] 6.2 Add `func beginDrawingLoop()` / `func cancelDrawingLoop()` (the latter clears waypoints, any loop preview, and exits the state)
- [x] 6.3 In `mapTapped(at:)`, when `isDrawingLoop` append the coordinate to `loopWaypoints` instead of setting the destination; add `func removeLastLoopWaypoint()`
- [x] 6.4 Add `func planLoop()` that calls `OSRMClient.loopRoute(through:)` and stores the result in `pendingRoute` (reuse the existing planning/`isPlanningRoute` plumbing), guarded by `canPlanLoop`
- [x] 6.5 Add `func confirmLoop()` that dispatches the planned closed-loop polyline via `SidecarClient.shared.walk(points:speedMps:loop: true)` and tracks looping state
- [x] 6.6 Add `func stopLoop()` that calls `SidecarClient.shared.clear()` and returns to the idle Walk view
- [x] 6.7 In `setMode(_:)`, clear loop-draw state when leaving `.walk`
- [x] 6.8 Add `static let maxLoopWaypoints = 25` soft cap; ignore taps past the cap with a banner, and show the cap in the loop draw sheet

## 7. App — MapSurface rendering

- [x] 7.1 In `app/Sources/Views/MapSurface.swift`, render `loopWaypoints` as ordered markers (numbered) while `isDrawingLoop`
- [x] 7.2 Draw the polygon outline connecting consecutive waypoints and closing back to the first
- [x] 7.3 When a loop `pendingRoute` exists, render its closed-loop polyline (reuse the existing polyline overlay path)
- [x] 7.4 Ensure the tap gesture routes to the loop-append branch when `isDrawingLoop` (via `mapTapped`)

## 8. App — Loop controls UI

- [x] 8.1 Add a loop-area entry control to the Walk UI (in `WalkPreviewSheet.swift` / `ContentView.swift`) that calls `beginDrawingLoop()`
- [x] 8.2 While drawing, show waypoint count, a "Remove last" action, and a "Plan loop" action enabled only when `canPlanLoop`
- [x] 8.3 In the loop preview, show per-lap distance and ETA (distance ÷ speed) with Confirm (→ `confirmLoop()`) and Cancel (→ `cancelDrawingLoop()`) buttons, docked so it does not occlude the loop
- [x] 8.4 While a loop is running, show a Stop control wired to `stopLoop()`
- [x] 8.5 Wire Esc at `ContentView` level to `cancelDrawingLoop()` when `isDrawingLoop` (compose with the existing Esc / picking-start handling so neither steals from the other)

## 9. Manual verification

- [x] 9.1 Draw a 4-point loop in a real neighborhood; confirm OSRM returns a closed foot route and the preview shows a sensible per-lap distance/ETA
- [x] 9.2 Confirm the loop and watch the iPhone walk lap after lap with no jump at the lap boundary; `/status` stays `walking: true`
- [x] 9.3 Press Stop; confirm the iPhone stops and `walking` becomes false
- [x] 9.4 Trigger a teleport and a new single walk mid-loop; confirm each cleanly cancels the loop
- [x] 9.5 Force OSRM failure (offline) and confirm the closed-polygon straight-line fallback loops correctly with the fallback banner
- [x] 9.6 Verify a normal single-destination walk is unchanged (no `loop`, stops on final point)
