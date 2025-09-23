//
//  ProxyConfiguration.swift
//  TWGNetwork
//
//  Created by Elie Melki on 11/09/2025.
//
import Foundation

public struct ProxyConfiguration {
    public enum Kind { case http, https, socks }
    public var host: String
    public var port: Int
    public var kind: Kind
    public var username: String?
    public var password: String?
    
    public init(host: String, port: Int, kind: Kind = .http, username: String? = nil, password: String? = nil) {
        self.host = host
        self.port = port
        self.kind = kind
        self.username = username
        self.password = password
    }
    
    // Map to URLSessionConfiguration.connectionProxyDictionary
    var dictionary: [AnyHashable: Any] {
        var dict: [AnyHashable: Any] = [:]
        switch kind {
        case .http, .https:
            dict[kCFNetworkProxiesHTTPEnable as String] = true
            dict[kCFNetworkProxiesHTTPProxy as String] = host
            dict[kCFNetworkProxiesHTTPPort as String] = port
            if let u = username { dict[kCFProxyUsernameKey as String] = u }
            if let p = password { dict[kCFProxyPasswordKey as String] = p }
            if kind == .https {
                dict["HTTPSEnable"] = true
                dict["HTTPSProxy"] = host
                dict["HTTPSPort"] = port
            }
        case .socks:
            dict["SOCKSEnable"] = true
            dict["SOCKSProxy"] = host
            dict["SOCKSPort"] = port
            if let u = username { dict[kCFProxyUsernameKey as String] = u }
            if let p = password { dict[kCFProxyPasswordKey as String] = p }
        }
        return dict
    }
}
