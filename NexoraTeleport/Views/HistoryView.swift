import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.history.isEmpty {
                ContentUnavailableView("No history", systemImage: "clock.arrow.circlepath", description: Text("Completed, stopped and failed route sessions appear here when History is enabled."))
            }
            ForEach(model.history) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.routeName).font(.headline)
                        Spacer()
                        Text(item.outcome.rawValue.capitalized)
                            .font(.caption.bold())
                            .foregroundStyle(item.outcome == .completed ? .green : (item.outcome == .failed ? .red : .secondary))
                    }
                    Text("\(item.startedAt.formatted(date: .abbreviated, time: .shortened)) → \(item.endedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(item.distanceMeters / 1000, specifier: "%.1f") km · \(item.message)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !model.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { model.clearHistory() }
                }
            }
        }
    }
}
