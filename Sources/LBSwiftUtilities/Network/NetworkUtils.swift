//
//  NetworkUtils.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 23/09/2025.
//

import Foundation

public protocol NetworkUtils: Sendable {
    func isUsingProxy() -> Bool
}

public final class DefaultNetworkUtils : NetworkUtils {
    public init() {
        
    }
    
    public func isUsingProxy() -> Bool {
        guard let proxy = CFNetworkCopySystemProxySettings()?.takeUnretainedValue(),
              let dict = proxy as? [String: Any],
              let proxy = dict["HTTPProxy"] as? String else
        {
            return false
        }
        
        return !proxy.isEmpty
    }
}
