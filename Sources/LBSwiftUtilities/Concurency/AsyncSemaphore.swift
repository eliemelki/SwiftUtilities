////
////  AsyncSemaphore.swift
////  LBSwiftUtilities
////
////  Created by Elie Melki on 11/09/2025.
////
import Foundation

/// A lightweight, actor-based, **cancellable** semaphore for Swift Concurrency.
///
/// `AsyncSemaphore` lets you bound parallel work with **FIFO fairness**:
/// - If a permit is available, `acquire()` returns immediately.
/// - Otherwise the caller is queued in submission order and **suspends** until a permit is released.
/// - If the **waiting task is cancelled**, it is dequeued and `acquire()` throws `CancellationError`.
///
/// Compared to `DispatchSemaphore`, this type:
/// - **Never blocks a thread** (suspends cooperatively instead).
/// - Integrates with **Task cancellation**.
/// - Is **fair** (FIFO) for waiters.
///
/// > Important:
/// > - Always pair `acquire()` with a **single** `release()` (prefer `defer`) to avoid leaking permits or double-releasing.
/// > - This semaphore is **not re-entrant**: acquiring twice in the same task without an intervening release can deadlock your logic.
/// > - Calls into an actor must be `await`ed from outside the actor (e.g. `await semaphore.release()`).
/// > - Avoid using this actor directly, and have a layer that control the acquire,release without manually add it. see @AsyncTaskQueue
actor AsyncSemaphore {
    /// Current number of available permits (can grow if `release()` is called more than acquired).
    private var permits: Int
    /// FIFO queue of waiter IDs.
    private var waitOrder: [UUID] = []
    /// The continuation for each queued waiter.
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    /// Creates a semaphore with the given number of initial permits.
    /// - Parameter value: Initial permits (negative values are clamped to `0`).
    init(value: Int) {
        self.permits = max(0, value)
    }

    /// Acquire a permit or suspend until one becomes available.
    ///
    /// - Behavior:
    ///   - If a permit is available, this returns immediately and **consumes** one permit.
    ///   - Otherwise, the current task is queued (FIFO) and **suspends** until another task calls `release()`.
    ///   - If the waiting task is **cancelled**, the wait is aborted and a `CancellationError` is thrown.
    ///
    /// - Throws: `CancellationError` if the task is cancelled while waiting.
    ///
    /// - Complexity: Amortized **O(1)**.
    func acquire() async throws {
        if permits > 0 {
            permits -= 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                // Enqueue a waiter with a unique ID so we can cancel precisely.
                waitOrder.append(id)
                waiters[id] = cont
            }
        } onCancel: {
            // If the task is cancelled while queued, clean up and resume with an error.
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Cancel and dequeue a waiter if it still exists.
    ///
    /// - Note: This is invoked by the cancellation handler in `acquire()`.
    private func cancelWaiter(id: UUID) {
        if let cont = waiters.removeValue(forKey: id) {
            waitOrder.removeAll { $0 == id }
            cont.resume(throwing: CancellationError())
        }
    }

    /// Release a permit to the next waiter, or increase `permits` if nobody is waiting.
    ///
    /// - Behavior:
    ///   - If there is a queued waiter, resume **the oldest** (FIFO) immediately.
    ///   - Otherwise, increment the available `permits`.
    ///
    /// - Complexity: **O(1)**.
    func release() {
        if let next = waitOrder.first, let cont = waiters.removeValue(forKey: next) {
            waitOrder.removeFirst()
            // For `Void`, be explicit:
            cont.resume(returning: ())
        } else {
            permits += 1
        }
    }
}
