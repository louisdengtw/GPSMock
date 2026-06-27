import SwiftUI

struct ContentView: View {
    @Environment(ConnectionStateModel.self) private var connection
    @Environment(StatusPollModel.self) private var status
    @Environment(AppViewModel.self) private var app

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapSurface()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ConnectionPill()
                if !connection.state.isReady {
                    OnboardingCard()
                }
                if let banner = app.banner {
                    BannerView(text: banner)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .top) {
            SearchBar()
                .padding(.top, 16)
        }
        .overlay(alignment: .topTrailing) {
            LocateMeButton()
                .padding(16)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if app.isLooping {
                    LoopRunningBar()
                } else if app.isDrawingLoop {
                    LoopDrawSheet(plan: app.pendingRoute)
                } else if let plan = app.pendingRoute, app.mode == .walk {
                    WalkPreviewSheet(plan: plan)
                } else if app.mode == .walk {
                    LoopEntryButton()
                }
                ControlsPanel()
            }
            .padding(16)
        }
        .background(
            Button("") {
                // Esc backs out of whichever transient state is active.
                if app.isDrawingLoop {
                    app.cancelDrawingLoop()
                } else if app.isPickingStart {
                    app.endPickingStart()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(!app.isPickingStart && !app.isDrawingLoop)
            .opacity(0)
            .accessibilityHidden(true)
        )
    }
}

private struct BannerView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 1)
    }
}
