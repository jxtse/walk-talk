// Sources/LocalGravity/Net/LLMClient.swift
//
// Minimal OpenAI-compatible chat completion client. Plan reference: P1-T7.
// Default endpoint: http://100.99.139.20:18141 (per spec).
import Foundation

public struct ChatMessage: Codable, Equatable {
    public let role: String   // "system" | "user" | "assistant" | "tool"
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct ChatRequest: Codable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public init(model: String, messages: [ChatMessage], temperature: Double? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
    }
}

public struct ChatResponse: Codable {
    public struct Choice: Codable { public let message: ChatMessage }
    public let choices: [Choice]
}

public enum LLMClientError: Error, Equatable {
    case http(Int, String)
}

public final class LLMClient {
    let endpoint: URL
    let apiKey: String
    let session: URLSession

    public init(endpoint: URL = Secrets.shared.llmEndpoint,
                apiKey: String = Secrets.shared.llmApiKey,
                session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    public func chat(_ request: ChatRequest) async throws -> ChatResponse {
        var url = endpoint
        url.append(path: "/v1/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMClientError.http((response as? HTTPURLResponse)?.statusCode ?? -1, body)
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }
}
