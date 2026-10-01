import Foundation
import CoreLocation

struct RouteHealthService {
    func inspect(_ route: RoutePlan) -> RouteHealthReport {
        var warnings: [String] = []
        guard route.points.count >= 2 else {
            return RouteHealthReport(isHealthy: false, warnings: ["Route has fewer than two points."], offlineReady: false)
        }

        if !route.distanceMeters.isFinite || route.distanceMeters <= 0 {
            warnings.append("Invalid route distance.")
        }
        if !route.targetSpeedKmh.isFinite || route.targetSpeedKmh <= 0 || route.targetSpeedKmh > 200 {
            warnings.append("Speed is outside the supported range.")
        }

        var largestSegment = 0.0
        for pair in zip(route.points, route.points.dropFirst()) {
            let a = pair.0
            let b = pair.1
            guard (-90...90).contains(a.latitude), (-180...180).contains(a.longitude),
                  (-90...90).contains(b.latitude), (-180...180).contains(b.longitude) else {
                warnings.append("Route contains an invalid coordinate.")
                continue
            }
            let distance = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            largestSegment = max(largestSegment, distance)
        }
        if largestSegment > 500 {
            warnings.append("One route segment is unusually large (\(Int(largestSegment)) m).")
        }

        return RouteHealthReport(
            isHealthy: warnings.isEmpty,
            warnings: warnings,
            offlineReady: route.points.count >= 2
        )
    }
}

actor CloudSyncService {
    static let shared = CloudSyncService()
    private let key = "nexora.teleport.portableBundle"

    func isAvailable() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func push(_ bundle: PortableBundle) throws {
        let data = try JSONEncoder().encode(bundle)
        guard data.count < 900_000 else {
            throw NSError(domain: "NexoraTeleport", code: 413, userInfo: [NSLocalizedDescriptionKey: "Cloud backup is too large for iCloud key-value sync."])
        }
        NSUbiquitousKeyValueStore.default.set(data, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    func pull() throws -> PortableBundle? {
        NSUbiquitousKeyValueStore.default.synchronize()
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(PortableBundle.self, from: data)
    }
}

struct ExportService {
    func portableBundleURL(_ bundle: PortableBundle) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nexora-Teleport-Backup.nexora.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func diagnosticsURL(_ snapshot: DiagnosticSnapshot) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nexora-Teleport-Diagnostics.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func gpxURL(route: RoutePlan) throws -> URL {
        let points = route.points.map { coordinate in
            "    <trkpt lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\"></trkpt>"
        }.joined(separator: "\n")
        let escapedName = route.name
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Nexora Teleport" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>\(escapedName)</name><trkseg>
        \(points)
          </trkseg></trk>
        </gpx>
        """
        let safe = route.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).gpx")
        try Data(xml.utf8).write(to: url, options: .atomic)
        return url
    }

    func decodePortableBundle(from url: URL) throws -> PortableBundle {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortableBundle.self, from: data)
    }
}

final class GPXParser: NSObject, XMLParserDelegate {
    private(set) var points: [Coordinate] = []

    func parse(url: URL) throws -> [Coordinate] {
        points = []
        guard let parser = XMLParser(contentsOf: url) else {
            throw NSError(domain: "NexoraTeleport", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unable to open GPX file."])
        }
        parser.delegate = self
        guard parser.parse(), points.count >= 2 else {
            throw parser.parserError ?? NSError(domain: "NexoraTeleport", code: 422, userInfo: [NSLocalizedDescriptionKey: "GPX does not contain a usable route."])
        }
        return points
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        guard elementName == "trkpt" || elementName == "rtept",
              let latText = attributeDict["lat"], let lonText = attributeDict["lon"],
              let lat = Double(latText), let lon = Double(lonText) else { return }
        points.append(Coordinate(latitude: lat, longitude: lon))
    }
}
