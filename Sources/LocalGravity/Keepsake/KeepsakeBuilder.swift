// Sources/LocalGravity/Keepsake/KeepsakeBuilder.swift
//
// P4-T6 — Orchestrate the poster pipeline. Always returns a poster URL,
// even when the LLM fails AND diffusion fails AND there are no clips.
//
// The "always returns a URL" invariant (the failsafe rule) is sacred. The
// only path that throws is the catastrophic "we couldn't even encode a
// PNG to disk" branch — every upstream failure is caught and folded into
// the failsafe output.
//
// Parallel-write notes
// --------------------
//  • This file is the canonical P4 KeepsakeBuilder. P5 is expected to wrap
//    or extend it (e.g. via a `VideoAssembling` dep) without changing the
//    poster-only invariant.
//  • Implements `KeepsakeBuilding` (declared in `Sources/LocalGravity/Walk/
//    KeepsakeBuilding.swift`) so `WalkController` can hold the builder by
//    protocol and never import the Keepsake module directly. The
//    `KeepsakeBuilding.build(rawVideoURL:momentLog:trackBuffer:)` signature
//    forwards into `buildPoster` after collecting materials.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public final class KeepsakeBuilder: KeepsakeBuilding {

    private let scripter: ScriptGenerator?
    private let diffusion: DiffusionClient?
    private let composer: PosterComposer?
    private let p5Scripter: KeepsakeScripting?
    private let p5Diffusion: DiffusionGenerating?
    private let p5Poster: PosterComposing?
    private let p5Video: VideoAssembling?

    /// `walkStartedAt` lookup for the protocol entry point.
    /// In normal operation `WalkController` knows when the walk started;
    /// when called via the protocol we use `Date()` as a best-effort.
    public init(scripter: ScriptGenerator,
                diffusion: DiffusionClient = DiffusionClient(),
                composer: PosterComposer = PosterComposer()) {
        self.scripter = scripter
        self.diffusion = diffusion
        self.composer = composer
        self.p5Scripter = nil
        self.p5Diffusion = nil
        self.p5Poster = nil
        self.p5Video = nil
    }

    public init(scripter: KeepsakeScripting,
                diffusion: DiffusionGenerating,
                poster: PosterComposing,
                video: VideoAssembling?) {
        self.scripter = nil
        self.diffusion = nil
        self.composer = nil
        self.p5Scripter = scripter
        self.p5Diffusion = diffusion
        self.p5Poster = poster
        self.p5Video = video
    }

    // MARK: - Plan-canonical entry point

    /// Always returns a path. Will fall back to the failsafe poster
    /// (script-less, diffusion-less, map-less if needed) on any failure.
    public func buildPoster(materials: KeepsakeMaterials,
                            outputDir: URL) async throws -> URL {
        guard let scripter, let diffusion, let composer else {
            throw KeepsakeFailure.allFailed("poster builder dependencies unavailable")
        }

        // 1. Script — failsafe on any LLM error.
        let script: KeepsakeScript
        do {
            script = try await scripter.generate(materials)
        } catch {
            script = Self.failsafeScript(materials)
        }

        // 2. Parallel: AI poster + map snapshot (each independently safe).
        async let aiPosterTask: UIImage? = {
            do { return try await self.diffusion.generate(prompt: script.posterPrompt) }
            catch { return nil }
        }()
        async let mapTask: UIImage? = MapRenderer.renderStaticSnapshot(
            track: materials.track.map(\.coordinate),
            size: CGSize(width: 1024, height: 600)
        )
        let aiPoster = await aiPosterTask
        let map = await mapTask

        // 3. Compose (always succeeds — composer tolerates nil inputs).
        let img = composer.compose(script: script, materials: materials,
                                   aiPoster: aiPoster, mapImage: map)

        // 4. Persist to disk.
        try FileManager.default.createDirectory(at: outputDir,
                                                withIntermediateDirectories: true)
        let url = outputDir.appendingPathComponent("poster-\(UUID().uuidString).png")
        guard let data = img.pngData() else {
            throw KeepsakeFailure.allFailed("png encode failed")
        }
        try data.write(to: url)
        return url
    }

    public func build(materials: KeepsakeMaterials) async throws -> KeepsakeResult {
        guard let scripter = p5Scripter, let poster = p5Poster else {
            throw KeepsakeFailure.allFailed("P5 builder dependencies unavailable")
        }
        let script: KeepsakeScript
        do {
            script = try await scripter.generate(materials)
        } catch {
            script = Self.failsafeScript(materials)
        }
        _ = try? await p5Diffusion?.generate(prompt: script.posterPrompt)
        let posterURL = try await poster.compose(materials: materials, script: script)

        guard let video = p5Video,
              materials.videoFile != nil,
              !script.videoClips.isEmpty else {
            return KeepsakeResult(url: posterURL, kind: .poster)
        }

        do {
            let videoURL = try await video.assemble(materials: materials,
                                                    posterURL: posterURL,
                                                    script: script)
            return KeepsakeResult(url: videoURL, kind: .video)
        } catch {
            return KeepsakeResult(url: posterURL, kind: .poster)
        }
    }

    // MARK: - KeepsakeBuilding protocol bridge

    public func build(rawVideoURL: URL?,
                      momentLog: MomentLog,
                      trackBuffer: TrackBuffer) async throws -> URL {
        let now = Date()
        // We have no DialogLog here; the protocol predates P4-T1's wiring.
        // Callers that need dialog should call buildPoster directly.
        let mats = KeepsakeMaterials(
            track: trackBuffer.snapshot,
            moments: momentLog.snapshot(),
            dialog: [],
            videoURL: rawVideoURL,
            startedAt: now.addingTimeInterval(-1),
            endedAt: now
        )
        let outDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keepsakes", isDirectory: true)
        return try await buildPoster(materials: mats, outputDir: outDir)
    }

    // MARK: - Failsafe

    /// Hard-coded script used when the LLM round-trip fails. Conservative
    /// posterPrompt + neutral title so the poster still looks intentional.
    static func failsafeScript(_ m: KeepsakeMaterials) -> KeepsakeScript {
        KeepsakeScript(
            title: "一段散步",
            narration: "脚步会记得这条路。",
            posterPrompt: "abstract minimalist watercolor of a quiet walking path",
            videoClips: [],
            bgmTag: "calm",
            highlightMomentIds: Array(m.moments.indices.prefix(3))
        )
    }
}
#else
public final class KeepsakeBuilder: KeepsakeBuilding {
    private let scripter: KeepsakeScripting
    private let diffusion: DiffusionGenerating
    private let poster: PosterComposing
    private let video: VideoAssembling?

    public init(scripter: KeepsakeScripting,
                diffusion: DiffusionGenerating,
                poster: PosterComposing,
                video: VideoAssembling?) {
        self.scripter = scripter
        self.diffusion = diffusion
        self.poster = poster
        self.video = video
    }

    public func build(materials: KeepsakeMaterials) async throws -> KeepsakeResult {
        let script: KeepsakeScript
        do {
            script = try await scripter.generate(materials)
        } catch {
            script = Self.failsafeScript(materials)
        }
        _ = try? await diffusion.generate(prompt: script.posterPrompt)
        let posterURL = try await poster.compose(materials: materials, script: script)

        guard let video,
              materials.videoFile != nil,
              !script.videoClips.isEmpty else {
            return KeepsakeResult(url: posterURL, kind: .poster)
        }

        do {
            let videoURL = try await video.assemble(materials: materials,
                                                    posterURL: posterURL,
                                                    script: script)
            return KeepsakeResult(url: videoURL, kind: .video)
        } catch {
            return KeepsakeResult(url: posterURL, kind: .poster)
        }
    }

    public func build(rawVideoURL: URL?,
                      momentLog: MomentLog,
                      trackBuffer: TrackBuffer) async throws -> URL {
        let now = Date()
        let materials = KeepsakeMaterials(track: trackBuffer.snapshot,
                                          moments: momentLog.snapshot(),
                                          dialog: [],
                                          videoURL: rawVideoURL,
                                          startedAt: now.addingTimeInterval(-1),
                                          endedAt: now)
        return try await build(materials: materials).url
    }

    static func failsafeScript(_ m: KeepsakeMaterials) -> KeepsakeScript {
        KeepsakeScript(
            title: "一段散步",
            narration: "脚步会记得这条路。",
            posterPrompt: "abstract minimalist watercolor of a quiet walking path",
            videoClips: [],
            bgmTag: "calm",
            highlightMomentIds: Array(m.moments.indices.prefix(3))
        )
    }
}
#endif
