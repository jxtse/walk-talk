// Sources/LocalGravity/Camera/CameraBridge.swift
//
// Abstracts the Insta360 camera so production code can be unit-tested with
// mocks. Plan reference: P1-T3.
import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public typealias PreviewImage = UIImage
#else
public struct PreviewImage: Equatable {
    public init() {}
}
#endif

public enum CameraBridgeError: Error, Equatable {
    case notConnected
    case alreadyRecording
    case notRecording
    case downloadFailed(String)
    case underlying(String)
}

/// Abstracts the Insta360 camera so production code can be unit-tested with mocks.
public protocol CameraBridge: AnyObject {
    /// True when the camera is paired and ready.
    var isConnected: Bool { get }

    /// Connect over WiFi. Throws on failure.
    func connect() async throws

    /// Subscribe to preview frames. The callback fires at ~1–2 fps with the latest sampled frame.
    /// Sampling rate and format are determined by the bridge implementation.
    func startPreviewStream(_ onFrame: @escaping (PreviewFrame) -> Void) throws

    /// Stop the preview stream.
    func stopPreviewStream()

    /// Begin on-camera recording. Throws if already recording.
    func startRecording() async throws

    /// Stop on-camera recording. Returns the resulting video file's identifier on the camera.
    @discardableResult
    func stopRecording() async throws -> CameraVideoHandle

    /// Download the recorded file from the camera to a local URL on the phone.
    func downloadVideo(_ handle: CameraVideoHandle, to localURL: URL) async throws
}

public struct PreviewFrame {
    public let image: PreviewImage
    public let capturedAt: Date

    public init(image: PreviewImage, capturedAt: Date) {
        self.image = image
        self.capturedAt = capturedAt
    }
}

public struct CameraVideoHandle: Equatable {
    public let id: String          // SDK-defined file id on the camera
    public let approxDurationSec: Double

    public init(id: String, approxDurationSec: Double) {
        self.id = id
        self.approxDurationSec = approxDurationSec
    }
}
