import Foundation

// MARK: - User

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    var avatarUrl: String?
}

// MARK: - Dog

struct Dog: Codable, Identifiable {
    let id: String
    var name: String
    var breed: String?
    var weightLbs: Double?
    var avatarUrl: String?
    let createdAt: Date
}

// MARK: - Collar

struct Collar: Codable, Identifiable {
    let id: String
    let dogId: String
    let provider: CollarProvider
    var externalId: String?
    var bleServiceUUID: String?
    var lastSyncedAt: Date?
}

enum CollarProvider: String, Codable {
    case fi
    case whistle
    case tractive
    case bleGeneric = "ble_generic"
}

// MARK: - Location

struct Location: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: LocationType
    let lat: Double
    let lng: Double
    let radiusMeters: Int
    let isVerified: Bool
    var distanceMeters: Double?
}

enum LocationType: String, Codable {
    case dogPark = "dog_park"
    case trail
    case beach
    case other
}

// MARK: - Session

struct Session: Codable, Identifiable {
    let id: String
    let dogId: String
    var locationId: String?
    let startedAt: Date
    var endedAt: Date?
    let entryMethod: EntryMethod
    var totalSteps: Int
    var maxSpeedMph: Double
    var avgSpeedMph: Double
    var peakAccelG: Double
    var durationSecs: Int?
}

enum EntryMethod: String, Codable {
    case geofence
    case checkin
}

// MARK: - Leaderboard

struct LeaderboardEntry: Codable, Identifiable {
    var id: String { sessionId }
    let rank: Int
    let dogId: String
    let dogName: String
    let ownerName: String
    let value: Double
    let sessionId: String
}

struct LeaderboardResponse: Codable {
    let locationId: String
    let metric: String
    let period: String
    let entries: [LeaderboardEntry]
}

// MARK: - Collar Reading (normalized)

struct CollarReading {
    let collarId: String
    let timestamp: Date
    let steps: Int
    let speedMph: Double
    let accelerationG: Double
    let batteryPct: Double
}

// MARK: - Dog Stats

struct DogStats: Codable {
    let totalSessions: Int
    let totalSteps: Int
    let bestSpeedMph: Double
    let totalDurationSecs: Int
    let avgSpeedMph: Double
    let bestAccelG: Double
    let favoritePark: String?
    let favoriteParkVisits: Int
}

// MARK: - Auth

struct AuthResponse: Codable {
    let token: String
    let refreshToken: String?
    let user: User
}
