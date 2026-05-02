// Sources/LocalGravity/Map/MapRenderer.swift
//
// Thin facade over the 高德 basemap. In P1 this only exposes a stub static
// renderer used by KeepsakeBuilder; the real renderer arrives in P4-T2.
// Plan reference: P1-T6.
import Foundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public final class MapRenderer {
    public init() {}

    /// Render the given track to a static UIImage of the given size. In P1
    /// returns a solid blue square so callers can be unit-tested. P4-T2
    /// replaces this with a real Amap snapshot.
    public func renderStatic(track: [CLLocationCoordinate2D], size: CGSize) async throws -> UIImage {
        UIGraphicsBeginImageContext(size)
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
}
#endif
