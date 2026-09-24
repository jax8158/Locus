import CoreLocation
import Foundation
import MapKit

struct RouteWaypoint: Identifiable, Hashable {
    let id: UUID
    var pathIndex: Int
    var speedMultiplier: Double

    init(id: UUID = UUID(), pathIndex: Int, speedMultiplier: Double = 1.0) {
        self.id = id
        self.pathIndex = pathIndex
        self.speedMultiplier = speedMultiplier
    }
}

enum RouteBuilder {
    static func roadRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = mode.mkTransportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "Locus", code: 1, userInfo: [NSLocalizedDescriptionKey: "No route found"])
        }
        return sample(polyline: route.polyline, every: 12)
    }

    static func defaultWaypoints(for coordinates: [CLLocationCoordinate2D]) -> [RouteWaypoint] {
        guard !coordinates.isEmpty else { return [] }
        guard coordinates.count > 1 else {
            return [RouteWaypoint(pathIndex: 0, speedMultiplier: 1.0)]
        }
        return [
            RouteWaypoint(pathIndex: 0, speedMultiplier: 1.0),
            RouteWaypoint(pathIndex: coordinates.count - 1, speedMultiplier: 1.0),
        ]
    }

    static func normalizedWaypoints(_ waypoints: [RouteWaypoint], pathCount: Int) -> [RouteWaypoint] {
        guard pathCount > 0 else { return [] }

        let clamped = waypoints
            .map { waypoint in
                RouteWaypoint(
                    id: waypoint.id,
                    pathIndex: min(max(0, waypoint.pathIndex), pathCount - 1),
                    speedMultiplier: waypoint.speedMultiplier
                )
            }
            .sorted { $0.pathIndex < $1.pathIndex }

        var deduped: [RouteWaypoint] = []
        for waypoint in clamped {
            if let last = deduped.last, last.pathIndex == waypoint.pathIndex {
                deduped[deduped.count - 1] = waypoint
            } else {
                deduped.append(waypoint)
            }
        }

        if deduped.isEmpty {
            if pathCount == 1 {
                return [RouteWaypoint(pathIndex: 0, speedMultiplier: 1.0)]
            }
            return [
                RouteWaypoint(pathIndex: 0, speedMultiplier: 1.0),
                RouteWaypoint(pathIndex: pathCount - 1, speedMultiplier: 1.0),
            ]
        }

        if deduped.first?.pathIndex != 0 {
            deduped.insert(
                RouteWaypoint(pathIndex: 0, speedMultiplier: deduped.first?.speedMultiplier ?? 1.0),
                at: 0
            )
        }

        if deduped.last?.pathIndex != pathCount - 1 {
            deduped.append(
                RouteWaypoint(pathIndex: pathCount - 1, speedMultiplier: deduped.last?.speedMultiplier ?? 1.0)
            )
        }

        return deduped
    }

    static func nearestIndex(in coordinates: [CLLocationCoordinate2D], to coordinate: CLLocationCoordinate2D) -> Int {
        guard !coordinates.isEmpty else { return 0 }

        var bestIndex = 0
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude

        for (index, point) in coordinates.enumerated() {
            let distance = CLLocation(latitude: point.latitude, longitude: point.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    static func sample(polyline: MKPolyline, every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return sample(coordinates: coords, every: meters)
    }

    static func sample(coordinates: [CLLocationCoordinate2D], every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        var sampled = [coordinates[0]]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let dist = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let steps = max(1, Int(ceil(dist / meters)))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                sampled.append(CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }
        return sampled
    }
}

enum GPXCodec {
    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var coords: [CLLocationCoordinate2D] = []
        let pattern = #"lat="([^"]+)"[^>]*lon="([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let latR = Range(match.range(at: 1), in: text),
                  let lonR = Range(match.range(at: 2), in: text),
                  let lat = Double(text[latR]),
                  let lon = Double(text[lonR]) else { return }
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        // Also support lon before lat
        if coords.isEmpty {
            let alt = #"lon="([^"]+)"[^>]*lat="([^"]+)""#
            let altRegex = try NSRegularExpression(pattern: alt)
            altRegex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match,
                      let lonR = Range(match.range(at: 1), in: text),
                      let latR = Range(match.range(at: 2), in: text),
                      let lon = Double(text[lonR]),
                      let lat = Double(text[latR]) else { return }
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        guard !coords.isEmpty else {
            throw NSError(domain: "Locus", code: 2, userInfo: [NSLocalizedDescriptionKey: "No track points found in GPX"])
        }
        return coords
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Locus Route") -> String {
        var body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(name)</name>
            <trkseg>

        """
        for c in coordinates {
            body += String(format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\"></trkpt>\n", c.latitude, c.longitude)
        }
        body += """
            </trkseg>
          </trk>
        </gpx>
        """
        return body
    }
}
