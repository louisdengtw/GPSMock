import MapKit
import SwiftUI

struct MapSurface: View {
    @Environment(AppViewModel.self) private var app
    @Environment(StatusPollModel.self) private var status

    var body: some View {
        @Bindable var app = app

        MapReader { proxy in
            Map(position: $app.cameraPosition, interactionModes: .all) {
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
            .onTapGesture { screenPoint in
                if let coord = proxy.convert(screenPoint, from: .local) {
                    app.mapTapped(at: coord)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                app.cameraDidChange(context.region)
            }
        }
    }
}
