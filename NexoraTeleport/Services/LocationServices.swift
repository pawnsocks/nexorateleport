import Foundation
import CoreLocation

@MainActor
final class DeviceLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var actualLocation: CLLocation?
    @Published var lastError: String?
    @Published var isBackgroundTracking = false
    @Published var isLiveTracking = false
    @Published var headingDegrees: Double?
    @Published var lastUpdated: Date?
    @Published var batteryMode: BatteryMode = .balanced {
        didSet { applyBatteryMode() }
    }
    @Published var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    private let manager = CLLocationManager()
    private var wantsAlwaysAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        applyBatteryMode()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var speedKmh: Double {
        guard let speed = actualLocation?.speed, speed >= 0 else { return 0 }
        return speed * 3.6
    }

    var courseDegrees: Double? {
        guard let course = actualLocation?.course, course >= 0 else { return nil }
        return course
    }

    var accuracyMeters: Double? {
        guard let value = actualLocation?.horizontalAccuracy, value >= 0 else { return nil }
        return value
    }

    func requestPermissions() {
        wantsAlwaysAuthorization = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            lastError = nil
        case .denied, .restricted:
            lastError = "Location permission is disabled. Enable it in Settings."
        @unknown default:
            lastError = "Unknown location permission state."
        }
    }

    func startLiveTracking() {
        guard CLLocationManager.locationServicesEnabled() else {
            lastError = "Location Services are disabled."
            return
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            isLiveTracking = true
            isBackgroundTracking = false
            lastError = nil
        case .notDetermined:
            requestPermissions()
            lastError = "Grant location permission, then enable Live again."
        case .denied, .restricted:
            lastError = "Location permission is disabled. Enable it in Settings."
        @unknown default:
            lastError = "Unknown location permission state."
        }
    }

    func startBackgroundTracking() {
        guard CLLocationManager.locationServicesEnabled() else {
            lastError = "Location Services are disabled."
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            isBackgroundTracking = true
            isLiveTracking = true
            lastError = nil
        case .notDetermined:
            requestPermissions()
            lastError = "Grant location permission, then start again."
        case .denied, .restricted:
            lastError = "Location permission is disabled. Enable it in Settings."
        @unknown default:
            lastError = "Unknown location permission state."
        }
    }

    func downgradeToLiveTracking() {
        guard isLiveTracking || isBackgroundTracking else {
            startLiveTracking()
            return
        }
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        isBackgroundTracking = false
        isLiveTracking = true
    }

    func stopAllTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
        isBackgroundTracking = false
        isLiveTracking = false
    }

    func stopBackgroundTracking() {
        if isLiveTracking {
            downgradeToLiveTracking()
        } else {
            stopAllTracking()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if wantsAlwaysAuthorization, manager.authorizationStatus == .authorizedWhenInUse {
            wantsAlwaysAuthorization = false
            manager.requestAlwaysAuthorization()
        }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            stopAllTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        actualLocation = newest
        lastUpdated = Date()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        headingDegrees = value >= 0 ? value : nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }

    @objc private func thermalStateChanged() {
        thermalState = ProcessInfo.processInfo.thermalState
        applyBatteryMode()
    }

    private func applyBatteryMode() {
        let effectiveMode: BatteryMode
        switch thermalState {
        case .serious, .critical:
            effectiveMode = .saver
        default:
            effectiveMode = batteryMode
        }

        switch effectiveMode {
        case .performance:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
        case .balanced:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 5
        case .saver:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 25
        }
    }
}

/// Boundary for a supported location-output mechanism.
/// Public iOS APIs do not let one normal app replace Core Location for other apps.
protocol LocationOutputProvider: Sendable {
    var displayName: String { get }
    func begin() async throws
    func apply(_ coordinate: Coordinate, speedMetersPerSecond: Double) async throws
    func end() async
}

struct AppOnlyLocationProvider: LocationOutputProvider {
    let displayName = "In-app route engine"
    func begin() async throws { }
    func apply(_ coordinate: Coordinate, speedMetersPerSecond: Double) async throws { }
    func end() async { }
}
