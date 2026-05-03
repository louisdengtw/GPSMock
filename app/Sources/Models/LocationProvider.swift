import CoreLocation
import Foundation

/// One-shot CoreLocation wrapper used to center the map on first launch.
/// Returns nil on denial, restriction, error, or timeout — the caller falls back
/// to the persisted region or the documented default coordinate.
final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOnce(timeout: TimeInterval = 5) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            lock.lock()
            self.continuation = cont
            lock.unlock()

            DispatchQueue.main.async { [self] in
                switch manager.authorizationStatus {
                case .notDetermined:
                    manager.requestWhenInUseAuthorization()
                case .authorizedAlways:
                    manager.requestLocation()
                case .denied, .restricted:
                    resume(with: nil)
                @unknown default:
                    manager.requestLocation()
                }
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resume(with: nil)
            }
        }
    }

    private func resume(with coord: CLLocationCoordinate2D?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: coord)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        resume(with: locations.first?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(with: nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            resume(with: nil)
        default:
            break
        }
    }
}
