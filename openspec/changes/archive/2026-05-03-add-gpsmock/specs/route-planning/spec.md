## ADDED Requirements

### Requirement: OSRM foot routing

The app SHALL request walking routes from the public OSRM endpoint at `https://router.project-osrm.org/route/v1/foot/{lon1},{lat1};{lon2},{lat2}?overview=full&geometries=geojson` and parse the resulting GeoJSON polyline into the list of `[lat, lon]` points sent to the sidecar's `/walk`.

#### Scenario: Successful OSRM response

- **WHEN** the user picks a destination in walk mode and OSRM returns 200 with a non-empty `routes[0].geometry.coordinates`
- **THEN** the app SHALL render the polyline on the map, show distance and ETA at the selected speed, and present a Confirm/Cancel choice

#### Scenario: OSRM returns no route

- **WHEN** OSRM returns 200 with `routes` empty (e.g., disconnected island)
- **THEN** the app SHALL fall back to a single straight-line segment between origin and destination and surface the banner "OSRM returned no route — using straight line"

### Requirement: OSRM timeout and fallback

The app SHALL apply a 3 second hard timeout to every OSRM request and SHALL fall back to a two-point straight-line route when the request times out, fails connection, or returns a non-2xx response.

#### Scenario: OSRM times out

- **WHEN** an OSRM request does not return a response within 3 seconds
- **THEN** the app SHALL cancel the request, build a straight-line route, and display the banner "OSRM unavailable — using straight line"

#### Scenario: OSRM returns 5xx

- **WHEN** OSRM returns any 5xx status
- **THEN** the app SHALL fall back to a straight-line route and display the same "OSRM unavailable" banner

#### Scenario: Network offline

- **WHEN** the host has no internet connectivity
- **THEN** the app SHALL fail fast (not wait the full 3 s), fall back to straight-line, and display the banner "OSRM unavailable — using straight line"

### Requirement: Straight-line fallback geometry

When the straight-line fallback is active, the app SHALL produce a two-point polyline `[[origin_lat, origin_lon], [dest_lat, dest_lon]]` with no intermediate samples, and the sidecar's walker SHALL handle interpolation along that segment.

#### Scenario: Fallback polyline shape

- **WHEN** the fallback path is produced from origin `O` and destination `D`
- **THEN** the polyline SHALL be exactly `[O, D]` and the rendered map preview SHALL be a single straight line

### Requirement: Walker interpolation along polyline

The sidecar's walker SHALL traverse the supplied polyline segment-by-segment, interpolating intermediate coordinates such that the iPhone receives roughly one update per second at a great-circle distance approximating `speed_mps` meters per second.

#### Scenario: Interpolation pace

- **WHEN** a walk runs at `speed_mps = 1.3` along a 130 m straight segment
- **THEN** the walker SHALL push approximately 100 ± 15 intermediate coordinates and the wall-clock duration SHALL be 100 ± 15 seconds

#### Scenario: Polyline corner handling

- **WHEN** the polyline contains a corner between segments
- **THEN** the walker SHALL pass through the corner point exactly once and continue interpolating along the next segment without overshoot

### Requirement: Speed jitter

The walker SHALL apply a per-segment speed multiplier sampled uniformly from `[0.85, 1.15]` so that playback does not advance at a perfectly constant rate.

#### Scenario: Speed jitter present

- **WHEN** a walk is played at `speed_mps = 1.3` for at least 30 seconds
- **THEN** measured per-second displacements SHALL show a non-zero standard deviation greater than 5% of the mean

### Requirement: Coordinate jitter

The walker SHALL add an independent per-update offset of up to 1 meter in latitude and longitude to break perfect collinearity, while staying within `current` distance of the underlying interpolated point.

#### Scenario: Jitter within bound

- **WHEN** any coordinate is pushed during a walk
- **THEN** the great-circle distance from the underlying interpolated point SHALL NOT exceed 1 meter

### Requirement: Walk cancellation

The app SHALL allow the user to cancel an in-progress walk; cancellation SHALL stop the iPhone at its current interpolated coordinate, not snap back to origin or jump to destination.

#### Scenario: Mid-walk cancel

- **WHEN** the user clicks Cancel during an active walk
- **THEN** the app SHALL call `POST /clear` (or a dedicated cancel route) and `GET /status` SHALL return `walking: false` with `current` equal to the last pushed coordinate within 1 second
