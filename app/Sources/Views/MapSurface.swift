import CoreLocation
import MapKit
import SwiftUI

struct MapSurface: View {
    @Environment(AppViewModel.self) private var app
    @Environment(StatusPollModel.self) private var status
    @State private var draggingOrigin: CLLocationCoordinate2D?
    @State private var selectedPOI: MKMapItem?

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
                if let plan = app.pendingRoute, app.mode == .walk {
                    MapPolyline(coordinates: plan.polyline)
                        .stroke(.purple, lineWidth: 4)
                    if let start = draggingOrigin ?? plan.polyline.first {
                        Annotation("Start", coordinate: start) {
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
                            .gesture(
                                DragGesture(coordinateSpace: .named("map"))
                                    .onChanged { value in
                                        if let coord = proxy.convert(value.location, from: .named("map")) {
                                            draggingOrigin = coord
                                        }
                                    }
                                    .onEnded { value in
                                        if let coord = proxy.convert(value.location, from: .named("map")) {
                                            app.setCustomOrigin(coord)
                                        }
                                        draggingOrigin = nil
                                    }
                            )
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
        }
    }
}
