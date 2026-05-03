import CoreLocation
import Observation

@Observable
final class StatusPollModel {
    private(set) var current: CLLocationCoordinate2D?
    private(set) var walking: Bool = false
    private(set) var lastWalkEndedAt: Date?

    private var pollTask: Task<Void, Never>?

    func resume(connection: ConnectionState) {
        guard connection.isReady else { return }
        if pollTask != nil { return }
        pollTask = Task { await self.loop() }
    }

    func pause() {
        pollTask?.cancel()
        pollTask = nil
    }

    func connectionDidChange(to next: ConnectionState) {
        if next.isReady {
            resume(connection: next)
        } else {
            pause()
            // Drop stale current marker on disconnect.
            current = nil
            walking = false
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            do {
                let s = try await SidecarClient.shared.status()
                await MainActor.run {
                    let wasWalking = self.walking
                    self.walking = s.walking
                    if let c = s.current, c.count == 2 {
                        self.current = CLLocationCoordinate2D(latitude: c[0], longitude: c[1])
                    } else {
                        self.current = nil
                    }
                    if wasWalking && !s.walking {
                        self.lastWalkEndedAt = Date()
                    }
                }
            } catch {
                // Swallow — the connection model is responsible for surfacing sidecar-down.
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
