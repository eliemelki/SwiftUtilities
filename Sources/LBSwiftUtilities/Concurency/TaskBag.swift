//
//  TaskBag.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 17/09/2025.
//
import Foundation

public protocol CancellableTask {
    var id: UUID { get }
    func cancel() async
}

private protocol HasCancelTask {
    func cancelTask()
}

public struct TaskResult<T: Sendable>: CancellableTask, HasCancelTask, Sendable {
    public let id: UUID
    public let task: Task<T, Error>
    private weak var bag: TaskBag?
    
    public func cancel() async  {
        await bag?.remove(id: self.id)
        cancelTask()
    }
    
    fileprivate init(id: UUID, task: Task<T, Error>, bag: TaskBag) {
        self.id = id
        self.task = task
        self.bag = bag
    }
    
    fileprivate func cancelTask() {
        task.cancel()
    }
    
}

actor TaskBag {
    private var cancels: [UUID: CancellableTask & HasCancelTask] = [:]
    
    @discardableResult
    func add<T: Sendable>(id: UUID, task: Task<T, Error>) -> TaskResult<T> {
        let cancellable = TaskResult.init(id: id, task: task, bag: self)
        cancels[cancellable.id] = cancellable
        return cancellable
    }
    
    func remove(id: UUID) {
        cancels[id] = nil
    }
    
    func cancel(id: UUID) {
        if let c = cancels.removeValue(forKey: id) { c.cancelTask() }
    }
    
    func cancelAll() {
        let all = cancels.values
        cancels.removeAll()
        for c in all {  c.cancelTask() }
    }
    
}

// MARK: helpers
extension TaskBag {
    
    func count() -> Int {
        return cancels.count
    }
    
    func contains(id: UUID) -> Bool {
        return cancels[id] != nil
    }
    
    func contains(task: CancellableTask) -> Bool {
        return contains(id: task.id)
    }
}
