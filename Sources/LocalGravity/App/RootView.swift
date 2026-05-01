// Sources/LocalGravity/App/RootView.swift
//
// Pillars smoke-test screen. Each button is a placeholder until the matching
// task wires it to a real implementation:
//   1. Camera   -> P1-T4 (Insta360CameraBridge)
//   2. Location -> P1-T5 (LocationSvc)
//   3. Map      -> P1-T6 (MapPreviewView)
//   4. LLM      -> P1-T7 (LLMClient)
import SwiftUI
import Combine
import CoreLocation

public struct RootView: View {
    @State private var lastResult: String = "tap a button to smoke-test a pillar"
    @State private var showMap = false
    @StateObject private var locationModel = LocationModel()
    private let camera = Insta360CameraBridge()

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Local Gravity — pillars smoke test")
                .font(.headline)

            Button("1. Camera connect") {
                Task {
                    do {
                        try await camera.connect()
                        lastResult = "camera connected"
                    } catch {
                        lastResult = "camera failed: \(error)"
                    }
                }
            }
            Button("2. Location start") {
                locationModel.start { msg in lastResult = msg }
            }
            Button("3. Map preview") { showMap = true }
                .sheet(isPresented: $showMap) {
                    MapPreviewView(track: [
                        .init(latitude: 32.072, longitude: 118.794),
                        .init(latitude: 32.074, longitude: 118.796),
                        .init(latitude: 32.076, longitude: 118.797)
                    ])
                }
            Button("4. LLM ping") {
                Task {
                    do {
                        let resp = try await LLMClient().chat(ChatRequest(
                            // Replace with model id chosen in decisions/A4-vlm-model-selection.md
                            model: "REPLACE_WITH_MODEL_FROM_A4",
                            messages: [ChatMessage(role: "user", content: "用一个字回应：到")]
                        ))
                        lastResult = "LLM: \(resp.choices.first?.message.content ?? "<empty>")"
                    } catch {
                        lastResult = "LLM failed: \(error)"
                    }
                }
            }

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

@MainActor
public final class LocationModel: ObservableObject {
    let svc = LocationSvc()

    public init() {}

    public func start(_ onUpdate: @escaping (String) -> Void) {
        svc.requestPermission()
        svc.start()
        Task {
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let n = svc.buffer.count
                let last = svc.buffer.snapshot.last
                await MainActor.run {
                    if let p = last {
                        onUpdate("\(n) points; last: \(p.coordinate.latitude), \(p.coordinate.longitude)")
                    } else {
                        onUpdate("\(n) points; waiting…")
                    }
                }
            }
        }
    }
}
