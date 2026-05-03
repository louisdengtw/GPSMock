## ADDED Requirements

### Requirement: Teleport endpoint

The sidecar SHALL expose `POST /teleport` accepting `{lat: number, lon: number}` and SHALL push that single coordinate to the connected iPhone via `pymobiledevice3` DVT location simulation.

#### Scenario: Teleport with valid coordinates

- **WHEN** the app sends `POST /teleport` with `{lat: 25.0330, lon: 121.5654}` and an iPhone is connected
- **THEN** the sidecar SHALL return 200 within 1 second (excluding network) and the iPhone's reported location SHALL be within 5 meters of the requested point

#### Scenario: Teleport without device

- **WHEN** the app sends `POST /teleport` while no iPhone is connected
- **THEN** the sidecar SHALL return 503 with body `{error: "no_device"}` and SHALL NOT mutate any internal walk state

#### Scenario: Teleport with malformed body

- **WHEN** the app sends `POST /teleport` with missing or non-numeric `lat`/`lon`, or values outside `lat ∈ [-90, 90]` / `lon ∈ [-180, 180]`
- **THEN** the sidecar SHALL return 400 with a body describing the validation error

#### Scenario: Teleport interrupts an active walk

- **WHEN** a walk is in progress and the app sends `POST /teleport`
- **THEN** the sidecar SHALL stop the walker, push the teleport coordinate, and `GET /status` SHALL report `walking: false` with `current` equal to the teleported point

### Requirement: Walk endpoint

The sidecar SHALL expose `POST /walk` accepting `{points: Array<[lat, lon]>, speed_mps: number}` and SHALL play the polyline back to the iPhone by interpolating between consecutive points at the requested speed.

#### Scenario: Walk with valid polyline

- **WHEN** the app sends `POST /walk` with two or more points and `speed_mps` between 0.1 and 10
- **THEN** the sidecar SHALL return 202 immediately, set `walking: true`, and begin pushing interpolated coordinates

#### Scenario: Walk replaces walk

- **WHEN** a walk is in progress and the app sends a new `POST /walk`
- **THEN** the sidecar SHALL cancel the previous walk and start the new one without leaving the iPhone on a stale interpolated point

#### Scenario: Walk completes naturally

- **WHEN** the walker reaches the final point of the polyline
- **THEN** the iPhone's location SHALL remain on that final point, `walking` SHALL transition to `false`, and `current` SHALL equal the final point

#### Scenario: Walk with fewer than two points

- **WHEN** the app sends `POST /walk` with `points` of length 0 or 1
- **THEN** the sidecar SHALL return 400 with a body describing the validation error

#### Scenario: Walk with out-of-range speed

- **WHEN** the app sends `POST /walk` with `speed_mps` ≤ 0 or > 10
- **THEN** the sidecar SHALL return 400 and SHALL NOT start a walker

### Requirement: Clear endpoint

The sidecar SHALL expose `POST /clear` that stops any active walk, releases the simulated location on the iPhone, and restores real GPS.

#### Scenario: Clear during walk

- **WHEN** a walk is in progress and the app sends `POST /clear`
- **THEN** the walker SHALL stop, the sidecar SHALL call `pymobiledevice3` stop-simulation, and `GET /status` SHALL return `{current: null, walking: false}`

#### Scenario: Clear when idle

- **WHEN** no walk is active and the app sends `POST /clear`
- **THEN** the sidecar SHALL still call stop-simulation (idempotent), return 200, and report `{current: null, walking: false}`

#### Scenario: Real GPS restored

- **WHEN** `POST /clear` succeeds
- **THEN** the iPhone SHALL display its real GPS location within 60 seconds (subject to iOS's own simulation timeout)

### Requirement: Status endpoint

The sidecar SHALL expose `GET /status` returning `{current: [lat, lon] | null, walking: boolean}` describing the most recently pushed coordinate and whether a walk is in progress.

#### Scenario: Status while walking

- **WHEN** a walk is in progress and the app polls `GET /status`
- **THEN** the response SHALL include `walking: true` and `current` SHALL be a `[lat, lon]` pair within the polyline's bounding box

#### Scenario: Status when idle

- **WHEN** no walk is in progress and no teleport has occurred since the last `/clear`
- **THEN** `GET /status` SHALL return `{current: null, walking: false}`

#### Scenario: Status after teleport

- **WHEN** a teleport has succeeded and no walk follows
- **THEN** `GET /status` SHALL return `{current: [lat, lon], walking: false}` matching the teleported point

### Requirement: Sidecar shutdown cleanup

The sidecar SHALL handle `SIGTERM` and `SIGINT` by stopping any active walk, calling `pymobiledevice3` stop-simulation, and disconnecting from tunneld before exiting.

#### Scenario: Graceful sidecar quit

- **WHEN** the user sends `SIGTERM` (e.g., Ctrl-C) to the sidecar while a walk is running
- **THEN** the sidecar SHALL stop the walk, restore real GPS, and exit within 3 seconds

#### Scenario: Hard kill of sidecar

- **WHEN** the sidecar is killed with `SIGKILL`
- **THEN** the iPhone MAY remain on the last simulated coordinate until iOS's own simulation timeout (~60 s); this is documented as an accepted degradation
