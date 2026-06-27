import CoreLocation
import MapKit
import SwiftUI

struct MapSurface: View {
    @Environment(AppViewModel.self) private var app
    @Environment(StatusPollModel.self) private var status
    @State private var draggingOrigin: CLLocationCoordinate2D?
    @State private var selectedPOI: MKMapItem?
    @State private var hintVisible: Bool = false
    @State private var hintTask: Task<Void, Never>?

    var body: some View {
        @Bindable var app = app

        MapReader { proxy in
            Map(position: $app.cameraPosition,
                interactionModes: .all,
                selection: $selectedPOI) {
                if let target = app.pendingTarget {
                    Annotation("Target", coordinate: target) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                            .shadow(radius: 1)
                    }
                }
                if let current = status.current {
                    Annotation("iPhone", coordinate: current) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.25))
                                .frame(width: 28, height: 28)
                            Circle()
                                .fill(.blue)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        }
                        .shadow(radius: 1)
                    }
                }
                // Loop-area outline: numbered waypoints + a polygon closing back
                // to the first, shown while the user is drawing the area.
                if app.isDrawingLoop && app.mode == .walk {
                    if app.loopWaypoints.count >= 2 {
                        MapPolyline(coordinates: app.loopWaypoints + [app.loopWaypoints[0]])
                            .stroke(.purple.opacity(0.5), style: StrokeStyle(
                                lineWidth: 3, dash: [6, 4]))
                    }
                    ForEach(Array(app.loopWaypoints.enumerated()), id: \.offset) { idx, coord in
                        Annotation("\(idx + 1)", coordinate: coord) {
                            ZStack {
                                Circle()
                                    .fill(.purple)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                Text("\(idx + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                            .shadow(radius: 1)
                        }
                    }
                }
                if let plan = app.pendingRoute, app.mode == .walk {
                    MapPolyline(coordinates: plan.polyline)
                        .stroke(.purple.opacity(app.isPlanningRoute ? 0.4 : 1.0), lineWidth: 4)
                    // The draggable Start handle is only meaningful for a single
                    // origin→destination walk, not a loop (which has no origin).
                    if !app.isDrawingLoop, !app.isLooping,
                       let start = draggingOrigin ?? plan.polyline.first {
                        Annotation("Start", coordinate: start) {
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.25))
                                        .frame(width: 26, height: 26)
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 12, height: 12)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                }
                                .shadow(radius: 1)
                                .contentShape(Circle())
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 1, coordinateSpace: .named("map"))
                                        .onChanged { value in
                                            if let coord = proxy.convert(value.location, from: .named("map")) {
                                                draggingOrigin = coord
                                            }
                                            dismissHint()
                                        }
                                        .onEnded { value in
                                            if let coord = proxy.convert(value.location, from: .named("map")) {
                                                app.setCustomOrigin(coord)
                                            }
                                            draggingOrigin = nil
                                        }
                                )
                                if hintVisible {
                                    Text("Drag to change start")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.regularMaterial, in: Capsule())
                                        .shadow(radius: 1)
                                        .transition(.opacity)
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(
                elevation: .flat,
                pointsOfInterest: .all,
                showsTraffic: false))
            .onChange(of: selectedPOI) { _, item in
                guard let item else { return }
                app.placeSelected(item.location.coordinate)
            }
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named("map"))
                    .onEnded { value in
                        if let coord = proxy.convert(value.location, from: .named("map")) {
                            app.mapTapped(at: coord)
                        }
                    }
            )
            .coordinateSpace(.named("map"))
            .onMapCameraChange(frequency: .onEnd) { context in
                app.cameraDidChange(context.region)
            }
            .onChange(of: app.pendingRoute == nil) { _, isNil in
                if !isNil, app.mode == .walk, !app.seenStartHint {
                    showHintOnce()
                } else if isNil {
                    dismissHint()
                }
            }
        }
    }

    private func showHintOnce() {
        hintTask?.cancel()
        hintVisible = true
        app.markStartHintSeen()
        hintTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await MainActor.run {
                hintVisible = false
            }
        }
    }

    private func dismissHint() {
        hintTask?.cancel()
        hintVisible = false
    }
}
