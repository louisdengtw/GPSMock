import SwiftUI

struct ControlsPanel: View {
    @Environment(AppViewModel.self) private var app
    @Environment(ConnectionStateModel.self) private var connection
    @Environment(StatusPollModel.self) private var status

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 16) {
            // Mode toggle
            Picker("", selection: Binding(
                get: { app.mode },
                set: { app.setMode($0) }
            )) {
                ForEach(InteractionMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Divider().frame(height: 28)

            // Speed presets
            ForEach(SpeedPreset.allCases) { preset in
                Button {
                    app.setSpeed(preset.rawValue)
                } label: {
                    Text(preset.label)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(app.speedMps == preset.rawValue ? .accentColor : .secondary)
                .disabled(app.mode == .teleport)
            }

            // Speed slider
            VStack(alignment: .leading, spacing: 2) {
                Slider(
                    value: Binding(
                        get: { app.speedMps },
                        set: { app.setSpeed($0) }
                    ),
                    in: 0.1...10,
                    step: 0.1
                )
                .frame(width: 180)
                .disabled(app.mode == .teleport)
                Text(String(format: "%.1f m/s", app.speedMps))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 28)

            // Action buttons
            actionButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 2)
    }

    @ViewBuilder
    private var actionButtons: some View {
        let isReady = connection.state.isReady
        let canConfirm: Bool = {
            guard isReady, app.pendingTarget != nil else { return false }
            if app.mode == .walk { return app.pendingRoute != nil && !app.isPlanningRoute }
            return true
        }()

        Button(action: { app.confirmAction() }) {
            Label(confirmTitle, systemImage: "paperplane.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canConfirm)

        Button(role: .destructive, action: { app.clearAll() }) {
            Label("Clear", systemImage: "xmark.circle.fill")
        }
        .buttonStyle(.bordered)
        .disabled(!isReady)

        if status.walking {
            Button("Stop walk") { app.clearAll() }
                .buttonStyle(.bordered)
                .tint(.red)
        }
    }

    private var confirmTitle: String {
        switch app.mode {
        case .teleport: return "Teleport"
        case .walk:     return app.isPlanningRoute ? "Planning…" : "Walk"
        }
    }
}
