// Sources/LocalGravity/Session/DialogLog.swift
//
// P4-T1 step 2 — thread-safe append-only buffer for DialogTurn values.
// Created here as its own file (not modifying MomentLog.swift) so P3's
// MomentLog implementation stays untouched.

import Foundation

public final class DialogLog {
    private(set) public var turns: [DialogTurn] = []
    private let lock = NSLock()

    public init() {}

    public func append(_ t: DialogTurn) {
        lock.lock(); defer { lock.unlock() }
        turns.append(t)
    }

    public func snapshot() -> [DialogTurn] {
        lock.lock(); defer { lock.unlock() }
        return turns
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        turns.removeAll()
    }
}
