import SwiftUI

struct OnboardingCard: View {
    @Environment(ConnectionStateModel.self) private var connection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(connection.state.pillTitle)
                .font(.headline)
            if let cmd = connection.state.remediationCommand {
                Text("Run this in a terminal:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(cmd)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
            switch connection.state {
            case .sidecarDown:
                Text("First, run `sudo pymobiledevice3 remote tunneld` in a separate terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .tunneldUnreachable:
                Text("Tunneld must run as root and stay open in its own terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .sidecarUpDeviceAbsent:
                Text("If freshly trusted, unplug and replug the iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .sidecarUpDevicePresent:
                EmptyView()
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
        .frame(maxWidth: 420)
    }
}
