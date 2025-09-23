//
//  NetworkConfiguration.swift
//  TWGNetwork
//
//  Created by Elie Melki on 11/09/2025.
//

import Foundation

public struct NetworkConfiguration {
    public let baseURL: URL
    public let defaultHeaders: [String: String]
    public let timeout: TimeInterval
    public let proxy: ProxyConfiguration?
    public let sslPinning: SSLPinning
    public let jsonEncoder: JSONEncoder
    public let jsonDecoder: JSONDecoder
    public let allowProxy: Bool
    
    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        timeout: TimeInterval = 30,
        allowProxy: Bool = true,
        proxy: ProxyConfiguration? = nil,
        sslPinning: SSLPinning = .none,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.allowProxy = allowProxy
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeout = timeout
        self.proxy = proxy
        self.sslPinning = sslPinning
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }
}
