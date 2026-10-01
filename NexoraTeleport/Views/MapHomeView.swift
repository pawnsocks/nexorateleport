import SwiftUI
import MapKit

struct MapHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: DeviceLocationService
    @EnvironmentObject private var routeEngine: RouteEngine
    @StateObject private var search = SearchService()
    @State private var camera: MapCameraPosition = .automatic

    private var activeRoute: RoutePlan? {
        guard let routeID = routeEngine.snapshot.routeID else { return nil }
        return model.routes.first(where: { $0.id == routeID })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                styledMap

                VStack(spacing: 8) {
                    searchBox
                    searchResults
                    Spacer()
                    liveStrip
                }
                .padding()
            }
            .navigationTitle("Nexora Teleport")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if routeEngine.snapshot.status.isActive { model.killSwitch() }
                        else {
                            model.preferences.liveWhenIdle.toggle()
                            model.applyPreferences()
                        }
                    } label: {
                        Image(systemName: routeEngine.snapshot.status.isActive ? "stop.circle.fill" : (location.isLiveTracking ? "location.fill" : "location.slash"))
                            .foregroundStyle(routeEngine.snapshot.status.isActive ? .red : .indigo)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var styledMap: some View {
        switch model.preferences.mapAppearance {
        case .standard:
            baseMap.mapStyle(.standard(elevation: .realistic))
        case .hybrid:
            baseMap.mapStyle(.hybrid(elevation: .realistic))
        case .satellite:
            baseMap.mapStyle(.imagery(elevation: .realistic))
        }
    }

    private var baseMap: some View {
        Map(position: $camera) {
            ForEach(model.places) { place in
                Annotation(place.name, coordinate: place.coordinate.cl) {
                    Image(systemName: model.isFavorite(place) ? "star.circle.fill" : "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(model.isFavorite(place) ? .yellow : .indigo)
                }
            }

            if let coordinate = routeEngine.displayedCoordinate {
                Annotation("Route", coordinate: coordinate.cl) {
                    Image(systemName: "location.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                }
            } else if let current = location.actualLocation {
                Annotation("Live", coordinate: current.coordinate) {
                    ZStack {
                        Circle().fill(.blue.opacity(0.15)).frame(width: 38, height: 38)
                        Circle().fill(.blue).frame(width: 14, height: 14)
                        Circle().stroke(.white, lineWidth: 3).frame(width: 14, height: 14)
                    }
                }
            }

            if let route = activeRoute, route.points.count > 1 {
                MapPolyline(coordinates: route.points.map(\.cl))
                    .stroke(.indigo, lineWidth: 5)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
    }

    private var searchBox: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search location", text: $search.query)
                .textInputAutocapitalization(.never)
            if !search.query.isEmpty {
                Button { search.query = "" } label: { Image(systemName: "xmark.circle.fill") }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var searchResults: some View {
        if !search.query.isEmpty && !search.suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(search.suggestions.prefix(6)) { suggestion in
                    Button {
                        Task {
                            do {
                                let place = try await search.resolve(suggestion)
                                model.addPlace(place)
                                camera = .region(.init(center: place.coordinate.cl, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
                                search.query = ""
                            } catch { search.errorMessage = error.localizedDescription }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).foregroundStyle(.primary)
                            Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    Divider()
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        if let error = search.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red).padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var liveStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: activeRoute == nil ? "location.fill" : "figure.walk.motion")
                .foregroundStyle(activeRoute == nil ? .blue : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(activeRoute == nil ? (location.isLiveTracking ? "Live device location" : "Live is off") : (activeRoute?.name ?? "Active route"))
                    .font(.subheadline.bold()).lineLimit(1)
                if activeRoute == nil {
                    Text("\(location.speedKmh, specifier: "%.1f") km/h · accuracy \(location.accuracyMeters.map { "±\(Int($0)) m" } ?? "—")")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(routeEngine.snapshot.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if activeRoute == nil && !location.isLiveTracking {
                Button("Start") { model.preferences.liveWhenIdle = true; model.applyPreferences() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
