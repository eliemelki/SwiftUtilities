//
//  Sleeps.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 18/09/2025.
//

@inline(__always)
public func sleepMs(_ ms: UInt64) async  {
    try? await Task.sleep(nanoseconds: ms * 1_000_000)
}

public func sleepFor(ms: UInt64) async throws {
    try? await Task.sleep(nanoseconds: ms * 1_000_000)
}

public func sleepsFor(seconds: Double) async throws {
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}


