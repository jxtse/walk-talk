// Sources/LocalGravity/Walk/WalkSession.swift
//
// P3-T1: Walk session state machine.
//
// State diagram:
//   idle → walking → ending → generating → done | failed
//
// Transitions are async: `handle(_:)` is awaited so injected hooks
// (`onStart` / `onStop` / `onGenerateKeepsake`) can perform real I/O
// (camera connect, video download, agent wrap-up). Tests inject no-op
// hooks via `WalkSession.makeForTest()`.
//
// State changes are observed via Combine `@Published`, so SwiftUI
// (`WalkScreen`) and any other observer (e.g. analytics) can subscribe
// without polling.
import Foundation
#if canImport(Combine)
import Combine
#endif

public enum WalkSessionError: Error, Equatable {
    case invalidTransition(from: WalkState, event: String)
}

public final class WalkSession: ObservableObject, @unchecked Sendable {
    @Published public private(set) var state: WalkState = .idle
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var keepsakeURL: URL? = nil

    /// Hooks injected by `WalkController` (P3-T5). For unit tests they are no-ops.
    public var onStart: () async throws -> Void = {}
    public var onStop: () async throws -> Void = {}
    public var onGenerateKeepsake: () async throws -> URL = {
        URL(fileURLWithPath: "/tmp/stub.mp4")
    }

    public init() {}

    public func handle(_ event: WalkEvent) async throws {
        switch (state, event) {
        case (.idle, .start):
            state = .walking
            do {
                try await onStart()
            } catch {
                lastError = "\(error)"
                state = .failed
                throw error
            }

        case (.walking, .stop):
            state = .ending
            do {
                try await onStop()
            } catch {
                lastError = "\(error)"
                state = .failed
                throw error
            }
            state = .generating
            // Kick off keepsake generation; result delivered via
            // .keepsakeReady / .keepsakeFailed re-entrant events.
            Task { [weak self] in
                guard let self else { return }
                do {
                    let url = try await self.onGenerateKeepsake()
                    try? await self.handle(.keepsakeReady(url))
                } catch {
                    try? await self.handle(.keepsakeFailed("\(error)"))
                }
            }

        case (.generating, .keepsakeReady(let url)):
            keepsakeURL = url
            state = .done

        case (.generating, .keepsakeFailed(let msg)):
            lastError = msg
            state = .failed

        case (_, .fatal(let msg)):
            lastError = msg
            state = .failed

        default:
            throw WalkSessionError.invalidTransition(from: state, event: "\(event)")
        }
    }

    public static func makeForTest() -> WalkSession { WalkSession() }
}
