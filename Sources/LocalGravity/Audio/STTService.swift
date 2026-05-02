// Sources/LocalGravity/Audio/STTService.swift
//
// P3-T2: Streaming Chinese speech-to-text wrapper.
//
// `AppleSTTService` uses iOS `Speech` + `AVAudioEngine`. It is conditionally
// compiled because the Speech framework is only available on Apple platforms;
// on other build hosts (Windows / Linux SPM hosts used during development),
// only the protocol and `MockSTTService` are available, which is enough to
// keep the rest of the package buildable and unit-testable.
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech)
import Speech
#endif

public protocol STTService: AnyObject {
    /// Begin continuous recognition. Each finalized utterance fires `onUtterance`.
    func start(onUtterance: @escaping (String) -> Void) throws
    func stop()
    func requestPermission(_ done: @escaping (Bool) -> Void)
}

#if os(iOS) && canImport(Speech) && canImport(AVFoundation)

/// On-device-preferred Apple Speech wrapper. Locale: zh-CN.
///
/// Notes:
/// - `requiresOnDeviceRecognition` is enabled when the recognizer reports support
///   so we don't ship every utterance to Apple's servers (privacy + offline use
///   while walking with spotty cellular).
/// - We only forward `result.isFinal` segments to keep the agent loop from
///   firing on partial flickers; the agent decides what to do with each
///   complete utterance.
public final class AppleSTTService: NSObject, STTService {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public override init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        super.init()
    }

    public func requestPermission(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { done(status == .authorized) }
        }
    }

    public func start(onUtterance: @escaping (String) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "STT", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "speech recognizer not available"])
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                     options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        self.request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            req.append(buf)
        }
        audioEngine.prepare()
        try audioEngine.start()

        var lastFinalText = ""
        task = recognizer.recognitionTask(with: req) { result, _ in
            guard let result else { return }
            if result.isFinal {
                let txt = result.bestTranscription.formattedString
                if !txt.isEmpty && txt != lastFinalText {
                    lastFinalText = txt
                    onUtterance(txt)
                }
            }
        }
    }

    public func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}

#endif

/// Test double: emits scripted utterances on demand. Used by every unit test
/// that touches the agent loop or the audio coordinator without booting the
/// real Speech framework.
public final class MockSTTService: STTService {
    public var pendingPermission: Bool = true
    private var onUtterance: ((String) -> Void)?

    public init() {}

    public func requestPermission(_ done: @escaping (Bool) -> Void) {
        done(pendingPermission)
    }

    public func start(onUtterance: @escaping (String) -> Void) throws {
        self.onUtterance = onUtterance
    }

    public func stop() {
        onUtterance = nil
    }

    /// Test-only: simulate the user saying something.
    public func emit(_ text: String) {
        onUtterance?(text)
    }
}
