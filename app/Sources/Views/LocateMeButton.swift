import SwiftUI

struct LocateMeButton: View {
    @Environment(AppViewModel.self) private var app

    var body: some View {
        Button {
            Task { await app.recenterOnCurrentLocation() }
        } label: {
            Group {
                if app.isLocating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
        .shadow(radius: 2)
        .help("Center map on my location")
        .disabled(app.isLocating)
    }
}
