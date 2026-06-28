## ADDED Requirements

### Requirement: Prevent computer sleep toggle

The app SHALL expose a user-controllable setting that, when enabled, prevents the Mac from entering user-idle system sleep for as long as the GPSMock process is running. The setting SHALL default to off on first launch and SHALL persist across launches in `~/Library/Application Support/GPSMock/state.json` under the key `preventSleep`.

#### Scenario: Toggle on while app is open

- **WHEN** the user enables the "Prevent computer from sleeping while GPSMock is open" toggle
- **THEN** the app SHALL acquire a system-sleep-prevention assertion (equivalent to `kIOPMAssertPreventUserIdleSystemSleep`) and SHALL hold it until the toggle is turned off or the app exits

#### Scenario: Toggle off

- **WHEN** the user disables the toggle while the assertion is held
- **THEN** the app SHALL release the assertion within one second and the Mac SHALL be free to follow its normal idle-sleep policy

#### Scenario: App exit releases assertion

- **WHEN** the GPSMock process terminates (normal quit, window close, or crash)
- **THEN** any held sleep-prevention assertion SHALL be released so the system is not kept awake by a non-running app

#### Scenario: Setting persisted

- **WHEN** the user enables the toggle, quits, and relaunches the app
- **THEN** the toggle SHALL be on after relaunch and the assertion SHALL be re-acquired before the first user interaction

#### Scenario: Display sleep unaffected

- **WHEN** the toggle is enabled and the user does not touch the Mac for the system's display-sleep timeout
- **THEN** the display MAY still sleep, but the system SHALL NOT enter idle sleep and the simulated walk SHALL continue running

## MODIFIED Requirements

### Requirement: Persistent UI state

The app SHALL persist last map center, last zoom level, last speed value, and the prevent-sleep toggle value to `~/Library/Application Support/GPSMock/state.json` and SHALL restore them on next launch.

#### Scenario: First launch

- **WHEN** the app launches and `state.json` does not exist
- **THEN** the app SHALL center on a sensible default (e.g., the user's last-known macOS location, or a hard-coded fallback), the prevent-sleep toggle SHALL default to off, and the file SHALL be created on first state change

#### Scenario: Subsequent launch

- **WHEN** the app launches and a valid `state.json` exists
- **THEN** the map SHALL initialize at the saved center and zoom, the speed slider SHALL initialize to the saved value, and the prevent-sleep toggle SHALL initialize to the saved value (treating an absent `preventSleep` field as off for backward compatibility)
