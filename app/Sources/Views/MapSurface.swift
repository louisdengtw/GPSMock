import MapKit
import SwiftUI

struct MapSurface: View {
    @Environment(AppViewModel.self) private var app
    @Environment(StatusPollModel.self) private var status

    var body: some View {
        @Bindable var app = app

        MapReader { proxy in
            Map(position: $app.cameraPosition, interactionModes: .all) {
                if let mac = app.userLocation {
                    Annotation("Mac", coordinate: mac) {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.20))
                                .frame(width: 22, height: 22)
                            Circle()
                                .fill(.gray)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        }
                        .shadow(radius: 1)
                    }
                }
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
                }
            }
            .mapStyle(.standard(elevation: .flat))
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
