import CoreLocation
import Foundation
import MapKit

/// Persists `~/Library/Application Support/GPSMock/state.json`.
final class StateStore {
    struct Snapshot: Codable {
        var centerLat: Double?
        var centerLon: Double?
        var spanLatDelta: Double?
        var spanLonDelta: Double?
        var speedMps: Double?
        var preventSleep: Bool?
    }

    /// Hard-coded fallback when no last-known location is available.
    /// Taipei 101; documented in setup.md.
    static let defaultCenter = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
    static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    static let defaultSpeed: Double = 1.3

    private let url: URL
    private var pending: Snapshot?
    private var debounceTask: Task<Void, Never>?

    init() {
        let fm = FileManager.default
        let support = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("GPSMock", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("state.json")
    }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot()
        }
        return snap
    }

    func write(_ snapshot: Snapshot) {
        pending = snapshot
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func writeImmediately(_ snapshot: Snapshot) {
        pending = snapshot
        flush()
    }

    private func flush() {
        guard let snap = pending else { return }
        pending = nil
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence failures are non-fatal.
        }
    }
}
