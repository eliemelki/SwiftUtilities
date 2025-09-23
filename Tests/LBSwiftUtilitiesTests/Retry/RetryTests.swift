//
//  RetryTests.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 11/09/2025.
//


// RetryTests.swift
import XCTest
@testable import LBSwiftUtilities

final class RetryTests: XCTestCase {
    
    // MARK: - Helpers
    
    private struct DummyResult { let code: Int }
    
    private var zeroBackoff: Backoff { Backoff(kind: .fixed(seconds: 0)) }
    
    // MARK: - Basic success / no retry
    
    func testSuccessWithoutRetry() async throws {
        let policy = RetryPolicy(maxAttempts: 3, backoff: zeroBackoff)
        var attempts = 0
        
        let value: String = try await retry(policy) {
            attempts += 1
            return "ok"
        }
        
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(attempts, 1, "Should not retry on immediate success")
    }
    
    // MARK: - Retry on transient error then succeed
    
    func testRetriesThenSuccess() async throws {
        let policy = RetryPolicy(
            maxAttempts: 5,
            backoff: zeroBackoff,
            retryIfError: { error in
                if let e = error as? URLError { return e.isTransient }
                return false
            }
        )
        
        var attempts = 0
        var onRetryAttempts: [Int] = []
        var onRetryErrors: [Error?] = []
        
        let result: Int = try await retry(policy, onRetry: { attempt, error in
            onRetryAttempts.append(attempt)
            onRetryErrors.append(error)
        }) {
            attempts += 1
            if attempts < 3 { throw URLError(.timedOut) }
            return 42
        }
        
        XCTAssertEqual(result, 42)
        XCTAssertEqual(attempts, 3, "Two failures then success")
        XCTAssertEqual(onRetryAttempts, [1, 2])
        XCTAssertEqual(onRetryErrors.count, 2)
        XCTAssertTrue(onRetryErrors.allSatisfy { ($0 as? URLError) != nil })
    }
    
    // MARK: - Exhaust retries on error
    
    func testExhaustedRetriesPropagatesOriginalError() async {
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: zeroBackoff,
            retryIfError: { _ in true }
        )
        
        var attempts = 0
        do {
            _ = try await retry(policy) {
                attempts += 1
                throw URLError(.cannotConnectToHost)
            }
            XCTFail("Expected to throw")
        } catch {
            XCTAssertEqual(attempts, 3)
            XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost)
        }
    }
    
    // MARK: - Retry on unacceptable result, then give up
    
    // MARK: - Do not retry when retryIfError says false
    
    func testRetryIfErrorFalsePreventsRetry() async {
        let policy = RetryPolicy(
            maxAttempts: 5,
            backoff: zeroBackoff,
            retryIfError: { _ in false } // never retry on error
        )
        
        var attempts = 0
        do {
            _ = try await retry(policy) {
                attempts += 1
                throw URLError(.timedOut)
            }
            XCTFail("Expected immediate throw")
        } catch {
            XCTAssertEqual(attempts, 1, "Should not retry at all")
        }
    }
    
    // MARK: - Timeout
    
    func testTimeoutStopsBeforeNextAttempt() async {
        // small, real waits to exercise timeout path without slowing tests
        let policy = RetryPolicy(
            maxAttempts: 100,
            backoff: Backoff(kind: .fixed(seconds: 0.02)),
            timeout: 0.03,
            retryIfError: { _ in true }
        )
        
        let start = Date()
        do {
            _ = try await retry(policy)  {
                throw URLError(.timedOut)
            }
            XCTFail("Expected timeout")
        } catch let e as RetryError {
            switch e {
            case .timeout: break
            default: XCTFail("Expected .timeout, got \(e)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.25, "Shouldn't overshoot timeout by much")
    }
    
    // MARK: - Cancellation
    
    func testCancellationThrowsCancellationError() async {
        let policy = RetryPolicy(maxAttempts: 3, backoff: zeroBackoff)
        
        let task = Task { 
            try await retry(policy) {
                // Should never reach here; cancellation checked before first attempt.
                return 1
            }
        }
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Backoff math
    
    func testBackoffDelaySecondsMath() {
        let backoff = Backoff(kind: .exponential(initial: 0.2, multiplier: 2.0, max: 1.0, jitter: false))
        // attempts are 1-based: 0.2, 0.4, 0.8, 1.0 (capped), 1.0...
        XCTAssertEqual(backoff.delaySeconds(forAttempt: 1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(backoff.delaySeconds(forAttempt: 2), 0.4, accuracy: 1e-9)
        XCTAssertEqual(backoff.delaySeconds(forAttempt: 3), 0.8, accuracy: 1e-9)
        XCTAssertEqual(backoff.delaySeconds(forAttempt: 4), 1.0, accuracy: 1e-9)
        XCTAssertEqual(backoff.delaySeconds(forAttempt: 5), 1.0, accuracy: 1e-9)
    }
    
    func testBackoffJitterStaysWithinBounds() {
        let cap = 0.5
        let backoff = Backoff(kind: .exponential(initial: cap, multiplier: 2.0, max: cap, jitter: true))
        // Randomized; sample a few times to ensure range is respected
        for _ in 0..<10 {
            let d = backoff.delaySeconds(forAttempt: 3)
            XCTAssertGreaterThanOrEqual(d, 0.0)
            XCTAssertLessThanOrEqual(d, cap)
        }
    }
}

public extension URLError {
    var isTransient: Bool {
        switch self.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed,
             .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }
}

