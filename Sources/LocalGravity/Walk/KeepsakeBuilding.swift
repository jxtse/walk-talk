// Sources/LocalGravity/Walk/KeepsakeBuilding.swift
//
// Forward-declared keepsake-builder seam. P4 / P5 will provide the concrete
// implementation (video composer, poster fallback). Defining the protocol
// here keeps `WalkController` from importing the Keepsake module — which
// would otherwise need `WalkController` for `WalkSession` state, creating a
// circular dependency at SPM target boundaries.
import Foundation

public protocol KeepsakeBuilding: AnyObject {
    /// Build the final user-facing keepsake from raw walk artifacts.
    /// Returns a local file URL. Implementations are expected to always
    /// produce *something* (poster fallback at minimum, per spec §5.2).
    func build(rawVideoURL: URL?,
               momentLog: MomentLog,
               trackBuffer: TrackBuffer) async throws -> URL
}
