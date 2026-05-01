//
//  ClipExtractor.swift
//  LocalGravity / Keepsake / Video
//
//  P5-T2 — Cuts a sub-range out of the Insta360 recording into its own
//  MP4 file via AVAssetExportSession.
//
//  Contract:
//    - Throws KeepsakeError.assemblyFailed("...") on any failure so the
//      orchestrator can fall back to the P4 poster path.
//    - Output is overwritten if it already exists (export sessions refuse
//      to clobber).
//

#if canImport(AVFoundation)
import AVFoundation

public struct ClipExtractor {
    public init() {}

    public func extract(from src: URL, range: CMTimeRange, output: URL) async throws {
        try? FileManager.default.removeItem(at: output)

        let asset = AVURLAsset(url: src)
        guard let exporter = AVAssetExportSession(asset: asset,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            throw KeepsakeError.assemblyFailed("clip extract: exporter init")
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.timeRange = range
        exporter.shouldOptimizeForNetworkUse = true

        await exporter.export()

        if exporter.status != .completed {
            throw KeepsakeError.assemblyFailed("clip extract: \(exporter.error?.localizedDescription ?? "status \(exporter.status.rawValue)")")
        }
    }
}
#endif
