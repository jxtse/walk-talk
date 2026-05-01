// Sources/LocalGravity/Map/MapRenderer+Snapshot.swift
//
// P4-T2 — Keepsake-specific helpers for MapRenderer.
//
// Per the worktree contract for P4, the body of `MapRenderer.swift` itself
// (written in P1) MUST NOT be edited from this phase. All new keepsake
// helpers are added here as an extension. When the P1 base lands the file
// will compile against the same `MapRenderer` symbol.
//
// What this adds (mirrors plan §P4-T2 step 2):
//   • MapRenderer.center(of:) — pure helper, average of coordinates
//   • MapRenderer.zoomLevel(for:) — coarse heuristic from bbox span
//   • MapRenderer.renderStaticSnapshot(track:size:) — async helper that
//     forwards to the P1 base when available; until then it is a
//     deterministic placeholder so KeepsakeBuilder always gets *some*
//     image back. The placeholder draws the polyline in the bbox so even
//     without a basemap the user sees their walk shape.
//
// LOOKUP-AMAP-7: replace the placeholder body with `MAMapView.takeSnapshot`
// once Amap iOS SDK is integrated; the surface here stays stable.

import Foundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public extension MapRenderer {

    /// Centroid of `track`. Returns (0, 0) when empty.
    static func center(of track: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !track.isEmpty else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        let lat = track.map { $0.latitude }.reduce(0, +) / Double(track.count)
        let lng = track.map { $0.longitude }.reduce(0, +) / Double(track.count)
        return .init(latitude: lat, longitude: lng)
    }

    /// Coarse Amap zoom-level heuristic — bigger bbox → smaller zoom.
    static func zoomLevel(for track: [CLLocationCoordinate2D]) -> Double {
        guard let lats = track.map(\.latitude).minMax(),
              let lngs = track.map(\.longitude).minMax()
        else { return 16 }
        let span = max(lats.max - lats.min, lngs.max - lngs.min)
        switch span {
        case 0..<0.005:   return 17
        case 0.005..<0.02: return 15
        case 0.02..<0.1:  return 13
        case 0.1..<0.5:   return 11
        default:          return 9
        }
    }

    /// Static snapshot of the walk track. Until the Amap basemap is wired
    /// (LOOKUP-AMAP-7), draws a clean polyline-on-light-grey image so the
    /// poster still has something useful in the map slot.
    static func renderStaticSnapshot(track: [CLLocationCoordinate2D],
                                     size: CGSize) async -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            guard track.count >= 1 else { return }

            // bbox in geographic coords
            let lats = track.map(\.latitude)
            let lngs = track.map(\.longitude)
            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLng = lngs.min() ?? 0
            let maxLng = lngs.max() ?? 0

            let inset: CGFloat = 24
            let drawRect = CGRect(x: inset, y: inset,
                                  width: max(1, size.width - 2 * inset),
                                  height: max(1, size.height - 2 * inset))

            func project(_ c: CLLocationCoordinate2D) -> CGPoint {
                let dx = maxLng - minLng
                let dy = maxLat - minLat
                let x = dx > 0 ? (c.longitude - minLng) / dx : 0.5
                let y = dy > 0 ? 1.0 - (c.latitude - minLat) / dy : 0.5
                return CGPoint(x: drawRect.minX + CGFloat(x) * drawRect.width,
                               y: drawRect.minY + CGFloat(y) * drawRect.height)
            }

            let path = UIBezierPath()
            path.move(to: project(track[0]))
            for i in 1..<track.count { path.addLine(to: project(track[i])) }
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.systemTeal.setStroke()
            path.stroke()
        }
    }
}

private extension Array where Element == Double {
    func minMax() -> (min: Double, max: Double)? {
        guard let mn = self.min(), let mx = self.max() else { return nil }
        return (mn, mx)
    }
}
#endif
