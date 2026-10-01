import Foundation
import CoreLocation
import MapKit

enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case walking, driving
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var transportType: MKDirectionsTransportType { self == .walking ? .walking : .automobile }
}

enum SessionStatus: String, Codable {
    case idle, preparing, running, paused, waiting, recovering, completed, failed

    var isActive: Bool {
        [.preparing, .running, .paused, .waiting, .recovering].contains(self)
    }
}

struct Coordinate: Codable, Hashable, Identifiable {
    var id: String { "\(latitude),\(longitude)" }
    let latitude: Double
    let longitude: Double
    var cl: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    init(_ c: CLLocationCoordinate2D) {
        latitude = c.latitude
        longitude = c.longitude
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct SavedPlace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var subtitle: String
    var coordinate: Coordinate
}

struct RandomPauseRule: Codable, Hashable {
    var chancePercent: Int = 0
    var minimumSeconds: Int = 30
    var maximumSeconds: Int = 120
}

struct RoutePlan: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var start: SavedPlace
    var destination: SavedPlace
    var mode: TravelMode
    var targetSpeedKmh: Double
    var points: [Coordinate]
    var distanceMeters: Double
    var expectedTravelTime: TimeInterval
    var pauseAtDestination: TimeInterval
    var waypoints: [SavedPlace]? = nil
    var randomPause: RandomPauseRule? = nil
}

struct DelayWindow: Codable, Hashable {
    var minimumMinutes: Int = 0
    var maximumMinutes: Int = 0

    func randomizedSeconds() -> TimeInterval {
        let low = max(0, min(minimumMinutes, maximumMinutes))
        let high = max(low, max(minimumMinutes, maximumMinutes))
        return TimeInterval(Int.random(in: low...high) * 60)
    }
}

struct RoutineStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var scheduledHour: Int
    var scheduledMinute: Int
    var routeID: UUID?
    var stayDurationMinutes: Int
    var delay: DelayWindow
    var enabled: Bool = true
}

struct RoutineProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Calendar weekday values: 1 = Sunday ... 7 = Saturday
    var weekdays: Set<Int>
    var steps: [RoutineStep]
    var enabled: Bool = true
}

struct EngineSnapshot: Codable, Hashable {
    var status: SessionStatus = .idle
    var routeID: UUID?
    var routineID: UUID?
    var routineStepID: UUID?
    var pointIndex: Int = 0
    var lastCoordinate: Coordinate?
    var pauseUntil: Date?
    var destinationPauseSeconds: TimeInterval = 0
    var startedAt: Date?
    var lastHeartbeat: Date = .now
    var message: String = "Ready"
}

struct RoutineRuntimeState: Codable, Hashable {
    var targetDates: [String: Date] = [:]
    var completedKeys: [String] = []
}

struct SearchSuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion

    static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(subtitle)
    }
}
