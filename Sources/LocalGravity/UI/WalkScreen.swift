// Sources/LocalGravity/UI/WalkScreen.swift
//
// P3-T6: minimal SwiftUI walk screen.
//
// Two real states the user has to act on:
//   - `.idle`     → big "出门散步" button to start.
//   - `.walking`  → tiny status (mic / GPS / quota) + "结束散步" button.
// Everything else is informational (progress while generating, success /
// failure terminal screens). Per spec §3 this is intentionally minimal: the
// product is the walk, not the UI.
import SwiftUI

public struct WalkScreen: View {
    @ObservedObject var controller: WalkController

    public init(controller: WalkController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 24) {
            Text("本地引力")
                .font(.largeTitle)
                .bold()

            Text(stateLabel)
                .font(.headline)
                .foregroundStyle(.secondary)

            content
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch controller.session.state {
        case .idle:
            Button {
                Task { try? await controller.session.handle(.start) }
            } label: {
                Text("出门散步")
                    .font(.title2)
                    .frame(minWidth: 200, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)

        case .walking:
            walkingHUD
            Button {
                Task { try? await controller.session.handle(.stop) }
            } label: {
                Text("结束散步")
                    .frame(minWidth: 160, minHeight: 44)
            }
            .buttonStyle(.bordered)

        case .ending, .generating:
            ProgressView("正在生成纪念品…")
                .progressViewStyle(.circular)

        case .done:
            Text("纪念品已生成 ✅")
            if let url = controller.session.keepsakeURL {
                Text(url.lastPathComponent)
                    .font(.footnote)
                    .monospaced()
            }

        case .failed:
            Text("出错了：\(controller.session.lastError ?? "unknown")")
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    /// Tiny in-walk HUD: a mic dot, a GPS dot, and the proactive-quota count
    /// — just enough confirmation the underlying capture loop is alive.
    private var walkingHUD: some View {
        HStack(spacing: 16) {
            Label("麦", systemImage: "mic.fill")
                .foregroundStyle(.blue)
            Label(gpsLabel, systemImage: "location.fill")
                .foregroundStyle(controller.location.buffer.snapshot.last == nil ? .gray : .green)
            Label("\(controller.moments.moments.count) 个瞬间",
                  systemImage: "sparkle")
                .foregroundStyle(.purple)
        }
        .font(.footnote)
    }

    private var gpsLabel: String {
        controller.location.buffer.snapshot.last == nil ? "GPS …" : "GPS"
    }

    private var stateLabel: String {
        switch controller.session.state {
        case .idle: return "准备好就出发"
        case .walking: return "散步进行中…"
        case .ending: return "正在收尾…"
        case .generating: return "正在生成纪念品…"
        case .done: return "完成"
        case .failed: return "失败"
        }
    }
}
