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
    var preventSleep: Bool
    var seenStartHint: Bool

    // ---- Interaction state
    var pendingTarget: CLLocationCoordinate2D?
    var pendingRoute: RoutePlan?
    var isPlanningRoute: Bool = false
    var isPickingStart: Bool = false
    // ---- Loop-area state: outline an area by tapping waypoints, then walk a
    // closed loop through them continuously until stopped.
    var isDrawingLoop: Bool = false
    var loopWaypoints: [CLLocationCoordinate2D] = []
    var isLooping: Bool = false
    var canPlanLoop: Bool { loopWaypoints.count >= 3 }
    // Soft cap so the OSRM round-trip URL and route stay sane.
    static let maxLoopWaypoints = 25
    var banner: String?
    var transientToast: String?
    var isLocating: Bool = false
    var userLocation: CLLocationCoordinate2D?
    var customOrigin: CLLocationCoordinate2D?
    // Origin captured at the first walk plan of a preview session; reused on
    // subsequent re-plans so the Start dot doesn't jitter with iPhone GPS polls.
    // Cleared on cancel/clear/mode-switch/resetCustomOrigin.
    private var sessionOrigin: CLLocationCoordinate2D?

    // ---- Wired weak-ish via bootstrap
    private weak var connectionRef: ConnectionStateModel?
    private weak var statusRef: StatusPollModel?

    private let store = StateStore()
    private let hadPersistedCenter: Bool
    private let sleepAssertion = SleepAssertion()

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
        self.preventSleep = snap.preventSleep ?? false
        self.seenStartHint = snap.seenStartHint ?? false
        if self.preventSleep {
            sleepAssertion.enable()
        }
    }

    /// On first launch (no persisted center), ask CoreLocation for a one-shot
    /// fix and recenter the map. Falls back silently to the hard-coded default
    /// when permission is denied or the request times out.
    @MainActor
    func acquireInitialLocationIfNeeded() async {
        guard !hadPersistedCenter else { return }
        await recenterOnCurrentLocation(silent: true)
    }

    /// Toolbar "Locate me" action. Reads the Mac's CoreLocation, centers the
    /// map there, and — if the iPhone is connected — teleports the iPhone to
    /// that coordinate so the blue dot lands on top of where the user actually is.
    @MainActor
    func recenterOnCurrentLocation(silent: Bool = false) async {
        guard !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        let provider = LocationProvider()
        guard let coord = await provider.requestOnce() else {
            if !silent {
                banner = "Couldn't read your location — check System Settings → Privacy & Security → Location Services."
            }
            return
        }
        userLocation = coord
        let region = MKCoordinateRegion(center: coord, span: lastKnownRegion.span)
        lastKnownRegion = region
        cameraPosition = .region(region)
        persist()

        if isReady {
            await dispatchTeleport(coord)
        }
    }

    func bootstrap(connection: ConnectionStateModel, status: StatusPollModel) {
        self.connectionRef = connection
        self.statusRef = status
    }

    var isReady: Bool { connectionRef?.state.isReady ?? false }

    // ---------------------------------------------------------- map taps

    @MainActor
    func mapTapped(at coordinate: CLLocationCoordinate2D) {
        if isDrawingLoop && mode == .walk {
            guard loopWaypoints.count < Self.maxLoopWaypoints else {
                banner = "Loop area is limited to \(Self.maxLoopWaypoints) points"
                return
            }
            loopWaypoints.append(coordinate)
            // A new waypoint invalidates the previously planned loop polyline.
            pendingRoute = nil
            return
        }
        if isPickingStart && mode == .walk {
            isPickingStart = false
            setCustomOrigin(coordinate)
            return
        }
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
        customOrigin = nil
        sessionOrigin = nil
        isPickingStart = false
        isDrawingLoop = false
        loopWaypoints = []
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
        customOrigin = nil
        sessionOrigin = nil
        isPickingStart = false
        isDrawingLoop = false
        loopWaypoints = []
        isLooping = false
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
        sessionOrigin = nil
        if next != .walk {
            isPickingStart = false
            isDrawingLoop = false
            loopWaypoints = []
        }
    }

    func setPreventSleep(_ enabled: Bool) {
        preventSleep = enabled
        if enabled {
            sleepAssertion.enable()
        } else {
            sleepAssertion.disable()
        }
        persist()
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
            speedMps: speedMps,
            preventSleep: preventSleep,
            seenStartHint: seenStartHint
        ))
    }

    func markStartHintSeen() {
        guard !seenStartHint else { return }
        seenStartHint = true
        persist()
    }

    @MainActor
    func beginPickingStart() {
        guard mode == .walk else { return }
        isPickingStart = true
    }

    @MainActor
    func endPickingStart() {
        isPickingStart = false
    }

    @MainActor
    func resetCustomOrigin() {
        customOrigin = nil
        // Force a fresh capture from the iPhone GPS / Mac CL on the next plan.
        sessionOrigin = nil
        if let target = pendingTarget, mode == .walk {
            Task { await self.planRoute(to: target) }
        }
    }

    // ---------------------------------------------------------- loop area

    @MainActor
    func beginDrawingLoop() {
        guard mode == .walk else { return }
        // Loop drawing is its own flow — drop any single-destination preview.
        pendingTarget = nil
        pendingRoute = nil
        isPickingStart = false
        loopWaypoints = []
        isDrawingLoop = true
    }

    @MainActor
    func cancelDrawingLoop() {
        isDrawingLoop = false
        loopWaypoints = []
        pendingRoute = nil
        isPlanningRoute = false
    }

    @MainActor
    func removeLastLoopWaypoint() {
        guard !loopWaypoints.isEmpty else { return }
        loopWaypoints.removeLast()
        pendingRoute = nil
    }

    @MainActor
    func planLoop() {
        guard canPlanLoop else { return }
        let waypoints = loopWaypoints
        Task {
            await MainActor.run {
                self.isPlanningRoute = true
                self.banner = nil
            }
            let plan = await OSRMClient.loopRoute(through: waypoints)
            await MainActor.run {
                self.pendingRoute = plan
                self.isPlanningRoute = false
                self.banner = plan.fallbackReason
            }
        }
    }

    @MainActor
    func confirmLoop() {
        guard isReady, let plan = pendingRoute else { return }
        Task { await self.dispatchLoop(plan) }
    }

    @MainActor
    func stopLoop() {
        isLooping = false
        pendingRoute = nil
        loopWaypoints = []
        isDrawingLoop = false
        guard isReady else { return }
        Task {
            do {
                try await SidecarClient.shared.clear()
            } catch {
                // best-effort
            }
        }
    }

    private func dispatchLoop(_ plan: RoutePlan) async {
        let pts = plan.polyline.map { (lat: $0.latitude, lon: $0.longitude) }
        do {
            try await SidecarClient.shared.walk(points: pts, speedMps: speedMps, loop: true)
            await MainActor.run {
                self.isDrawingLoop = false
                self.loopWaypoints = []
                self.isLooping = true
                self.banner = plan.fallbackReason
            }
        } catch let e as SidecarError {
            await MainActor.run { self.banner = e.userMessage }
        } catch {
            await MainActor.run { self.banner = error.localizedDescription }
        }
    }

    // ---------------------------------------------------------- async dispatch

    private func planRoute(to destination: CLLocationCoordinate2D) async {
        let origin = await currentOrigin()
        await MainActor.run {
            self.isPlanningRoute = true
            // Keep the previous plan rendered (faded by the view) while re-planning
            // so the preview panel doesn't blank out; replaced atomically below.
            self.banner = nil
        }
        let plan = await OSRMClient.route(from: origin, to: destination)
        await MainActor.run {
            self.pendingRoute = plan
            self.isPlanningRoute = false
            self.banner = plan.fallbackReason
        }
    }

    /// Direct teleport from the lat/lon input bar — bypasses the map-tap flow.
    @MainActor
    func teleportDirect(to coord: CLLocationCoordinate2D) async {
        pendingTarget = coord
        pendingRoute = nil
        await dispatchTeleport(coord)
    }

    /// Called when the user picks a search result. Sets the destination and
    /// recenters the map; in walk mode also kicks off OSRM planning.
    @MainActor
    func placeSelected(_ coord: CLLocationCoordinate2D) {
        pendingTarget = coord
        let region = MKCoordinateRegion(center: coord, span: lastKnownRegion.span)
        lastKnownRegion = region
        cameraPosition = .region(region)
        persist()
        if mode == .walk {
            Task { await self.planRoute(to: coord) }
        } else {
            pendingRoute = nil
        }
    }

    private func dispatchTeleport(_ target: CLLocationCoordinate2D) async {
        // A teleport cancels any running walk/loop server-side, so drop the
        // loop UI and stale loop polyline regardless of the call's outcome.
        await MainActor.run {
            self.isLooping = false
            self.pendingRoute = nil
        }
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
                // A fresh single walk replaces any running loop.
                self.isLooping = false
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
        // Priority: user-dragged custom origin > cached session origin (so the
        // start doesn't jitter with GPS polls between re-plans) > simulated
        // iPhone GPS > Mac CoreLocation > map center.
        if let c = customOrigin { return c }
        if let cached = sessionOrigin { return cached }
        let fresh: CLLocationCoordinate2D
        if let c = statusRef?.current { fresh = c }
        else if let u = userLocation { fresh = u }
        else { fresh = lastKnownRegion.center }
        await MainActor.run { self.sessionOrigin = fresh }
        return fresh
    }

    /// Called when the user drags the green start marker; sets the custom
    /// origin and re-plans the existing route.
    @MainActor
    func setCustomOrigin(_ coord: CLLocationCoordinate2D) {
        customOrigin = coord
        if let target = pendingTarget, mode == .walk {
            Task { await self.planRoute(to: target) }
        }
    }

    // ---------------------------------------------------------- lifecycle

    func handleAppExit() {
        sleepAssertion.disable()
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

