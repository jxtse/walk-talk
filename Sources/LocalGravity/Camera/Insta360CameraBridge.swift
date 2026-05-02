// Sources/LocalGravity/Camera/Insta360CameraBridge.swift
//
// Real-device CameraBridge backed by the Insta360 iOS SDK. The SDK binary is
// not vendored in this repo (development host has no Mac toolchain); each
// LOOKUP-N marker below is a precise question to answer from the SDK headers
// and sample code on a Mac. **Do not invent method names.** If a LOOKUP
// cannot be resolved, escalate. See docs/superpowers/decisions/A2-insta360-ios-sdk.md.
import Foundation

// LOOKUP-1: import the actual Insta360 SDK module name. Examples possibly seen:
//   import INSCameraSDK
//   import InstaCameraSDK
// Confirm from the framework's umbrella header.
//
// import INSCameraSDK

public final class Insta360CameraBridge: CameraBridge {
    public private(set) var isConnected: Bool = false

    // LOOKUP-2: the SDK likely vends a singleton or manager
    // (e.g. `INSCameraManager.shared()`). Hold a reference to it here as a
    // stored property.
    // private let sdk = INSCameraManager.shared()

    private var onFrame: ((PreviewFrame) -> Void)?
    private var currentRecordingId: String?

    public init() {}

    public func connect() async throws {
        // LOOKUP-3: connect API. Typically:
        //   - check WiFi SSID matches camera's broadcast (CHECK_WIFI)
        //   - call sdk.setupConnection(...) or similar
        //   - wait for delegate callback `onConnected` / `connectionDidEstablish`
        // Wrap the delegate-style callback into async via withCheckedThrowingContinuation.
        //
        // try await withCheckedThrowingContinuation { cont in
        //     sdk.setupConnection(success: { cont.resume() },
        //                        failure: { err in cont.resume(throwing: CameraBridgeError.underlying(err.localizedDescription)) })
        // }
        // self.isConnected = true
        throw CameraBridgeError.underlying("Insta360CameraBridge.connect not yet implemented — see LOOKUP-3")
    }

    public func startPreviewStream(_ onFrame: @escaping (PreviewFrame) -> Void) throws {
        guard isConnected else { throw CameraBridgeError.notConnected }
        self.onFrame = onFrame
        // LOOKUP-4: preview stream API. Typically:
        //   - start a streaming session (sdk.startPreviewStream(params))
        //   - register a delegate that receives raw frames or a player view
        //   - we want raw frames so we can feed them to VLM. If the SDK only
        //     exposes a player view, fall back to grabbing snapshots from
        //     that view periodically (per A1 mitigation).
        //
        // Per A1 spike outcome (see docs/superpowers/decisions/A1-camera-concurrency.md):
        //   - if confirmed, use full preview stream
        //   - if mitigation, use periodic snapshot polling (≤ 2 fps)
        //   - if architecture change, ... (decision file specifies the swap)
    }

    public func stopPreviewStream() {
        // LOOKUP-5: stop preview API
        onFrame = nil
    }

    public func startRecording() async throws {
        guard isConnected else { throw CameraBridgeError.notConnected }
        // LOOKUP-6: start recording API. Likely sdk.startRecording(options:completion:)
        //   - capture the resulting file id / handle into currentRecordingId
        throw CameraBridgeError.underlying("Insta360CameraBridge.startRecording not yet implemented — see LOOKUP-6")
    }

    @discardableResult
    public func stopRecording() async throws -> CameraVideoHandle {
        // LOOKUP-7: stop recording API; SDK should return file metadata in the completion.
        guard let id = currentRecordingId else { throw CameraBridgeError.notRecording }
        defer { currentRecordingId = nil }
        // return CameraVideoHandle(id: id, approxDurationSec: <from SDK>)
        _ = id
        throw CameraBridgeError.underlying("Insta360CameraBridge.stopRecording not yet implemented — see LOOKUP-7")
    }

    public func downloadVideo(_ handle: CameraVideoHandle, to localURL: URL) async throws {
        // LOOKUP-8: download API. Usually sdk.downloadFile(fileId:to:progress:completion:)
        //   - return only after the file is fully on-phone
        //   - wrap progress into async via continuation
        _ = (handle, localURL)
        throw CameraBridgeError.underlying("Insta360CameraBridge.downloadVideo not yet implemented — see LOOKUP-8")
    }
}
