import WidgetKit
import SwiftUI
import ActivityKit

struct NexoraStatusEntry: TimelineEntry {
    let date: Date
}

struct NexoraStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> NexoraStatusEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (NexoraStatusEntry) -> Void) { completion(.init(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NexoraStatusEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct NexoraStatusWidget: Widget {
    let kind = "NexoraTeleportStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NexoraStatusProvider()) { _ in
            VStack(alignment: .leading, spacing: 10) {
                Label("Nexora Teleport", systemImage: "location.fill")
                    .font(.headline)
                Text("Quick controls")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Link(destination: URL(string: "nexorateleport://today")!) { Label("Today", systemImage: "sun.max") }
                    Spacer()
                    Link(destination: URL(string: "nexorateleport://resume")!) { Image(systemName: "play.fill") }
                    Link(destination: URL(string: "nexorateleport://stop")!) { Image(systemName: "stop.fill") }
                }
                .font(.caption.bold())
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .padding()
        }
        .configurationDisplayName("Nexora Teleport")
        .description("Open Today or control an active route.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NexoraTeleportLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TeleportActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(context.state.routeName).font(.headline).lineLimit(1)
                    Spacer()
                    Text(context.state.status).font(.caption.bold()).foregroundStyle(.indigo)
                }
                ProgressView(value: context.state.progress).tint(.indigo)
                Text(context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "location.fill").foregroundStyle(.indigo)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%").monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.routeName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress).tint(.indigo)
                }
            } compactLeading: {
                Image(systemName: "location.fill").foregroundStyle(.indigo)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "location.fill").foregroundStyle(.indigo)
            }
        }
    }
}

@main
struct NexoraTeleportWidgets: WidgetBundle {
    var body: some Widget {
        NexoraStatusWidget()
        NexoraTeleportLiveActivity()
    }
}
