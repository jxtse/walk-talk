//
//  CaptionOverlay.swift
//  LocalGravity / Keepsake / Video
//
//  P5-T3 — Builds an AVMutableVideoComposition that overlays timed
//  captions on top of an asset using a CALayer hierarchy + CAKeyframe
//  opacity animations.
//
//  Notes:
//    - `build` is `async throws` because we read the asset's duration via
//      the modern (iOS 16+) `load(.duration)` API.
//    - Layer animations use `AVCoreAnimationBeginTimeAtZero` so they line
//      up with the composition timeline (CALayer treats `0` as "now",
//      AVFoundation treats `0` as "ignore" — this constant disambiguates).
//

#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit
import QuartzCore

public struct CaptionEntry: Equatable {
    public let text: String
    public let start: TimeInterval     // seconds, in composition time
    public let duration: TimeInterval  // seconds

    public init(text: String, start: TimeInterval, duration: TimeInterval) {
        self.text = text
        self.start = start
        self.duration = duration
    }
}

public struct CaptionOverlay {
    public init() {}

    /// Build a video composition that renders `captions` on top of `asset`.
    public func build(for asset: AVAsset,
                      size: CGSize,
                      captions: [CaptionEntry]) async throws -> AVMutableVideoComposition {
        let comp = AVMutableVideoComposition()
        comp.renderSize = size
        comp.frameDuration = CMTime(value: 1, timescale: 30)

        // Layer hierarchy: parent contains the post-processed video layer
        // and our caption layers on top.
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        parent.backgroundColor = UIColor.black.cgColor

        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        for cap in captions {
            let text = makeCaptionLayer(text: cap.text, size: size)
            text.opacity = 0

            let appear = CAKeyframeAnimation(keyPath: "opacity")
            appear.values = [0.0, 1.0, 1.0, 0.0]
            appear.keyTimes = [0.0, 0.1, 0.9, 1.0].map { NSNumber(value: $0) }
            appear.beginTime = AVCoreAnimationBeginTimeAtZero + cap.start
            appear.duration = max(0.05, cap.duration)
            appear.isRemovedOnCompletion = false
            appear.fillMode = .forwards
            text.add(appear, forKey: "fade")

            parent.addSublayer(text)
        }

        comp.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parent
        )

        // Single instruction spanning the asset.
        let duration = try await asset.load(.duration)
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: duration)

        // Layer instruction(s) for the asset's first video track, if any —
        // required for export to succeed against a real composition.
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let track = videoTracks.first {
            let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            instr.layerInstructions = [layerInstr]
        }
        comp.instructions = [instr]

        return comp
    }

    private func makeCaptionLayer(text: String, size: CGSize) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.fontSize = 48
        layer.font = UIFont.systemFont(ofSize: 48, weight: .semibold)
        layer.alignmentMode = .center
        layer.foregroundColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        layer.contentsScale = UIScreen.main.scale
        layer.frame = CGRect(x: 0, y: 120, width: size.width, height: 80)
        return layer
    }
}
#endif
