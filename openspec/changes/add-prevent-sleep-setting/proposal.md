## Why

GPSMock drives long-running iPhone walks (sometimes 30+ minutes) where the user is watching the map but not actively touching the Mac. macOS display sleep stops the foreground polling cadence and idle sleep can suspend the AppKit run loop, which interrupts the simulated walk and forces the user to wake the machine just to keep their phone moving. Adding an opt-in "prevent computer sleep while GPSMock is open" toggle removes this friction.

## What Changes

- Add a user-controllable setting "Prevent computer from sleeping while GPSMock is open" to the controls panel.
- When enabled, the app holds an `IOPMAssertion` (`kIOPMAssertPreventUserIdleSystemSleep`) for the lifetime of the app process; releases it when disabled or on app exit.
- Persist the setting alongside existing UI state (`state.json`) so it survives relaunches.
- Default is **off** so behavior is unchanged for users who don't opt in.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `map-ui`: adds a new requirement for a sleep-prevention toggle and extends the persisted UI state contract to include the toggle's value.

## Impact

- **App code**: new `SleepAssertion` helper around `IOKit.pwr_mgt`; `AppViewModel` / `StateStore` gain a `preventSleep` field; `ControlsPanel` (or a new settings affordance) gains the toggle UI; `GPSMockApp` releases the assertion on terminate.
- **Persisted state**: `~/Library/Application Support/GPSMock/state.json` gains a `preventSleep: bool` field (additive, backward-compatible).
- **Frameworks/dependencies**: links `IOKit` (system framework, no new third-party deps).
- **Sidecar / iPhone**: no impact.
