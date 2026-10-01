import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit

struct MapHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: DeviceLocationService
    @EnvironmentObject private var routeEngine: RouteEngine
    @Environment(\.openURL) private var openURL

    @StateObject private var search = SearchService()
    @State private var camera: MapCameraPosition = .automatic
    @State private var interactionMode: InteractionMode = .browse
    @State private var pickedCoordinate: Coordinate?
    @State private var draftPoints: [Coordinate] = []
    @State private var showRouteEditor = false
    @State private var draftName = "Custom Route"
    @State private var draftDurationMinutes = 20
    @State private var draftStartAt = Date().addingTimeInterval(300)
    @State private var draftReminderEnabled = false
    @State private var uiMessage: String?
    @FocusState private var searchFocused: Bool

    private enum InteractionMode {
        case browse
        case draw
    }

    private var activeRoute: RoutePlan? {
        guard let routeID = routeEngine.snapshot.routeID else { return nil }
        return model.routes.first(where: { $0.id == routeID })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                styledMap
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 8) {
                    searchBox
                    searchResults

                    HStack {
                        Spacer()
                        statusPill
                    }

                    Spacer()

                    if interactionMode == .draw {
                        drawToolbar
                    } else if routeEngine.snapshot.status.isActive {
                        activeRouteBar
                    } else if let pickedCoordinate {
                        pickedPlaceCard(pickedCoordinate)
                    } else {
                        compactDock
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .navigationTitle("Teleport")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRouteEditor) {
                routeEditor
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
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
            interactiveMap.mapStyle(.standard(elevation: .realistic))
        case .hybrid:
            interactiveMap.mapStyle(.hybrid(elevation: .realistic))
        case .satellite:
            interactiveMap.mapStyle(.imagery(elevation: .realistic))
        }
    }

    private var interactiveMap: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let destination = model.selectedDestination {
                    Annotation("Target", coordinate: destination.coordinate.cl) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.indigo)
                            .background(Circle().fill(.white).padding(6))
                    }
                }

                if let pickedCoordinate, interactionMode == .browse {
                    Annotation("Selected", coordinate: pickedCoordinate.cl) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                    }
                }

                if interactionMode == .draw {
                    ForEach(Array(draftPoints.enumerated()), id: \.offset) { index, point in
                        Annotation("\(index + 1)", coordinate: point.cl) {
                            ZStack {
                                Circle().fill(index == 0 ? .green : .indigo)
                                    .frame(width: 28, height: 28)
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    if draftPoints.count > 1 {
                        MapPolyline(coordinates: draftPoints.map(\.cl))
                            .stroke(.indigo, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }

                if let coordinate = routeEngine.displayedCoordinate {
                    Annotation("Route", coordinate: coordinate.cl) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.green)
                    }
                } else if let current = location.actualLocation {
                    Annotation("Current", coordinate: current.coordinate) {
                        ZStack {
                            Circle().fill(.blue.opacity(0.18)).frame(width: 40, height: 40)
                            Circle().fill(.blue).frame(width: 14, height: 14)
                            Circle().stroke(.white, lineWidth: 3).frame(width: 14, height: 14)
                        }
                    }
                }

                if let route = activeRoute, route.points.count > 1 {
                    MapPolyline(coordinates: route.points.map(\.cl))
                        .stroke(.green, lineWidth: 5)
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if searchFocused {
                            dismissKeyboard()
                            return
                        }
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        handleMapTap(coordinate)
                    }
            )
        }
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
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    @ViewBuilder
    private var searchResults: some View {
        if !search.query.isEmpty && (!search.directResults.isEmpty || !search.suggestions.isEmpty || search.errorMessage != nil) {
            VStack(spacing: 0) {
                if !search.directResults.isEmpty {
                    ForEach(Array(search.directResults.prefix(5).enumerated()), id: \.element.id) { index, place in
                        resultButton(title: place.name, subtitle: place.subtitle) {
                            selectTarget(place)
                        }
                        if index < min(search.directResults.count, 5) - 1 { Divider() }
                    }
                } else if !search.suggestions.isEmpty {
                    ForEach(Array(search.suggestions.prefix(5).enumerated()), id: \.element.id) { index, suggestion in
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
                        if index < min(search.suggestions.count, 5) - 1 { Divider() }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
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
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(11)
        }
        .buttonStyle(.plain)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }

    private var statusText: String {
        if routeEngine.snapshot.status.isActive { return "ROUTE" }
        return location.isLiveTracking ? "LIVE" : "OFF"
    }

    private var statusColor: Color {
        if routeEngine.snapshot.status.isActive { return .green }
        return location.isLiveTracking ? .blue : .secondary
    }

    private var compactDock: some View {
        HStack(spacing: 8) {
            Button {
                dismissKeyboard()
                centerOnCurrentLocation()
            } label: {
                Image(systemName: "location.fill")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)

            Button {
                beginDrawing()
            } label: {
                Label("Draw Route", systemImage: "pencil.and.scribble")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)

            Button {
                model.preferences.liveWhenIdle.toggle()
                model.applyPreferences()
            } label: {
                Image(systemName: location.isLiveTracking ? "location.circle.fill" : "location.slash")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(location.isLiveTracking ? "Turn live location off" : "Turn live location on")
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func pickedPlaceCard(_ coordinate: Coordinate) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected point")
                        .font(.subheadline.bold())
                    Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    pickedCoordinate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    usePickedPointAsTarget(coordinate)
                } label: {
                    Label("Set Target", systemImage: "mappin.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button {
                    interactionMode = .draw
                    draftPoints = [coordinate]
                    pickedCoordinate = nil
                } label: {
                    Label("Draw From Here", systemImage: "pencil.line")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var drawToolbar: some View {
        VStack(spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draw Route")
                        .font(.subheadline.bold())
                    Text(draftPoints.isEmpty ? "Tap the map to place the first point" : "\(draftPoints.count) points · \(formattedDraftDistance)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    if !draftPoints.isEmpty { draftPoints.removeLast() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(draftPoints.isEmpty)

                Button {
                    draftPoints.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(draftPoints.isEmpty)
            }

            HStack(spacing: 8) {
                if draftPoints.isEmpty {
                    Button {
                        addCurrentLocationToDraft()
                    } label: {
                        Label("Start at Me", systemImage: "location")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }

                Button("Cancel") {
                    interactionMode = .browse
                    draftPoints.removeAll()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Done") {
                    guard draftPoints.count >= 2 else {
                        uiMessage = "Add at least two points."
                        return
                    }
                    draftStartAt = Date().addingTimeInterval(300)
                    draftName = "Custom Route"
                    showRouteEditor = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(draftPoints.count < 2)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var activeRouteBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(activeRoute?.destination.name ?? "Route active")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(routeEngine.snapshot.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if routeEngine.snapshot.status == .running {
                Button("Pause") { routeEngine.pause() }
                    .buttonStyle(.bordered)
            } else {
                Button("Resume") { model.resumeRoute() }
                    .buttonStyle(.borderedProminent)
            }

            Button(role: .destructive) {
                model.killSwitch()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var routeEditor: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField("Route name", text: $draftName)

                    LabeledContent("Distance", value: formattedDraftDistance)

                    Stepper(value: $draftDurationMinutes, in: 1...720) {
                        LabeledContent("Duration", value: "\(draftDurationMinutes) min")
                    }

                    LabeledContent("Calculated speed", value: formattedDraftSpeed)
                }

                Section("Start time") {
                    Toggle("Add start-time reminder", isOn: $draftReminderEnabled)

                    if draftReminderEnabled {
                        DatePicker(
                            "Start",
                            selection: $draftStartAt,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        Text("Nexora can remind you at this time. iOS may not allow the route to auto-start if the app is suspended or closed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        saveDraftRoute(startImmediately: false)
                    } label: {
                        Label("Save Route", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        saveDraftRoute(startImmediately: true)
                    } label: {
                        Label("Save & Start Now", systemImage: "play.fill")
                    }
                }
            }
            .navigationTitle("Route Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRouteEditor = false }
                }
            }
        }
    }

    private var formattedDraftDistance: String {
        let meters = draftDistance
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    private var formattedDraftSpeed: String {
        guard draftDurationMinutes > 0 else { return "—" }
        let kmh = draftDistance / 1000 / (Double(draftDurationMinutes) / 60)
        return String(format: "%.1f km/h", kmh)
    }

    private var draftDistance: Double {
        guard draftPoints.count > 1 else { return 0 }
        return zip(draftPoints, draftPoints.dropFirst()).reduce(0) { total, pair in
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + a.distance(from: b)
        }
    }

    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        dismissKeyboard()
        let point = Coordinate(coordinate)

        switch interactionMode {
        case .browse:
            pickedCoordinate = point
        case .draw:
            if draftPoints.last != point {
                draftPoints.append(point)
            }
        }
    }

    private func usePickedPointAsTarget(_ coordinate: Coordinate) {
        let place = SavedPlace(
            name: "Map Pin",
            subtitle: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
            coordinate: coordinate
        )
        selectTarget(place)
        pickedCoordinate = nil
    }

    private func beginDrawing() {
        dismissKeyboard()
        pickedCoordinate = nil
        draftPoints.removeAll()
        interactionMode = .draw
    }

    private func addCurrentLocationToDraft() {
        guard let current = location.actualLocation else {
            model.preferences.liveWhenIdle = true
            model.applyPreferences()
            uiMessage = "Waiting for your current location."
            return
        }
        draftPoints = [Coordinate(current.coordinate)]
        camera = .region(MKCoordinateRegion(
            center: current.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }

    private func saveDraftRoute(startImmediately: Bool) {
        guard draftPoints.count >= 2 else { return }

        let distance = max(1, draftDistance)
        let duration = TimeInterval(max(1, draftDurationMinutes) * 60)
        let calculatedSpeed = max(1, min(200, distance / duration * 3.6))
        let densePoints = densify(draftPoints, spacingMeters: max(3, min(20, calculatedSpeed / 3.6 * 0.8)))

        guard let first = densePoints.first, let last = densePoints.last else { return }

        let start = SavedPlace(name: "Drawn Start", subtitle: "Custom map route", coordinate: first)
        let destination = SavedPlace(name: "Drawn End", subtitle: "Custom map route", coordinate: last)
        let route = RoutePlan(
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Route" : draftName,
            start: start,
            destination: destination,
            mode: .walking,
            targetSpeedKmh: calculatedSpeed,
            points: densePoints,
            distanceMeters: distance,
            expectedTravelTime: duration,
            pauseAtDestination: 0,
            waypoints: nil,
            randomPause: nil
        )

        model.saveRouteCandidate(route)
        model.selectedStart = start
        model.selectedDestination = destination

        if draftReminderEnabled {
            scheduleRouteReminder(route, at: draftStartAt)
        }

        if startImmediately {
            model.startRoute(route)
        }

        showRouteEditor = false
        interactionMode = .browse
        draftPoints.removeAll()
        pickedCoordinate = nil
        uiMessage = startImmediately ? "Custom route started." : "Custom route saved."
    }

    private func scheduleRouteReminder(_ route: RoutePlan, at date: Date) {
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Nexora Teleport"
        content.body = "Your route “\(route.name)” is planned to start now."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )

        let request = UNNotificationRequest(
            identifier: "route-\(route.id.uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func densify(_ input: [Coordinate], spacingMeters: Double) -> [Coordinate] {
        guard let first = input.first else { return [] }
        var result = [first]

        for index in 0..<(input.count - 1) {
            let a = input[index]
            let b = input[index + 1]
            let start = CLLocation(latitude: a.latitude, longitude: a.longitude)
            let end = CLLocation(latitude: b.latitude, longitude: b.longitude)
            let distance = start.distance(from: end)
            let steps = max(1, Int(ceil(distance / spacingMeters)))

            for step in 1...steps {
                let t = Double(step) / Double(steps)
                result.append(Coordinate(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }

        return result
    }

    private func dismissKeyboard() {
        searchFocused = false
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
            location.requestPermissions()
            uiMessage = "Waiting for your current location."
            return
        }

        camera = .region(MKCoordinateRegion(
            center: current.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }
}
