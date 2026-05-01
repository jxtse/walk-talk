// Sources/LocalGravity/Amap/AmapClient.swift
//
// REST wrapper for the four 高德 Web Service APIs we need:
//   - place around / text search
//   - walking direction
//   - reverse geocode
//
// Plan reference: P1-T8. Reference docs:
// https://lbs.amap.com/api/webservice/guide/api/search
//
// Default key: AMAP_KEY env var, then Secrets.plist, then the test key
// documented in the spec (Secrets.defaultAmapKey).
import Foundation
import CoreLocation

public struct AmapPOI: Equatable {
    public let id: String
    public let name: String
    public let type: String
    public let address: String
    public let coordinate: CLLocationCoordinate2D
    public let distanceMeters: Int?

    public init(id: String, name: String, type: String, address: String, coordinate: CLLocationCoordinate2D, distanceMeters: Int?) {
        self.id = id; self.name = name; self.type = type
        self.address = address; self.coordinate = coordinate
        self.distanceMeters = distanceMeters
    }
}

public enum AmapClientError: Error, Equatable {
    case http(Int, String)
    case apiStatus(String, String)   // (status, info)
    case decoding(String)
}

public final class AmapClient {
    private let baseURL = URL(string: "https://restapi.amap.com")!
    private let key: String
    private let session: URLSession

    public init(key: String = Secrets.shared.amapApiKey, session: URLSession = .shared) {
        self.key = key
        self.session = session
    }

    public func aroundSearch(lat: Double, lng: Double,
                             keyword: String? = nil,
                             types: String? = nil,
                             radius: Int = 1000,
                             pageSize: Int = 10) async throws -> [AmapPOI] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v3/place/around"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "location", value: "\(lng),\(lat)"),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "offset", value: String(pageSize)),
            URLQueryItem(name: "extensions", value: "base")
        ]
        if let keyword { comps.queryItems?.append(URLQueryItem(name: "keywords", value: keyword)) }
        if let types { comps.queryItems?.append(URLQueryItem(name: "types", value: types)) }
        return try await fetchPOIs(url: comps.url!)
    }

    public func textSearch(query: String, region: String? = nil) async throws -> [AmapPOI] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v3/place/text"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "extensions", value: "base")
        ]
        if let region { comps.queryItems?.append(URLQueryItem(name: "city", value: region)) }
        return try await fetchPOIs(url: comps.url!)
    }

    public struct WalkingDirection: Equatable {
        public let distanceMeters: Int
        public let durationSeconds: Int
        public let bearingFromOrigin: Double   // degrees, 0=N

        public init(distanceMeters: Int, durationSeconds: Int, bearingFromOrigin: Double) {
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.bearingFromOrigin = bearingFromOrigin
        }
    }

    public func walkingDirection(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> WalkingDirection {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v3/direction/walking"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "origin", value: "\(from.longitude),\(from.latitude)"),
            URLQueryItem(name: "destination", value: "\(to.longitude),\(to.latitude)")
        ]
        let data = try await fetchRaw(comps.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String, status == "1",
              let route = json["route"] as? [String: Any],
              let paths = route["paths"] as? [[String: Any]],
              let first = paths.first,
              let dStr = first["distance"] as? String, let d = Int(dStr),
              let tStr = first["duration"] as? String, let t = Int(tStr)
        else { throw AmapClientError.decoding("walking shape unexpected") }

        let bearing = Self.bearing(from: from, to: to)
        return WalkingDirection(distanceMeters: d, durationSeconds: t, bearingFromOrigin: bearing)
    }

    public struct GeoResult: Equatable {
        public let formattedAddress: String
        public let coordinate: CLLocationCoordinate2D

        public init(formattedAddress: String, coordinate: CLLocationCoordinate2D) {
            self.formattedAddress = formattedAddress
            self.coordinate = coordinate
        }
    }

    public func reverseGeocode(_ c: CLLocationCoordinate2D) async throws -> GeoResult {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v3/geocode/regeo"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "location", value: "\(c.longitude),\(c.latitude)")
        ]
        let data = try await fetchRaw(comps.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String, status == "1",
              let regeo = json["regeocode"] as? [String: Any],
              let addr = regeo["formatted_address"] as? String
        else { throw AmapClientError.decoding("regeo shape unexpected") }
        return GeoResult(formattedAddress: addr, coordinate: c)
    }

    // MARK: - shared

    private func fetchRaw(_ url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AmapClientError.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                                       String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func fetchPOIs(url: URL) async throws -> [AmapPOI] {
        let data = try await fetchRaw(url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AmapClientError.decoding("not a json object")
        }
        if let status = json["status"] as? String, status != "1" {
            let info = json["info"] as? String ?? ""
            throw AmapClientError.apiStatus(status, info)
        }
        guard let arr = json["pois"] as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let loc = dict["location"] as? String
            else { return nil }
            let parts = loc.split(separator: ",")
            guard parts.count == 2,
                  let lng = Double(parts[0]),
                  let lat = Double(parts[1])
            else { return nil }
            let dist: Int? = (dict["distance"] as? String).flatMap(Int.init)
            return AmapPOI(
                id: id, name: name,
                type: dict["type"] as? String ?? "",
                address: dict["address"] as? String ?? "",
                coordinate: .init(latitude: lat, longitude: lng),
                distanceMeters: dist
            )
        }
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}
