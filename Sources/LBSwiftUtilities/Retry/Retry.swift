//
//  Retry.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 11/09/2025.
//

import Foundation

// MARK: - Core Retry

/// Retries an async operation according to the given policy.
/// - Parameters:
///   - policy: RetryPolicy controlling attempts/backoff/timeout/conditions
///   - onRetry: Called before each retry sleep with (attemptNumberStartingAt1, errorIfAny)
///   - operation: The async throwing work to perform
/// - Returns: The successful value
public func retry<T>(_ policy: RetryPolicy,
                     onRetry: ((Int, Error?) -> Void)? = nil,
                     operation: @escaping () async throws -> T) async throws -> T {
    
    let deadline: Date? = policy.timeout.map { Date().addingTimeInterval($0) }
    
    var lastError: Error?
    var previousDelay: Double = 0
    
    for attempt in 1...policy.maxAttempts {
        try Task.checkCancellation()
        if let d = deadline, Date() >= d {
            throw RetryError.timeout
        }
        
        do {
            let value = try await operation()
            return value
        } catch {
            lastError = error
            let shouldRetryError = policy.retryIfError?(error) ?? true
            
            if attempt == policy.maxAttempts || !shouldRetryError {
                throw error
            }
            
            onRetry?(attempt, error)
            
            let planned = policy.backoff.delaySeconds(forAttempt: attempt, previous: previousDelay)
            previousDelay = planned
            let remaining = deadline.map { max(0, $0.timeIntervalSinceNow) }
            let sleepFor = remaining.map { min($0, planned) } ?? planned
            if sleepFor > 0 {
                try await sleepsFor(seconds: sleepFor)
            }
        }
    }
    
    // Should not reach here, but just in case:
    throw RetryError.gaveUp(lastError: lastError)
}
