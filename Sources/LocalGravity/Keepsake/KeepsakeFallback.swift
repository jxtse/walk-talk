// Sources/LocalGravity/Keepsake/KeepsakeFallback.swift
//
// P4-T6 step 1 — types describing keepsake output and failure shapes.

import Foundation

public enum KeepsakeOutput: Equatable {
    case poster(URL)        // path to PNG (P4)
    case video(URL)         // path to MP4 (P5)
}

public enum KeepsakeFailure: Error, Equatable {
    case scriptFailed(String)
    case allFailed(String)
}
