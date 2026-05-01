// Sources/LocalGravity/Keepsake/KeepsakeMaterials.swift
//
// P4-T1 — value type that bundles every input KeepsakeBuilder needs.
// Mirrors plan §P4-T1 step 1, mapped to SPM layout.
//
// Cross-phase note: TrackPoint comes from P1 (Sources/LocalGravity/Location/),
// Moment / MomentKind come from P2/P3 (Sources/LocalGravity/Session/MomentLog.swift).
// Both are parallel-written; this file only references their public surface.

import Foundation
import CoreLocation

public struct KeepsakeMaterials: Equatable {
    public let track: [TrackPoint]
    public let moments: [Moment]
    public let dialog: [DialogTurn]
    public let videoURL: URL?
    public let startedAt: Date
    public let endedAt: Date

    public init(track: [TrackPoint],
                moments: [Moment],
                dialog: [DialogTurn],
                videoURL: URL?,
                startedAt: Date,
                endedAt: Date) {
        self.track = track
        self.moments = moments
        self.dialog = dialog
        self.videoURL = videoURL
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var durationSeconds: Double { endedAt.timeIntervalSince(startedAt) }

    /// Sum of pairwise great-circle distances between successive track points.
    public var distanceMeters: Double {
        guard track.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<track.count {
            let a = CLLocation(latitude: track[i-1].coordinate.latitude,
                               longitude: track[i-1].coordinate.longitude)
            let b = CLLocation(latitude: track[i].coordinate.latitude,
                               longitude: track[i].coordinate.longitude)
            total += b.distance(from: a)
        }
        return total
    }
}

/// A single user↔assistant turn captured during a walk.
public struct DialogTurn: Equatable, Codable {
    public enum Speaker: String, Codable { case user, assistant }
    public let speaker: Speaker
    public let text: String
    public let timestamp: Date

    public init(speaker: Speaker, text: String, timestamp: Date) {
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}
