## Context

GPSMock is a SwiftUI macOS app that drives an iPhone's simulated GPS via the local sidecar. A "walk" can run for tens of minutes while the user watches the map, leaves the laptop on the desk, and does not interact with the keyboard or trackpad. macOS's default behavior under those conditions is:

1. After `Settings → Lock Screen → Turn display off when inactive`, the display sleeps. Foreground status polling and any animations stop.
2. After the system idle-sleep timer (or when the lid is closed on a desktop-mode setup), the system suspends. The AppKit run loop pauses, the sidecar HTTP polling thread is suspended, and the simulated walk effectively freezes from the user's point of view until the Mac wakes.

There is currently no in-app way to keep the Mac awake while GPSMock is open. Users have to either change global Energy settings or run `caffeinate` from a terminal — both are friction the app should eliminate.

## Goals / Non-Goals

**Goals:**
- Add a single, opt-in toggle that prevents user-idle system sleep while GPSMock is open.
- Tie the assertion's lifetime to the toggle state and the app process; never leak the assertion across launches.
- Persist the toggle so users only set it once.
- Keep the change additive — default off, no behavioral change for existing users.

**Non-Goals:**
- Preventing display sleep (`kIOPMAssertPreventUserIdleDisplaySleep`). Out of scope; the user can still see status updates by waking the screen, and keeping the display on has higher battery cost. Can be revisited if requested.
- Auto-enabling sleep prevention only "while a walk is active." Adds state-machine complexity for marginal benefit; the toggle is the user's explicit intent and they can flip it off.
- Surfacing the assertion to the system Energy pane (we use `IOPMAssertionCreateWithName`, which already shows up under `pmset -g assertions` for debugging).

## Decisions

### Use `IOPMAssertionCreateWithName` with `kIOPMAssertPreventUserIdleSystemSleep`

- **Why**: It's the documented IOKit API for "keep the system awake while my app needs it." Equivalent to what `caffeinate -i` uses.
- **Alternatives considered**:
  - `NSProcessInfo.beginActivity(options: .idleSystemSleepDisabled, reason:)` — higher-level, but lifetime is tied to a returned token whose ownership semantics are slightly awkward to model on a long-lived toggle. IOKit's create/release pair maps cleanly to "toggle on / toggle off."
  - Shelling out to `caffeinate` — works, but spawns a child process we'd have to babysit and would surprise users (process tree pollution, codesigning implications).
- **Trade-off**: We take a direct dependency on `IOKit.pwr_mgt`. It's a system framework on every macOS install, no third-party risk.

### Encapsulate in a small `SleepAssertion` value type

- A single file (`Models/SleepAssertion.swift`) with `enable()` / `disable()` and a `deinit` that releases. Keeps IOKit calls confined to one place; the rest of the app sees a Swift API.
- Holds the `IOPMAssertionID` in a private property; `enable()` is idempotent (no-op if already held), `disable()` releases and clears.

### Persist in `state.json`, owned by `AppViewModel`

- `StateStore.Snapshot` gains an optional `preventSleep: Bool?`. Decoder treats missing as `false`, so old `state.json` files load without migration.
- `AppViewModel` exposes `preventSleep: Bool` (Observable) and a `setPreventSleep(_:)` mutator. Mutator updates the assertion immediately, then persists.
- On `init`, `AppViewModel` reads the persisted value and, if true, calls `enable()` so the assertion is up before the first frame.

### UI placement: ControlsPanel overflow menu

- Add a small gear/menu button to the right side of `ControlsPanel`'s top row, next to Clear. Inside, a `Toggle("Prevent computer from sleeping while GPSMock is open", …)`.
- **Why a menu, not a top-level toggle**: it's a "set once" preference, not a per-action control; promoting it would clutter the primary surface.
- **Alternative**: a full Settings scene. Overkill for one toggle; revisit if more preferences accumulate.

### Release on app exit

- `GPSMockApp.handleAppExit` already runs on the Quit command and on window disappear. Add an explicit `appModel.releaseSleepAssertion()` call there. Also rely on `SleepAssertion.deinit` as a backstop for crashes — the kernel releases assertions when the owning process exits, so even a hard crash will not leak.

## Risks / Trade-offs

- **Risk**: User enables the toggle, forgets, closes the lid expecting the Mac to sleep, then later notices battery drain. → Mitigation: toggle copy makes it explicit ("while GPSMock is open"); the assertion is released on quit. Document in README under "Known quirks."
- **Risk**: We hold the assertion across `applicationWillTerminate` race conditions if the user force-quits. → Mitigation: kernel auto-releases on process death; nothing leaks beyond the process lifetime.
- **Trade-off**: We do not block display sleep, so the user still has to wake the screen to see live updates. Acceptable — the goal is to keep the *walk* running, not the *screen* on.

## Migration Plan

- Additive change; no migration needed.
- Old `state.json` files continue to load (missing `preventSleep` decodes as `nil` → treated as off).
- Rollback: revert the change; the field in any user's `state.json` is ignored on older builds.
