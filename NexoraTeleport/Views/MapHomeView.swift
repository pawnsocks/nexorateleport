import SwiftUI
import MapKit
import CoreLocation

struct MapHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: DeviceLocationService
    @EnvironmentObject private var routeEngine: RouteEngine
    @Environment(\.openURL) private var openURL

    @StateObject private var search = SearchService()
    @State private var camera: MapCameraPosition = .automatic
    @State private var mode: TravelMode = .walking
    @State private var speedKmh: Double = 5
    @State private var isStartingRoute = false
    @State private var uiMessage: String?
    @FocusState private var searchFocused: Bool

    private var activeRoute: RoutePlan? {
        guard let routeID = routeEngine.snapshot.routeID else { return nil }
        return model.routes.first(where: { $0.id == routeID })
    }

    private var statusTitle: String {
        if routeEngine.snapshot.status.isActive { return "ROUTE ACTIVE" }
        return location.isLiveTracking ? "LIVE ON" : "LIVE OFF"
    }

    private var statusColor: Color {
        if routeEngine.snapshot.status.isActive { return .green }
        return location.isLiveTracking ? .blue : .secondary
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                styledMap
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 8) {
                    searchBox
                    searchResults
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .safeAreaInset(edge: .bottom) {
                controlPanel
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .background(.bar)
            }
            .navigationTitle("Teleport")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !location.isLiveTracking && model.preferences.liveWhenIdle {
                    location.startLiveTracking()
                }
                if let current = location.actualLocation {
                    search.updateRegion(center: current.coordinate)
                }
            }
            .onChange(of: location.lastUpdated) { _, _ in
                if let current = location.actualLocation {
                    search.updateRegion(center: current.coordinate)
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
            if let destination = model.selectedDestination {
                Annotation("Target", coordinate: destination.coordinate.cl) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.indigo)
                        .background(Circle().fill(.white).padding(6))
                }
            }

            if let coordinate = routeEngine.displayedCoordinate {
                Annotation("Route", coordinate: coordinate.cl) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                }
            } else if let current = location.actualLocation {
                Annotation("Current", coordinate: current.coordinate) {
                    ZStack {
                        Circle().fill(.blue.opacity(0.18)).frame(width: 42, height: 42)
                        Circle().fill(.blue).frame(width: 15, height: 15)
                        Circle().stroke(.white, lineWidth: 3).frame(width: 15, height: 15)
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
        .simultaneousGesture(
            TapGesture().onEnded { dismissKeyboard() }
        )
    }

    private var searchBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search city, street, postcode…", text: $search.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onSubmit {
                    dismissKeyboard()
                    Task { await search.searchNow() }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { dismissKeyboard() }
                    }
                }

            if search.isSearching {
                ProgressView().controlSize(.small)
            } else if !search.query.isEmpty {
                Button {
                    search.query = ""
                    uiMessage = nil
                    dismissKeyboard()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                dismissKeyboard()
                Task { await search.searchNow() }
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
            }
            .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }

    @ViewBuilder
    private var searchResults: some View {
        if !search.query.isEmpty && (!search.directResults.isEmpty || !search.suggestions.isEmpty || search.errorMessage != nil) {
            VStack(spacing: 0) {
                if !search.directResults.isEmpty {
                    ForEach(Array(search.directResults.prefix(6).enumerated()), id: \.element.id) { index, place in
                        resultButton(title: place.name, subtitle: place.subtitle) {
                            selectTarget(place)
                        }
                        if index < min(search.directResults.count, 6) - 1 { Divider() }
                    }
                } else if !search.suggestions.isEmpty {
                    ForEach(Array(search.suggestions.prefix(6).enumerated()), id: \.element.id) { index, suggestion in
                        resultButton(title: suggestion.title, subtitle: suggestion.subtitle) {
                            Task {
                                do {
                                    let place = try await search.resolve(suggestion)
                                    selectTarget(place)
                                } catch {
                                    search.errorMessage = (error as NSError).localizedDescription
                                }
                            }
                        }
                        if index < min(search.suggestions.count, 6) - 1 { Divider() }
                    }
                }

                if let error = search.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        }
    }

    private func resultButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(12)
        }
        .buttonStyle(.plain)
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(statusColor).frame(width: 9, height: 9)
                    Text(statusTitle).font(.caption.bold())
                }
                Spacer()
                if let updated = location.lastUpdated, !routeEngine.snapshot.status.isActive {
                    Text(updated.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            locationRows

            if routeEngine.snapshot.status.isActive {
                activeRouteControls
            } else {
                routeSetupControls
            }

            if let uiMessage {
                Text(uiMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = location.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if location.authorization == .denied {
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.footnote.bold())
                    }
                }
            }

            Text("Location output: in-app route engine. This build does not replace the iOS system location for other apps.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: -2)
    }

    private var locationRows: some View {
        VStack(spacing: 8) {
            infoRow(
                icon: "location.fill",
                title: "Current",
                value: currentLocationText,
                color: .blue
            )
            infoRow(
                icon: "mappin.circle.fill",
                title: "Target",
                value: model.selectedDestination?.name ?? "Search and select a place",
                color: .indigo
            )
        }
    }

    private func infoRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Spacer()
        }
    }

    private var routeSetupControls: some View {
        VStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { location.isLiveTracking },
                set: { enabled in
                    model.preferences.liveWhenIdle = enabled
                    model.applyPreferences()
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Live device location").font(.subheadline.weight(.semibold))
                    Text("Shows your real iPhone location inside Nexora")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Picker("Mode", selection: $mode) {
                    ForEach(TravelMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Menu {
                    Button("Walking · 5 km/h") { mode = .walking; speedKmh = 5 }
                    Button("Bike-like · 15 km/h") { mode = .walking; speedKmh = 15 }
                    Button("Driving · 40 km/h") { mode = .driving; speedKmh = 40 }
                    Button("Driving · 80 km/h") { mode = .driving; speedKmh = 80 }
                } label: {
                    Text("\(Int(speedKmh)) km/h")
                        .font(.subheadline.bold())
                        .frame(minWidth: 76)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button {
                    dismissKeyboard()
                    centerOnCurrentLocation()
                } label: {
                    Label("My Location", systemImage: "location")
                }
                .buttonStyle(.bordered)

                Button {
                    dismissKeyboard()
                    model.selectedDestination = nil
                    uiMessage = nil
                } label: {
                    Label("Clear Target", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedDestination == nil)
            }

            Button {
                dismissKeyboard()
                Task { await startRouteFromCurrentLocation() }
            } label: {
                HStack {
                    if isStartingRoute { ProgressView().tint(.white) }
                    Text(isStartingRoute ? "Building Route…" : "Start Route")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isStartingRoute || model.selectedDestination == nil)
        }
    }

    private var activeRouteControls: some View {
        VStack(spacing: 10) {
            if let route = activeRoute {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.destination.name).font(.headline).lineLimit(1)
                        Text(routeEngine.snapshot.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(route.targetSpeedKmh)) km/h")
                        .font(.caption.bold())
                        .monospacedDigit()
                }
            }

            HStack(spacing: 10) {
                if routeEngine.snapshot.status == .running {
                    Button("Pause") { routeEngine.pause() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                } else if routeEngine.snapshot.status == .paused || routeEngine.snapshot.status == .recovering {
                    Button("Resume") { model.resumeRoute() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }

                Button(role: .destructive) {
                    model.killSwitch()
                    uiMessage = "Route stopped."
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func dismissKeyboard() {
        searchFocused = false
    }

    private var currentLocationText: String {
        guard let current = location.actualLocation else {
            switch location.authorization {
            case .denied, .restricted: return "Permission required"
            case .notDetermined: return "Tap Live to allow access"
            default: return location.isLiveTracking ? "Finding location…" : "Live is off"
            }
        }
        let accuracy = location.accuracyMeters.map { " ±\(Int($0)) m" } ?? ""
        return String(format: "%.5f, %.5f%@", current.coordinate.latitude, current.coordinate.longitude, accuracy)
    }

    private func selectTarget(_ place: SavedPlace) {
        model.selectedDestination = place
        model.addPlace(place)
        search.query = ""
        searchFocused = false
        uiMessage = "Target set to \(place.name)."
        camera = .region(MKCoordinateRegion(
            center: place.coordinate.cl,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        ))
    }

    private func centerOnCurrentLocation() {
        guard let current = location.actualLocation else {
            model.preferences.liveWhenIdle = true
            model.applyPreferences()
            uiMessage = "Waiting for your current location…"
            return
        }
        camera = .region(MKCoordinateRegion(
            center: current.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }

    private func startRouteFromCurrentLocation() async {
        guard let destination = model.selectedDestination else {
            uiMessage = "Search and select a target first."
            return
        }

        guard let current = location.actualLocation else {
            model.preferences.liveWhenIdle = true
            model.applyPreferences()
            location.requestPermissions()
            uiMessage = "Enable Live and wait for your current location, then tap Start Route again."
            return
        }

        isStartingRoute = true
        defer { isStartingRoute = false }
        uiMessage = nil

        let start = SavedPlace(
            name: "Current Location",
            subtitle: "Device location",
            coordinate: Coordinate(current.coordinate)
        )
        model.selectedStart = start
        model.selectedDestination = destination
        model.selectedWaypoints = []

        await model.calculateRouteAlternatives(mode: mode, speedKmh: speedKmh)

        guard let route = model.routeCandidates.first else {
            uiMessage = model.lastError ?? "Couldn't build a route. Try another mode or target."
            return
        }

        model.saveRouteCandidate(route)
        model.startRoute(route)
        uiMessage = "Route started."
        camera = .automatic
    }
}
