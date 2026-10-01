import SwiftUI

struct StatusView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: DeviceLocationService
    @EnvironmentObject private var routeEngine: RouteEngine
    @EnvironmentObject private var routineEngine: RoutineEngine

    var body: some View {
        List {
            Section("Engine") {
                LabeledContent("Status", value: routeEngine.snapshot.status.rawValue.capitalized)
                LabeledContent("Message", value: routeEngine.snapshot.message)
                LabeledContent("Waypoint", value: String(routeEngine.snapshot.pointIndex))
                LabeledContent("Heartbeat age", value: heartbeatAge)
                if let pauseUntil = routeEngine.snapshot.pauseUntil, routeEngine.snapshot.status == .waiting {
                    LabeledContent("Waiting until", value: pauseUntil.formatted(date: .omitted, time: .shortened))
                }
            }

            Section("Live Location") {
                LabeledContent("Live", value: location.isLiveTracking ? "Active" : "Stopped")
                LabeledContent("Background", value: location.isBackgroundTracking ? "Active" : "Stopped")
                LabeledContent("Permission", value: permissionLabel)
                LabeledContent("Battery mode", value: location.batteryMode.label)
                LabeledContent("Thermal", value: thermalLabel)
                if location.actualLocation != nil {
                    LabeledContent("Speed", value: "\(location.speedKmh, specifier: "%.1f") km/h")
                    LabeledContent("Accuracy", value: location.accuracyMeters.map { "±\(Int($0)) m" } ?? "—")
                    LabeledContent("Last update", value: location.lastUpdated?.formatted(date: .omitted, time: .standard) ?? "—")
                    Text("Location acquired (coordinates hidden on this diagnostics screen).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = location.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
            }

            Section("Scheduler") {
                LabeledContent("Next", value: routineEngine.nextEvent)
                LabeledContent("Routines", value: String(model.routines.filter(\.enabled).count))
                LabeledContent("Exception days", value: String(model.exceptions.count))
            }

            Section("Recovery") {
                Button("Resume active route") { model.resumeRoute() }
                    .disabled(![.paused, .recovering].contains(routeEngine.snapshot.status))
                Button("Pause") { routeEngine.pause() }.disabled(routeEngine.snapshot.status != .running)
                Button(role: .destructive) { model.killSwitch() } label: { Label("Stop everything", systemImage: "stop.circle") }
                    .disabled(!routeEngine.snapshot.status.isActive)
            }
        }
        .navigationTitle("Status Center")
    }

    private var heartbeatAge: String {
        "\(Int(max(0, Date().timeIntervalSince(routeEngine.snapshot.lastHeartbeat))))s"
    }

    private var thermalLabel: String {
        switch location.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious · Saver active"
        case .critical: return "Critical · Saver active"
        @unknown default: return "Unknown"
        }
    }

    private var permissionLabel: String {
        switch location.authorization {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using"
        @unknown default: return "Unknown"
        }
    }
}
