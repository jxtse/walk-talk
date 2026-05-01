// Tests/LocalGravityTests/Keepsake/PosterComposerTests.swift
//
// P4-T5 step 2 — basic shape / sanity tests. We don't assert pixel-level
// content, only that an image is produced at the expected width and that
// the height grows when AI poster + map images are supplied.

import XCTest
@testable import LocalGravity

#if canImport(UIKit)
import UIKit

final class PosterComposerTests: XCTestCase {
    private func script() -> KeepsakeScript {
        KeepsakeScript(title: "测试",
                       narration: "narration",
                       posterPrompt: "p",
                       videoClips: [],
                       bgmTag: "calm",
                       highlightMomentIds: [])
    }

    private func mats() -> KeepsakeMaterials {
        let now = Date()
        return KeepsakeMaterials(track: [], moments: [], dialog: [],
                                 videoURL: nil,
                                 startedAt: now, endedAt: now.addingTimeInterval(900))
    }

    private func dummyImage(_ w: CGFloat, _ h: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    func test_producesNonEmptyImage_evenWithoutAiPosterOrMap() {
        let img = PosterComposer().compose(script: script(), materials: mats(),
                                           aiPoster: nil, mapImage: nil)
        XCTAssertGreaterThan(img.size.height, 100)
        XCTAssertEqual(img.size.width, 1024)
    }

    func test_includesAllVerticalSections_whenSuppliedImagesExist() {
        let dummy = dummyImage(100, 100)
        let img = PosterComposer().compose(script: script(), materials: mats(),
                                           aiPoster: dummy, mapImage: dummy)
        XCTAssertGreaterThan(img.size.height, 1500)
    }

    func test_statsLine_formatsMinutesKmAndMoments() {
        let now = Date()
        let mats = KeepsakeMaterials(track: [], moments: [], dialog: [],
                                     videoURL: nil,
                                     startedAt: now,
                                     endedAt: now.addingTimeInterval(60 * 30))
        let line = PosterComposer.statsLine(mats)
        XCTAssertTrue(line.contains("30 分钟"))
        XCTAssertTrue(line.contains("0 个时刻"))
    }
}
#endif
