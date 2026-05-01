// Sources/LocalGravity/Net/DiffusionClient.swift
//
// P4-T4 — One-shot poster image generation against the OpenAI-compatible
// LLM endpoint (http://100.99.139.20:18141/v1/images/generations).
//
// Design notes:
//  • Returns a UIImage (decoded from base64) AND optionally writes the bytes
//    into a tmp file. PosterComposer only needs the in-memory UIImage;
//    KeepsakeBuilder writes its own composed PNG to disk separately.
//  • Built without depending on a Secrets singleton — endpoint/apiKey are
//    plain init params so the test stub can pass `URLSession` with a
//    URLProtocol shim.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public enum DiffusionError: Error, Equatable {
    case http(Int)
    case decoding
    case requestEncoding
}

public final class DiffusionClient {
    public static let defaultEndpoint = URL(string: "http://100.99.139.20:18141")!

    private let endpoint: URL
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(endpoint: URL = DiffusionClient.defaultEndpoint,
                apiKey: String = "",
                model: String = "dall-e-3",
                session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    /// Generate one image. On success returns the in-memory UIImage; the
    /// caller decides whether to persist it.
    public func generate(prompt: String, size: String = "1024x1024") async throws -> UIImage {
        let url = endpoint.appendingPathComponent("v1/images/generations")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "size": size,
            "n": 1,
            "response_format": "b64_json"
        ]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw DiffusionError.requestEncoding
        }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DiffusionError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let arr = json["data"] as? [[String: Any]],
            let first = arr.first
        else { throw DiffusionError.decoding }

        // Two flavours of OpenAI-compatible responses: b64_json or url.
        if let b64 = first["b64_json"] as? String,
           let imgData = Data(base64Encoded: b64),
           let img = UIImage(data: imgData) {
            return img
        }
        if let urlString = first["url"] as? String, let imgURL = URL(string: urlString) {
            let (imgData, imgResp) = try await session.data(from: imgURL)
            guard let http2 = imgResp as? HTTPURLResponse, (200..<300).contains(http2.statusCode),
                  let img = UIImage(data: imgData) else {
                throw DiffusionError.decoding
            }
            return img
        }
        throw DiffusionError.decoding
    }

    /// Convenience: generate and write to a tmp PNG file. Returns the file URL.
    public func generateToTempFile(prompt: String, size: String = "1024x1024") async throws -> URL {
        let img = try await generate(prompt: prompt, size: size)
        guard let png = img.pngData() else { throw DiffusionError.decoding }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poster-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }
}
#endif
