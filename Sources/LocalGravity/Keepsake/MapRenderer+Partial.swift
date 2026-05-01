//
//  MapRenderer+Partial.swift
//  LocalGravity / Keepsake
//
//  P5-T1 — Adds `MapRenderer.snapshotPartial(track:size:fraction:)` used by
//  TrackAnimRenderer to render a growing polyline animation.
//
//  Strategy:
//    - `fraction` is clamped to [0, 1].
//    - The visible point count is `max(1, floor(fraction * track.count))`.
//    - The partial polyline is rendered into the same bounding box as the
//      *full* track so the camera does not zoom mid-animation. We compute
//      the bbox from the full track here; if the P4 implementation already
//      exposes a bbox helper, this can be swapped to call into it.
//
//  This file is namespaced as an extension on `MapRenderer`, which is
//  expected to exist (added in P4).
//

#if canImport(UIKit)
import UIKit
import CoreGraphics

extension MapRenderer {
    /// Render the first `floor(fraction * count)` points of `track` as a polyline,
    /// laid out within the bounding box of the *full* track so the camera is stable.
    public static func snapshotPartial(track: [GPSPoint],
                                       size: CGSize,
                                       fraction: Double) async throws -> UIImage {
        let f = max(0.0, min(1.0, fraction))
        guard !track.isEmpty else {
            return solidImage(size: size, color: .black)
        }
        let n = max(1, Int((Double(track.count) * f).rounded(.down)))
        let visible = Array(track.prefix(n))

        // Bounding box from the FULL track keeps the camera stable as the
        // line grows. Add a small inset so the line is not flush to the edge.
        let bbox = boundingBox(of: track)
        let inset: CGFloat = 0.06 // 6% padding on each side
        let padW = size.width * inset
        let padH = size.height * inset
        let drawRect = CGRect(x: padW,
                              y: padH,
                              width: max(1, size.width - 2 * padW),
                              height: max(1, size.height - 2 * padH))

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Background.
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            guard visible.count >= 1 else { return }

            // Project lat/lon -> pixel using the full bbox.
            func project(_ p: GPSPoint) -> CGPoint {
                let dx = bbox.maxLon - bbox.minLon
                let dy = bbox.maxLat - bbox.minLat
                let x = dx > 0 ? (p.lon - bbox.minLon) / dx : 0.5
                // Latitude grows north → invert y so north appears at top.
                let y = dy > 0 ? 1.0 - (p.lat - bbox.minLat) / dy : 0.5
                return CGPoint(x: drawRect.minX + CGFloat(x) * drawRect.width,
                               y: drawRect.minY + CGFloat(y) * drawRect.height)
            }

            let path = UIBezierPath()
            let first = project(visible[0])
            path.move(to: first)
            for i in 1..<visible.count {
                path.addLine(to: project(visible[i]))
            }
            path.lineWidth = 6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.systemTeal.setStroke()
            path.stroke()

            // Head dot.
            if let last = visible.last {
                let p = project(last)
                let dot = UIBezierPath(arcCenter: p,
                                       radius: 10,
                                       startAngle: 0,
                                       endAngle: .pi * 2,
                                       clockwise: true)
                UIColor.white.setFill()
                dot.fill()
            }
        }
    }

    // MARK: - bbox helper (kept local to avoid touching P4 surface)

    fileprivate struct BBox {
        var minLat: Double
        var maxLat: Double
        var minLon: Double
        var maxLon: Double
    }

    fileprivate static func boundingBox(of track: [GPSPoint]) -> BBox {
        var box = BBox(minLat: .greatestFiniteMagnitude,
                       maxLat: -.greatestFiniteMagnitude,
                       minLon: .greatestFiniteMagnitude,
                       maxLon: -.greatestFiniteMagnitude)
        for p in track {
            box.minLat = min(box.minLat, p.lat)
            box.maxLat = max(box.maxLat, p.lat)
            box.minLon = min(box.minLon, p.lon)
            box.maxLon = max(box.maxLon, p.lon)
        }
        if box.minLat == .greatestFiniteMagnitude {
            box = BBox(minLat: 0, maxLat: 0, minLon: 0, maxLon: 0)
        }
        return box
    }

    fileprivate static func solidImage(size: CGSize, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#endif
