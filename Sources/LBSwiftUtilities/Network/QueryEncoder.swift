//
//  QueryEncoder.swift
//  TWGNetwork
//
//  Created by Elie Melki on 11/09/2025.
//
import Foundation

public struct QueryEncoder {
    public init() {}
    
    public func encode<T: Encodable>(_ value: T) throws -> [URLQueryItem] {
        // Encode to JSON then walk the object graph into flat query items.
        let data = try JSONEncoder().encode(AnyEncodable(value))
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        var items: [URLQueryItem] = []
        func walk(_ keyPath: String?, value: Any) {
            switch value {
            case let dict as [String: Any]:
                for (k, v) in dict {
                    let next = keyPath.map { "\($0)[\(k)]" } ?? k
                    walk(next, value: v)
                }
            case let arr as [Any]:
                for v in arr {
                    let next = keyPath.map { "\($0)[]"} ?? "[]"
                    walk(next, value: v)
                }
            case let n as NSNumber:
                items.append(URLQueryItem(name: keyPath ?? "", value: n.stringValue))
            case let s as NSString:
                items.append(URLQueryItem(name: keyPath ?? "", value: s as String))
            case _ as NSNull:
                items.append(URLQueryItem(name: keyPath ?? "", value: nil))
            default:
                items.append(URLQueryItem(name: keyPath ?? "", value: "\(value)"))
            }
        }
        walk(nil, value: json)
        // Sort for determinism (optional)
        return items.sorted { $0.name < $1.name }
    }
}
