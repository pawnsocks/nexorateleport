import Foundation
import SwiftUI
import UserNotifications
import CoreLocation

@MainActor
final class AppModel: ObservableObject {
    @Published var places: [SavedPlace] = []
    @Published var routes: [RoutePlan] = [] { didSet { routeEngine.configure(routes: routes) } }
    @Published var routines: [RoutineProfile] = []
    @Published var history: [SessionHistoryEntry] = []
    @Published var profiles: [TeleportProfile] = []
    @Published var exceptions: [RoutineException] = []
    @Published var placeMetadata: [String: PlaceMetadata] = [:]
    @Published var preferences = AppPreferences()
    @Published var activeProfileID: UUID?
    @Published var routeCandidates: [RoutePlan] = []
    @Published var selectedWaypoints: [SavedPlace] = []
    @Published var selectedStart: SavedPlace?
    @Published var selectedDestination: SavedPlace?
    @Published var routePauseChance = 0
    @Published var routePauseMinimumSeconds = 30
    @Published var routePauseMaximumSeconds = 120
    @Published var lastError: String?
    @Published var cloudMessage: String?

    let location = DeviceLocationService()
    let routeEngine = RouteEngine()
    let routineEngine = RoutineEngine()

    private let store = StateStore.shared
    private let routeService = RouteService()
    private let exportService = ExportService()
    private let cloud = CloudSyncService.shared
    private var bootstrapped = false

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true

        places = await store.load([SavedPlace].self, name: "places.json", fallback: [])
        routes = await store.load([RoutePlan].self, name: "routes.json", fallback: [])
        routines = await store.load([RoutineProfile].self, name: "routines.json", fallback: [])
        history = await store.load([SessionHistoryEntry].self, name: "history.json", fallback: [])
        profiles = await store.load([TeleportProfile].self, name: "profiles.json", fallback: [])
        exceptions = await store.load([RoutineException].self, name: "exceptions.json", fallback: [])
        placeMetadata = await store.load([String: PlaceMetadata].self, name: "place-metadata.json", fallback: [:])
        preferences = await store.load(AppPreferences.self, name: "preferences.json", fallback: AppPreferences())
        let restoredProfile: UUID? = await store.load(Optional<UUID>.self, name: "active-profile.json", fallback: nil)
        activeProfileID = restoredProfile

        location.batteryMode = preferences.batteryMode
        routeEngine.configure(routes: routes)
        routeEngine.onSessionEnded = { [weak self] in
            guard let self else { return }
            if self.preferences.liveWhenIdle {
                self.location.downgradeToLiveTracking()
            } else {
                self.location.stopAllTracking()
            }
        }
        routeEngine.onRouteFinished = { [weak self] route, outcome, message, startedAt, endedAt in
            self?.recordHistory(route: route, outcome: outcome, message: message, startedAt: startedAt, endedAt: endedAt)
        }
        await routeEngine.restore()
        routineEngine.attach(self)

        if preferences.liveWhenIdle {
            location.startLiveTracking()
        }
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            routineEngine.restart()
            if preferences.liveWhenIdle && !routeEngine.snapshot.status.isActive {
                location.startLiveTracking()
            }
        case .background, .inactive:
            checkpoint()
        @unknown default:
            break
        }
    }

    func checkpoint() {
        let placesSnapshot = places
        let routesSnapshot = routes
        let routinesSnapshot = routines
        let historySnapshot = history
        let profilesSnapshot = profiles
        let exceptionsSnapshot = exceptions
        let metadataSnapshot = placeMetadata
        let preferenceSnapshot = preferences
        let profileSnapshot = activeProfileID
        Task {
            try? await store.save(placesSnapshot, name: "places.json")
            try? await store.save(routesSnapshot, name: "routes.json")
            try? await store.save(routinesSnapshot, name: "routines.json")
            try? await store.save(historySnapshot, name: "history.json")
            try? await store.save(profilesSnapshot, name: "profiles.json")
            try? await store.save(exceptionsSnapshot, name: "exceptions.json")
            try? await store.save(metadataSnapshot, name: "place-metadata.json")
            try? await store.save(preferenceSnapshot, name: "preferences.json")
            try? await store.save(profileSnapshot, name: "active-profile.json")
            if preferenceSnapshot.cloudSyncEnabled {
                try? await cloud.push(portableBundle())
            }
        }
    }

    func addPlace(_ place: SavedPlace) {
        guard !places.contains(where: { $0.coordinate == place.coordinate && $0.name == place.name }) else { return }
        places.append(place)
        savePlaces()
    }

    func deletePlace(_ id: UUID) {
        places.removeAll { $0.id == id }
        placeMetadata.removeValue(forKey: id.uuidString)
        selectedWaypoints.removeAll { $0.id == id }
        if selectedStart?.id == id { selectedStart = nil }
        if selectedDestination?.id == id { selectedDestination = nil }
        savePlaces()
    }

    func toggleFavorite(_ place: SavedPlace) {
        var metadata = placeMetadata[place.id.uuidString] ?? PlaceMetadata()
        metadata.isFavorite.toggle()
        placeMetadata[place.id.uuidString] = metadata
        saveMetadata()
    }

    func updateNote(for place: SavedPlace, note: String) {
        var metadata = placeMetadata[place.id.uuidString] ?? PlaceMetadata()
        metadata.note = note
        placeMetadata[place.id.uuidString] = metadata
        saveMetadata()
    }

    func isFavorite(_ place: SavedPlace) -> Bool {
        placeMetadata[place.id.uuidString]?.isFavorite == true
    }

    var favoritePlaces: [SavedPlace] {
        places.filter(isFavorite)
    }

    func calculateRoute(mode: TravelMode, speedKmh: Double) async {
        await calculateRouteAlternatives(mode: mode, speedKmh: speedKmh)
        if let first = routeCandidates.first { saveRouteCandidate(first) }
    }

    func calculateRouteAlternatives(mode: TravelMode, speedKmh: Double) async {
        guard let start = selectedStart, let destination = selectedDestination else {
            lastError = "Choose a start and destination first."
            return
        }
        do {
            routeCandidates = try await routeService.calculateAlternatives(
                start: start,
                destination: destination,
                waypoints: selectedWaypoints,
                mode: mode,
                speedKmh: speedKmh
            ).map { candidate in
                var route = candidate
                if routePauseChance > 0 {
                    route.randomPause = RandomPauseRule(
                        chancePercent: min(100, max(0, routePauseChance)),
                        minimumSeconds: min(routePauseMinimumSeconds, routePauseMaximumSeconds),
                        maximumSeconds: max(routePauseMinimumSeconds, routePauseMaximumSeconds)
                    )
                }
                return route
            }
            lastError = nil
        } catch {
            routeCandidates = []
            lastError = error.localizedDescription
        }
    }

    func saveRouteCandidate(_ route: RoutePlan) {
        if !routes.contains(where: { $0.id == route.id }) {
            routes.append(route)
            Task { try? await store.save(routes, name: "routes.json") }
        }
    }

    func importGPX(url: URL, name: String? = nil, speedKmh: Double = 5) throws {
        let points = try GPXParser().parse(url: url)
        guard let first = points.first, let last = points.last else { return }
        let start = SavedPlace(name: "GPX Start", subtitle: "Imported GPX", coordinate: first)
        let destination = SavedPlace(name: "GPX End", subtitle: "Imported GPX", coordinate: last)
        var distance = 0.0
        for pair in zip(points, points.dropFirst()) {
            distance += CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        let safeSpeed = max(1, min(speedKmh, 200))
        routes.append(RoutePlan(
            name: name ?? url.deletingPathExtension().lastPathComponent,
            start: start,
            destination: destination,
            mode: .walking,
            targetSpeedKmh: safeSpeed,
            points: points,
            distanceMeters: distance,
            expectedTravelTime: distance / (safeSpeed / 3.6),
            pauseAtDestination: 0,
            waypoints: nil
        ))
        checkpoint()
    }

    func saveReversedCopy(of route: RoutePlan) {
        var copy = route
        copy.id = UUID()
        copy.name = "\(route.destination.name) → \(route.start.name)"
        copy.start = route.destination
        copy.destination = route.start
        copy.points = Array(route.points.reversed())
        copy.waypoints = route.waypoints.map { Array($0.reversed()) }
        routes.append(copy)
        checkpoint()
    }

    func saveLoopCopy(of route: RoutePlan) {
        guard route.points.count >= 2 else { return }
        var copy = route
        copy.id = UUID()
        copy.name = "\(route.name) · Loop"
        copy.destination = route.start
        let returnPoints = Array(route.points.dropLast().reversed())
        copy.points = route.points + returnPoints
        copy.distanceMeters = route.distanceMeters * 2
        copy.expectedTravelTime = route.expectedTravelTime * 2
        copy.waypoints = (route.waypoints ?? []) + Array((route.waypoints ?? []).reversed())
        routes.append(copy)
        checkpoint()
    }

    func deleteRoute(_ id: UUID) {
        if routeEngine.snapshot.routeID == id, routeEngine.snapshot.status.isActive {
            routeEngine.stop(reason: "Active route deleted")
        }
        routes.removeAll { $0.id == id }
        for profileIndex in routines.indices {
            for stepIndex in routines[profileIndex].steps.indices where routines[profileIndex].steps[stepIndex].routeID == id {
                routines[profileIndex].steps[stepIndex].routeID = nil
            }
        }
        checkpoint()
        routineEngine.restart()
    }

    func startRoute(_ route: RoutePlan, pauseAtDestination: TimeInterval? = nil, routineID: UUID? = nil, routineStepID: UUID? = nil) {
        location.startBackgroundTracking()
        routeEngine.start(route: route, pauseAtDestination: pauseAtDestination, routineID: routineID, routineStepID: routineStepID)
    }

    func resumeRoute() {
        location.startBackgroundTracking()
        routeEngine.resume()
    }

    func saveRoutines() {
        let snapshot = routines
        Task { try? await store.save(snapshot, name: "routines.json") }
        routineEngine.restart()
    }

    func addRoutine(_ profile: RoutineProfile) {
        routines.append(profile)
        saveRoutines()
    }

    func deleteRoutine(_ id: UUID) {
        routines.removeAll { $0.id == id }
        exceptions.removeAll { $0.profileID == id }
        saveRoutines()
        checkpoint()
    }

    func addException(_ exception: RoutineException) {
        exceptions.removeAll { item in
            item.profileID == exception.profileID && Calendar.current.isDate(item.date, inSameDayAs: exception.date)
        }
        exceptions.append(exception)
        checkpoint()
        routineEngine.restart()
    }

    func deleteException(_ id: UUID) {
        exceptions.removeAll { $0.id == id }
        checkpoint()
        routineEngine.restart()
    }

    func addProfile(_ profile: TeleportProfile) {
        profiles.append(profile)
        checkpoint()
    }

    func activateProfile(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfileID = id
        preferences.batteryMode = profile.batteryMode
        preferences.mapAppearance = profile.mapAppearance
        preferences.liveWhenIdle = profile.liveWhenIdle
        location.batteryMode = profile.batteryMode
        for index in routines.indices {
            routines[index].enabled = profile.routineIDs.contains(routines[index].id)
        }
        applyLivePreference()
        saveRoutines()
        checkpoint()
    }

    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = nil }
        checkpoint()
    }

    func applyPreferences() {
        location.batteryMode = preferences.batteryMode
        applyLivePreference()
        checkpoint()
    }

    func applyLivePreference() {
        if routeEngine.snapshot.status.isActive { return }
        if preferences.liveWhenIdle {
            location.startLiveTracking()
        } else {
            location.stopAllTracking()
        }
    }

    func clearHistory() {
        history = []
        checkpoint()
    }

    func killSwitch() {
        routeEngine.stop(reason: "Stopped by kill switch")
        if preferences.liveWhenIdle {
            location.downgradeToLiveTracking()
        } else {
            location.stopAllTracking()
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "nexorateleport" else { return }
        switch url.host {
        case "resume": resumeRoute()
        case "stop": killSwitch()
        case "live":
            preferences.liveWhenIdle = true
            applyPreferences()
        default: break
        }
    }

    func portableBundle() -> PortableBundle {
        PortableBundle(
            places: places,
            routes: routes,
            routines: routines,
            profiles: profiles,
            exceptions: exceptions,
            placeMetadata: placeMetadata,
            preferences: preferences
        )
    }

    func exportBackupURL() throws -> URL { try exportService.portableBundleURL(portableBundle()) }
    func exportGPXURL(route: RoutePlan) throws -> URL { try exportService.gpxURL(route: route) }

    func importBackup(from url: URL) throws {
        let bundle = try exportService.decodePortableBundle(from: url)
        places = bundle.places
        routes = bundle.routes
        routines = bundle.routines
        profiles = bundle.profiles
        exceptions = bundle.exceptions
        placeMetadata = bundle.placeMetadata
        preferences = bundle.preferences
        location.batteryMode = preferences.batteryMode
        routeEngine.configure(routes: routes)
        applyLivePreference()
        checkpoint()
        routineEngine.restart()
    }

    func syncToICloud() async {
        do {
            guard await cloud.isAvailable() else {
                cloudMessage = "iCloud is unavailable. Enable the iCloud capability and sign in to iCloud."
                return
            }
            try await cloud.push(portableBundle())
            cloudMessage = "Backup uploaded to iCloud."
        } catch {
            cloudMessage = error.localizedDescription
        }
    }

    func restoreFromICloud() async {
        do {
            guard let bundle = try await cloud.pull() else {
                cloudMessage = "No Nexora Teleport backup found in iCloud."
                return
            }
            places = bundle.places
            routes = bundle.routes
            routines = bundle.routines
            profiles = bundle.profiles
            exceptions = bundle.exceptions
            placeMetadata = bundle.placeMetadata
            preferences = bundle.preferences
            location.batteryMode = preferences.batteryMode
            routeEngine.configure(routes: routes)
            checkpoint()
            routineEngine.restart()
            cloudMessage = "iCloud backup restored."
        } catch {
            cloudMessage = error.localizedDescription
        }
    }

    func diagnosticsURL() throws -> URL {
        let permission: String
        switch location.authorization {
        case .notDetermined: permission = "notDetermined"
        case .restricted: permission = "restricted"
        case .denied: permission = "denied"
        case .authorizedAlways: permission = "authorizedAlways"
        case .authorizedWhenInUse: permission = "authorizedWhenInUse"
        @unknown default: permission = "unknown"
        }
        let snapshot = DiagnosticSnapshot(
            generatedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            engineStatus: routeEngine.snapshot.status.rawValue,
            engineMessage: routeEngine.snapshot.message,
            heartbeatAgeSeconds: max(0, Date().timeIntervalSince(routeEngine.snapshot.lastHeartbeat)),
            locationPermission: permission,
            backgroundTracking: location.isBackgroundTracking,
            liveTracking: location.isLiveTracking,
            placeCount: places.count,
            routeCount: routes.count,
            routineCount: routines.count,
            historyCount: history.count,
            note: "Coordinates and saved-place names are intentionally excluded."
        )
        return try exportService.diagnosticsURL(snapshot)
    }

    private func recordHistory(route: RoutePlan, outcome: SessionOutcome, message: String, startedAt: Date, endedAt: Date) {
        guard preferences.historyEnabled else { return }
        history.insert(SessionHistoryEntry(
            routeID: route.id,
            routeName: route.name,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: route.distanceMeters,
            outcome: outcome,
            message: message
        ), at: 0)
        if history.count > 300 { history = Array(history.prefix(300)) }
        checkpoint()
    }

    private func savePlaces() {
        let snapshot = places
        Task { try? await store.save(snapshot, name: "places.json") }
    }

    private func saveMetadata() {
        let snapshot = placeMetadata
        Task { try? await store.save(snapshot, name: "place-metadata.json") }
    }
}
