//
//  StorageManager.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 11/09/2025.
//
import Foundation

public protocol StorageManager<T> {
    associatedtype T: Codable
    func save(value: T?)
    func getValue() -> T?
    func clear()
}

public class DefaultStorageManager<T: Codable>: StorageManager {
    private var value: T?
    private let key: String
    
    init(key: String) {
        self.key = key
    }
    
    public func save(value: T?) {
        guard let value else {
            self.clear()
            return
        }
        
        self.value = value
        let data = try? JSONEncoder().encode(value)
        UserDefaults.standard.set(data, forKey: key)
    }
    
    public func getValue() -> T? {
        guard let value else {
            guard let data = UserDefaults.standard.data(forKey: key) else {
                return nil
            }
            
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return value
    }
    
    public func clear() {
        self.value = nil
        UserDefaults.standard.removeObject(forKey: key)
    }
}

public struct AnyStorageManager<Value: Codable>: StorageManager {
    private let _save: (Value?) -> Void
    private let _getValue: () -> Value?
    private let _clear: () -> Void

    // Wrap a concrete StorageManager
    public init<S: StorageManager>(_ base: S) where S.T == Value {
        _save = { base.save(value: $0) }
        _getValue = { base.getValue() }
        _clear = { base.clear() }
    }

    public func save(value: Value?) { _save(value) }
    public func getValue() -> Value? { _getValue() }
    public func clear() { _clear() }
}
