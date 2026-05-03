## Context

Greenfield single-user macOS tool. The repo currently has only OpenSpec scaffolding; nothing is implemented. The job is to set the iPhone's system-level location to a point I pick on a map, for use with location-based apps. Apple removed `idevicelocation` and the Xcode-based location-simulation flow no longer works at the system level on iOS 17+; the only stable, non-jailbreak path today is `pymobiledevice3`'s `remote tunneld` + DVT services over a USB-tethered RemoteXPC tunnel. Tunneld must be run as root, must be a long-lived process, and is operationally awkward to embed inside a sandboxed UI app — so the architecture deliberately keeps tunneld, the sidecar, and the UI as three independent processes that the user starts in order.

Constraints driving the design:

- **iOS 17 / 18 / 26**, macOS 14+ Apple Silicon, single user, USB-tethered.
- `pymobiledevice3` is Python-only; the UI must be SwiftUI for native MapKit.
- No private Apple APIs, no jailbreak, no sideload.
- All sockets bound to `127.0.0.1`, no auth, no cloud.
- Personal-use latency budget: ≤ 1 s map-click → iPhone displays new location (excluding OSRM round-trip).

## Goals / Non-Goals

**Goals:**
- A SwiftUI app that talks to a Python sidecar over `127.0.0.1:5555` JSON HTTP and lets me teleport or walk-route the iPhone from a map click.
- A Python sidecar that wraps `pymobiledevice3` cleanly, hides DVT/tunneld details from the UI, and stays testable from `curl` alone.
- Robust connection-state UX: the app always tells me which of {sidecar, tunneld/iPhone} is missing, with the exact command to fix it.
- Auto-`/clear` on app exit so I can't leave the iPhone stuck on a fake fix.
- Walk playback that *looks* like walking on a path — interpolated along an OSRM `foot` polyline, with light speed and coordinate jitter.

**Non-Goals:**
- Auto-launching tunneld or the sidecar (root requirement + ergonomic ambiguity → user does it).
- Anti-detection logic in the tool (cooldowns, speed caps, geofences). I'll self-police.
- Multi-iPhone, multi-user, account sync, or any non-USB transport.
- iOS ≤ 16, Android, Windows/Linux.
- A reusable Python library; the sidecar is a single-purpose process.

## Decisions

### D1: Three-process split (Swift app ⇄ HTTP ⇄ Python sidecar ⇄ pymobiledevice3 tunneld)
**Choice.** Keep three processes the user launches in order: `sudo pymobiledevice3 remote tunneld` → `python sidecar/main.py` → `GPSMock.app`.
**Why over alternatives:**
- *Embed `pymobiledevice3` in-app via PythonKit / embedded interpreter*: pulls a Python runtime into the macOS bundle, makes signing/notarization painful, and tunneld's root requirement still leaks out. Rejected.
- *Rewrite the RemoteXPC client in Swift*: enormous surface area (RemoteXPC, DVT, mounter, lockdown), drifts every iOS release. Rejected as the explicit non-goal — `pymobiledevice3` is the load-bearing dependency by design.
- *Single combined CLI, no UI*: defeats the entire reason for the project (point on map, not type lat/lon). Rejected.
The split also means I can `curl` the sidecar without launching the app, which is a real debugging benefit on a tool that depends on a fragile USB stack.

### D2: HTTP+JSON between Swift and Python (not Unix socket / shared memory / gRPC)
**Choice.** FastAPI on `127.0.0.1:5555`, plain JSON, six endpoints.
**Why:** trivially testable with `curl`, no codegen, no schema toolchain, no extra runtime deps in Swift. Latency budget allows it (sub-millisecond local HTTP). gRPC was considered and rejected — overkill for six endpoints and one client.

### D3: Walk playback runs in the sidecar, not the app
**Choice.** `/walk` accepts the full polyline + `speed_mps` and the sidecar owns a worker thread that interpolates and pushes coordinates to `pymobiledevice3` at ~1 Hz. The app polls `/status` for the current point.
**Why:**
- Single source of truth for "where the iPhone thinks it is" — the sidecar.
- App can be backgrounded / minimized / briefly unresponsive without stuttering the walk.
- `pymobiledevice3` connection objects are easier to keep warm in one place.
- If the app crashes mid-walk, the sidecar still owns the cleanup path (auto-`/clear` on next connect or on its own SIGTERM handler).
*Alternative — drive coordinates from the app, sidecar is stateless*: would need to push at 1 Hz over HTTP, and pause/resume gets awkward across UI lifecycle events. Rejected.

### D4: OSRM public endpoint with hard 3 s timeout and straight-line fallback
**Choice.** Call `https://router.project-osrm.org/route/v1/foot/...`, 3 s timeout in the Swift client, on failure switch to two-point linear interpolation and surface a banner "OSRM unavailable — using straight line."
**Why:** OSRM is free, no key, and `foot` profile is the right model. Self-hosting is out of scope for v1. The straight-line fallback keeps the tool usable when the public endpoint is rate-limiting or down. Open question: `foot` coverage in Taiwan — flagged in the proposal, deferred until I hit it in practice.

### D5: Auto-`/clear` on app exit, plus best-effort cleanup on sidecar exit
**Choice.** `applicationWillTerminate` (and an `atexit` analogue around scene phase changes) fires a synchronous `/clear` to the sidecar; the sidecar handles `SIGTERM` / `SIGINT` by issuing `pymobiledevice3`'s stop-simulation and disconnecting cleanly.
**Why:** the worst failure mode of this tool is leaving the iPhone stuck on a fake fix. Two layers of cleanup mean even an app crash → sidecar `SIGTERM` from the user → still resets. Acceptance criterion #5 acknowledges that a hard `kill -9` may leave the iPhone waiting for iOS's own simulation timeout; that's acceptable.

### D6: State persistence to `~/Library/Application Support/GPSMock/state.json`
**Choice.** Plain JSON, written on UI changes (debounced ~1 s), loaded on launch. Stores last map center/zoom and selected speed preset.
**Why:** trivial, debuggable by hand, no Core Data overhead for ~5 fields. Favorites (a `COULD`) extends the same file when added.

### D7: Status polling at 1 Hz
**Choice.** Swift polls `GET /status` every 1 s while the app is foregrounded; pauses when backgrounded.
**Why:** latency target is 1 s, and the human eye doesn't need finer than that for a "current iPhone marker" on a map. WebSocket / SSE was considered — extra complexity for no perceived benefit at this poll rate. Revisit if walk playback feels jerky.

### D8: Connection-state machine surfaced explicitly in UI
States: `sidecarDown` → `sidecarUp/iPhoneAbsent` → `sidecarUp/iPhonePresent`. Each state has a single named action ("Start sidecar with `python sidecar/main.py`", "Connect iPhone & start `sudo pymobiledevice3 remote tunneld`", "Ready"). Polling for sidecar `/health` continues at 2 s on failure with backoff to 10 s.
**Why:** the most common failure isn't a code bug — it's "I forgot to start tunneld." The UI must make that diagnosable in one glance.

## Risks / Trade-offs

- **`pymobiledevice3` iOS 26 / personalized DDI behavior may differ** → Mitigation: pin a known-good `pymobiledevice3` version in `pyproject.toml`, document the upgrade procedure in `docs/setup.md`, and validate `pymobiledevice3 mounter auto-mount` on first run; surface mounter failures verbatim from the sidecar to the UI.
- **Tunneld requires `sudo` and is operationally awkward** → Mitigation: explicit "Terminal A / Terminal B / app" launch order in README and in-app onboarding card; do not attempt to wrap `sudo` from inside the app.
- **OSRM public endpoint can rate-limit or be slow** → Mitigation: hard 3 s timeout, straight-line fallback, banner warning. Self-host deferred.
- **App ↔ sidecar coupling on a fixed port (5555)** → Mitigation: hard-fail with a clear error if `5555` is taken (don't silently pick another port — that breaks the contract that you can `curl localhost:5555`).
- **iPhone left stuck on fake fix after a hard crash** → Mitigation: dual cleanup (D5). Worst case (`kill -9` of sidecar): documented as an acceptable degradation; iOS clears within ~1 minute.
- **Walk playback feels mechanical** → Mitigation: ±10–15% per-segment speed jitter, sub-meter coordinate jitter (`SHOULD`-tier, can ship without and add). Trade-off: too much jitter and the path looks drunken; tune empirically.
- **HTTP polling burns CPU when idle** → Mitigation: 1 Hz `/status` only while walking or app foregrounded; 2 s `/health` with exponential backoff to 10 s when sidecar is down.
- **No auth on the local API** → Trade-off: explicitly accepted. Bind to `127.0.0.1` only; document that any local process can drive the iPhone while the sidecar is up.

## Migration Plan

Greenfield repo — no migration. Rollback is "don't run it." Cleanup if I uninstall:

1. Quit the app (auto-`/clear` runs).
2. `Ctrl-C` the sidecar (its `SIGTERM` handler runs `/clear` again).
3. `Ctrl-C` tunneld.
4. Reboot iPhone if it somehow stays stuck (rare; iOS times out on its own within ~1 min).
5. Delete `~/Library/Application Support/GPSMock/`.

## Open Questions

- OSRM `foot` profile coverage quality in Taiwan — defer until empirically broken; if poor, fall back to `driving` profile but keep a walking speed cap.
- iOS 26 personalized DDI auto-mount behavior — validate on real hardware during sidecar bring-up; if it diverges from iOS 17–18, document the manual mount step in `docs/setup.md`.
- Sidecar crash UX in the app — v1 surfaces an error and lets the user restart it manually; revisit auto-restart only if it becomes a daily annoyance.
- Whether to pin OSRM to a self-hosted instance later — defer until public endpoint becomes a problem.
