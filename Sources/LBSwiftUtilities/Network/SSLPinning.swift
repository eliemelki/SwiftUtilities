//
//  SSLPinning.swift
//  TWGNetwork
//
//  Created by Elie Melki on 11/09/2025.
//
import Foundation

public enum SSLPinning: Sendable {
    case none
    /// Pin DER-encoded certificate data (e.g. from *.cer files).
    case certificates([Data])
    /// Pin SPKI public keys (DER-encoded SubjectPublicKeyInfo).
    case publicKeys([Data])
    
    /// Convenience to load .cer files from a bundle.
    public static func certificates(named names: [String], in bundle: Bundle = .main) -> SSLPinning {
        let datas:[Data] = names.compactMap { name in
            guard let url = bundle.url(forResource: name, withExtension: "cer"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return data
        }
        return .certificates(datas)
    }
}
