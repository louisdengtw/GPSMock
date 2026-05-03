import SwiftUI

struct WalkPreviewSheet: View {
    let plan: RoutePlan
    @Environment(AppViewModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.walk")
                Text("Walk preview")
                    .font(.headline)
            }
            HStack(spacing: 16) {
                stat(label: "Distance", value: String(format: "%.0f m", plan.distanceMeters))
                stat(label: "ETA", value: etaString)
                if plan.usedFallback {
                    Label("straight-line", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    app.cancelPreview()
                }
                .buttonStyle(.bordered)
                Button("Confirm") {
                    app.confirmAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
        .frame(maxWidth: 360)
    }

    private var etaString: String {
        let seconds = plan.distanceMeters / max(app.speedMps, 0.1)
        if seconds < 90 {
            return String(format: "%.0f s", seconds)
        }
        return String(format: "%.1f min", seconds / 60)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.monospacedDigit())
        }
    }
}
