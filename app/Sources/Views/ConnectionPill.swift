import SwiftUI

struct ConnectionPill: View {
    @Environment(ConnectionStateModel.self) private var connection

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(connection.state.pillTitle)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 1)
    }

    private var color: Color {
        switch connection.state {
        case .sidecarUpDevicePresent:  return .green
        case .sidecarUpDeviceAbsent:   return .yellow
        case .tunneldUnreachable:      return .orange
        case .sidecarDown:             return .red
        }
    }
}
