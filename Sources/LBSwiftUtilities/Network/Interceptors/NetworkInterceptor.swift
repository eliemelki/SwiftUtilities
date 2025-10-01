//
//  NetworkInterceptor.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 23/09/2025.
//
import Foundation


public protocol NetworkInterceptor: Sendable {
    /// Inspect/modify request before sending.
    func adapt(_ request: URLRequest) async throws -> URLRequest
    /// Observe the result (for logging/metrics/auth refresh etc.)
    func receive(_ result: Result<(Data, URLResponse), Error>, for request: URLRequest) async
}

public extension NetworkInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest {
        request
    }
    func receive(_ result: Result<(Data, URLResponse), Error>, for request: URLRequest) async {
        
    }
}
