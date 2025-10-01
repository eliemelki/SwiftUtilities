//
//  MWApiLogger.swift
//  TWGNetwork
//
//  Created by Elie Melki on 15/09/2025.
//
import Foundation
public protocol NetworkLogger: Sendable {
    func logNetworkError(_ error: Error, for request: URLRequest)
}

