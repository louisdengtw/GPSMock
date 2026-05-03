import CoreLocation
import MapKit
import Observation

@Observable
final class PlaceSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var query: String = ""
    var suggestions: [MKLocalSearchCompletion] = []
    var isResolving: Bool = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    @MainActor
    func updateQuery(_ q: String) {
        query = q
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = []
            completer.cancel()
        } else {
            completer.queryFragment = trimmed
        }
    }

    @MainActor
    func setRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    @MainActor
    func clear() {
        query = ""
        suggestions = []
        completer.cancel()
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.suggestions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }

    @MainActor
    func resolve(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        isResolving = true
        defer { isResolving = false }
        let req = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: req)
        do {
            let response = try await search.start()
            return response.mapItems.first?.location.coordinate
        } catch {
            return nil
        }
    }
}
