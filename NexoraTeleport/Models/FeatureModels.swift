import Foundation
import CoreLocation

enum BatteryMode: String, Codable, CaseIterable, Identifiable {
    case performance
    case balanced
    case saver

    var id: String { rawValue }
    var label: String {
        switch self {
        case .performance: return "Performance"
        case .balanced: return "Balanced"
        case .saver: return "Battery Saver"
        }
    }
}

enum MapAppearance: String, Codable, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct AppPreferences: Codable, Hashable {
    var liveWhenIdle = true
    var batteryMode: BatteryMode = .balanced
    var mapAppearance: MapAppearance = .standard
    var historyEnabled = true
    var cloudSyncEnabled = false
    var localOnlyMode = true
}

struct PlaceMetadata: Codable, Hashable {
    var isFavorite = false
    var note = ""
}

enum SessionOutcome: String, Codable {
    case completed, failed, stopped
}

struct SessionHistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var routeID: UUID
    var routeName: String
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var outcome: SessionOutcome
    var message: String
}

enum RoutineExceptionKind: String, Codable, CaseIterable, Identifiable {
    case skipDay
    case delay

    var id: String { rawValue }
    var label: String { self == .skipDay ? "Skip day" : "Extra delay" }
}

struct RoutineException: Codable, Identifiable, Hashable {
    var id = UUID()
    var profileID: UUID
    var date: Date
    var kind: RoutineExceptionKind
    var delayMinutes: Int = 0
    var note: String = ""
}

struct TeleportProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var routineIDs: Set<UUID>
    var batteryMode: BatteryMode = .balanced
    var mapAppearance: MapAppearance = .standard
    var liveWhenIdle = true
}

struct RouteHealthReport: Hashable {
    var isHealthy: Bool
    var warnings: [String]
    var offlineReady: Bool
}

struct PortableBundle: Codable {
    var version = 1
    var exportedAt = Date()
    var places: [SavedPlace]
    var routes: [RoutePlan]
    var routines: [RoutineProfile]
    var profiles: [TeleportProfile]
    var exceptions: [RoutineException]
    var placeMetadata: [String: PlaceMetadata]
    var preferences: AppPreferences
}

struct DiagnosticSnapshot: Codable {
    var generatedAt: Date
    var appVersion: String
    var engineStatus: String
    var engineMessage: String
    var heartbeatAgeSeconds: Double
    var locationPermission: String
    var backgroundTracking: Bool
    var liveTracking: Bool
    var placeCount: Int
    var routeCount: Int
    var routineCount: Int
    var historyCount: Int
    var note: String
}
