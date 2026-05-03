import Foundation

enum SidecarError: Error, Equatable {
    case sidecarUnreachable(detail: String)   // connection refused, timeout
    case tunneldUnreachable(detail: String)   // 503 error: tunneld_unreachable
    case noDevice(detail: String)             // 404 from /device
    case mounterFailed(detail: String)        // 503 error: mounter_failed
    case validation(detail: String)           // 400/422
    case server(detail: String)               // 5xx (other)
    case malformed(detail: String)            // unparseable response

    var userMessage: String {
        switch self {
        case .sidecarUnreachable: return "Sidecar not running"
        case .tunneldUnreachable: return "Tunneld unreachable"
        case .noDevice:           return "No iPhone detected"
        case .mounterFailed(let d): return "DDI mount failed: \(d)"
        case .validation(let d):  return "Invalid request: \(d)"
        case .server(let d):      return "Sidecar error: \(d)"
        case .malformed(let d):   return "Malformed response: \(d)"
        }
    }
}
