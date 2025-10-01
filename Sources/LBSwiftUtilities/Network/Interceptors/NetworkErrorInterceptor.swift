//
//  MWErrorInterceptor.swift
//  TWGNetwork
//
//  Created by Elie Melki on 17/09/2025.
//

import Foundation

public final class NetworkErrorInterceptor: NetworkInterceptor {
    private let logger: NetworkLogger
    
    public init(logger: NetworkLogger) {
        self.logger = logger
    }
    
    public func receive(_ result: Result<(Data, URLResponse), any Error>, for request: URLRequest) async {
        switch result {
        case .failure(let error):
            logger.logNetworkError(error, for: request)
        default:
            break
        }
    }
}
