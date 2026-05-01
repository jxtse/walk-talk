// Sources/LocalGravity/Camera/MockCameraBridge.swift
//
// Fully-functional CameraBridge for unit tests and simulator runs.
// Emits a configurable stub UIImage at 1Hz when previewing; recording and
// download both write small canned files. Plan reference: P1-T3.
import Foundation
import UIKit

public final class MockCameraBridge: CameraBridge {
    public var isConnected: Bool = false
    public var connectShouldThrow: Bool = false
    public var recordingActive: Bool = false
    public var fakeVideoId: String = "mock-video-001"
    public var fakeVideoDuration: Double = 30.0

    private var frameTimer: Timer?
    private var onFrame: ((PreviewFrame) -> Void)?

    /// Optional preloaded image for the mock to emit. If nil, falls back to
    /// the bundled `mock_frame.jpg` fixture, then finally a 1x1 black pixel.
    public var stubFrameImage: UIImage?

    public init() {}

    public func connect() async throws {
        if connectShouldThrow { throw CameraBridgeError.underlying("mock connect failure") }
        isConnected = true
    }

    public func startPreviewStream(_ onFrame: @escaping (PreviewFrame) -> Void) throws {
        guard isConnected else { throw CameraBridgeError.notConnected }
        self.onFrame = onFrame
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let img = self.stubFrameImage ?? Self.blackPixel()
            self.onFrame?(PreviewFrame(image: img, capturedAt: Date()))
        }
    }

    public func stopPreviewStream() {
        frameTimer?.invalidate()
        frameTimer = nil
        onFrame = nil
    }

    public func startRecording() async throws {
        guard isConnected else { throw CameraBridgeError.notConnected }
        if recordingActive { throw CameraBridgeError.alreadyRecording }
        recordingActive = true
    }

    public func stopRecording() async throws -> CameraVideoHandle {
        guard recordingActive else { throw CameraBridgeError.notRecording }
        recordingActive = false
        return CameraVideoHandle(id: fakeVideoId, approxDurationSec: fakeVideoDuration)
    }

    public func downloadVideo(_ handle: CameraVideoHandle, to localURL: URL) async throws {
        // Write 8 zero bytes so callers can verify file existence and size.
        try Data(repeating: 0, count: 8).write(to: localURL)
    }

    /// Emit one frame synchronously. Useful for tests that don't want to spin
    /// the run-loop waiting for the timer.
    public func emitOneFrame(_ onFrame: (PreviewFrame) -> Void) {
        let img = stubFrameImage ?? Self.blackPixel()
        onFrame(PreviewFrame(image: img, capturedAt: Date()))
    }

    private static func blackPixel() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        UIColor.black.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
}
