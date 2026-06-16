import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int, String?)
    case decodingError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let e): return e.localizedDescription
        case .httpError(let code, let msg): return msg ?? "HTTP \(code)"
        case .decodingError(let e): return "Decoding error: \(e.localizedDescription)"
        case .unauthorized: return "Unauthorized — please log in again"
        }
    }
}

@MainActor
final class APIClient: ObservableObject {
    static let shared = APIClient()

    var baseURL: String = "http://localhost:3000"

    private var token: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }

    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "refresh_token") }
        set { UserDefaults.standard.set(newValue, forKey: "refresh_token") }
    }

    var isAuthenticated: Bool { token != nil }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Core Request

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (some Encodable)? = nil as String?
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try encoder.encode(body) }

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse

        if http.statusCode == 401 {
            // Attempt token refresh
            if let refreshed = try? await performRefresh() {
                self.token = refreshed.token
                self.refreshToken = refreshed.refreshToken
                // Retry once
                return try await request(path, method: method, body: body)
            }
            self.token = nil
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(http.statusCode, msg)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func performRefresh() async throws -> (token: String, refreshToken: String) {
        guard let rt = refreshToken else { throw APIError.unauthorized }
        guard let url = URL(string: "\(baseURL)/auth/refresh") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(["refreshToken": rt])

        let (data, _) = try await URLSession.shared.data(for: req)
        let res = try decoder.decode([String: String].self, from: data)
        guard let token = res["token"], let newRT = res["refreshToken"] else {
            throw APIError.unauthorized
        }
        return (token, newRT)
    }

    // MARK: - Auth

    func register(email: String, displayName: String, password: String) async throws -> AuthResponse {
        let body = ["email": email, "displayName": displayName, "password": password]
        let res: AuthResponse = try await request("/auth/register", method: "POST", body: body)
        token = res.token
        refreshToken = res.refreshToken
        return res
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = ["email": email, "password": password]
        let res: AuthResponse = try await request("/auth/login", method: "POST", body: body)
        token = res.token
        refreshToken = res.refreshToken
        return res
    }

    func logout() {
        token = nil
        refreshToken = nil
    }

    // MARK: - Dogs

    func fetchDogs() async throws -> [Dog] {
        try await request("/dogs")
    }

    func createDog(name: String, breed: String?, weightLbs: Double?) async throws -> Dog {
        struct Body: Encodable {
            let name: String
            let breed: String?
            let weightLbs: Double?
        }
        return try await request("/dogs", method: "POST", body: Body(name: name, breed: breed, weightLbs: weightLbs))
    }

    func fetchCollars(dogId: String) async throws -> [Collar] {
        try await request("/dogs/\(dogId)/collars")
    }

    func addCollar(dogId: String, provider: String, bleServiceUUID: String?) async throws -> Collar {
        struct Body: Encodable {
            let provider: String
            let bleServiceUuid: String?
        }
        return try await request("/dogs/\(dogId)/collars", method: "POST",
                                 body: Body(provider: provider, bleServiceUuid: bleServiceUUID))
    }

    // MARK: - Sessions

    func startSession(dogId: String, locationId: String?, entryMethod: String) async throws -> Session {
        struct Body: Encodable {
            let dogId: String
            let locationId: String?
            let entryMethod: String
        }
        return try await request("/sessions", method: "POST",
                                 body: Body(dogId: dogId, locationId: locationId, entryMethod: entryMethod))
    }

    func endSession(sessionId: String, stats: SessionStats) async throws -> Session {
        return try await request("/sessions/\(sessionId)", method: "PATCH", body: stats)
    }

    func fetchSessionHistory(dogId: String) async throws -> [Session] {
        try await request("/dogs/\(dogId)/sessions")
    }

    // MARK: - Locations

    func fetchLocations() async throws -> [Location] {
        try await request("/locations")
    }

    func fetchNearbyLocations(lat: Double, lng: Double) async throws -> [Location] {
        try await request("/locations/nearby?lat=\(lat)&lng=\(lng)&radiusMeters=500")
    }

    // MARK: - Leaderboard

    func fetchLeaderboard(locationId: String, metric: String, period: String) async throws -> LeaderboardResponse {
        try await request("/locations/\(locationId)/leaderboard?metric=\(metric)&period=\(period)")
    }

    // MARK: - Metrics

    func ingestMetrics(sessionId: String, readings: [MetricPayload]) async throws {
        struct Body: Encodable { let readings: [MetricPayload] }
        let _: EmptyResponse = try await request("/sessions/\(sessionId)/metrics", method: "POST",
                                                  body: Body(readings: readings))
    }
}

struct SessionStats: Encodable {
    let endedAt: Date
    let totalSteps: Int
    let maxSpeedMph: Double
    let avgSpeedMph: Double
    let peakAccelG: Double
}

struct MetricPayload: Encodable {
    let collarId: String
    let recordedAt: Date
    let steps: Int
    let speedMph: Double
    let accelerationG: Double
}

private struct EmptyResponse: Decodable {}
