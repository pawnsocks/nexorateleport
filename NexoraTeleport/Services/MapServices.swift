import Foundation
import MapKit
import CoreLocation

@MainActor
final class SearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            completer.queryFragment = trimmed
            if trimmed.isEmpty {
                suggestions = []
                directResults = []
                errorMessage = nil
            }
        }
    }
    @Published var suggestions: [SearchSuggestion] = []
    @Published var directResults: [SavedPlace] = []
    @Published var errorMessage: String?
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var preferredRegion: MKCoordinateRegion?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateRegion(center: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7)
        )
        preferredRegion = region
        completer.region = region
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(8).map {
            .init(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
        if !suggestions.isEmpty { errorMessage = nil }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func searchNow() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            directResults = []
            errorMessage = "Type at least 2 characters."
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await search(text: trimmed)
            directResults = results
            if results.isEmpty {
                errorMessage = "No places found. Try a city, street, postcode, or landmark."
            } else {
                errorMessage = nil
            }
        } catch {
            directResults = []
            errorMessage = friendlyMessage(for: error)
        }
    }

    func resolve(_ suggestion: SearchSuggestion) async throws -> SavedPlace {
        do {
            let request = MKLocalSearch.Request(completion: suggestion.completion)
            if let preferredRegion { request.region = preferredRegion }
            let response = try await MKLocalSearch(request: request).start()
            if let item = response.mapItems.first {
                return place(from: item, fallbackName: suggestion.title, fallbackSubtitle: suggestion.subtitle)
            }
        } catch {
            if let mkError = error as? MKError, mkError.code != .placemarkNotFound {
                throw NSError(
                    domain: "NexoraTeleport.Search",
                    code: Int(mkError.code.rawValue),
                    userInfo: [NSLocalizedDescriptionKey: friendlyMessage(for: error)]
                )
            }
        }

        let fallbackText = [suggestion.title, suggestion.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let results = try await search(text: fallbackText)
        guard let first = results.first else {
            throw NSError(
                domain: "NexoraTeleport.Search",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't find that place. Try a more specific search."]
            )
        }
        return first
    }

    func friendlyMessage(for error: Error) -> String {
        guard let mkError = error as? MKError else {
            return "Search couldn't finish. Check your connection and try again."
        }

        switch mkError.code {
        case .placemarkNotFound:
            return "Couldn't find that place. Try a city, street, postcode, or landmark."
        case .directionsNotFound:
            return "No route is available between those locations."
        case .loadingThrottled:
            return "Map search is temporarily busy. Try again in a moment."
        case .serverFailure:
            return "Apple Maps is temporarily unavailable. Try again shortly."
        case .decodingFailed:
            return "The map result couldn't be read. Try another search."
        case .unknown:
            return "Map search failed. Try a more specific place name."
        @unknown default:
            return "Map search failed. Try again."
        }
    }

    private func search(text: String) async throws -> [SavedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        if let preferredRegion { request.region = preferredRegion }

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(10).map {
                place(from: $0, fallbackName: text, fallbackSubtitle: "")
            }
        } catch {
            throw NSError(
                domain: "NexoraTeleport.Search",
                code: Int((error as? MKError)?.code.rawValue ?? 1),
                userInfo: [NSLocalizedDescriptionKey: friendlyMessage(for: error)]
            )
        }
    }

    private func place(from item: MKMapItem, fallbackName: String, fallbackSubtitle: String) -> SavedPlace {
        SavedPlace(
            name: item.name ?? fallbackName,
            subtitle: item.placemark.title ?? fallbackSubtitle,
            coordinate: Coordinate(item.placemark.coordinate)
        )
    }
}

struct RouteService {
    func calculateAlternatives(
        start: SavedPlace,
        destination: SavedPlace,
        waypoints: [SavedPlace] = [],
        mode: TravelMode,
        speedKmh: Double
    ) async throws -> [RoutePlan] {
        if !waypoints.isEmpty {
            return [try await calculateMultiLeg(start: start, destination: destination, waypoints: waypoints, mode: mode, speedKmh: speedKmh)]
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate.cl))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate.cl))
        request.transportType = mode.transportType
        request.requestsAlternateRoutes = true

        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch {
            throw normalizedDirectionsError(error)
        }
        guard !response.routes.isEmpty else { throw noRouteError }

        return response.routes.prefix(3).enumerated().map { index, route in
            buildPlan(
                route: route,
                name: index == 0 ? "\(start.name) → \(destination.name)" : "\(start.name) → \(destination.name) · Alt \(index + 1)",
                start: start,
                destination: destination,
                waypoints: [],
                mode: mode,
                speedKmh: speedKmh
            )
        }
    }

    func calculate(start: SavedPlace, destination: SavedPlace, mode: TravelMode, speedKmh: Double) async throws -> RoutePlan {
        guard let first = try await calculateAlternatives(start: start, destination: destination, mode: mode, speedKmh: speedKmh).first else {
            throw noRouteError
        }
        return first
    }

    private func calculateMultiLeg(
        start: SavedPlace,
        destination: SavedPlace,
        waypoints: [SavedPlace],
        mode: TravelMode,
        speedKmh: Double
    ) async throws -> RoutePlan {
        let places = [start] + waypoints + [destination]
        var allCoordinates: [CLLocationCoordinate2D] = []
        var totalDistance = 0.0

        for index in 0..<(places.count - 1) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: places[index].coordinate.cl))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: places[index + 1].coordinate.cl))
            request.transportType = mode.transportType
            request.requestsAlternateRoutes = false

            let response: MKDirections.Response
            do {
                response = try await MKDirections(request: request).calculate()
            } catch {
                throw normalizedDirectionsError(error)
            }

            guard let route = response.routes.first else { throw noRouteError }
            totalDistance += route.distance
            var coordinates = Array(repeating: CLLocationCoordinate2D(), count: route.polyline.pointCount)
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))
            if !allCoordinates.isEmpty, !coordinates.isEmpty { coordinates.removeFirst() }
            allCoordinates.append(contentsOf: coordinates)
        }

        guard allCoordinates.count >= 2 else { throw noRouteError }
        let safeSpeedKmh = max(1, min(speedKmh, 200))
        let speedMps = safeSpeedKmh / 3.6
        let spacingMeters = max(2.0, min(20.0, speedMps * 0.8))
        let dense = densify(allCoordinates, spacingMeters: spacingMeters)
        return RoutePlan(
            name: "\(start.name) → \(destination.name) via \(waypoints.count) stop\(waypoints.count == 1 ? "" : "s")",
            start: start,
            destination: destination,
            mode: mode,
            targetSpeedKmh: safeSpeedKmh,
            points: dense.map(Coordinate.init),
            distanceMeters: totalDistance,
            expectedTravelTime: totalDistance / speedMps,
            pauseAtDestination: 0,
            waypoints: waypoints
        )
    }

    private func buildPlan(
        route: MKRoute,
        name: String,
        start: SavedPlace,
        destination: SavedPlace,
        waypoints: [SavedPlace],
        mode: TravelMode,
        speedKmh: Double
    ) -> RoutePlan {
        var rawCoordinates = Array(repeating: CLLocationCoordinate2D(), count: route.polyline.pointCount)
        route.polyline.getCoordinates(&rawCoordinates, range: NSRange(location: 0, length: route.polyline.pointCount))
        let safeSpeedKmh = max(1, min(speedKmh, 200))
        let speedMps = safeSpeedKmh / 3.6
        let spacingMeters = max(2.0, min(20.0, speedMps * 0.8))
        let coordinates = densify(rawCoordinates, spacingMeters: spacingMeters)
        return RoutePlan(
            name: name,
            start: start,
            destination: destination,
            mode: mode,
            targetSpeedKmh: safeSpeedKmh,
            points: coordinates.map(Coordinate.init),
            distanceMeters: route.distance,
            expectedTravelTime: route.distance / speedMps,
            pauseAtDestination: 0,
            waypoints: waypoints
        )
    }

    private var noRouteError: NSError {
        NSError(
            domain: "NexoraTeleport.Route",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No usable route was found. Try another travel mode or target."]
        )
    }

    private func normalizedDirectionsError(_ error: Error) -> NSError {
        let message: String
        if let mkError = error as? MKError {
            switch mkError.code {
            case .directionsNotFound, .placemarkNotFound:
                message = "No usable route was found. Try another travel mode or target."
            case .loadingThrottled:
                message = "Route service is temporarily busy. Try again in a moment."
            case .serverFailure:
                message = "Apple Maps is temporarily unavailable. Try again shortly."
            default:
                message = "Route calculation failed. Check your connection and try again."
            }
        } else {
            message = "Route calculation failed. Check your connection and try again."
        }
        return NSError(domain: "NexoraTeleport.Route", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func densify(_ input: [CLLocationCoordinate2D], spacingMeters: Double) -> [CLLocationCoordinate2D] {
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
                result.append(CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }
        return result
    }
}
