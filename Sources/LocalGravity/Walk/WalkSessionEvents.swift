// Sources/LocalGravity/Walk/WalkSessionEvents.swift
//
// P3-T1: Walk session state machine — public state and event types.
// Mirrors `WalkTalk/Session/WalkSessionEvents.swift` from the plan; the SPM
// layout under Sources/LocalGravity/Walk/ is what the engineering CLAUDE
// instructions remap "Session/" to.
import Foundation

public enum WalkState: String, Equatable, Sendable {
    case idle
    case walking
    case ending
    case generating
    case done
    case failed
}

public enum WalkEvent: Sendable {
    case start
    case stop
    case keepsakeReady(URL)
    case keepsakeFailed(String)
    case fatal(String)
}
