//
//  AnyEncodable.swift
//  TWGNetwork
//
//  Created by Elie Melki on 11/09/2025.
//


// MARK: - AnyEncodable (type erasure)

public struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    
    public init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }
    
    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
