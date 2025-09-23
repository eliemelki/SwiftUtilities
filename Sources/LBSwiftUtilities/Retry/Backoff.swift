//
//  Backoff.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 11/09/2025.
//

import Foundation

public struct Backoff: Sendable {
    public enum Kind: Sendable {
        case fixed(seconds: Double)
        case exponential(initial: Double, multiplier: Double = 2.0, max: Double? = nil, jitter: Bool = false)
    }
    public let kind: Kind

    public init(kind: Kind) { self.kind = kind }

    public func delaySeconds(forAttempt attempt: Int, previous: Double = 0) -> Double {
        switch kind {
        case .fixed(let s):
            return max(0, s)

        case .exponential(let initial, let mult, let maxCap, let jitter):
            let base = max(0, initial) * pow(max(1, mult), Double(max(0, attempt - 1)))
            let capped = min(base, maxCap ?? base)
            if jitter {
                // "full jitter": random in [0, capped]
                return Double.random(in: 0...capped)
            } else {
                return capped
            }
        }
    }
}
