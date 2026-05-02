// Sources/LocalGravity/Keepsake/KeepsakeContracts.swift
//
// Shared P4/P5 keepsake contracts. P4's canonical builder still exposes the
// poster URL bridge used by WalkController; P5 adds a richer result so callers
// can distinguish poster fallback from assembled video.

import Foundation

public enum KeepsakeKind: Equatable {
    case poster
    case video
}

public struct KeepsakeResult: Equatable {
    public let url: URL
    public let kind: KeepsakeKind

    public init(url: URL, kind: KeepsakeKind) {
        self.url = url
        self.kind = kind
    }
}

public enum KeepsakeError: Error, Equatable {
    case assemblyFailed(String)
}

public protocol KeepsakeScripting {
    func generate(_ materials: KeepsakeMaterials) async throws -> KeepsakeScript
}

public protocol DiffusionGenerating {
    func generate(prompt: String) async throws -> URL
}

public protocol PosterComposing {
    func compose(materials: KeepsakeMaterials,
                 script: KeepsakeScript) async throws -> URL
}

public protocol VideoAssembling {
    func assemble(materials: KeepsakeMaterials,
                  posterURL: URL,
                  script: KeepsakeScript) async throws -> URL
}

extension ScriptGenerator: KeepsakeScripting {}

public typealias GPSPoint = TrackPoint
