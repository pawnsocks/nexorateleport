import Foundation
import ActivityKit

@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<TeleportActivityAttributes>?
    private var lastUpdate = Date.distantPast

    func start(route: RoutePlan) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            if let current = activity {
                await current.end(nil, dismissalPolicy: .immediate)
                activity = nil
            }
            let attributes = TeleportActivityAttributes(routeID: route.id.uuidString)
            let state = TeleportActivityAttributes.ContentState(
                routeName: route.name,
                status: "Preparing",
                progress: 0,
                detail: "Starting route"
            )
            let content = ActivityContent(state: state, staleDate: nil)
            activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
            lastUpdate = .now
        }
    }

    func update(route: RoutePlan, status: SessionStatus, pointIndex: Int, message: String, force: Bool = false) {
        guard let activity else { return }
        guard force || Date().timeIntervalSince(lastUpdate) >= 2 else { return }
        lastUpdate = .now
        let denominator = max(1, route.points.count - 1)
        let progress = min(1, max(0, Double(pointIndex) / Double(denominator)))
        let state = TeleportActivityAttributes.ContentState(
            routeName: route.name,
            status: status.rawValue.capitalized,
            progress: progress,
            detail: message
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(route: RoutePlan?, message: String, completed: Bool) {
        guard let activity else { return }
        self.activity = nil
        let state = TeleportActivityAttributes.ContentState(
            routeName: route?.name ?? "Nexora Teleport",
            status: completed ? "Completed" : "Stopped",
            progress: completed ? 1 : 0,
            detail: message
        )
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now.addingTimeInterval(20))
            )
        }
    }
}
