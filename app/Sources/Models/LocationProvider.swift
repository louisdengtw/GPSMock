import CoreLocation
import Foundation

/// One-shot CoreLocation wrapper used to center the map on first launch.
/// Returns nil on denial, restriction, error, or timeout — the caller falls back
/// to the persisted region or the documented default coordinate.
final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var didStart = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOnce(timeout: TimeInterval = 8) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            lock.lock()
            self.continuation = cont
            lock.unlock()

            DispatchQueue.main.async { [self] in
                switch manager.authorizationStatus {
                case .notDetermined:
                    manager.requestWhenInUseAuthorization()
                case .authorizedAlways, .authorizedWhenInUse:
                    startUpdating()
                case .denied, .restricted:
                    resume(with: nil)
                @unknown default:
                    startUpdating()
                }
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resume(with: nil)
            }
        }
    }

    // Continuous updates rather than `requestLocation()` so that a transient
    // `kCLErrorLocationUnknown` (common when the daemon has no cached fix yet,
    // e.g. desktop Macs that rely on Wi-Fi positioning) doesn't terminate the
    // request — we keep waiting for a fix until the caller's timeout.
    private func startUpdating() {
        guard !didStart else { return }
        didStart = true
        manager.startUpdatingLocation()
    }

    private func resume(with coord: CLLocationCoordinate2D?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        let wasStarted = didStart
        didStart = false
        lock.unlock()
        if wasStarted {
            DispatchQueue.main.async { [manager] in
                manager.stopUpdatingLocation()
            }
        }
        cont?.resume(returning: coord)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        resume(with: locations.first?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        resume(with: nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdating()
        case .denied, .restricted:
            resume(with: nil)
        default:
            break
        }
    }
}
