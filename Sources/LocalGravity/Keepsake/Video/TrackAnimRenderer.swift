//
//  TrackAnimRenderer.swift
//  LocalGravity / Keepsake / Video
//
//  P5-T1 — Renders the intro segment of the short-video keepsake: a
//  GPS polyline that grows from start to end over `duration` seconds,
//  encoded to an h.264 MP4 via AVAssetWriter.
//
//  Design contract (see plan §P5-T1, spec §5.2):
//    - Output: portrait 1080x1920 by default, 30 fps, h.264 MP4.
//    - Frames produced by `MapRenderer.snapshotPartial(track:size:fraction:)`
//      with fraction = (i + 1) / totalFrames; the polyline is drawn for
//      the first `floor(fraction * count)` GPS points only.
//    - On any AVAssetWriter failure throws `KeepsakeError.assemblyFailed("intro")`
//      so the orchestrator (KeepsakeBuilderV2) can fall back to the P4 poster.
//
//  Verification: Mac-only — Windows MinGW64 has no AVFoundation runtime.
//

#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit
import CoreMedia
import CoreVideo

public struct TrackAnimRenderer {
    public init() {}

    /// Renders an MP4 where the GPS polyline grows from start to end over `duration` seconds.
    public func render(track: [GPSPoint],
                       size: CGSize,
                       duration: TimeInterval,
                       output: URL) async throws {
        // Clean any stale output (AVAssetWriter refuses to overwrite).
        try? FileManager.default.removeItem(at: output)

        let fps: Int32 = 30
        let totalFrames = max(1, Int(duration * Double(fps)))

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attrs)

        guard writer.canAdd(input) else {
            throw KeepsakeError.assemblyFailed("intro: writer cannot add input")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw KeepsakeError.assemblyFailed("intro: startWriting failed: \(writer.error?.localizedDescription ?? "?")")
        }
        writer.startSession(atSourceTime: .zero)

        for i in 0..<totalFrames {
            let frac = Double(i + 1) / Double(totalFrames)
            let img = try await MapRenderer.snapshotPartial(track: track, size: size, fraction: frac)

            // Wait for the writer to be ready without busy-spinning.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000) // 5 ms
            }

            let buf = try img.pixelBuffer(size: size)
            let pts = CMTime(value: CMTimeValue(i), timescale: fps)
            if !adaptor.append(buf, withPresentationTime: pts) {
                input.markAsFinished()
                await writer.finishWriting()
                throw KeepsakeError.assemblyFailed("intro: append failed at frame \(i): \(writer.error?.localizedDescription ?? "?")")
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw KeepsakeError.assemblyFailed("intro: finish status \(writer.status.rawValue) \(writer.error?.localizedDescription ?? "")")
        }
    }
}
#endif
