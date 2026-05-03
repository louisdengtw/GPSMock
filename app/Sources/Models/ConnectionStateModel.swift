import Foundation
import Observation

enum ConnectionState: Equatable {
    case sidecarDown(detail: String)
    case sidecarUpDeviceAbsent(detail: String)
    case tunneldUnreachable(detail: String)
    case sidecarUpDevicePresent(device: DeviceInfo)

    var isReady: Bool {
        if case .sidecarUpDevicePresent = self { return true }
        return false
    }

    var pillTitle: String {
        switch self {
        case .sidecarDown:                return "Sidecar not running"
        case .sidecarUpDeviceAbsent:      return "No iPhone detected"
        case .tunneldUnreachable:         return "Tunneld unreachable"
        case .sidecarUpDevicePresent(let d): return "Connected: \(d.name)"
        }
    }

    /// Concrete next-step the user should run, if any.
    var remediationCommand: String? {
        switch self {
        case .sidecarDown:           return "python -m gpsmock_sidecar"
        case .tunneldUnreachable:    return "sudo pymobiledevice3 remote tunneld"
        case .sidecarUpDeviceAbsent: return "Plug in iPhone via USB and trust the Mac"
        case .sidecarUpDevicePresent: return nil
        }
    }
}

@Observable
final class ConnectionStateModel {
    private(set) var state: ConnectionState = .sidecarDown(detail: "starting")
    private var pollTask: Task<Void, Never>?

    func start() async {
        pollTask?.cancel()
        pollTask = Task { await self.pollLoop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollLoop() async {
        var failureBackoff: UInt64 = 2_000_000_000  // 2 s
        let maxBackoff: UInt64    = 10_000_000_000  // 10 s
        let steadyInterval: UInt64 = 5_000_000_000  // 5 s when up

        while !Task.isCancelled {
            let next = await tickOnce()
            await MainActor.run { self.state = next }

            let interval: UInt64
            if next.isReady {
                interval = steadyInterval
                failureBackoff = 2_000_000_000
            } else {
                interval = failureBackoff
                failureBackoff = min(failureBackoff * 2, maxBackoff)
            }
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    private func tickOnce() async -> ConnectionState {
        do {
            try await SidecarClient.shared.health()
        } catch let e as SidecarError {
            return .sidecarDown(detail: e.userMessage)
        } catch {
            return .sidecarDown(detail: error.localizedDescription)
        }
        do {
            let info = try await SidecarClient.shared.device()
            return .sidecarUpDevicePresent(device: info)
        } catch let e as SidecarError {
            switch e {
            case .noDevice(let d):
                return .sidecarUpDeviceAbsent(detail: d)
            case .tunneldUnreachable(let d), .mounterFailed(let d):
                return .tunneldUnreachable(detail: d)
            case .sidecarUnreachable(let d):
                return .sidecarDown(detail: d)
            default:
                return .sidecarUpDeviceAbsent(detail: e.userMessage)
            }
        } catch {
            return .sidecarDown(detail: error.localizedDescription)
        }
    }
}
