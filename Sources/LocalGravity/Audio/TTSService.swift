// Sources/LocalGravity/Audio/TTSService.swift
//
// P3-T3: Composite text-to-speech with degradation policy.
//
// Per A5 decision: prefer remote TTS for warmth (the LLM endpoint exposes an
// OpenAI-compatible `/v1/audio/speech`); fall back to on-device
// `AVSpeechSynthesizer` whenever the remote round-trip exceeds 1.5s, the
// network is sad, or the remote returns a non-2xx. Failure is silent for
// the caller — they always get audio out.
//
// Design notes:
// - `Speaker` is the minimal protocol from the spec (§4 AI contract: tools
//   call `speak_to_user.speak`). It's declared here because the audio
//   subsystem owns what "speaking" means; P2's `SpeakToUserTool` consumes
//   any `Speaker` (typically a `TTSService`).
// - `CompositeTTSService` accepts any `Speaker` for remote and local, not
//   the concrete `RemoteTTS` / `LocalTTS` types. This deviates slightly
//   from the plan's literal snippet so the timeout/fallback policy can be
//   exercised by unit tests without booting `AVSpeechSynthesizer` or the
//   network.
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Minimal speaker protocol. P2's `SpeakToUserTool` depends on this.
public protocol Speaker: AnyObject {
    func speak(_ text: String) async throws
}

public protocol TTSService: Speaker {
    func cancel()
}

// MARK: - Composite (remote-preferred, local fallback)

/// Tries `remote` first with a hard timeout; on timeout/failure falls
/// through to `local`. Both must implement `Speaker`.
public final class CompositeTTSService: TTSService {
    private let remote: Speaker?
    private let local: Speaker
    private let remoteTimeout: TimeInterval

    public init(remote: Speaker?,
                local: Speaker,
                remoteTimeout: TimeInterval = 1.5) {
        self.remote = remote
        self.local = local
        self.remoteTimeout = remoteTimeout
    }

    public func speak(_ text: String) async throws {
        if let remote {
            do {
                try await Self.withTimeout(remoteTimeout) {
                    try await remote.speak(text)
                }
                return
            } catch {
                // Any remote error (including timeout) → degrade to local.
            }
        }
        try await local.speak(text)
    }

    public func cancel() {
        (local as? TTSService)?.cancel()
        (remote as? TTSService)?.cancel()
    }

    /// Race the body against a sleep; whichever finishes first wins.
    /// On timeout we throw `TTSTimeout`. Cancellation propagates to the body.
    static func withTimeout<T>(_ seconds: TimeInterval,
                               _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TTSTimeout()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

public struct TTSTimeout: Error, Equatable {
    public init() {}
}

// MARK: - LocalTTS (AVSpeechSynthesizer)

#if canImport(AVFoundation)

/// On-device Chinese TTS via `AVSpeechSynthesizer`. Always available, never
/// requires network — the safety-net of the composite.
public final class LocalTTS: NSObject, TTSService, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var done: CheckedContinuation<Void, Never>?

    public override init() {
        super.init()
        synth.delegate = self
    }

    public func speak(_ text: String) async throws {
        cancel()
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.done = cont
            synth.speak(u)
        }
    }

    public func cancel() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        done?.resume()
        done = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didFinish utterance: AVSpeechUtterance) {
        done?.resume()
        done = nil
    }
}

// MARK: - RemoteTTS (OpenAI-compatible /v1/audio/speech)

/// Streams MP3 from the LLM endpoint's `/v1/audio/speech` route and plays it
/// through `AudioPlayer`. Errors and non-2xx responses throw — `Composite`
/// catches them and degrades to `LocalTTS`.
public final class RemoteTTS: TTSService {
    private let endpoint: URL
    private let apiKey: String
    private let model: String
    private let voice: String
    private let session: URLSession
    private let player = AudioPlayer()

    public init(endpoint: URL,
                apiKey: String,
                model: String = "tts-1",
                voice: String = "alloy",
                session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
        self.session = session
    }

    public func speak(_ text: String) async throws {
        var url = endpoint
        url.append(path: "/v1/audio/speech")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "voice": voice,
            "input": text,
            "response_format": "mp3"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "RemoteTTS",
                          code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try await player.play(data: data)
    }

    public func cancel() {
        player.stop()
    }
}

/// Tiny `AVAudioPlayer` wrapper that resolves async when playback ends.
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var done: CheckedContinuation<Void, Error>?

    func play(data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                self.done = cont
                self.player = p
                p.play()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    func stop() {
        player?.stop()
        done?.resume()    // resolve so the caller doesn't hang
        done = nil
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        done?.resume()
        done = nil
    }
}

#endif
