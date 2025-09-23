////
////  ConcurrencyMode.swift
////  LBSwiftUtilities
////
////  Created by Elie Melki on 10/09/2025.
////
//

import Foundation

public protocol Scheduler {
    func run<T>(_ op: @Sendable @escaping () async throws -> T) async throws -> T
    func run<T>(_ op: @Sendable @escaping () async throws -> T) async throws -> CancellableTask
    func cancelAll()
    func cancel(id: UUID)
}

// MARK: - NetworkScheduler
public final class DefaultNetworkScheduler: Scheduler {
    
    private let queue: AsyncTaskQueue

    public init(mode: AsyncTaskQueue.Mode = .concurrent(10)) {
        self.queue = AsyncTaskQueue(mode)
    }

    @discardableResult
    public func run<T: Sendable>(_ op: @Sendable @escaping () async throws -> T) async throws -> T {

        let task = await queue.submit(op)
        return try await task.task.value
    }
    
    public func run<T:Sendable>(_ op: @Sendable @escaping () async throws -> T) async throws -> any CancellableTask {
        return await queue.submit(op)
    }
    public func cancelAll() {
        self.queue.cancelAll()
    }
    
    public func cancel(id: UUID) {
        self.queue.cancel(id: id)
    }
}



