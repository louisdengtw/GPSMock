## Context

Walk mode is a one-shot flow: the user taps a destination, the app asks OSRM for an origin→destination foot route (`OSRMClient.route`), renders the polyline, and on Confirm posts it to the sidecar's `POST /walk`. The sidecar's `Walker` plays the polyline once, lands cleanly on the final point with no jitter, sets `walking = false`, and stops (`walker.py` `_run`). There is no notion of repeating, and OSRM is only ever asked for two points.

This change adds a "keep moving inside an area" capability. The chosen shape (confirmed with the user): the user outlines an area by tapping **three or more waypoints** forming a polygon, the loop follows **real walking paths** via OSRM, and it runs **indefinitely until the user stops it**. The work spans both codebases — Swift app (UI, OSRM client, sidecar client, view model) and Python sidecar (request DTO, walker loop) — which is why this needs a design doc rather than going straight to tasks.

Key constraints from the existing system:
- OSRM is the FOSSGIS `routed-foot` instance with a hard 3 s timeout and a straight-line fallback that never throws (`OSRMClient`).
- The sidecar walker is single-flight: a new walk cancels the active one; `/teleport` and `/clear` also cancel. Status is polled via `GET /status` returning `{current, walking}`.
- The `/walk` body is validated by `WalkBody` (Pydantic) and `Walker.start` (≥2 points, speed in (0, 10]).

## Goals / Non-Goals

**Goals:**
- Let the user outline an area with ≥3 tapped waypoints and walk a closed loop through them along real foot paths.
- Make each lap seamless — no teleport/jump at the lap boundary — by closing the routed polyline back onto its own start.
- Loop continuously until the user stops it (Stop button, `/teleport`, `/clear`, or a replacing walk), with `walking: true` reported throughout.
- Keep all existing single-walk and teleport behavior byte-for-byte unchanged; the loop path is strictly additive.

**Non-Goals:**
- No fixed lap count (the user chose run-until-stopped; an `N laps` variant is out of scope).
- No geometric/circle area mode and no rectangle-drag mode — only the multi-point polygon (the user's choice).
- No persistence of loop waypoints across relaunch — they are transient interaction state.
- No change to OSRM provider, jitter model, tick rate, or speed bounds.

## Decisions

### Decision 1: Loop in the sidecar (server-side repeat), not by re-dispatching from the app

The walker replays the polyline in a `while not cancel.is_set()` wrapper when `loop=True`, rather than having the Mac app detect completion via `/status` polling and POST a fresh `/walk` each lap.

- **Why:** Re-dispatching from the app creates a seam at every lap — the status poll is ~1 Hz, so the app would notice completion late, and each new `/walk` re-publishes `points[0]` after the walker already landed on the final point, producing a visible stutter/jump and a flicker of `walking: false`. Server-side repeat keeps `walking: true` continuously and flows straight from the last segment into the next lap.
- **Alternative considered:** App-side re-dispatch. Rejected for the seam, the extra round-trips, and the race between "walk finished" and "next walk accepted" (teleport/clear could interleave).

### Decision 2: Close the loop in the route geometry, not in the walker

The app asks OSRM for a round-trip by appending the first waypoint to the request (`p0;p1;…;pN;p0`) so the returned polyline already ends where it begins. The walker just repeats whatever polyline it is given.

- **Why:** Keeps the walker dumb and generic (it already plays an arbitrary polyline; "loop" only means "repeat it"). Routing the return leg through OSRM means the closing segment also follows real paths instead of cutting straight across the polygon. Because the polyline's last point ≈ its first point, repeating it produces no positional jump.
- **Alternative considered:** Walker auto-appends `points[0]` and jumps back. Rejected — the return leg would be a straight line through buildings, defeating the "real paths" goal, and the jump would be visible.
- **Consequence:** When looping, the walker must NOT apply the existing "land on final point with no jitter" step — that step exists so a one-shot walk ends exactly on the user's destination. In a loop there is no destination; it should flow into the next lap normally.

### Decision 3: Additive `loop` flag, default false, everywhere on the wire

`WalkBody.loop: bool = False`, `Walker.start(..., loop=False)`, `SidecarClient.walk(..., loop: Bool = false)`. Absent/false reproduces today's behavior exactly.

- **Why:** Backward compatibility — an older app posting `/walk` with no `loop` field, or any single-walk path, is unchanged. Validation (≥2 points, speed bounds) is shared between loop and non-loop.
- **Alternative considered:** A separate `POST /walk_loop` endpoint. Rejected as redundant — the body and the walker logic are 95% identical; a flag is less surface area.

### Decision 4: Multi-waypoint OSRM as a new function, not a generalization of `route`

Add `OSRMClient.loopRoute(through waypoints:)` (ordered, closes back to the first) alongside the existing two-point `route(from:to:)`, sharing the GeoJSON decode and the straight-line fallback helper.

- **Why:** The two-point call site (single walk + teleport-mode preview) is hot and well-tested; leaving its signature untouched avoids churn. The loop function builds the `;`-joined coordinate path and closes it.
- **Fallback:** On any OSRM failure the loop falls back to a straight-line polygon through the waypoints in order, closed back to the first (reusing Haversine for per-lap distance) — consistent with the existing "never throws" fallback contract, surfaced with the same banner style.

### Decision 5: Loop-area drawing as a transient sub-state of Walk mode

The app gains a loop-draw interaction state (an ordered `[CLLocationCoordinate2D]` of in-progress waypoints) entered from the walk UI. While active, a map tap appends a waypoint instead of setting a destination; ≥3 waypoints enables planning the closed loop; Confirm dispatches with `loop: true`; a Stop affordance cancels via `/clear`.

- **Why:** Mirrors the existing `isPickingStart` transient-state pattern from `redesign-walk-flow`, so the gesture routing and Esc-to-cancel conventions are reused rather than reinvented.

## Risks / Trade-offs

- **OSRM round-trip with many waypoints may be slow or rejected** → keep the same 3 s timeout; on timeout/failure fall back to the straight-line closed polygon so the user always gets a usable loop. Optionally cap waypoint count in the UI (e.g., warn past ~25).
- **Degenerate polygon (waypoints collinear or all clustered)** → the closed polyline may be very short; the walker already skips sub-0.5 m segments, so a tiny loop just cycles quickly. Require ≥3 waypoints before Confirm is enabled to avoid a zero-area loop.
- **Continuous loop never stops on its own** → ensure every existing cancel path (`/clear`, `/teleport`, replacing `/walk`, app-exit `clearBestEffort`, SIGTERM) still cancels the looping walker; the `while not cancel.is_set()` check must be evaluated at the top of each lap AND each segment (it already is per-segment). Add an explicit Stop button so the user is never stuck.
- **`/status` consumers assume `walking` flips to false on completion** → with loop on it stays true by design; verify the app's status poll / UI treats a long-lived `walking: true` correctly (it already does for long walks).

## Migration Plan

Purely additive; no data migration. Ship order: sidecar first (accepts `loop`, ignored by old app), then app (sends `loop` and the loop UI). Rollback is removing the loop UI entry point — the `loop` flag can stay dormant. No persisted-state changes, so no `state.json` compatibility concerns.

## Open Questions

- Per-lap speed jitter currently re-seeds each segment; over many laps this is fine, but should lap count or elapsed time be surfaced in the UI? (Deferred — Stop + "looping" indicator is enough for v1.)
- ~~Should the UI cap the number of waypoints to keep the OSRM URL and route sane?~~ Resolved: yes — soft cap at 25 (`AppViewModel.maxLoopWaypoints`). Taps past the cap are ignored with a banner.
