//
//  VideoAssembler.swift
//  LocalGravity / Keepsake / Video
//
//  P5-T5 — Top-level video assembly: intro (track-anim) + N clips
//  (extracted from the Insta360 recording, with captions) + outro
//  (poster freeze frame). Final audio = looped BGM under everything.
//
//  Failure mode contract: any `throw` from this type bubbles up to
//  KeepsakeBuilderV2, which catches it and falls back to the P4 poster.
//

#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit
import CoreMedia

/// Abstraction so KeepsakeBuilderV2 can be unit-tested with stubs.
public protocol VideoAssembling {
    func assemble(materials: KeepsakeMaterials,
                  posterURL: URL,
                  script: KeepsakeScript) async throws -> URL
}

public struct VideoAssembler: VideoAssembling {
    public let introRenderer: TrackAnimRenderer
    public let extractor: ClipExtractor
    public let overlay: CaptionOverlay
    public let bgm: BGMMixer
    public let size: CGSize
    public let introDuration: TimeInterval
    public let outroDuration: TimeInterval
    public let bgmName: String

    public init(introRenderer: TrackAnimRenderer = .init(),
                extractor: ClipExtractor = .init(),
                overlay: CaptionOverlay = .init(),
                bgm: BGMMixer = .init(),
                size: CGSize = CGSize(width: 1080, height: 1920),
                introDuration: TimeInterval = 4.0,
                outroDuration: TimeInterval = 2.0,
                bgmName: String = "walk_default") {
        self.introRenderer = introRenderer
        self.extractor = extractor
        self.overlay = overlay
        self.bgm = bgm
        self.size = size
        self.introDuration = introDuration
        self.outroDuration = outroDuration
        self.bgmName = bgmName
    }

    public func assemble(materials: KeepsakeMaterials,
                         posterURL: URL,
                         script: KeepsakeScript) async throws -> URL {
        guard let videoFile = materials.videoFile else {
            throw KeepsakeError.assemblyFailed("no recorded video file in materials")
        }
        guard !script.videoClips.isEmpty else {
            throw KeepsakeError.assemblyFailed("script has no video clips")
        }
        guard let posterImage = UIImage(contentsOfFile: posterURL.path) else {
            throw KeepsakeError.assemblyFailed("poster image unreadable at \(posterURL.path)")
        }

        let tmp = FileManager.default.temporaryDirectory
        let workingDir = tmp.appendingPathComponent("keepsake_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)

        // 1. Intro segment.
        let introURL = workingDir.appendingPathComponent("intro.mp4")
        try await introRenderer.render(track: materials.gpsTrack,
                                       size: size,
                                       duration: introDuration,
                                       output: introURL)

        // 2. Per-clip extraction.
        var clipFiles: [(url: URL, caption: CaptionEntry)] = []
        for (i, clip) in script.videoClips.enumerated() {
            let url = workingDir.appendingPathComponent("clip_\(i).mp4")
            let range = CMTimeRange(
                start: CMTime(seconds: clip.start, preferredTimescale: 600),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
            )
            try await extractor.extract(from: videoFile, range: range, output: url)
            clipFiles.append((url, CaptionEntry(text: clip.caption, start: 0, duration: clip.duration)))
        }

        // 3. Outro: poster frozen for `outroDuration` seconds.
        let outroURL = workingDir.appendingPathComponent("outro.mp4")
        try await stillImageVideo(image: posterImage,
                                  size: size,
                                  duration: outroDuration,
                                  output: outroURL)

        // 4. Compose video tracks back-to-back.
        let comp = AVMutableComposition()
        guard let videoTrack = comp.addMutableTrack(withMediaType: .video,
                                                    preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw KeepsakeError.assemblyFailed("could not add composition video track")
        }
        let segmentURLs: [URL] = [introURL] + clipFiles.map { $0.url } + [outroURL]
        for src in segmentURLs {
            let asset = AVURLAsset(url: src)
            let dur = try await asset.load(.duration)
            guard let srcTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw KeepsakeError.assemblyFailed("segment has no video track: \(src.lastPathComponent)")
            }
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur),
                                           of: srcTrack,
                                           at: comp.duration)
        }

        // 5. Captions: shift each clip caption by its absolute start in the timeline.
        var captions: [CaptionEntry] = []
        var cursor = introDuration  // captions start after the intro
        for (_, cap) in clipFiles {
            captions.append(CaptionEntry(text: cap.text, start: cursor, duration: cap.duration))
            cursor += cap.duration
        }
        let videoComp = try await overlay.build(for: comp, size: size, captions: captions)

        // 6. BGM is best-effort. If it fails (e.g. placeholder file not
        // dropped in yet), keep going — KeepsakeBuilderV2 prefers a
        // silent video over falling back to the poster.
        do {
            try await bgm.mix(into: comp, bgmName: bgmName)
        } catch {
            LGLog.warn("BGM mix failed (continuing without audio): \(error)")
        }

        // 7. Export.
        let outURL = tmp.appendingPathComponent("keepsake_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)
        guard let exporter = AVAssetExportSession(asset: comp,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            throw KeepsakeError.assemblyFailed("exporter init")
        }
        exporter.videoComposition = videoComp
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        await exporter.export()
        if exporter.status != .completed {
            throw KeepsakeError.assemblyFailed("export: \(exporter.error?.localizedDescription ?? "status \(exporter.status.rawValue)")")
        }
        return outURL
    }

    // MARK: - Still-image MP4 helper (outro freeze)

    /// Writes a `duration`-second h.264 MP4 of `image` at 30fps.
    /// Mirror of TrackAnimRenderer's writer loop with a constant frame.
    private func stillImageVideo(image: UIImage,
                                 size: CGSize,
                                 duration: TimeInterval,
                                 output: URL) async throws {
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
            throw KeepsakeError.assemblyFailed("outro: writer cannot add input")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw KeepsakeError.assemblyFailed("outro: startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        // Build the pixel buffer ONCE, then re-append each frame.
        let buf = try image.pixelBuffer(size: size)
        for i in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let pts = CMTime(value: CMTimeValue(i), timescale: fps)
            if !adaptor.append(buf, withPresentationTime: pts) {
                input.markAsFinished()
                await writer.finishWriting()
                throw KeepsakeError.assemblyFailed("outro: append failed at frame \(i)")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw KeepsakeError.assemblyFailed("outro: finish status \(writer.status.rawValue)")
        }
    }
}
#endif
