// Sources/LocalGravity/Walk/WalkController.swift
//
// P3-T5: WalkController — application-level coordinator that owns every
// runtime collaborator (camera, location, audio, agent, frame window,
// moment log) and wires them onto `WalkSession` lifecycle hooks.
//
// `WalkSession` stays focused on state transitions; `WalkController` owns
// the side effects (start camera, start location, start audio, schedule
// proactive ticks; on stop: drain everything, download the recording, kick
// off keepsake generation).
//
// Cross-phase note: this file references P1 (`CameraBridge`, `LocationSvc`,
// `LLMClient`, `AmapClient`, `MomentLog`, `FrameWindow`) and P2
// (`AgentRuntime`, `ToolRegistry`, `ProactiveQuota`, the eight tools,
// `VLMAnalyzer`) types per the plan's contracted signatures. They are
// implemented in their own batches; this file compiles together with them
// as a single SPM target.
import Foundation
#if canImport(Combine)
import Combine
#endif

@MainActor
public final class WalkController: ObservableObject {
    public let session = WalkSession()

    public let camera: CameraBridge
    public let location: LocationSvc
    public let frameWindow = FrameWindow()
    public let moments = MomentLog()
    public let audio: AudioIO
    public let agent: AgentRuntime

    /// Optional keepsake builder, injected by P4/P5. When nil, the session
    /// resolves to the raw video URL so P3 walks still produce a usable
    /// "done" state without depending on later batches.
    public var keepsakeBuilder: KeepsakeBuilding?

    private var locationTickTimer: Timer?
    private var cameraVideoHandle: CameraVideoHandle?
    private var downloadedVideoURL: URL?

    public init(camera: CameraBridge,
                audio: AudioIO,
                llm: LLMClient,
                model: String,
                location: LocationSvc = LocationSvc(),
                amap: AmapClient = AmapClient(),
                vlm: VLMAnalyzer,
                keepsakeBuilder: KeepsakeBuilding? = nil) {
        self.camera = camera
        self.audio = audio
        self.location = location
        self.keepsakeBuilder = keepsakeBuilder

        let quota = ProactiveQuota(limit: 3, window: 600)
        let registry = ToolRegistry([
            SpeakToUserTool(speaker: audio.tts, quota: quota),
            RecordMomentTool(log: moments, trackBuffer: location.buffer),
            GetCameraFrameTool(window: frameWindow),
            AnalyzeFrameVLMTool(vlm: vlm),
            AmapAroundSearchTool(amap: amap),
            AmapTextSearchTool(amap: amap),
            AmapDirectionTool(amap: amap),
            AmapGeoTool(amap: amap),
        ])
        self.agent = AgentRuntime(llm: llm, model: model, tools: registry)

        // Wire session lifecycle hooks. We capture `self` weakly to avoid
        // a retain cycle through the published session.
        session.onStart = { [weak self] in try await self?.startEverything() }
        session.onStop = { [weak self] in try await self?.stopEverything() }
        session.onGenerateKeepsake = { [weak self] in
            guard let self else {
                return URL(fileURLWithPath: "/tmp/no_video.mp4")
            }
            if let builder = self.keepsakeBuilder {
                return try await builder.build(
                    rawVideoURL: self.downloadedVideoURL,
                    momentLog: self.moments,
                    trackBuffer: self.location.buffer
                )
            }
            // P3 fallback: surface the raw video so the walk loop still
            // reaches `.done`. P4 replaces this with a real keepsake.
            return self.downloadedVideoURL ?? URL(fileURLWithPath: "/tmp/no_video.mp4")
        }
    }

    // MARK: - Lifecycle

    private func startEverything() async throws {
        try await camera.connect()
        try camera.startPreviewStream { [weak self] frame in
            self?.frameWindow.append(frame)
        }
        try await camera.startRecording()

        location.requestPermission()
        location.start()

        try audio.start { [weak self] utterance in
            self?.handleUtterance(utterance)
        }

        // Periodic proactive trigger: every 30s the agent gets a tick and
        // decides (subject to ProactiveQuota) whether to recommend a POI.
        locationTickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.fireLocationTick() }
        }
    }

    private func stopEverything() async throws {
        locationTickTimer?.invalidate()
        locationTickTimer = nil
        audio.stop()
        location.stop()
        camera.stopPreviewStream()
        let handle = try await camera.stopRecording()
        cameraVideoHandle = handle
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("walk-\(UUID().uuidString).mp4")
        try await camera.downloadVideo(handle, to: dest)
        downloadedVideoURL = dest
    }

    // MARK: - Agent dispatch

    private func handleUtterance(_ text: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let hints = self.currentHints()
                _ = try await self.agent.handle(.userSpoke(text), contextHints: hints)
            } catch {
                print("agent error on utterance: \(error)")
            }
        }
    }

    private func fireLocationTick() async {
        do {
            let hints = currentHints()
            _ = try await agent.handle(.locationTick, contextHints: hints)
        } catch {
            print("agent error on tick: \(error)")
        }
    }

    private func currentHints() -> [String: String] {
        var h: [String: String] = [:]
        if let last = location.buffer.snapshot.last {
            h["lat"] = String(format: "%.6f", last.coordinate.latitude)
            h["lng"] = String(format: "%.6f", last.coordinate.longitude)
            h["ts"] = ISO8601DateFormatter().string(from: last.timestamp)
        }
        h["frames_in_window"] = String(frameWindow.count)
        return h
    }
}
