import Foundation

struct DeviceInfo: Decodable, Equatable {
    let udid: String
    let name: String
    let ios_version: String
}

struct SidecarStatus: Decodable, Equatable {
    let current: [Double]?    // [lat, lon] or nil
    let walking: Bool
}

actor SidecarClient {
    static let shared = SidecarClient()

    private let baseURL = URL(string: "http://127.0.0.1:5555")!

    private let standardSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        cfg.timeoutIntervalForResource = 2
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private let walkSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 10
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    // ------------------------------------------------------------- endpoints

    func health() async throws {
        let req = makeRequest(path: "/health", method: "GET")
        let (_, resp) = try await perform(req, session: standardSession)
        if resp.statusCode != 200 {
            throw SidecarError.server(detail: "health \(resp.statusCode)")
        }
    }

    func device() async throws -> DeviceInfo {
        let req = makeRequest(path: "/device", method: "GET")
        let (data, resp) = try await perform(req, session: standardSession)
        switch resp.statusCode {
        case 200:
            return try decode(DeviceInfo.self, from: data)
        case 404:
            throw SidecarError.noDevice(detail: errorDetail(data))
        case 503:
            let detail = errorDetail(data)
            if detail.contains("mounter") {
                throw SidecarError.mounterFailed(detail: detail)
            }
            throw SidecarError.tunneldUnreachable(detail: detail)
        default:
            throw SidecarError.server(detail: "\(resp.statusCode): \(errorDetail(data))")
        }
    }

    func teleport(lat: Double, lon: Double) async throws {
        var req = makeRequest(path: "/teleport", method: "POST")
        req.httpBody = try JSONEncoder().encode(["lat": lat, "lon": lon])
        let (data, resp) = try await perform(req, session: standardSession)
        try ensureSuccess(data: data, response: resp, expecting: 200)
    }

    func walk(points: [(lat: Double, lon: Double)], speedMps: Double) async throws {
        struct Body: Encodable {
            let points: [[Double]]
            let speed_mps: Double
        }
        let body = Body(
            points: points.map { [$0.lat, $0.lon] },
            speed_mps: speedMps
        )
        var req = makeRequest(path: "/walk", method: "POST")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await perform(req, session: walkSession)
        try ensureSuccess(data: data, response: resp, expecting: 202)
    }

    func clear() async throws {
        let req = makeRequest(path: "/clear", method: "POST")
        let (data, resp) = try await perform(req, session: standardSession)
        try ensureSuccess(data: data, response: resp, expecting: 200)
    }

    /// Best-effort synchronous-ish clear used at app exit. Swallows errors.
    func clearBestEffort(timeout: TimeInterval = 2) async {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        let s = URLSession(configuration: cfg)
        let req = makeRequest(path: "/clear", method: "POST")
        _ = try? await s.data(for: req)
    }

    func status() async throws -> SidecarStatus {
        let req = makeRequest(path: "/status", method: "GET")
        let (data, resp) = try await perform(req, session: standardSession)
        if resp.statusCode != 200 {
            throw SidecarError.server(detail: "status \(resp.statusCode)")
        }
        return try decode(SidecarStatus.self, from: data)
    }

    // ------------------------------------------------------------- helpers

    private func makeRequest(path: String, method: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func perform(
        _ req: URLRequest,
        session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw SidecarError.malformed(detail: "non-HTTP response")
            }
            return (data, http)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
                 .notConnectedToInternet, .dnsLookupFailed:
                throw SidecarError.sidecarUnreachable(detail: urlError.localizedDescription)
            case .timedOut:
                throw SidecarError.sidecarUnreachable(detail: "timeout")
            default:
                throw SidecarError.sidecarUnreachable(detail: urlError.localizedDescription)
            }
        }
    }

    private func ensureSuccess(
        data: Data, response: HTTPURLResponse, expecting: Int
    ) throws {
        if response.statusCode == expecting { return }
        switch response.statusCode {
        case 400, 422:
            throw SidecarError.validation(detail: errorDetail(data))
        case 404:
            throw SidecarError.noDevice(detail: errorDetail(data))
        case 503:
            let detail = errorDetail(data)
            if detail.contains("mounter") {
                throw SidecarError.mounterFailed(detail: detail)
            }
            throw SidecarError.tunneldUnreachable(detail: detail)
        default:
            throw SidecarError.server(detail: "\(response.statusCode): \(errorDetail(data))")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SidecarError.malformed(detail: error.localizedDescription)
        }
    }

    private func errorDetail(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        if let detail = obj["detail"] as? String { return detail }
        if let error = obj["error"] as? String { return error }
        return obj.description
    }
}
