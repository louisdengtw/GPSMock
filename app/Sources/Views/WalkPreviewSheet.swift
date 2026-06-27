import SwiftUI

struct WalkPreviewSheet: View {
    let plan: RoutePlan
    @Environment(AppViewModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Label("Walk preview", systemImage: "figure.walk")
                    .font(.headline)
                stat(label: "Distance", value: String(format: "%.0f m", plan.distanceMeters))
                stat(label: "ETA", value: etaString)
                if plan.usedFallback {
                    Label("straight-line", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if app.isPlanningRoute {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Re-planning…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button {
                    if app.isPickingStart {
                        app.endPickingStart()
                    } else {
                        app.beginPickingStart()
                    }
                } label: {
                    Label(
                        app.isPickingStart ? "Cancel pick" : "Set start here",
                        systemImage: app.isPickingStart ? "xmark.circle" : "mappin.and.ellipse"
                    )
                }
                .buttonStyle(.bordered)
                .tint(app.isPickingStart ? .accentColor : nil)

                if app.customOrigin != nil {
                    Button {
                        app.resetCustomOrigin()
                    } label: {
                        Label("Reset start to GPS", systemImage: "location.circle")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Cancel", role: .cancel) {
                    app.cancelPreview()
                }
                .buttonStyle(.bordered)

                Button("Confirm") {
                    app.confirmAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.isPlanningRoute)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
        .frame(maxWidth: 480)
    }

    private var etaString: String {
        let seconds = plan.distanceMeters / max(app.speedMps, 0.1)
        if seconds < 90 {
            return String(format: "%.0f s", seconds)
        }
        return String(format: "%.1f min", seconds / 60)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.monospacedDigit())
        }
    }
}

// MARK: - Loop area

/// Idle entry point shown in Walk mode that starts the loop-area drawing flow.
struct LoopEntryButton: View {
    @Environment(AppViewModel.self) private var app

    var body: some View {
        Button {
            app.beginDrawingLoop()
        } label: {
            Label("Loop an area", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
    }
}

/// Drawing + preview panel for a loop area: waypoint count, remove-last, plan,
/// and (once planned) per-lap distance/ETA with Start/Cancel.
struct LoopDrawSheet: View {
    let plan: RoutePlan?
    @Environment(AppViewModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Label("Loop area", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)
                HStack(spacing: 4) {
                    Text("\(app.loopWaypoints.count) point\(app.loopWaypoints.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    if app.loopWaypoints.count >= AppViewModel.maxLoopWaypoints {
                        Text("· max \(AppViewModel.maxLoopWaypoints)")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if let plan {
                    stat(label: "Per lap", value: String(format: "%.0f m", plan.distanceMeters))
                    stat(label: "ETA / lap", value: etaString(plan))
                    if plan.usedFallback {
                        Label("straight-line", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text("Tap the map to outline an area (3+ points)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if app.isPlanningRoute {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Planning…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button {
                    app.removeLastLoopWaypoint()
                } label: {
                    Label("Remove last", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(app.loopWaypoints.isEmpty)

                Button {
                    app.planLoop()
                } label: {
                    Label(plan == nil ? "Plan loop" : "Re-plan", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(!app.canPlanLoop || app.isPlanningRoute)

                Spacer()

                Button("Cancel", role: .cancel) {
                    app.cancelDrawingLoop()
                }
                .buttonStyle(.bordered)

                Button("Start loop") {
                    app.confirmLoop()
                }
                .buttonStyle(.borderedProminent)
                .disabled(plan == nil || app.isPlanningRoute || !app.isReady)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
        .frame(maxWidth: 520)
    }

    private func etaString(_ plan: RoutePlan) -> String {
        let seconds = plan.distanceMeters / max(app.speedMps, 0.1)
        if seconds < 90 {
            return String(format: "%.0f s", seconds)
        }
        return String(format: "%.1f min", seconds / 60)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.monospacedDigit())
        }
    }
}

/// Compact bar shown while a loop is actively running, with a Stop control.
struct LoopRunningBar: View {
    @Environment(AppViewModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Label("Looping this area", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text("walking until you stop")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Stop", role: .destructive) {
                app.stopLoop()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
        .frame(maxWidth: 520)
    }
}
