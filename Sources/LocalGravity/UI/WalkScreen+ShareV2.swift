//
//  WalkScreen+ShareV2.swift
//  LocalGravity / UI
//
//  P5-T6 — Adds a `keepsakeShareLink(for:)` SwiftUI helper that the
//  WalkScreen can drop in place of its existing P4 share button. We
//  keep this as an extension file so we don't have to edit WalkScreen
//  directly from the P5 batch (the UI batch owns that file).
//
//  Usage in WalkScreen:
//      Self.keepsakeShareLink(for: result)
//
//  Behaviour:
//    - .video → "分享短视频"
//    - .poster → "分享海报"
//

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
extension WalkScreen {

    /// Returns a ShareLink whose label adapts to whether the keepsake
    /// came back as a short video (P5) or a static poster (P4).
    @ViewBuilder
    public static func keepsakeShareLink(for result: KeepsakeResult) -> some View {
        switch result.kind {
        case .video:
            ShareLink(item: result.url) {
                Label("分享短视频", systemImage: "square.and.arrow.up")
            }
        case .poster:
            ShareLink(item: result.url) {
                Label("分享海报", systemImage: "square.and.arrow.up")
            }
        }
    }
}
#endif
