import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

enum InteractionMode: String, CaseIterable, Identifiable {
    case teleport
    case walk
    var id: String { rawValue }
    var label: String { self == .teleport ? "Teleport" : "Walk" }
}

enum SpeedPreset: Double, CaseIterable, Identifiable {
    case walk = 1.3
    case jog = 2.7
    case bike = 5.0
    var id: Double { rawValue }
    var label: String {
        switch self {
        case .walk: return "Walk · 1.3"
        case .jog:  return "Jog · 2.7"
        case .bike: return "Bike · 5.0"
        }
    }
}

@Observable
final class AppViewModel {
    // ---- Persistent UI state
    var cameraPosition: MapCameraPosition
    var lastKnownRegion: MKCoordinateRegion
    var speedMps: Double
    var mode: InteractionMode = .teleport

    // ---- Interaction state
    var pendingTarget: CLLocationCoordinate2D?
    var pendingRoute: RoutePlan?
    var isPlanningRoute: Bool = false
    var banner: String?
    var transientToast: String?
    var isLocating: Bool = false
    var userLocation: CLLocationCoordinate2D?

    // ---- Wired weak-ish via bootstrap
    private weak var connectionRef: ConnectionStateModel?
    private weak var statusRef: StatusPollModel?

    private let store = StateStore()
    private let hadPersistedCenter: Bool

    init() {
        let snap = store.load()
        self.hadPersistedCenter = (snap.centerLat != nil && snap.centerLon != nil)
        let center = CLLocationCoordinate2D(
            latitude: snap.centerLat ?? StateStore.defaultCenter.latitude,
            longitude: snap.centerLon ?? StateStore.defaultCenter.longitude
        )
        let span = MKCoordinateSpan(
            latitudeDelta: snap.spanLatDelta ?? StateStore.defaultSpan.latitudeDelta,
            longitudeDelta: snap.spanLonDelta ?? StateStore.defaultSpan.longitudeDelta
        )
        let region = MKCoordinateRegion(center: center, span: span)
        self.lastKnownRegion = region
        self.cameraPosition = .region(region)
        self.speedMps = snap.speedMps ?? StateStore.defaultSpeed
    }

    /// On first launch (no persisted center), ask CoreLocation for a one-shot
    /// fix and recenter the map. Falls back silently to the hard-coded default
    /// when permission is denied or the request times out.
    @MainActor
    func acquireInitialLocationIfNeeded() async {
        guard !hadPersistedCenter else { return }
        await recenterOnCurrentLocation(silent: true)
    }

    /// Toolbar "Locate me" action. Always queries CoreLocation and surfaces a
    /// banner when permission is denied or the request times out.
    @MainActor
    func recenterOnCurrentLocation(silent: Bool = false) async {
        guard !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        let provider = LocationProvider()
        guard let coord = await provider.requestOnce(timeout: 5) else {
            if !silent {
                banner = "Couldn't read your location — check System Settings → Privacy → Location Services."
            }
            return
        }
        userLocation = coord
        let region = MKCoordinateRegion(center: coord, span: lastKnownRegion.span)
        lastKnownRegion = region
        cameraPosition = .region(region)
        persist()
    }

    func bootstrap(connection: ConnectionStateModel, status: StatusPollModel) {
        self.connectionRef = connection
        self.statusRef = status
    }

    var isReady: Bool { connectionRef?.state.isReady ?? false }

    // ---------------------------------------------------------- map taps

    func mapTapped(at coordinate: CLLocationCoordinate2D) {
        // Always allow placing a target — confirm/dispatch is gated separately
        // so users can preview routes before the iPhone is connected.
        pendingTarget = coordinate
        switch mode {
        case .teleport:
            pendingRoute = nil
        case .walk:
            Task { await self.planRoute(to: coordinate) }
        }
    }

    func confirmAction() {
        guard isReady, let target = pendingTarget else { return }
        switch mode {
        case .teleport:
            Task { await self.dispatchTeleport(target) }
        case .walk:
            guard let plan = pendingRoute else { return }
            Task { await self.dispatchWalk(plan) }
        }
    }

    func cancelPreview() {
        pendingTarget = nil
        pendingRoute = nil
        isPlanningRoute = false
    }

    func clearAll() {
        guard isReady else { return }
        Task {
            do {
                try await SidecarClient.shared.clear()
            } catch {
                // best-effort
            }
        }
        pendingTarget = nil
        pendingRoute = nil
    }

    // ---------------------------------------------------------- speed / mode

    func setSpeed(_ value: Double) {
        speedMps = max(0.1, min(10, value))
        persist()
    }

    func setMode(_ next: InteractionMode) {
        mode = next
        // Switching modes invalidates any preview built for the other mode.
        pendingRoute = nil
    }

    // ---------------------------------------------------------- camera persistence

    func cameraDidChange(_ region: MKCoordinateRegion) {
        lastKnownRegion = region
        persist()
    }

    private func persist() {
        store.write(StateStore.Snapshot(
            centerLat: lastKnownRegion.center.latitude,
            centerLon: lastKnownRegion.center.longitude,
            spanLatDelta: lastKnownRegion.span.latitudeDelta,
            spanLonDelta: lastKnownRegion.span.longitudeDelta,
            speedMps: speedMps
        ))
    }

    // ---------------------------------------------------------- async dispatch

    private func planRoute(to destination: CLLocationCoordinate2D) async {
        let origin = await currentOrigin()
        await MainActor.run {
            self.isPlanningRoute = true
            self.pendingRoute = nil
            self.banner = nil
        }
        let plan = await OSRMClient.route(from: origin, to: destination)
        await MainActor.run {
            self.pendingRoute = plan
            self.isPlanningRoute = false
            self.banner = plan.fallbackReason
        }
    }

    private func dispatchTeleport(_ target: CLLocationCoordinate2D) async {
        do {
            try await SidecarClient.shared.teleport(lat: target.latitude, lon: target.longitude)
            await MainActor.run { self.banner = nil }
        } catch let e as SidecarError {
            await MainActor.run { self.banner = e.userMessage }
        } catch {
            await MainActor.run { self.banner = error.localizedDescription }
        }
    }

    private func dispatchWalk(_ plan: RoutePlan) async {
        let pts = plan.polyline.map { (lat: $0.latitude, lon: $0.longitude) }
        do {
            try await SidecarClient.shared.walk(points: pts, speedMps: speedMps)
            await MainActor.run {
                self.pendingRoute = nil
                self.banner = plan.fallbackReason
            }
        } catch let e as SidecarError {
            await MainActor.run { self.banner = e.userMessage }
        } catch {
            await MainActor.run { self.banner = error.localizedDescription }
        }
    }

    private func currentOrigin() async -> CLLocationCoordinate2D {
        if let c = statusRef?.current { return c }
        return lastKnownRegion.center
    }

    // ---------------------------------------------------------- lifecycle

    func handleAppExit() {
        // Synchronous-ish best-effort clear; do not block UI more than ~2 s.
        let group = DispatchGroup()
        group.enter()
        Task {
            await SidecarClient.shared.clearBestEffort(timeout: 2)
            group.leave()
        }
        _ = group.wait(timeout: .now() + 2.5)
    }
}

