//
//  MockNetworkUtils.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 23/09/2025.
//
@testable import LBSwiftUtilities

final class MockNetworkUtils: NetworkUtils {
  
    
    let isProxy: Bool
    
    init(isProxy: Bool) {
        self.isProxy = isProxy
    }
    
    func isUsingProxy() -> Bool {
        self.isProxy
    }
}
