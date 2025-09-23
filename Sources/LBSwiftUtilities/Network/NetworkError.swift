//
//  NetworkError.swift
//  TWGNetwork
//
//  Created by Elie Melki on 11/09/2025.
//
import Foundation

public enum NetworkError: Error {
    case invalidURL
    case proxyNotAllowed
    case serialization(Error)
    case transport(Error)
    case server(statusCode: Int, data: Data?, response: HTTPURLResponse)
    case decoding(Error, data: Data)
    case sslPinningFailed
}
