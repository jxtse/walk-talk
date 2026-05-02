//
//  BGMMixer.swift
//  LocalGravity / Keepsake / Video
//
//  P5-T4 — Adds a single royalty-free music track underneath the
//  composition's video, looping it to cover the full video duration.
//
//  Source of `walk_default.m4a` is documented in
//  `Sources/LocalGravity/Resources/BGM/walk_default.m4a.PLACEHOLDER.md`.
//
//  The mixer never throws on "BGM missing" softly — it surfaces a typed
//  error so KeepsakeBuilderV2 can decide whether the rest of the video
//  is still useful (it is: VideoAssembler currently treats BGM as
//  best-effort and lets the assembly continue without audio).
//

#if canImport(AVFoundation)
import AVFoundation

public struct BGMMixer {
    public enum MixError: Error, Equatable {
        case bgmNotFound(name: String)
        case insertFailed(String)
    }

    public init() {}

    /// Insert `bgmName.m4a` into `comp` as an audio track, looping to
    /// match the composition's current video duration.
    public func mix(into comp: AVMutableComposition, bgmName: String) async throws {
        let url = try locateBGM(named: bgmName)
        let bgm = AVURLAsset(url: url)
        guard let bgmTrack = try await bgm.loadTracks(withMediaType: .audio).first else {
            throw MixError.insertFailed("source asset has no audio track")
        }
        guard let audio = comp.addMutableTrack(withMediaType: .audio,
                                               preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MixError.insertFailed("could not add composition audio track")
        }

        let videoDur = comp.duration
        let bgmDur = try await bgm.load(.duration)
        guard CMTimeCompare(bgmDur, .zero) > 0 else {
            throw MixError.insertFailed("source BGM has zero duration")
        }

        var cursor = CMTime.zero
        while CMTimeCompare(cursor, videoDur) < 0 {
            let remaining = CMTimeSubtract(videoDur, cursor)
            let take = CMTimeMinimum(bgmDur, remaining)
            do {
                try audio.insertTimeRange(CMTimeRange(start: .zero, duration: take),
                                          of: bgmTrack,
                                          at: cursor)
            } catch {
                throw MixError.insertFailed("\(error)")
            }
            cursor = CMTimeAdd(cursor, take)
        }
    }

    // MARK: - Bundle lookup

    /// Look in BGM/ subdirectory first, then bundle root. `Bundle.module`
    /// is only synthesized when SwiftPM has real resources; this repo ships
    /// a documented placeholder until the binary BGM asset is supplied.
    private func locateBGM(named name: String) throws -> URL {
        let candidates: [Bundle] = [.main]
        for bundle in candidates {
            if let url = bundle.url(forResource: name, withExtension: "m4a", subdirectory: "BGM") {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: "m4a") {
                return url
            }
        }
        throw MixError.bgmNotFound(name: name)
    }
}
#endif
