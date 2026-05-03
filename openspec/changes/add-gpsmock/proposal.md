## Why

I need a personal, reliable way to set my iPhone's system-level location to an arbitrary point picked on a map — primarily for location-based apps such as Pikmin Bloom — without jailbreaking, sideloading, or relying on flaky third-party iOS tools. iOS 17+ closed off the old Xcode/`idevicelocation` paths, but `pymobiledevice3`'s tunneld now offers a stable RemoteXPC route over USB; this change builds a small native macOS app on top of it so the workflow is "click map → phone moves" rather than "remember CLI flags."

## What Changes

- Add a new macOS-only repo containing three independently-launched processes: a SwiftUI app, a Python FastAPI sidecar, and the user-launched `pymobiledevice3 remote tunneld`.
- Add a SwiftUI map UI (MapKit) with two interaction modes: **teleport** (single point) and **walk** (OSRM `foot` route preview → confirm → interpolated playback at a selected speed).
- Add a Python sidecar exposing a small JSON HTTP API on `127.0.0.1:5555` (`/health`, `/device`, `/teleport`, `/walk`, `/clear`, `/status`) that wraps `pymobiledevice3`'s DVT location simulation.
- Add a route-planning client that calls public OSRM (`https://router.project-osrm.org`) with a 3-second timeout and falls back to straight-line interpolation on failure.
- Add connection-state surfacing in the UI for sidecar reachability and tunneld-detected iPhone, plus auto-`/clear` on app exit so the phone is never left stuck on a fake location.
- Persist UI state (last map center/zoom, speed preset) to `~/Library/Application Support/GPSMock/state.json`.
- Explicitly **out of scope**: Android, multi-device, accounts/auth, anti-detection heuristics, iOS ≤ 16, Windows/Linux, auto-launching tunneld or the sidecar.

## Capabilities

### New Capabilities
- `device-connection`: sidecar health checks, tunneld-detected iPhone discovery, USB reconnect handling, and the launch-order guidance shown when prerequisites are missing.
- `gps-simulation`: the teleport / walk / clear / status surface that mutates and reports the iPhone's simulated location through `pymobiledevice3`.
- `route-planning`: OSRM `foot` routing with timeout, straight-line fallback, and walk-playback shaping (per-segment interpolation, speed jitter, coordinate jitter).
- `map-ui`: the SwiftUI MapKit surface — point selection, mode toggle, target-vs-current markers, speed preset + slider, walk preview/confirm/cancel, and persisted view state.

### Modified Capabilities
<!-- None — this is a greenfield repo with no existing specs. -->

## Impact

- **New code**: `app/` (Xcode SwiftUI project), `sidecar/` (FastAPI + `pymobiledevice3` wrapper + walker thread), `docs/setup.md` (tunneld + Developer Mode setup).
- **Runtime dependencies**: `pymobiledevice3` (Python, requires `sudo` for tunneld), FastAPI/uvicorn, MapKit (system), public OSRM endpoint.
- **Platform**: macOS 14+ Apple Silicon host, iPhone iOS 17 / 18 / 26 with Developer Mode and Mac trusted.
- **Network**: UI ↔ sidecar bound to `127.0.0.1` only; only outbound network is OSRM. No auth (single-user local tool).
- **Operational**: user is responsible for starting `sudo pymobiledevice3 remote tunneld` and the sidecar before launching the app; the app surfaces clear errors when either is missing.
- **Risk**: `pymobiledevice3` API drift between iOS releases (notably iOS 26 personalized DDI) — flagged as an open question, not a blocker for v1.
