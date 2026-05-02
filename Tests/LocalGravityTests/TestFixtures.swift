import Foundation
import CoreLocation
@testable import LocalGravity

enum TestFixtures {
    static let xuanwuLakeShortTrack: [GPSPoint] = [
        GPSPoint(coordinate: CLLocationCoordinate2D(latitude: 32.072, longitude: 118.794),
                 timestamp: Date(timeIntervalSince1970: 0),
                 horizontalAccuracy: 5),
        GPSPoint(coordinate: CLLocationCoordinate2D(latitude: 32.074, longitude: 118.796),
                 timestamp: Date(timeIntervalSince1970: 10),
                 horizontalAccuracy: 5),
        GPSPoint(coordinate: CLLocationCoordinate2D(latitude: 32.076, longitude: 118.797),
                 timestamp: Date(timeIntervalSince1970: 20),
                 horizontalAccuracy: 5)
    ]

    static func fixtureURL(_ name: String, extension ext: String) -> URL? {
        let bundleHit = Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext)
        let sourceHit = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).\(ext)")
        return bundleHit ?? (FileManager.default.fileExists(atPath: sourceHit.path) ? sourceHit : nil)
    }

    static func bgmURL(named name: String) -> URL? {
        let bundle = Bundle(for: BundleToken.self)
        if let url = bundle.url(forResource: name, withExtension: "m4a", subdirectory: "BGM")
            ?? bundle.url(forResource: name, withExtension: "m4a") {
            return url
        }
        let sourceHit = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LocalGravity/Resources/BGM")
            .appendingPathComponent("\(name).m4a")
        return FileManager.default.fileExists(atPath: sourceHit.path) ? sourceHit : nil
    }
}

private final class BundleToken {}
