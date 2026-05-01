// Sources/LocalGravity/UI/WalkScreen+Share.swift
//
// P4-T7 — Add a ShareLink for the generated keepsake without editing
// `WalkScreen.swift`. Per the P4 worktree contract the main UI file
// is owned by P3; this extension layers the share affordance on top.
//
// Usage from P3 / future polish:
//   WalkScreen(controller: ctrl)
//       .keepsakeShareOverlay(controller: ctrl)
//
// The overlay is a no-op while the session is not in `.done`, so it can
// be applied unconditionally (typical SwiftUI composition).
//
// If/when WalkScreen is rewritten to inline the ShareLink, this file can
// be deleted.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public struct KeepsakeShareOverlay: ViewModifier {
    @ObservedObject var controller: WalkController

    public func body(content: Content) -> some View {
        VStack(spacing: 16) {
            content
            if controller.session.state == .done,
               let url = controller.session.keepsakeURL {
                if let img = Self.loadImage(at: url) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .cornerRadius(8)
                }
                ShareLink(item: url) {
                    Label("分享纪念品", systemImage: "square.and.arrow.up")
                        .frame(minWidth: 180, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private static func loadImage(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

public extension View {
    /// Append a poster preview + ShareLink underneath this view when the
    /// walk session reaches `.done`.
    func keepsakeShareOverlay(controller: WalkController) -> some View {
        modifier(KeepsakeShareOverlay(controller: controller))
    }
}
#endif
