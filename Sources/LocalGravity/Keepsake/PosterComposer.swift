// Sources/LocalGravity/Keepsake/PosterComposer.swift
//
// P4-T5 — Compose the long vertical poster (1024 × variable) from a script,
// the walk's materials, an optional AI image, and an optional map snapshot.
//
// Layout (top → bottom):
//   ┌─────────────┐
//   │  AI poster  │  (1024×1024, optional)
//   ├─────────────┤
//   │  title      │
//   │  narration  │
//   ├─────────────┤
//   │  map track  │  (1024×600, optional)
//   ├─────────────┤
//   │  stats      │
//   │  highlights │
//   └─────────────┘
//
// All inputs are optional or graceful-empty so the failsafe path always
// produces a non-zero image.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public final class PosterComposer {
    public init() {}

    public func compose(script: KeepsakeScript,
                        materials: KeepsakeMaterials,
                        aiPoster: UIImage?,
                        mapImage: UIImage?) -> UIImage {
        let width: CGFloat = 1024
        let aiH: CGFloat = aiPoster != nil ? 1024 : 0
        let mapH: CGFloat = mapImage != nil ? 600 : 0
        let textBlockH: CGFloat = 280
        let highlightCount = max(0, min(materials.moments.count, 5))
        let statsH: CGFloat = 220 + CGFloat(highlightCount) * 40
        let total = aiH + textBlockH + mapH + statsH + 80

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: total))
        return renderer.image { ctx in
            UIColor(white: 0.98, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: total))

            var y: CGFloat = 0
            if let ai = aiPoster {
                ai.draw(in: CGRect(x: 0, y: y, width: width, height: aiH))
                y += aiH
            }

            // Title + narration block
            y += 40
            let title = NSAttributedString(string: script.title, attributes: [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.label
            ])
            title.draw(at: CGPoint(x: 60, y: y))
            y += 80

            let narration = NSAttributedString(string: script.narration, attributes: [
                .font: UIFont.systemFont(ofSize: 28, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ])
            narration.draw(in: CGRect(x: 60, y: y, width: width - 120, height: 120))
            y += 160

            if let map = mapImage {
                map.draw(in: CGRect(x: 0, y: y, width: width, height: mapH))
                y += mapH
            }

            // Stats line
            y += 40
            let stats = NSAttributedString(string: Self.statsLine(materials), attributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.label
            ])
            stats.draw(at: CGPoint(x: 60, y: y))
            y += 60

            for mo in materials.moments.prefix(5) {
                let line = "• \(mo.context)"
                NSAttributedString(string: line, attributes: [
                    .font: UIFont.systemFont(ofSize: 22),
                    .foregroundColor: UIColor.secondaryLabel
                ]).draw(at: CGPoint(x: 80, y: y))
                y += 36
            }
        }
    }

    static func statsLine(_ m: KeepsakeMaterials) -> String {
        let mins = Int(m.durationSeconds / 60)
        let km = m.distanceMeters / 1000.0
        return String(format: "%d 分钟 · %.2f 公里 · %d 个时刻",
                      mins, km, m.moments.count)
    }
}
#endif
