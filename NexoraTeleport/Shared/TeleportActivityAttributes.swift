import Foundation
import ActivityKit

struct TeleportActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var routeName: String
        var status: String
        var progress: Double
        var detail: String
    }

    var routeID: String
}
