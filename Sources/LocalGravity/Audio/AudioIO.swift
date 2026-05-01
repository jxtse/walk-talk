// Sources/LocalGravity/Audio/AudioIO.swift
//
// P3-T4: AudioIO — coordinator that wires STT and TTS together.
//
// Why this exists: with both STT (mic listening) and TTS (speaker playing)
// running on the same device, the AI's own voice is picked up by the
// recognizer and treated as a fresh user utterance — feedback loop. The
// trivial fix is to pause STT for the duration of every TTS playback. Doing
// it here keeps the rest of the system (agent, tools) ignorant of audio
// device contention.
import Foundation

public final class AudioIO {
    public let stt: STTService
    public let tts: TTSService
    private var sttRunning = false
    private var onUtterance: ((String) -> Void)?

    public init(stt: STTService, tts: TTSService) {
        self.stt = stt
        self.tts = tts
    }

    public func start(onUtterance: @escaping (String) -> Void) throws {
        self.onUtterance = onUtterance
        try stt.start { [weak self] text in
            self?.onUtterance?(text)
        }
        sttRunning = true
    }

    public func stop() {
        stt.stop()
        sttRunning = false
    }

    /// Speak via TTS. While speaking, STT is paused so the AI doesn't hear
    /// itself; STT is restarted afterward iff it was running before the
    /// call. Errors from `tts.speak` propagate, but STT is always restored.
    public func speak(_ text: String) async throws {
        let wasRunning = sttRunning
        if wasRunning {
            stt.stop()
            sttRunning = false
        }
        defer {
            if wasRunning {
                try? stt.start { [weak self] u in self?.onUtterance?(u) }
                sttRunning = true
            }
        }
        try await tts.speak(text)
    }
}
