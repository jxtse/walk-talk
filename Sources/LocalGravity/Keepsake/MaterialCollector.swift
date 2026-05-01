// Sources/LocalGravity/Keepsake/MaterialCollector.swift
//
// P4-T1 step 4 — gathers everything KeepsakeBuilder needs.
//
// Design note (Windows / parallel-write friendly):
// The plan signature `collect(from controller: WalkController, …)` reaches into
// `controller.location.buffer.snapshot`, `controller.moments.snapshot()`,
// `controller.dialog.snapshot()`. To avoid editing P3's WalkController from
// the P4 worktree, we expose the equivalent collector as a pure function that
// takes the four snapshots directly. P3's WalkController is expected to
// instantiate `KeepsakeMaterials` (or call this collector) inside its
// `session.onGenerateKeepsake` closure (see plan §P4-T6 step 3).

import Foundation

public final class MaterialCollector {
    public init() {}

    /// Pure collector — the caller (typically WalkController) supplies the
    /// already-snapshotted arrays so we don't need to know about controller
    /// internals.
    public func collect(track: [TrackPoint],
                        moments: [Moment],
                        dialog: [DialogTurn],
                        videoURL: URL?,
                        startedAt: Date,
                        endedAt: Date) -> KeepsakeMaterials {
        KeepsakeMaterials(
            track: track,
            moments: moments,
            dialog: dialog,
            videoURL: videoURL,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }
}
