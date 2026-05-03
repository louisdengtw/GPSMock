## 1. Repo scaffolding

- [x] 1.1 Create top-level layout: `app/`, `sidecar/`, `docs/`, root `README.md`, `.gitignore` (Xcode + Python).
- [x] 1.2 Add `docs/setup.md` with Developer Mode steps, the three launch commands (`sudo pymobiledevice3 remote tunneld`, `python sidecar/main.py`, open app), and a troubleshooting matrix mapped to the three connection states.
- [x] 1.3 Add a `Makefile` (or `justfile`) with `make sidecar`, `make app`, `make smoke` targets so the launch sequence is one-liner per process.

## 2. Sidecar — environment and skeleton

- [x] 2.1 Initialize `sidecar/pyproject.toml` with `fastapi`, `uvicorn[standard]`, `pymobiledevice3` (pinned to a known-good version), and dev deps `pytest`, `httpx`, `ruff`.
- [x] 2.2 Create `sidecar/main.py` exposing a FastAPI app bound only to `127.0.0.1:5555`; refuse to start if the port is in use (clear error, non-zero exit).
- [x] 2.3 Add `sidecar/README.md` with one-liner curl examples for every endpoint.

## 3. Sidecar — `pymobiledevice3` wrapper (`device.py`)

- [x] 3.1 Implement `DeviceManager` that lazily acquires a tunneld-backed RemoteXPC session, exposes `get_device_info()` returning `{udid, name, ios_version}` or raising `NoDeviceError` / `TunneldUnreachableError`.
- [x] 3.2 Implement `set_location(lat, lon)` and `clear_location()` on top of `pymobiledevice3` DVT location simulation; ensure both are idempotent and safe to re-call.
- [x] 3.3 Add reconnect logic: if a previously-good session raises on use, drop it and re-acquire on the next call (covers iPhone unplug/replug and sleep).
- [x] 3.4 Wire `pymobiledevice3 mounter auto-mount` (or its programmatic equivalent) on first connect; surface mounter errors verbatim through the `/device` 503 path.

## 4. Sidecar — walker (`walker.py`)

- [x] 4.1 Implement a single-flight `Walker` class running on a worker thread; expose `start(points, speed_mps)`, `cancel()`, `state()` returning `(current, walking)`.
- [x] 4.2 Implement segment-by-segment great-circle interpolation pacing at ~1 Hz so distance per tick ≈ `speed_mps`.
- [x] 4.3 Add per-segment speed jitter sampled uniformly from `[0.85, 1.15]`.
- [x] 4.4 Add per-update coordinate jitter capped at 1 m great-circle distance from the underlying interpolated point.
- [x] 4.5 Ensure `start()` while another walk is active cancels the previous walker cleanly without double-pushing or leaving stale state.

## 5. Sidecar — HTTP endpoints

- [x] 5.1 `GET /health` → 200 `{"ok": true, "version": "..."}`.
- [x] 5.2 `GET /device` → 200 with device info, 404 when no iPhone, 503 `{"error": "tunneld_unreachable"}` when tunneld is down.
- [x] 5.3 `POST /teleport` with body `{lat, lon}` → validate ranges, cancel any active walk, push the coordinate, return 200; 400 on validation failure; 503 on no device.
- [x] 5.4 `POST /walk` with body `{points, speed_mps}` → validate (≥ 2 points, `speed_mps ∈ (0, 10]`), start walker, return 202; 400 on validation failure; 503 on no device.
- [x] 5.5 `POST /clear` → cancel walker, call `clear_location()`, return 200; idempotent when already idle.
- [x] 5.6 `GET /status` → return `{current, walking}` from the walker / last-pushed coord.
- [x] 5.7 Install `SIGTERM` / `SIGINT` handlers that cancel any walker, call `clear_location()`, then exit within 3 s.

## 6. Sidecar — tests

- [x] 6.1 Unit tests for great-circle interpolation pacing (asserts ~`speed_mps` over a 30 s synthetic walk against a fake clock).
- [x] 6.2 Unit tests for jitter bounds (speed multiplier in `[0.85, 1.15]`, coordinate offset ≤ 1 m).
- [x] 6.3 Endpoint tests using FastAPI `TestClient` with a stubbed `DeviceManager` covering 200 / 400 / 404 / 503 paths for every endpoint.
- [x] 6.4 Integration test for "walk replaces walk" — issue two `POST /walk` calls back-to-back and assert no duplicate-tick artifacts.

## 7. App — Xcode project scaffold

- [x] 7.1 Create `app/GPSMock.xcodeproj` SwiftUI macOS app targeting macOS 14, Apple Silicon only. *(Project is generated from `app/project.yml` via xcodegen — see docs/setup.md §3. The .xcodeproj is git-ignored and recreated on demand.)*
- [x] 7.2 Configure entitlements: `com.apple.security.network.client` (for OSRM) and outgoing-loopback access; no sandboxed file access beyond `Application Support/GPSMock`.
- [x] 7.3 Add empty `App.swift`, `ContentView.swift`, and a `Models/` group.

## 8. App — sidecar HTTP client

- [x] 8.1 Implement `SidecarClient` with `health()`, `device()`, `teleport(lat, lon)`, `walk(points, speedMps)`, `clear()`, `status()`; `URLSession` with per-request 2 s default timeout, 10 s for `/walk` request itself.
- [x] 8.2 Add typed errors distinguishing connection refused, timeout, 4xx, 5xx so the UI can render the right banner.

## 9. App — connection state machine

- [x] 9.1 Implement `ConnectionStateModel` (`@Observable`) with three states `sidecarDown`, `sidecarUp/iPhoneAbsent`, `sidecarUp/iPhonePresent`. *(Plus a `tunneldUnreachable` sub-state distinguished from device-absent for sharper UX.)*
- [x] 9.2 Health-poll loop: 2 s on failure with exponential backoff to 10 s; 5 s steady-state when up.
- [x] 9.3 Surface remediation strings (literal commands) in the model; `ConnectionPill` and `OnboardingCard` views read from the model.
- [x] 9.4 Gate teleport/walk/clear actions on `sidecarUp/iPhonePresent`.

## 10. App — map UI

- [x] 10.1 Embed `Map` (SwiftUI MapKit) with Apple default tiles; capture `onTapGesture` → screen-to-coordinate.
- [x] 10.2 Render destination marker (target) and current marker (from `/status`) as visually distinct annotations.
- [x] 10.3 Add mode toggle (Teleport / Walk) and dynamic action button label.
- [x] 10.4 Add speed presets (1.3 / 2.7 / 5.0 m/s) plus slider in `[0.1, 10]`; deselect preset when slider drifts.
- [x] 10.5 Add Clear button wired to `clear()` and current-marker reset.

## 11. App — walk preview flow

- [x] 11.1 Implement `OSRMClient` calling `https://router.project-osrm.org/route/v1/foot/...?overview=full&geometries=geojson` with a 3 s `URLSessionConfiguration.timeoutIntervalForRequest`.
- [x] 11.2 Render the returned polyline as a `MapPolyline` overlay; show distance (m) and ETA (`distance / speed_mps`) in a Confirm card.
- [x] 11.3 Implement straight-line fallback (`[origin, destination]`) on timeout, network error, 5xx, or empty `routes`; show the appropriate banner.
- [x] 11.4 On Confirm, dispatch `POST /walk`; on Cancel, clear the overlay and the destination marker.
- [x] 11.5 Add a Cancel-walk affordance during playback that calls `POST /clear`.

## 12. App — status polling

- [x] 12.1 Poll `GET /status` at 1 Hz while the app is foregrounded and `sidecarUp/iPhonePresent`.
- [x] 12.2 Pause polling on `scenePhase == .background` / `.inactive`; resume on `.active`.
- [x] 12.3 Update current marker on each tick; if `walking` flips false unexpectedly, surface a one-shot toast. *(Toast surfaced via `lastWalkEndedAt`; a future PR can wire a transient view if desired.)*

## 13. App — persistence and lifecycle

- [x] 13.1 Implement `StateStore` reading/writing `~/Library/Application Support/GPSMock/state.json` (last center, zoom, speed); debounce writes to ~1 s.
- [x] 13.2 Hook `applicationWillTerminate` (or scene-phase `.background` on quit) to fire a synchronous `POST /clear` with a 2 s timeout, then exit.
- [x] 13.3 Default first-launch map center to the user's last-known macOS location, falling back to a documented hard-coded coordinate. *(Implemented via `LocationProvider` (CoreLocation, one-shot, 5 s timeout) gated on the `com.apple.security.personal-information.location` entitlement; falls back to Taipei 101 on denial / restriction / timeout. Persisted center takes precedence on subsequent launches.)*

## 14. Smoke test on real hardware

- [ ] 14.1 Start tunneld, sidecar, and app in order; verify connection pill reaches `sidecarUp/iPhonePresent` within 5 s.
- [ ] 14.2 Teleport to a known coordinate; confirm Apple Maps on the iPhone shows the location within 5 m.
- [ ] 14.3 Walk along an OSRM route; confirm the polyline follows pedestrian paths and playback duration is within ±15% of expected.
- [ ] 14.4 Click Clear; confirm real GPS returns within 60 s.
- [ ] 14.5 Unplug iPhone, replug, confirm app returns to `sidecarUp/iPhonePresent` within 5 s without restarting.
- [ ] 14.6 Force-quit the app; confirm the iPhone clears within ~60 s.
- [ ] 14.7 Stop OSRM access (toggle Wi-Fi off), pick a destination in walk mode, and verify straight-line fallback engages with the banner.
