## MODIFIED Requirements

### Requirement: Walk endpoint

The sidecar SHALL expose `POST /walk` accepting `{points: Array<[lat, lon]>, speed_mps: number, loop?: boolean}` and SHALL play the polyline back to the iPhone by interpolating between consecutive points at the requested speed. When `loop` is absent or `false`, the walker SHALL play the polyline once and stop. When `loop` is `true`, the walker SHALL replay the polyline continuously, lap after lap, until cancelled.

#### Scenario: Walk with valid polyline

- **WHEN** the app sends `POST /walk` with two or more points and `speed_mps` between 0.1 and 10
- **THEN** the sidecar SHALL return 202 immediately, set `walking: true`, and begin pushing interpolated coordinates

#### Scenario: Walk replaces walk

- **WHEN** a walk is in progress and the app sends a new `POST /walk`
- **THEN** the sidecar SHALL cancel the previous walk and start the new one without leaving the iPhone on a stale interpolated point

#### Scenario: Walk completes naturally

- **WHEN** the walker reaches the final point of the polyline and `loop` is absent or `false`
- **THEN** the iPhone's location SHALL remain on that final point, `walking` SHALL transition to `false`, and `current` SHALL equal the final point

#### Scenario: Loop walk repeats until cancelled

- **WHEN** the app sends `POST /walk` with `loop: true` and a polyline whose last point coincides with its first
- **THEN** the sidecar SHALL return 202, keep `walking: true`, and on reaching the end of the polyline SHALL immediately begin the next lap from the first point — without landing-and-stopping and without a no-jitter final-point publish — repeating until cancelled

#### Scenario: Loop walk cancelled by clear

- **WHEN** a loop walk is in progress and the app sends `POST /clear` (or `POST /teleport`, or a replacing `POST /walk`)
- **THEN** the sidecar SHALL stop the looping walker within one tick, set `walking: false`, and SHALL NOT start another lap

#### Scenario: Walk with fewer than two points

- **WHEN** the app sends `POST /walk` with `points` of length 0 or 1 (with or without `loop`)
- **THEN** the sidecar SHALL return 400 with a body describing the validation error

#### Scenario: Walk with out-of-range speed

- **WHEN** the app sends `POST /walk` with `speed_mps` ≤ 0 or > 10
- **THEN** the sidecar SHALL return 400 and SHALL NOT start a walker
