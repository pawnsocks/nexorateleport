import SwiftUI

struct RoutesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mode: TravelMode = .walking
    @State private var speed = 5.0
    @State private var previewRoute: RoutePlan?

    private let presets: [(String, TravelMode, Double)] = [
        ("Walk", .walking, 5),
        ("Run", .walking, 10),
        ("City Drive", .driving, 35),
        ("Drive", .driving, 55),
        ("Highway", .driving, 100)
    ]

    var body: some View {
        NavigationStack {
            List {
                savedPlacesSection
                buildRouteSection
                candidatesSection
                savedRoutesSection
            }
            .navigationTitle("Routes")
            .sheet(item: $previewRoute) { route in
                RoutePreviewView(route: route) { model.saveRouteCandidate(route) }
            }
        }
    }

    private var savedPlacesSection: some View {
        Section("Saved places") {
            if model.places.isEmpty {
                Text("Search and save locations from the Map tab.").foregroundStyle(.secondary)
            }
            ForEach(model.places) { place in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                            Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.toggleFavorite(place) } label: {
                            Image(systemName: model.isFavorite(place) ? "star.fill" : "star")
                                .foregroundStyle(model.isFavorite(place) ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("Note", text: Binding(
                        get: { model.placeMetadata[place.id.uuidString]?.note ?? "" },
                        set: { model.updateNote(for: place, note: $0) }
                    ))
                    .font(.caption)
                    if !model.selectedWaypoints.contains(where: { $0.id == place.id }) {
                        Button("Add as waypoint") { model.selectedWaypoints.append(place) }
                            .font(.caption)
                    } else {
                        Button("Remove waypoint", role: .destructive) { model.selectedWaypoints.removeAll { $0.id == place.id } }
                            .font(.caption)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { model.deletePlace(model.places[index].id) }
            }
        }
    }

    private var buildRouteSection: some View {
        Section("Build route") {
            Picker("Start", selection: $model.selectedStart) {
                Text("Select").tag(SavedPlace?.none)
                ForEach(model.places) { Text($0.name).tag(Optional($0)) }
            }
            Picker("Destination", selection: $model.selectedDestination) {
                Text("Select").tag(SavedPlace?.none)
                ForEach(model.places) { Text($0.name).tag(Optional($0)) }
            }
            if !model.selectedWaypoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Waypoints").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.selectedWaypoints) { waypoint in
                        HStack {
                            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.orange)
                            Text(waypoint.name).font(.subheadline)
                            Spacer()
                            Button { model.selectedWaypoints.removeAll { $0.id == waypoint.id } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            Picker("Mode", selection: $mode) {
                ForEach(TravelMode.allCases) { Text($0.label).tag($0) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(presets, id: \.0) { preset in
                        Button(preset.0) { mode = preset.1; speed = preset.2 }
                            .buttonStyle(.bordered)
                    }
                }
            }
            HStack {
                Text("Speed")
                Slider(value: $speed, in: 1...120)
                Text("\(speed, specifier: "%.0f") km/h").monospacedDigit().frame(width: 76, alignment: .trailing)
            }
            Stepper("Pause chance: \(model.routePauseChance)%", value: $model.routePauseChance, in: 0...100, step: 5)
            if model.routePauseChance > 0 {
                Stepper("Pause min: \(model.routePauseMinimumSeconds)s", value: $model.routePauseMinimumSeconds, in: 5...600, step: 5)
                Stepper("Pause max: \(model.routePauseMaximumSeconds)s", value: $model.routePauseMaximumSeconds, in: model.routePauseMinimumSeconds...900, step: 5)
            }
            Button("Find route alternatives") {
                Task { await model.calculateRouteAlternatives(mode: mode, speedKmh: speed) }
            }
            .disabled(model.selectedStart == nil || model.selectedDestination == nil)

            if let error = model.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }

    @ViewBuilder
    private var candidatesSection: some View {
        if !model.routeCandidates.isEmpty {
            Section("Preview") {
                ForEach(model.routeCandidates) { route in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(route.name).font(.headline)
                        Text("\(route.distanceMeters / 1000, specifier: "%.1f") km · \(Int(route.expectedTravelTime / 60)) min · offline after save")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Preview") { previewRoute = route }.buttonStyle(.bordered)
                            Button("Save") { model.saveRouteCandidate(route) }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }

    private var savedRoutesSection: some View {
        Section("Saved routes") {
            if model.routes.isEmpty { Text("No routes yet").foregroundStyle(.secondary) }
            ForEach(model.routes) { route in
                let health = RouteHealthService().inspect(route)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(route.name).font(.headline)
                        Spacer()
                        Image(systemName: health.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(health.isHealthy ? .green : .orange)
                    }
                    Text("\(route.mode.label) · \(route.distanceMeters/1000, specifier: "%.1f") km · \(route.targetSpeedKmh, specifier: "%.0f") km/h")
                        .font(.caption).foregroundStyle(.secondary)
                    if let waypoints = route.waypoints, !waypoints.isEmpty {
                        Text("\(waypoints.count) waypoint\(waypoints.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Start") { model.startRoute(route) }.buttonStyle(.borderedProminent)
                        Button("Preview") { previewRoute = route }.buttonStyle(.bordered)
                        Menu {
                            Button("Save reversed copy") { model.saveReversedCopy(of: route) }
                            Button("Save loop copy") { model.saveLoopCopy(of: route) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .buttonStyle(.bordered)
                        if let url = try? model.exportGPXURL(route: route) {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                for index in offsets { model.deleteRoute(model.routes[index].id) }
            }
        }
    }
}
