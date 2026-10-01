import SwiftUI
import CoreLocation

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: DeviceLocationService
    @EnvironmentObject private var routeEngine: RouteEngine
    @EnvironmentObject private var routineEngine: RoutineEngine

    private var activeRoute: RoutePlan? {
        guard let id = routeEngine.snapshot.routeID else { return nil }
        return model.routes.first(where: { $0.id == id })
    }

    private var routeProgress: Double {
        guard let route = activeRoute, route.points.count > 1 else { return 0 }
        return min(1, max(0, Double(routeEngine.snapshot.pointIndex) / Double(route.points.count - 1)))
    }

    private var todayProfiles: [RoutineProfile] {
        let weekday = Calendar.current.component(.weekday, from: .now)
        return model.routines.filter { $0.enabled && $0.weekdays.contains(weekday) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    liveCard
                    nextCard
                    timelineCard
                    favoritesCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if routeEngine.snapshot.status.isActive {
                        Button(role: .destructive) { model.killSwitch() } label: {
                            Image(systemName: "stop.fill")
                        }
                    }
                }
            }
        }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(activeRoute == nil ? "Live" : "Active Route", systemImage: activeRoute == nil ? "location.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)
                Spacer()
                Text(activeRoute == nil ? (location.isLiveTracking ? "LIVE" : "OFF") : routeEngine.snapshot.status.rawValue.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(activeRoute == nil ? (location.isLiveTracking ? .green : .secondary) : .indigo)
            }

            if let route = activeRoute {
                Text(route.name).font(.title3.bold())
                ProgressView(value: routeProgress)
                    .tint(.indigo)
                HStack {
                    metric("Progress", "\(Int(routeProgress * 100))%")
                    metric("Speed", "\(route.targetSpeedKmh, specifier: "%.0f") km/h")
                    metric("Remaining", remainingText(route: route))
                }
                HStack {
                    if routeEngine.snapshot.status == .running {
                        Button("Pause") { routeEngine.pause() }.buttonStyle(.bordered)
                    } else if [.paused, .recovering].contains(routeEngine.snapshot.status) {
                        Button("Resume") { model.resumeRoute() }.buttonStyle(.borderedProminent)
                    }
                    Button(role: .destructive) { model.killSwitch() } label: { Text("Stop") }
                        .buttonStyle(.bordered)
                }
            } else {
                if let current = location.actualLocation {
                    HStack {
                        metric("Speed", "\(location.speedKmh, specifier: "%.1f") km/h")
                        metric("Accuracy", location.accuracyMeters.map { "±\(Int($0)) m" } ?? "—")
                        metric("Heading", headingText)
                    }
                    Text("\(current.coordinate.latitude, specifier: "%.5f"), \(current.coordinate.longitude, specifier: "%.5f")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let updated = location.lastUpdated {
                        Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enable Live to show your current device location, speed, heading and accuracy even when no route is active.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(location.isLiveTracking ? "Stop Live" : "Start Live") {
                    if location.isLiveTracking {
                        model.preferences.liveWhenIdle = false
                    } else {
                        model.preferences.liveWhenIdle = true
                    }
                    model.applyPreferences()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }

    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Next", systemImage: "clock")
                .font(.headline)
            Text(routineEngine.nextEvent)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today's Routine", systemImage: "calendar")
                .font(.headline)
            if todayProfiles.isEmpty {
                Text("No routine is enabled for today.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todayProfiles) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profile.name).font(.subheadline.bold())
                        ForEach(profile.steps.sorted(by: sortSteps)) { step in
                            HStack(alignment: .top) {
                                Text(String(format: "%02d:%02d", step.scheduledHour, step.scheduledMinute))
                                    .font(.caption.monospacedDigit().bold())
                                    .frame(width: 48, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title)
                                    if let id = step.routeID, let route = model.routes.first(where: { $0.id == id }) {
                                        Text(route.name).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    if profile.id != todayProfiles.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var favoritesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Places", systemImage: "star.fill").font(.headline)
            if model.favoritePlaces.isEmpty {
                Text("Mark saved places as favorites to show them here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.favoritePlaces) { place in
                            Button {
                                model.selectedDestination = place
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(place.name).font(.subheadline.bold()).lineLimit(1)
                                    Text("Use as destination").font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(width: 150, alignment: .leading)
                                .padding(12)
                                .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headingText: String {
        guard let value = location.headingDegrees ?? location.courseDegrees else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    private func remainingText(route: RoutePlan) -> String {
        let seconds = max(0, route.expectedTravelTime * (1 - routeProgress))
        if seconds < 60 { return "<1 min" }
        return "\(Int(seconds / 60)) min"
    }

    private func sortSteps(_ lhs: RoutineStep, _ rhs: RoutineStep) -> Bool {
        (lhs.scheduledHour, lhs.scheduledMinute) < (rhs.scheduledHour, rhs.scheduledMinute)
    }
}
