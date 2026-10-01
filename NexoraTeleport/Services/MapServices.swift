import Foundation
import MapKit
import CoreLocation

@MainActor
final class SearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published var suggestions: [SearchSuggestion] = []
    @Published var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(8).map {
            .init(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }

    func resolve(_ suggestion: SearchSuggestion) async throws -> SavedPlace {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw NSError(domain: "NexoraTeleport", code: 404, userInfo: [NSLocalizedDescriptionKey: "Location not found"])
        }
        return SavedPlace(
            name: item.name ?? suggestion.title,
            subtitle: item.placemark.title ?? suggestion.subtitle,
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
        let response = try await MKDirections(request: request).calculate()
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
            let response = try await MKDirections(request: request).calculate()
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
        NSError(domain: "NexoraTeleport", code: 404, userInfo: [NSLocalizedDescriptionKey: "No route available"])
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
