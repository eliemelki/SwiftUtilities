//
//  URLProtocolStubRegistry.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 23/09/2025.
//


import Foundation

actor MockURLProtocolStubRegistry {
    typealias Matcher = (URLRequest) -> Bool
    typealias Responder = (URLRequest) throws -> (HTTPURLResponse, Data, TimeInterval)

    private var routes: [(Matcher, Responder)] = []
    
    static let shared = MockURLProtocolStubRegistry()

    func add(matching: @escaping Matcher, respond: @escaping Responder) {
        routes.append((matching, respond))
    }

    func removeAll() {
        routes.removeAll()
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data, TimeInterval)?   {
        for (m, r) in routes where m(request) {
            return try r(request)
        }
        return nil
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    
    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: (any URLProtocolClient)?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
       
        Task {
            do {
                let result = try await MockURLProtocolStubRegistry.shared.response(for: self.request)
                guard let (resp, data, delay) = result else {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                    return
                }
                // simulate latency
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                self.client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                if !data.isEmpty { self.client?.urlProtocol(self, didLoad: data) }
                self.client?.urlProtocolDidFinishLoading(self)
            }catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() { /* no-op */ }
}

private extension InputStream {
    func readAll() -> Data {
        open()
        defer { close() }
        var data = Data()
        let bufSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }
        while hasBytesAvailable {
            let read = self.read(buffer, maxLength: bufSize)
            if read > 0 { data.append(buffer, count: read) }
            else { break }
        }
        return data
    }
}

enum MockURLProtocolKeys {
    static let body = "MockURLProtocol.Body"
}

public extension URLRequest {
    
    func extractHTTPBody() -> Data? {
        if let body = self.httpBody { return body }
        if let stream = self.httpBodyStream { return stream.readAll() }
        if let saved = URLProtocol.property(forKey: MockURLProtocolKeys.body, in: self) as? Data {
            return saved
        }
        return nil
    }
}
