import SwiftUI

@main
struct GPSMockApp: App {
    @State private var connection = ConnectionStateModel()
    @State private var status = StatusPollModel()
    @State private var appModel = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("GPSMock") {
            ContentView()
                .environment(connection)
                .environment(status)
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    appModel.bootstrap(connection: connection, status: status)
                    async let locate: Void = appModel.acquireInitialLocationIfNeeded()
                    await connection.start()
                    await locate
                }
                .onChange(of: connection.state) { _, newState in
                    status.connectionDidChange(to: newState)
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background, .inactive:
                        status.pause()
                    case .active:
                        status.resume(connection: connection.state)
                    @unknown default:
                        break
                    }
                }
                .onDisappear {
                    appModel.handleAppExit()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit GPSMock") {
                    appModel.handleAppExit()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
