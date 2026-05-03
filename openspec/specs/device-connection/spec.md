# device-connection Specification

## Purpose

Defines how the GPSMock app and sidecar coordinate to detect the sidecar process, the connected iPhone, and the resulting connection state surfaced to the user.

## Requirements

### Requirement: Sidecar health probing

The app SHALL probe the sidecar at `GET http://127.0.0.1:5555/health` on launch and at runtime, and treat any non-200 response, connection refusal, or timeout as "sidecar down."

#### Scenario: Sidecar reachable on launch

- **WHEN** the app launches and the sidecar responds 200 to `/health` within 2 seconds
- **THEN** the app SHALL transition the connection state to `sidecarUp` and proceed to probe `/device`

#### Scenario: Sidecar unreachable on launch

- **WHEN** the app launches and `/health` is unreachable (connection refused or timeout)
- **THEN** the app SHALL display the onboarding card with the literal command `python sidecar/main.py` and the connection state SHALL remain `sidecarDown`

#### Scenario: Sidecar disappears at runtime

- **WHEN** the sidecar stops responding to `/health` while the app is running
- **THEN** the app SHALL transition to `sidecarDown`, surface an error banner, and retry `/health` with backoff (2 s → 10 s)

### Requirement: iPhone presence detection via sidecar

The app SHALL determine iPhone presence by calling `GET /device` on the sidecar; the sidecar SHALL return 200 with device info when tunneld reports a paired, trusted iPhone, and 404 otherwise.

#### Scenario: iPhone present and trusted

- **WHEN** tunneld is running and an iPhone is connected via USB and trusted
- **THEN** `GET /device` SHALL return 200 with at least `{udid, name, ios_version}` and the app SHALL transition to `iPhonePresent`

#### Scenario: Tunneld running but no iPhone

- **WHEN** tunneld is running but no iPhone is connected
- **THEN** `GET /device` SHALL return 404 and the app SHALL show "Connect iPhone via USB" guidance

#### Scenario: Tunneld not running

- **WHEN** tunneld is not running (sidecar cannot reach it)
- **THEN** `GET /device` SHALL return a 503 with body `{error: "tunneld_unreachable"}` and the app SHALL display the literal command `sudo pymobiledevice3 remote tunneld`

### Requirement: Connection state machine

The app SHALL expose exactly three connection states to the user — `sidecarDown`, `sidecarUp/iPhoneAbsent`, `sidecarUp/iPhonePresent` — and SHALL gate location-control actions on `sidecarUp/iPhonePresent`.

#### Scenario: Action disabled without device

- **WHEN** the app is in `sidecarDown` or `sidecarUp/iPhoneAbsent`
- **THEN** the Teleport, Walk, and Clear buttons SHALL be disabled and the status pill SHALL show the current blocking step

#### Scenario: Actions enabled when ready

- **WHEN** the app reaches `sidecarUp/iPhonePresent`
- **THEN** Teleport, Walk, and Clear SHALL be enabled and the status pill SHALL display the connected iPhone's name

### Requirement: USB reconnect resilience

The app and sidecar SHALL recover from an iPhone being unplugged, slept, or re-plugged without requiring a restart of either process.

#### Scenario: Unplug and replug

- **WHEN** the user unplugs the iPhone, waits, and re-plugs it
- **THEN** within 5 seconds `GET /device` SHALL again return 200 and the app SHALL transition back to `sidecarUp/iPhonePresent`

#### Scenario: iPhone goes to sleep mid-session

- **WHEN** the iPhone screen sleeps while connected
- **THEN** the sidecar SHALL keep its tunneld session, `/device` SHALL continue returning 200, and pending location commands SHALL succeed

### Requirement: Sidecar binds only to loopback

The sidecar SHALL bind exclusively to `127.0.0.1:5555` and SHALL refuse to start if that port is already in use rather than silently picking a different port.

#### Scenario: Loopback-only bind

- **WHEN** the sidecar starts successfully
- **THEN** `lsof` SHALL show it listening on `127.0.0.1:5555` and not on any non-loopback interface

#### Scenario: Port already in use

- **WHEN** another process is already bound to `127.0.0.1:5555`
- **THEN** the sidecar SHALL exit with a non-zero status and print an error naming the conflicting port

### Requirement: Auto-clear on app exit

The app SHALL issue a synchronous `POST /clear` to the sidecar on normal termination so the iPhone is not left on a simulated location.

#### Scenario: Normal app quit

- **WHEN** the user quits the app via Cmd-Q or by closing the last window
- **THEN** the app SHALL block termination on a `POST /clear` call (≤ 2 s timeout) before exiting

#### Scenario: App quit while disconnected

- **WHEN** the user quits while the sidecar is unreachable
- **THEN** the app SHALL skip `/clear` (it cannot succeed), log the skip, and exit without hanging
