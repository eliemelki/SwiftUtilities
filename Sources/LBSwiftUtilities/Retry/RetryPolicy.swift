//
//  RetryPolicy.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 11/09/2025.
//

import Foundation

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let backoff: Backoff
    /// Overall timeout across all attempts (seconds). If nil, no overall time limit.
    public let timeout: TimeInterval?
    /// Only retry if this returns true for the thrown error. If nil, retry on all errors.
    public let retryIfError: (@Sendable (Error) -> Bool)?

    public init(
        maxAttempts: Int,
        backoff: Backoff = Backoff(kind: .exponential(initial: 0.2, multiplier: 2, max: 5, jitter: true)),
        timeout: TimeInterval? = nil,
        retryIfError: (@Sendable (Error) -> Bool)? = nil
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoff = backoff
        self.timeout = timeout
        self.retryIfError = retryIfError
    }
}
