// Sources/LocalGravity/Keepsake/ScriptGenerator.swift
//
// P4-T3 — One LLM call → structured KeepsakeScript.
//
// The generator does *not* throw a hard error on parse failure when used by
// KeepsakeBuilder — the builder catches and substitutes its own failsafe
// script. We still surface ScriptGeneratorError so that callers (or tests)
// who want to inspect why the LLM output was rejected can do so.
//
// JSON contract is mirrored 1:1 from plan §P4-T3 (system prompt + CodingKeys).

import Foundation

public struct KeepsakeScript: Codable, Equatable {
    public struct VideoClip: Codable, Equatable {
        public let startSec: Double
        public let durationSec: Double
        public let caption: String

        public init(startSec: Double, durationSec: Double, caption: String) {
            self.startSec = startSec
            self.durationSec = durationSec
            self.caption = caption
        }

        public init(start: Double, duration: Double, caption: String) {
            self.init(startSec: start, durationSec: duration, caption: caption)
        }

        public var start: Double { startSec }
        public var duration: Double { durationSec }

        enum CodingKeys: String, CodingKey {
            case startSec = "start_sec"
            case durationSec = "duration_sec"
            case caption
        }
    }

    public let title: String           // ≤ 14 字
    public let narration: String       // 1-2 句诗意总结
    public let posterPrompt: String    // diffusion prompt (English to keep model behaviour stable)
    public let videoClips: [VideoClip]
    public let bgmTag: String          // "calm" | "contemplative" | "upbeat"
    public let highlightMomentIds: [Int]

    public init(title: String,
                narration: String,
                posterPrompt: String,
                videoClips: [VideoClip],
                bgmTag: String,
                highlightMomentIds: [Int]) {
        self.title = title
        self.narration = narration
        self.posterPrompt = posterPrompt
        self.videoClips = videoClips
        self.bgmTag = bgmTag
        self.highlightMomentIds = highlightMomentIds
    }

    public typealias Clip = VideoClip

    public init(videoClips: [VideoClip], posterText: String?) {
        let text = posterText ?? "散步"
        self.init(title: text,
                  narration: text,
                  posterPrompt: text,
                  videoClips: videoClips,
                  bgmTag: "calm",
                  highlightMomentIds: [])
    }

    enum CodingKeys: String, CodingKey {
        case title, narration
        case posterPrompt = "poster_prompt"
        case videoClips = "video_clips"
        case bgmTag = "bgm_tag"
        case highlightMomentIds = "highlight_moment_ids"
    }
}

public enum ScriptGeneratorError: Error, Equatable {
    case noContent
    case parse(String)
}

/// Minimal protocol the generator needs from the chat client. Cross-phase note:
/// the concrete `LLMClient` written in P1 is expected to provide an equivalent
/// `chat(model:messages:temperature:)` async method. Keeping the dependency
/// expressed as a protocol means the generator is fully testable from this
/// worktree without depending on the not-yet-merged P1 implementation.
public protocol ScriptChatting {
    func scriptChat(model: String,
                    systemPrompt: String,
                    userMessage: String,
                    temperature: Double) async throws -> String
}

public final class ScriptGenerator {
    private let client: ScriptChatting
    private let model: String

    public init(client: ScriptChatting, model: String) {
        self.client = client
        self.model = model
    }

    public func generate(_ m: KeepsakeMaterials) async throws -> KeepsakeScript {
        let summary = Self.summarize(m)
        let raw = try await client.scriptChat(model: model,
                                              systemPrompt: Self.systemPrompt,
                                              userMessage: summary,
                                              temperature: 0.7)
        let json = Self.extractJSON(from: raw)
        guard let data = json.data(using: .utf8) else {
            throw ScriptGeneratorError.parse("not utf8")
        }
        do {
            return try JSONDecoder().decode(KeepsakeScript.self, from: data)
        } catch {
            throw ScriptGeneratorError.parse("\(error). raw=\(raw)")
        }
    }

    static let systemPrompt: String = """
    你是「散步纪念品」的剧本生成器。基于下面的散步素材，输出严格 JSON：
    {
      "title": "≤14 字的标题",
      "narration": "1-2 句诗意总结（≤60 字）",
      "poster_prompt": "english diffusion prompt for a square illustrated poster of this walk; reference time of day, mood, key landmarks",
      "video_clips": [
        {"start_sec": 12.5, "duration_sec": 4.0, "caption": "一句字幕"}
      ],
      "bgm_tag": "calm | contemplative | upbeat",
      "highlight_moment_ids": [0, 2]
    }

    要求：
    - video_clips 选 3–5 段，每段 3–6 秒，从用户散步视频中分散选取，避开开头 5 秒和结尾 5 秒
    - 字幕用中文
    - 不要解释，不要 markdown，只输出 JSON
    """

    static func summarize(_ m: KeepsakeMaterials) -> String {
        let f = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("散步起止：\(f.string(from: m.startedAt)) → \(f.string(from: m.endedAt))")
        lines.append("时长：\(Int(m.durationSeconds))秒；距离：\(Int(m.distanceMeters))米；轨迹点：\(m.track.count)")
        lines.append("视频文件：\(m.videoURL?.lastPathComponent ?? "无")")
        lines.append("\n=== 关键时刻（moments）===")
        for (i, mo) in m.moments.enumerated() {
            lines.append("[\(i)] \(mo.kind.rawValue) @ \(f.string(from: mo.timestamp)): \(mo.context)")
        }
        lines.append("\n=== 对话精华（最多 20 轮）===")
        for t in m.dialog.suffix(20) {
            lines.append("\(t.speaker.rawValue): \(t.text)")
        }
        return lines.joined(separator: "\n")
    }

    /// Tolerate accidental code fences / leading prose by extracting the first
    /// `{ ... }` block from `raw`.
    static func extractJSON(from raw: String) -> String {
        if let start = raw.firstIndex(of: "{"),
           let end = raw.lastIndex(of: "}"),
           start < end {
            return String(raw[start...end])
        }
        return raw
    }
}
