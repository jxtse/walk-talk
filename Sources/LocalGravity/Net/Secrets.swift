// Sources/LocalGravity/Net/Secrets.swift
//
// Loads runtime secrets from (in order of precedence):
//   1. Environment variables (AMAP_KEY, LLM_ENDPOINT, LLM_API_KEY) — handy
//      for `swift test` and CI.
//   2. `Secrets.plist` in the app bundle — populated by the developer from
//      `Resources/Secrets.example.plist`.
//   3. Hard-coded fallbacks documented in the spec (Amap test key, the
//      private LLM endpoint at 100.99.139.20:18141).
import Foundation

public struct Secrets {
    public let amapApiKey: String
    public let llmEndpoint: URL
    public let llmApiKey: String

    public static let shared: Secrets = load()

    public init(amapApiKey: String, llmEndpoint: URL, llmApiKey: String) {
        self.amapApiKey = amapApiKey
        self.llmEndpoint = llmEndpoint
        self.llmApiKey = llmApiKey
    }

    /// Default Amap Web API key documented in the spec (test key only — do
    /// not use for high-quota production traffic).
    public static let defaultAmapKey = "ff287a156a20b1b95830b719d6c6a047"

    /// Default OpenAI-compatible endpoint documented in the spec.
    public static let defaultLLMEndpoint = URL(string: "http://100.99.139.20:18141")!

    private static func load() -> Secrets {
        let env = ProcessInfo.processInfo.environment
        let plist = loadPlist()

        let amap = env["AMAP_KEY"]
            ?? plist?["AMapApiKey"]
            ?? defaultAmapKey

        let endpoint: URL = (env["LLM_ENDPOINT"].flatMap(URL.init(string:)))
            ?? (plist?["LLMEndpoint"].flatMap(URL.init(string:)))
            ?? defaultLLMEndpoint

        let llmKey = env["LLM_API_KEY"]
            ?? plist?["LLMApiKey"]
            ?? ""

        return Secrets(amapApiKey: amap, llmEndpoint: endpoint, llmApiKey: llmKey)
    }

    private static func loadPlist() -> [String: String]? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = raw as? [String: String]
        else { return nil }
        return dict
    }
}
