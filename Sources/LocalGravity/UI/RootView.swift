// Sources/LocalGravity/UI/RootView.swift
//
// P3-T6: replaces the P1 demo router with the production walk loop.
//
// `RootView` is the single SwiftUI entry point. It owns the
// `WalkController` (and therefore every runtime collaborator) so that
// switching screens (idle → walking → done) does not tear down the
// underlying session.
//
// All concrete bindings live here so the rest of the codebase stays
// dependency-injectable: swap `Insta360CameraBridge` for `MockCameraBridge`
// in the simulator, or `RemoteTTS` for `nil` to force on-device TTS in a
// debug build.
import SwiftUI

public struct RootView: View {
    @StateObject private var controller: WalkController = RootView.makeController()

    public init() {}

    public var body: some View {
        WalkScreen(controller: controller)
    }

    @MainActor
    private static func makeController() -> WalkController {
        let camera: CameraBridge = Insta360CameraBridge()      // swap to MockCameraBridge in simulator
        let stt: STTService
        #if os(iOS) && canImport(Speech) && canImport(AVFoundation)
        stt = AppleSTTService()
        #else
        stt = MockSTTService()
        #endif

        let local: TTSService
        let remote: Speaker?
        #if canImport(AVFoundation)
        local = LocalTTS()
        remote = RemoteTTS(endpoint: Secrets.shared.llmEndpoint,
                           apiKey: Secrets.shared.llmApiKey)
        #else
        local = MockTTSService()
        remote = nil
        #endif

        let tts = CompositeTTSService(remote: remote, local: local, remoteTimeout: 1.5)
        let audio = AudioIO(stt: stt, tts: tts)

        return WalkController(
            camera: camera,
            audio: audio,
            llm: LLMClient(),
            model: "gpt-4o",
            vlm: LLMVLMAnalyzer()
        )
    }
}

/// Vision-capable wrapper over the same OpenAI-compatible endpoint. Used by
/// `AnalyzeFrameVLMTool`. The exact content shape varies by provider; this
/// uses the markdown-style data URL form that works on the LLM endpoint
/// chosen by A4. Swap to the structured `[{type:image_url}, …]` form for
/// strict providers.
final class LLMVLMAnalyzer: VLMAnalyzer {
    private let llm = LLMClient()

    func analyze(imageB64: String, question: String) async throws -> String {
        let req = ChatRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: "system",
                            content: "你是户外散步场景识别助手。一句话回答用户问题。"),
                ChatMessage(role: "user",
                            content: "data:image/jpeg;base64,\(imageB64)\n\n问题：\(question)")
            ]
        )
        let r = try await llm.chat(req)
        return r.choices.first?.message.content ?? "（没看清）"
    }
}

#if !canImport(AVFoundation)
/// Stand-in TTS used when building on hosts without AVFoundation (Linux /
/// Windows SPM). Production iOS builds always have AVFoundation, so the
/// real `LocalTTS` is used there.
final class MockTTSService: TTSService {
    func speak(_ text: String) async throws { /* no-op */ }
    func cancel() {}
}
#endif
