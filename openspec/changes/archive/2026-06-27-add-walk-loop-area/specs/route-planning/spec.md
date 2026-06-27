## ADDED Requirements

### Requirement: OSRM multi-waypoint loop routing

In loop-area mode the app SHALL request a closed-loop walking route from OSRM by issuing an ordered multi-waypoint foot request whose coordinate path is the user's waypoints in tap order with the first waypoint appended at the end (`p0;p1;…;pN;p0`), and SHALL parse the resulting GeoJSON polyline into the `[lat, lon]` points sent to the sidecar's `/walk`. The returned polyline's last point SHALL coincide with its first so each lap joins seamlessly.

#### Scenario: Successful loop route

- **WHEN** the user outlines an area with three or more waypoints and OSRM returns 200 with a non-empty `routes[0].geometry.coordinates` for the round-trip request
- **THEN** the app SHALL render the closed-loop polyline on the map, show the per-lap distance and ETA at the selected speed, and present a Confirm/Cancel choice

#### Scenario: Loop route OSRM failure falls back to closed polygon

- **WHEN** the round-trip OSRM request times out (3 s), fails to connect, returns a non-2xx status, or returns an empty `routes`
- **THEN** the app SHALL fall back to a straight-line route that connects the waypoints in tap order and closes back to the first waypoint, compute per-lap distance via Haversine, and surface the existing "OSRM unavailable — using straight line" banner style

#### Scenario: Fewer than three waypoints

- **WHEN** the user has placed zero, one, or two loop waypoints
- **THEN** the app SHALL NOT issue a loop route request and Confirm SHALL remain disabled until at least three waypoints exist

#### Scenario: Two-point routing unchanged

- **WHEN** the user plans a single (non-loop) walk or previews a teleport destination
- **THEN** the app SHALL use the existing two-point `from→to` OSRM request unchanged, with no appended return waypoint
