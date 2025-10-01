//
//  AsyncSemaphore 2.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 17/09/2025.
//
import Foundation

/// A lightweight async task queue with **serial** or **bounded concurrent** execution.
///
/// - Uses an `AsyncSemaphore` internally to cap the number of tasks that may run in parallel.
/// - Each `submit` spawns a child `Task`. The queue:
///   - acquires a permit before running your `operation`
///   - releases the permit when the task finishes **(even if it throws or is cancelled)**
///   - removes the task from the internal bag for precise `cancel(id:)` and `cancelAll()`
///
/// ### Cancellation semantics
/// - **cancel(id:)**: Cancels the specific task whether it is **waiting** for a permit or **already running**.
///   - If waiting, its `acquire()` will throw `CancellationError`, and it won’t execute your `operation`.
///   - If running, the underlying `Task` is cancelled; your operation should cooperatively check for
///     cancellation (e.g. `try Task.checkCancellation()`, `Task.sleep`, `URLSession`, etc.).
/// - **cancelAll()**: Cancels all queued/running tasks currently tracked by the queue.
///
/// ### Concurrency modes
/// - `.serial` is equivalent to `.concurrent(1)`.
/// - `.concurrent(n)` runs up to `max(1, n)` tasks in parallel (values ≤ 0 are clamped to 1).
public final class AsyncTaskQueue: Sendable {
    /// Queue execution mode.
    public enum Mode {
        /// Run one task at a time (FIFO).
        case serial
        /// Run up to `n` tasks in parallel.
        case concurrent(Int)
    }
    
    private let semaphore: AsyncSemaphore
    private let bag = TaskBag()
    
    /// Creates a queue with the given execution mode.
    /// - Parameter mode: `.serial` or `.concurrent(n)`; values ≤ 0 are clamped to 1.
    public init(_ mode: Mode) {
        switch mode {
        case .serial:
            self.semaphore = AsyncSemaphore(value: 1)
        case .concurrent(let n):
            self.semaphore = AsyncSemaphore(value: max(1, n))
        }
    }
    
    /// Enqueue an asynchronous operation.
    ///
    /// The queue will:
    /// 1. Wait for a semaphore permit (suspending cooperatively).
    /// 2. Run `operation`.
    /// 3. Release the permit and unregister the task, even if `operation` throws or the task is cancelled.
    ///
    /// - Parameters:
    ///   - priority: Optional `TaskPriority` for the spawned child task.
    ///   - operation: Your asynchronous, throwable closure.
    /// - Returns: A task “handle/result” produced by `TaskBag.add(id:task:)`; typically includes the `id`
    ///
    ///            so you can call `cancel(id:)`. Adjust your tests if your `TaskResult` type differs.

    @discardableResult
    public func submit<T>(priority: TaskPriority? = nil,
                          _ operation: @Sendable @escaping () async throws -> T) async -> TaskResult<T> {
        let id = UUID()

        let t = Task(priority: priority) { [semaphore, bag] in
            var acquired = false
            defer {
                Task { await bag.remove(id: id) }
                if acquired {
                    Task { await semaphore.release() }
                }
            }
            
            try Task.checkCancellation()
            try await semaphore.acquire()
            acquired = true
            
            try Task.checkCancellation()
            return try await operation()
        }
       
        return await bag.add(id: id, task: t)
    }
    
    /// Cancel a specific task using the identifier returned from `submit`.
    /// - Parameter id: The task id that was produced by `submit`.
    public func cancel(id: UUID) {
        Task {
            await bag.cancel(id: id)
        }
    }
    
    /// Cancel all queued and running tasks currently tracked by the queue.
    public func cancelAll() {
        Task { await bag.cancelAll() }
    }
}

