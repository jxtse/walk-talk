// Sources/LocalGravity/Map/MapPreviewView.swift
//
// SwiftUI wrapper around 高德 SDK's MAMapView. Until LOOKUP-AMAP-* are
// resolved on a Mac, returns a placeholder UIView so the rest of the app
// still builds. Plan reference: P1-T6.
import SwiftUI
import CoreLocation
import UIKit

// LOOKUP-AMAP-3: import MAMapKit

public struct MapPreviewView: UIViewRepresentable {
    public let track: [CLLocationCoordinate2D]
    public init(track: [CLLocationCoordinate2D]) { self.track = track }

    public func makeUIView(context: Context) -> UIView {
        // LOOKUP-AMAP-4: instantiate MAMapView, set delegate, return it.
        // let v = MAMapView(frame: .zero)
        // v.showsUserLocation = false
        // return v
        let placeholder = UIView()
        placeholder.backgroundColor = .systemGray5
        return placeholder
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        // LOOKUP-AMAP-5: convert track → MAPolyline, remove old overlays, add new.
        // guard let mapView = uiView as? MAMapView else { return }
        // mapView.removeOverlays(mapView.overlays ?? [])
        // let coords = track
        // let line = MAPolyline(coordinates: coords, count: UInt(coords.count))
        // mapView.add(line)
    }
}
