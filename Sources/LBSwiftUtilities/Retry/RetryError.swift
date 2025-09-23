//
//  RetryError.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 11/09/2025.
//
import Foundation

public enum RetryError: Error, LocalizedError {
    case timeout
    case gaveUp(lastError: Error?)

    public var errorDescription: String? {
        switch self {
        case .timeout: return "Retry timed out."
        case .gaveUp(let last): return "Exhausted retries." + (last.map { " Last error: \($0)" } ?? "")
        }
    }
}
