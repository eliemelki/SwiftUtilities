//
//  MultipartForm.swift
//  TWGNetwork
//
//  Created by Elie Melki on 11/09/2025.
//

import Foundation

// MARK: - Multipart Builder

public enum MultipartForm {
    public struct Part {
        public enum Body {
            case data(Data)
            case fileURL(URL) // reads into memory (adjust to stream if needed)
        }
        public var name: String
        public var filename: String?
        public var mimeType: String?
        public var body: Body
        
        public init(name: String, filename: String? = nil, mimeType: String? = nil, body: Body) {
            self.name = name
            self.filename = filename
            self.mimeType = mimeType
            self.body = body
        }
    }
    
    public static func buildBody(parts: [Part], boundary: String = "Boundary-\(UUID().uuidString)") -> (Data, String) {
        var body = Data()
        let lineBreak = "\r\n"
        for p in parts {
            body.append("--\(boundary)\(lineBreak)")
            if let filename = p.filename {
                body.append("Content-Disposition: form-data; name=\"\(p.name)\"; filename=\"\(filename)\"\(lineBreak)")
                body.append("Content-Type: \(p.mimeType ?? "application/octet-stream")\(lineBreak)\(lineBreak)")
            } else {
                body.append("Content-Disposition: form-data; name=\"\(p.name)\"\(lineBreak)\(lineBreak)")
            }
            switch p.body {
            case .data(let d): body.append(d)
            case .fileURL(let url): if let d = try? Data(contentsOf: url) { body.append(d) }
            }
            body.append(lineBreak)
        }
        body.append("--\(boundary)--\(lineBreak)")
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
}

private extension Data {
    mutating func append(_ string: String) { append(string.data(using: .utf8)!) }
}
