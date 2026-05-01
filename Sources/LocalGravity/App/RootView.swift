// Sources/LocalGravity/App/RootView.swift
//
// Pillars smoke-test screen. Each button is a placeholder until the matching
// task wires it to a real implementation:
//   1. Camera   -> P1-T4 (Insta360CameraBridge)
//   2. Location -> P1-T5 (LocationSvc)
//   3. Map      -> P1-T6 (MapPreviewView)
//   4. LLM      -> P1-T7 (LLMClient)
import SwiftUI

public struct RootView: View {
    @State private var lastResult: String = "tap a button to smoke-test a pillar"

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Local Gravity — pillars smoke test")
                .font(.headline)

            Button("1. Camera") { lastResult = "TODO P1-T4" }
            Button("2. Location") { lastResult = "TODO P1-T5" }
            Button("3. Map") { lastResult = "TODO P1-T6" }
            Button("4. LLM") { lastResult = "TODO P1-T7" }

            Divider()
            ScrollView {
                Text(lastResult)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}

#if DEBUG
#Preview { RootView() }
#endif
