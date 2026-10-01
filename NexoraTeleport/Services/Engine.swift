import Foundation
import CoreLocation
import UserNotifications

@MainActor
final class RouteEngine: ObservableObject {
    @Published private(set) var snapshot = EngineSnapshot()
    @Published private(set) var displayedCoordinate: Coordinate?

    var onSessionEnded: (() -> Void)?
    var onRouteFinished: ((RoutePlan, SessionOutcome, String, Date, Date) -> Void)?

    private let store = StateStore.shared
    private var task: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var provider: LocationOutputProvider = AppOnlyLocationProvider()
    private var routes: [RoutePlan] = []
    private var activeSessionID: UUID?
    private var lifecycleEpoch: UInt64 = 0

    func configure(routes: [RoutePlan]) {
        self.routes = routes
    }

    func restore() async {
        snapshot = await store.load(
            EngineSnapshot.self,
            name: "engine.json",
            fallback: EngineSnapshot()
        )

        if snapshot.status.isActive {
            snapshot.status = .recovering
            snapshot.message = "Previous session can be resumed"
            await persist()
        }

        displayedCoordinate = snapshot.lastCoordinate
        startWatchdog()
    }

    func start(
        route: RoutePlan,
        pauseAtDestination: TimeInterval? = nil,
        routineID: UUID? = nil,
        routineStepID: UUID? = nil
    ) {
        guard route.points.count >= 2 else {
            snapshot.status = .failed
            snapshot.message = "Route has too few points"
            Task { await persist() }
            return
        }

        let previousTask = task
        previousTask?.cancel()
        lifecycleEpoch &+= 1
        let epoch = lifecycleEpoch
        let sessionID = UUID()
        activeSessionID = sessionID
        let destinationPause = max(0, pauseAtDestination ?? route.pauseAtDestination)
        snapshot = EngineSnapshot(
            status: .preparing,
            routeID: route.id,
            routineID: routineID,
            routineStepID: routineStepID,
            pointIndex: 0,
            lastCoordinate: route.points.first,
            pauseUntil: nil,
            destinationPauseSeconds: destinationPause,
            startedAt: .now,
            lastHeartbeat: .now,
            message: "Preparing route"
        )
        displayedCoordinate = route.points.first
        LiveActivityService.shared.start(route: route)
        Task { await persist() }
        task = Task { [weak self] in
            guard let self else { return }
            if let previousTask { _ = await previousTask.result }
            guard self.lifecycleEpoch == epoch, self.activeSessionID == sessionID else { return }
            await self.provider.end()
            guard self.lifecycleEpoch == epoch, self.activeSessionID == sessionID else { return }
            await self.run(route: route, resume: false, sessionID: sessionID)
        }
    }

    func pause() {
        guard snapshot.status == .running else { return }
        snapshot.status = .paused
        snapshot.message = "Paused"
        if let id = snapshot.routeID, let route = routes.first(where: { $0.id == id }) {
            LiveActivityService.shared.update(route: route, status: snapshot.status, pointIndex: snapshot.pointIndex, message: snapshot.message, force: true)
        }
        Task { await persist() }
    }

    func resume() {
        guard
            snapshot.status == .paused || snapshot.status == .recovering,
            let id = snapshot.routeID,
            let route = routes.first(where: { $0.id == id })
        else {
            return
        }

        LiveActivityService.shared.start(route: route)
        let previousTask = task
        previousTask?.cancel()
        lifecycleEpoch &+= 1
        let epoch = lifecycleEpoch
        let sessionID = UUID()
        activeSessionID = sessionID
        task = Task { [weak self] in
            guard let self else { return }
            if let previousTask { _ = await previousTask.result }
            guard self.lifecycleEpoch == epoch, self.activeSessionID == sessionID else { return }
            await self.provider.end()
            guard self.lifecycleEpoch == epoch, self.activeSessionID == sessionID else { return }
            await self.run(route: route, resume: true, sessionID: sessionID)
        }
    }

    func stop(reason: String = "Stopped") {
        let previousRoute = snapshot.routeID.flatMap { id in routes.first(where: { $0.id == id }) }
        let previousStartedAt = snapshot.startedAt
        let wasActive = snapshot.status.isActive
        let previousTask = task
        previousTask?.cancel()
        task = nil
        lifecycleEpoch &+= 1
        let epoch = lifecycleEpoch
        activeSessionID = nil
        snapshot.status = .idle
        snapshot.routeID = nil
        snapshot.routineID = nil
        snapshot.routineStepID = nil
        snapshot.pointIndex = 0
        snapshot.pauseUntil = nil
        snapshot.destinationPauseSeconds = 0
        snapshot.lastCoordinate = nil
        snapshot.message = reason
        snapshot.lastHeartbeat = .now
        displayedCoordinate = nil
        LiveActivityService.shared.end(route: previousRoute, message: reason, completed: false)

        Task { [weak self] in
            guard let self else { return }
            if let previousTask { _ = await previousTask.result }
            guard self.lifecycleEpoch == epoch, self.activeSessionID == nil else { return }
            await self.provider.end()
            await self.persist()
        }
        if wasActive, let route = previousRoute {
            onRouteFinished?(route, .stopped, reason, previousStartedAt ?? .now, .now)
        }
        onSessionEnded?()
    }

    private func run(route: RoutePlan, resume: Bool, sessionID: UUID) async {
        do {
            guard activeSessionID == sessionID else { return }
            try await provider.begin()
            guard activeSessionID == sessionID else { return }
            snapshot.status = .running
            snapshot.message = resume ? "Route resumed" : "Route active"
            snapshot.lastHeartbeat = .now
            await persist()

            let speed = max(0.5, route.targetSpeedKmh / 3.6)
            var index = resume ? min(snapshot.pointIndex, route.points.count - 1) : 0

            while index < route.points.count && !Task.isCancelled {
                while snapshot.status == .paused && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                guard !Task.isCancelled else { return }

                let coordinate = route.points[index]
                displayedCoordinate = coordinate
                snapshot.pointIndex = index
                snapshot.lastCoordinate = coordinate
                snapshot.lastHeartbeat = .now
                LiveActivityService.shared.update(route: route, status: snapshot.status, pointIndex: index, message: snapshot.message)

                try await provider.apply(
                    coordinate,
                    speedMetersPerSecond: speed
                )
                await persist()

                if index > 0, index % 20 == 0 {
                    try await waitForRandomPauseIfNeeded(route: route)
                    guard !Task.isCancelled else { return }
                }

                let delay = segmentDelay(
                    route: route,
                    index: index,
                    speedMps: speed
                )
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                }
                guard !Task.isCancelled else { return }
                index += 1
            }

            guard !Task.isCancelled else { return }
            try await waitAtDestinationIfNeeded()
            guard !Task.isCancelled else { return }

            guard activeSessionID == sessionID else { return }
            snapshot.status = .completed
            snapshot.message = "Destination reached"
            snapshot.lastHeartbeat = .now
            snapshot.pauseUntil = nil
            await provider.end()
            activeSessionID = nil
            LiveActivityService.shared.end(route: route, message: "Destination reached", completed: true)
            await persist()
            onRouteFinished?(route, .completed, snapshot.message, snapshot.startedAt ?? .now, .now)
            onSessionEnded?()
            await notify(title: "Route complete", body: route.destination.name)
        } catch is CancellationError {
            if activeSessionID == sessionID { await provider.end() }
            return
        } catch {
            guard activeSessionID == sessionID else { return }
            snapshot.status = .failed
            snapshot.message = error.localizedDescription
            snapshot.lastHeartbeat = .now
            await provider.end()
            activeSessionID = nil
            LiveActivityService.shared.end(route: route, message: snapshot.message, completed: false)
            await persist()
            onRouteFinished?(route, .failed, snapshot.message, snapshot.startedAt ?? .now, .now)
            onSessionEnded?()
        }
    }

    private func waitForRandomPauseIfNeeded(route: RoutePlan) async throws {
        guard let rule = route.randomPause, rule.chancePercent > 0 else { return }
        guard Int.random(in: 1...100) <= min(100, max(0, rule.chancePercent)) else { return }
        let low = max(1, min(rule.minimumSeconds, rule.maximumSeconds))
        let high = max(low, max(rule.minimumSeconds, rule.maximumSeconds))
        let seconds = Int.random(in: low...high)
        let previousStatus = snapshot.status
        snapshot.status = .waiting
        snapshot.message = "Route pause · \(seconds)s"
        snapshot.pauseUntil = Date().addingTimeInterval(TimeInterval(seconds))
        LiveActivityService.shared.update(route: route, status: snapshot.status, pointIndex: snapshot.pointIndex, message: snapshot.message, force: true)
        await persist()
        try await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        snapshot.status = previousStatus == .paused ? .paused : .running
        snapshot.message = "Route active"
        snapshot.pauseUntil = nil
        snapshot.lastHeartbeat = .now
        LiveActivityService.shared.update(route: route, status: snapshot.status, pointIndex: snapshot.pointIndex, message: snapshot.message, force: true)
        await persist()
    }

    private func waitAtDestinationIfNeeded() async throws {
        let pauseSeconds = max(0, snapshot.destinationPauseSeconds)
        guard pauseSeconds > 0 else { return }

        let endDate: Date
        if let existing = snapshot.pauseUntil, existing > .now {
            endDate = existing
        } else {
            endDate = Date().addingTimeInterval(pauseSeconds)
            snapshot.pauseUntil = endDate
        }

        snapshot.status = .waiting
        snapshot.message = "Waiting at destination"
        snapshot.lastHeartbeat = .now
        if let id = snapshot.routeID, let route = routes.first(where: { $0.id == id }) {
            LiveActivityService.shared.update(route: route, status: snapshot.status, pointIndex: snapshot.pointIndex, message: snapshot.message, force: true)
        }
        await persist()

        while Date() < endDate && !Task.isCancelled {
            snapshot.lastHeartbeat = .now
            await persist()
            let remaining = endDate.timeIntervalSinceNow
            try await Task.sleep(for: .seconds(min(max(remaining, 0.2), 5)))
        }
    }

    private func segmentDelay(
        route: RoutePlan,
        index: Int,
        speedMps: Double
    ) -> TimeInterval {
        guard index + 1 < route.points.count else { return 0 }
        let a = route.points[index].cl
        let b = route.points[index + 1].cl
        let meters = CLLocation(
            latitude: a.latitude,
            longitude: a.longitude
        ).distance(
            from: CLLocation(latitude: b.latitude, longitude: b.longitude)
        )
        return max(0.05, meters / speedMps)
    }

    private func startWatchdog() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }

                if self.snapshot.status == .running,
                   Date().timeIntervalSince(self.snapshot.lastHeartbeat) > 20 {
                    let staleTask = self.task
                    staleTask?.cancel()
                    self.task = nil
                    self.lifecycleEpoch &+= 1
                    let epoch = self.lifecycleEpoch
                    self.activeSessionID = nil
                    self.snapshot.status = .recovering
                    self.snapshot.message = "Heartbeat stale — tap Resume"
                    await self.persist()
                    if let staleTask { _ = await staleTask.result }
                    guard self.lifecycleEpoch == epoch, self.activeSessionID == nil else { continue }
                    await self.provider.end()
                }
            }
        }
    }

    private func persist() async {
        try? await store.save(snapshot, name: "engine.json")
    }

    private func notify(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }
}

@MainActor
final class RoutineEngine: ObservableObject {
    @Published var nextEvent: String = "No routine scheduled"

    private struct ScheduledEvent {
        let profile: RoutineProfile
        let step: RoutineStep
        let targetDate: Date
        let key: String
    }

    private var task: Task<Void, Never>?
    private weak var appModel: AppModel?
    private let store = StateStore.shared
    private var runtime = RoutineRuntimeState()
    private var runtimeLoaded = false

    func attach(_ model: AppModel) {
        appModel = model
        restart()
    }

    func restart() {
        task?.cancel()
        task = Task { [weak self] in
            await self?.loop()
        }
    }

    private func loop() async {
        await loadRuntimeIfNeeded()

        while !Task.isCancelled {
            guard let model = appModel else { return }
            guard let event = await nextScheduledEvent(model: model) else {
                nextEvent = "No routine scheduled in the next 7 days"
                try? await Task.sleep(for: .seconds(30))
                continue
            }

            let now = Date()
            let wait = event.targetDate.timeIntervalSince(now)
            if wait > 0 {
                nextEvent = "\(event.profile.name): \(event.step.title) at \(event.targetDate.formatted(date: .abbreviated, time: .shortened))"
                try? await Task.sleep(for: .seconds(min(wait, 30)))
                continue
            }

            // If the app was suspended, allow a reasonable catch-up window.
            if abs(wait) > 2 * 60 * 60 {
                markCompleted(event.key)
                await persistRuntime()
                continue
            }

            if model.routeEngine.snapshot.status.isActive {
                nextEvent = "Waiting for the active route to finish"
                try? await Task.sleep(for: .seconds(15))
                continue
            }

            if execute(event: event, model: model) {
                markCompleted(event.key)
                await persistRuntime()
            } else {
                nextEvent = "Routine route is missing"
                markCompleted(event.key)
                await persistRuntime()
            }
        }
    }

    private func execute(event: ScheduledEvent, model: AppModel) -> Bool {
        guard
            let routeID = event.step.routeID,
            let route = model.routes.first(where: { $0.id == routeID })
        else {
            return false
        }

        let stay = TimeInterval(max(0, event.step.stayDurationMinutes) * 60)
        nextEvent = "Running \(event.step.title)"
        model.startRoute(
            route,
            pauseAtDestination: stay,
            routineID: event.profile.id,
            routineStepID: event.step.id
        )
        return true
    }

    private func nextScheduledEvent(model: AppModel) async -> ScheduledEvent? {
        let calendar = Calendar.current
        let now = Date()
        var events: [ScheduledEvent] = []
        var changedRuntime = false

        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: day)

            for profile in model.routines where profile.enabled && profile.weekdays.contains(weekday) {
                let matchingException = model.exceptions.first { item in
                    item.profileID == profile.id && calendar.isDate(item.date, inSameDayAs: day)
                }
                if matchingException?.kind == .skipDay { continue }
                let exceptionDelay = matchingException?.kind == .delay ? max(0, matchingException?.delayMinutes ?? 0) : 0

                for step in profile.steps where step.enabled {
                    guard let scheduled = calendar.date(
                        bySettingHour: max(0, min(23, step.scheduledHour)),
                        minute: max(0, min(59, step.scheduledMinute)),
                        second: 0,
                        of: day
                    ) else {
                        continue
                    }

                    let key = executionKey(profileID: profile.id, stepID: step.id, date: scheduled, calendar: calendar)
                    if runtime.completedKeys.contains(key) { continue }

                    let baseTargetDate: Date
                    if let stored = runtime.targetDates[key] {
                        baseTargetDate = stored
                    } else {
                        baseTargetDate = scheduled.addingTimeInterval(step.delay.randomizedSeconds())
                        runtime.targetDates[key] = baseTargetDate
                        changedRuntime = true
                    }
                    let targetDate = baseTargetDate.addingTimeInterval(TimeInterval(exceptionDelay * 60))

                    events.append(
                        ScheduledEvent(
                            profile: profile,
                            step: step,
                            targetDate: targetDate,
                            key: key
                        )
                    )
                }
            }
        }

        if changedRuntime {
            pruneRuntime()
            await persistRuntime()
        }

        return events.sorted { $0.targetDate < $1.targetDate }.first
    }

    private func executionKey(
        profileID: UUID,
        stepID: UUID,
        date: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "\(day)|\(profileID.uuidString)|\(stepID.uuidString)"
    }

    private func markCompleted(_ key: String) {
        if !runtime.completedKeys.contains(key) {
            runtime.completedKeys.append(key)
        }
        runtime.targetDates.removeValue(forKey: key)
        pruneRuntime()
    }

    private func pruneRuntime() {
        if runtime.completedKeys.count > 120 {
            runtime.completedKeys = Array(runtime.completedKeys.suffix(120))
        }
        if runtime.targetDates.count > 120 {
            let keep = runtime.targetDates
                .sorted { $0.value < $1.value }
                .suffix(120)
            runtime.targetDates = Dictionary(uniqueKeysWithValues: keep)
        }
    }

    private func loadRuntimeIfNeeded() async {
        guard !runtimeLoaded else { return }
        runtime = await store.load(
            RoutineRuntimeState.self,
            name: "routine-runtime.json",
            fallback: RoutineRuntimeState()
        )
        runtimeLoaded = true
    }

    private func persistRuntime() async {
        try? await store.save(runtime, name: "routine-runtime.json")
    }
}
