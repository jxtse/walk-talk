// Sources/LocalGravity/Location/LocationSvc.swift
//
// Thin CoreLocation wrapper that pumps updates into a TrackBuffer.
// Plan reference: P1-T5. Production fault-handling lives in P3-T5.
import Foundation
import CoreLocation

public final class LocationSvc: NSObject, CLLocationManagerDelegate {
    public let buffer: TrackBuffer
    private let manager: CLLocationManager

    public init(buffer: TrackBuffer = TrackBuffer()) {
        self.buffer = buffer
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5            // meters
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .fitness
    }

    public func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    public func start() {
        manager.startUpdatingLocation()
    }

    public func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            buffer.append(TrackPoint(
                coordinate: loc.coordinate,
                timestamp: loc.timestamp,
                horizontalAccuracy: loc.horizontalAccuracy
            ))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // P1: just log. Production path handled in P3-T5.
        print("LocationSvc error: \(error)")
    }
}
