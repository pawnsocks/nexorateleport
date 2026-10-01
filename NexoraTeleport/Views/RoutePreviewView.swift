import SwiftUI
import MapKit

struct RoutePreviewView: View {
    let route: RoutePlan
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic

    private var health: RouteHealthReport { RouteHealthService().inspect(route) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $camera) {
                    Marker("Start", coordinate: route.start.coordinate.cl).tint(.green)
                    Marker("Destination", coordinate: route.destination.coordinate.cl).tint(.red)
                    ForEach(route.waypoints ?? []) { waypoint in
                        Marker(waypoint.name, coordinate: waypoint.coordinate.cl).tint(.orange)
                    }
                    MapPolyline(coordinates: route.points.map(\.cl)).stroke(.indigo, lineWidth: 5)
                }
                .frame(height: 360)

                List {
                    Section("Route") {
                        LabeledContent("Distance", value: "\(route.distanceMeters / 1000, specifier: "%.1f") km")
                        LabeledContent("Mode", value: route.mode.label)
                        LabeledContent("Speed", value: "\(route.targetSpeedKmh, specifier: "%.0f") km/h")
                        LabeledContent("Offline", value: health.offlineReady ? "Ready" : "No")
                    }
                    Section("Health") {
                        if health.isHealthy { Label("Route looks healthy", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        ForEach(health.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                }
            }
            .navigationTitle("Route Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(); dismiss() } }
            }
        }
    }
}
