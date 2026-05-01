//
//  KeepsakeBuilder.swift
//  LocalGravity / Keepsake
//
//  P4 + P5 — Single orchestration point for producing a keepsake from
//  the materials a finished walk emits. P4 introduced this type with a
//  poster-only path; P5 layers a video-first path on top with a HARD
//  fallback to the P4 poster on any video-assembly failure.
//
//  ---------------------------------------------------------------------
//  HARD FALLBACK INVARIANT (P4 → P5 carried forward)
//  ---------------------------------------------------------------------
//  `build(materials:)` MUST return a non-nil KeepsakeResult except in
//  catastrophic disk-write scenarios. Specifically:
//
//    • Scripter throws  → use `failsafeScript(materials)`.
//    • Poster render throws → re-throw (P4 close-out invariant: at the
//      very least we always produce a poster; if even that fails, the
//      walk has no keepsake and the caller surfaces an error).
//    • Video assembler throws → log + return the poster.
//    • Video assembler missing or script has no clips or no recorded
//      video file → silently skip video, return the poster.
//
//  Tests P5-T6 verify the last two paths; P4-T6 verifies the first two.
//
//  ---------------------------------------------------------------------
//  Re-application note for P4 maintainers
//  ---------------------------------------------------------------------
//  If a P4-only revision of this file is later re-applied, the changes
//  introduced by P5 are:
//    1. Added `VideoAssembling` dependency (optional — `nil` = poster-only).
//    2. Added the `if let video = video, ...` block in `build(materials:)`.
//    3. Returns `KeepsakeResult(url:kind:)` instead of bare URL.
//

import Foundation

public final class KeepsakeBuilder {

    // MARK: - Dependencies

    public let scripter: KeepsakeScripting
    public let diffusion: DiffusionGenerating
    public let poster: PosterComposing
    public let video: VideoAssembling?    // P5: nil keeps P4 poster-only behavior.

    public init(scripter: KeepsakeScripting,
                diffusion: DiffusionGenerating,
                poster: PosterComposing,
                video: VideoAssembling? = nil) {
        self.scripter = scripter
        self.diffusion = diffusion
        self.poster = poster
        self.video = video
    }

    // MARK: - Entry point

    /// Produce a keepsake from the walk's `materials`.
    /// - Returns: a poster (P4) or a video (P5) URL with `kind` describing which.
    /// - Throws: only if the poster path itself fails (P4 close-out invariant).
    public func build(materials: KeepsakeMaterials) async throws -> KeepsakeResult {
        // 1. Script — failsafe on any LLM error.
        let script: KeepsakeScript
        do {
            script = try await scripter.generate(materials)
        } catch {
            LGLog.warn("scripter failed (\(error)); using failsafe script")
            script = failsafeScript(materials)
        }

        // 2. Poster — must succeed for the keepsake to exist at all.
        let posterURL = try await renderPoster(materials: materials, script: script)

        // 3. Video — best effort on top.
        if let video = video,
           !script.videoClips.isEmpty,
           materials.videoFile != nil {
            do {
                let url = try await video.assemble(materials: materials,
                                                   posterURL: posterURL,
                                                   script: script)
                return KeepsakeResult(url: url, kind: .video)
            } catch {
                LGLog.warn("video assembly failed (\(error)); falling back to poster")
            }
        }
        return KeepsakeResult(url: posterURL, kind: .poster)
    }

    // MARK: - P4 helpers

    /// Render the P4 poster for `materials` + `script`.
    /// Implementation lives in `PosterComposer`; this is the seam P5 hangs the
    /// fallback off of.
    public func renderPoster(materials: KeepsakeMaterials,
                             script: KeepsakeScript) async throws -> URL {
        return try await poster.compose(materials: materials, script: script)
    }

    /// Deterministic, no-LLM script used when the LLM endpoint is down.
    /// Conservative: no video clips (so the V2 path skips itself) and a
    /// single neutral poster line so we never ship blank output.
    public func failsafeScript(_ materials: KeepsakeMaterials) -> KeepsakeScript {
        return KeepsakeScript(
            videoClips: [],
            posterText: "一段散步的记录"
        )
    }
}
