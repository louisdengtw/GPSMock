import AppKit
import CoreLocation
import SwiftUI

struct ControlsPanel: View {
    @Environment(AppViewModel.self) private var app
    @Environment(ConnectionStateModel.self) private var connection
    @Environment(StatusPollModel.self) private var status

    @State private var latText: String = ""
    @State private var lonText: String = ""
    @State private var inputError: String?

    var body: some View {
        @Bindable var app = app

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("", selection: Binding(
                    get: { app.mode },
                    set: { app.setMode($0) }
                )) {
                    ForEach(InteractionMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

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

            Divider()

            switch app.mode {
            case .teleport: teleportRow
            case .walk:     walkRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 2)
        .frame(maxWidth: 720)
        .onChange(of: app.pendingTarget?.latitude) { _, _ in syncFromMap() }
        .onChange(of: app.pendingTarget?.longitude) { _, _ in syncFromMap() }
    }

    // ──────────────────────────────────────────────────────────── teleport

    @ViewBuilder
    private var teleportRow: some View {
        HStack(spacing: 8) {
            Label("Coord", systemImage: "scope")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            TextField("latitude", text: $latText)
                .frame(width: 110)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .onSubmit(submitTeleport)
            TextField("longitude", text: $lonText)
                .frame(width: 120)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .onSubmit(submitTeleport)
            Button {
                pasteCoordinate()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .help(#"Parse "lat, lon" from the clipboard"#)

            if let err = inputError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: submitTeleport) {
                Label("Teleport", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isReady || parsedCoord == nil)
        }
    }

    private var parsedCoord: CLLocationCoordinate2D? {
        guard let lat = Double(latText.trimmingCharacters(in: .whitespaces)),
              let lon = Double(lonText.trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(lat),
              (-180...180).contains(lon)
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func submitTeleport() {
        guard let coord = parsedCoord else {
            inputError = "Invalid lat/lon"
            return
        }
        guard isReady else {
            inputError = "iPhone not connected"
            return
        }
        inputError = nil
        Task { await app.teleportDirect(to: coord) }
    }

    private func pasteCoordinate() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let parts = text
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1])
        else {
            inputError = #"Clipboard isn't "lat, lon""#
            return
        }
        latText = String(format: "%.6f", lat)
        lonText = String(format: "%.6f", lon)
        inputError = nil
    }

    private func syncFromMap() {
        guard app.mode == .teleport, let c = app.pendingTarget else { return }
        latText = String(format: "%.6f", c.latitude)
        lonText = String(format: "%.6f", c.longitude)
        inputError = nil
    }

    // ──────────────────────────────────────────────────────────── walk

    @ViewBuilder
    private var walkRow: some View {
        HStack(spacing: 10) {
            ForEach(SpeedPreset.allCases) { preset in
                Button {
                    app.setSpeed(preset.rawValue)
                } label: {
                    Text(preset.label)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(app.speedMps == preset.rawValue ? .accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Slider(
                    value: Binding(get: { app.speedMps }, set: { app.setSpeed($0) }),
                    in: 0.1...10,
                    step: 0.1
                )
                .frame(width: 200)
                Text(String(format: "%.1f m/s", app.speedMps))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { app.confirmAction() }) {
                Label(walkButtonTitle, systemImage: "figure.walk")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canConfirmWalk)
        }
    }

    private var canConfirmWalk: Bool {
        isReady && app.pendingTarget != nil && app.pendingRoute != nil && !app.isPlanningRoute
    }

    private var walkButtonTitle: String {
        app.isPlanningRoute ? "Planning…" : "Walk"
    }

    private var isReady: Bool { connection.state.isReady }
}
