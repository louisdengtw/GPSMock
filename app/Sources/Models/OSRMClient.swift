import CoreLocation
import Foundation

struct RoutePlan {
    let polyline: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let usedFallback: Bool
    let fallbackReason: String?
}

enum OSRMClient {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 3
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// Route from origin to destination, falling back to a straight line on any failure.
    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> RoutePlan {
        // FOSSGIS routed-foot — the project-osrm.org demo ignores the profile
        // path and serves car-only data, so `foot` requests there return
        // motorway-included routes. routing.openstreetmap.de hosts separate
        // OSRM instances per profile (routed-foot / routed-bike / routed-car).
        let url = URL(
            string: "https://routing.openstreetmap.de/routed-foot/route/v1/foot/" +
                "\(origin.longitude),\(origin.latitude);" +
                "\(destination.longitude),\(destination.latitude)" +
                "?overview=full&geometries=geojson"
        )!

        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return fallback(origin: origin, destination: destination,
                                reason: "OSRM unavailable — using straight line")
            }
            let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
            guard let route = decoded.routes.first,
                  !route.geometry.coordinates.isEmpty else {
                return fallback(origin: origin, destination: destination,
                                reason: "OSRM returned no route — using straight line")
            }
            let polyline = route.geometry.coordinates.map {
                // GeoJSON: [lon, lat]
                CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
            }
            return RoutePlan(
                polyline: polyline,
                distanceMeters: route.distance,
                usedFallback: false,
                fallbackReason: nil
            )
        } catch {
            return fallback(origin: origin, destination: destination,
                            reason: "OSRM unavailable — using straight line")
        }
    }

    /// Route a closed loop through the given waypoints in order, returning to the
    /// first waypoint, so each lap joins seamlessly. Falls back to a straight-line
    /// closed polygon on any failure.
    static func loopRoute(
        through waypoints: [CLLocationCoordinate2D]
    ) async -> RoutePlan {
        // Closing the loop needs at least two distinct points.
        guard waypoints.count >= 2 else {
            return loopFallback(
                waypoints: waypoints,
                reason: "Need at least 2 waypoints — using straight line"
            )
        }

        // Append the first waypoint to close the loop: p0;p1;…;pN;p0.
        let closed = waypoints + [waypoints[0]]
        let path = closed
            .map { "\($0.longitude),\($0.latitude)" }
            .joined(separator: ";")
        let url = URL(
            string: "https://routing.openstreetmap.de/routed-foot/route/v1/foot/" +
                path + "?overview=full&geometries=geojson"
        )!

        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return loopFallback(waypoints: waypoints,
                                    reason: "OSRM unavailable — using straight line")
            }
            let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
            guard let route = decoded.routes.first,
                  !route.geometry.coordinates.isEmpty else {
                return loopFallback(waypoints: waypoints,
                                    reason: "OSRM returned no route — using straight line")
            }
            let polyline = route.geometry.coordinates.map {
                // GeoJSON: [lon, lat]
                CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
            }
            return RoutePlan(
                polyline: polyline,
                distanceMeters: route.distance,
                usedFallback: false,
                fallbackReason: nil
            )
        } catch {
            return loopFallback(waypoints: waypoints,
                                reason: "OSRM unavailable — using straight line")
        }
    }

    private static func fallback(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        reason: String
    ) -> RoutePlan {
        let polyline = [origin, destination]
        let distance = haversine(origin, destination)
        return RoutePlan(
            polyline: polyline,
            distanceMeters: distance,
            usedFallback: true,
            fallbackReason: reason
        )
    }

    /// Straight-line closed polygon through the waypoints in order, back to the
    /// first. Distance is the summed Haversine length of every leg including the
    /// closing one, so per-lap ETA stays meaningful.
    private static func loopFallback(
        waypoints: [CLLocationCoordinate2D],
        reason: String
    ) -> RoutePlan {
        let closed = waypoints.isEmpty ? waypoints : waypoints + [waypoints[0]]
        var distance = 0.0
        for i in 0..<max(0, closed.count - 1) {
            distance += haversine(closed[i], closed[i + 1])
        }
        return RoutePlan(
            polyline: closed,
            distanceMeters: distance,
            usedFallback: true,
            fallbackReason: reason
        )
    }

    private static func haversine(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> Double {
        let R = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dlat = (b.latitude - a.latitude) * .pi / 180
        let dlon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dlat / 2) * sin(dlat / 2)
            + cos(lat1) * cos(lat2) * sin(dlon / 2) * sin(dlon / 2)
        return 2 * R * asin(sqrt(h))
    }
}

private struct OSRMResponse: Decodable {
    struct Route: Decodable {
        let distance: Double
        let geometry: Geometry
    }
    struct Geometry: Decodable {
        let coordinates: [[Double]]   // [[lon, lat], ...]
    }
    let routes: [Route]
}
