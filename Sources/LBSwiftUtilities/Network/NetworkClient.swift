//
//  HTTPMethod.swift
//  TWGNetwork
//
//  Created by Elie Melki on 10/09/2025.
//


import Foundation
import Security

// MARK: - Public Types

public enum HTTPMethod: String { case GET, POST, HEAD }



public protocol NetworkClient {
    func get<Q: Encodable, T: Decodable>(_ path: String,
                                         query: Q?,
                                         headers: [String: String]) async throws -> T
    
    func post<B: Encodable, T: Decodable>(_ path: String,
                                          body: B,
                                          headers: [String: String]) async throws -> T
    func head<Q: Encodable>( _ path: String,
                             query: Q?,
                             headers: [String: String]) async throws -> HTTPURLResponse
    
    func uploadMultipart<T: Decodable>(_ path: String,
                                       parts: [MultipartForm.Part],
                                       headers: [String: String]) async throws -> T
}

public protocol NetworkClientFactory {
    func makeClient(config: NetworkConfiguration, interceptors: [NetworkInterceptor]) -> NetworkClient
}
// DefaultNetworkClient.swift — with documentation comments and a test-only initializer
//
// Notes:
// - Public API surface unchanged. Two *internal* test seams were added:
//   1) a testing-only initializer that accepts a `URLSessionConfiguration` so we can inject a
//      `URLProtocol` stub; and
//   2) an `internal var isUsingProxy: () -> Bool` used by `send(...)` to check for proxies,
//      which tests can override to simulate proxy detection.
// - Everything else remains identical to the user-provided implementation.

import Foundation

// MARK: - Client

/// A lightweight, production-ready HTTP client built on `URLSession`.
///
/// Features
/// - GET with optional `Encodable` query object (encoded as URL query items)
/// - HEAD (returns the underlying `HTTPURLResponse`)
/// - POST (JSON) with `Encodable` body and `Decodable` response
/// - Multipart upload helper
/// - Request/response interceptor chain
/// - Optional corporate proxy gating
/// - SSL pinning (leaf certificate or public key)
/// - Pluggable JSON encoder/decoder via `NetworkConfiguration`
///
/// Threading: public APIs are `async` and call into `URLSession` suspending points.
///
/// Error Semantics
/// - Transport-layer failures (timeouts, DNS, no network) → `.transport(URLError)`
/// - Non-2xx HTTP status codes → `.server(statusCode:data:response)`
/// - JSON encoding errors → `.serialization(Error)`
/// - JSON decoding errors → `.decoding(Error, data: Data)`
public final class DefaultNetworkClient {
    private let config: NetworkConfiguration
    private let session: URLSession
    private let sessionDelegate: NetworkSessionDelegate
    private let interceptors: [NetworkInterceptor]
    private let networkUtils: NetworkUtils
    // MARK:
    // - Parameters:
    ///   - configuration: `NetworkConfiguration` containing baseURL, timeouts, codec, headers, SSL pinning, etc.
    ///   - interceptors: Optional ordered chain of interceptors that can adapt outgoing requests and observe responses.
    ///   - networkUtils: Optional
    ///   - sessionConfiguration: Optional
    public init(configuration: NetworkConfiguration,
                interceptors: [NetworkInterceptor] = [],
                networkUtils: NetworkUtils = DefaultNetworkUtils(),
                sessionConfiguration: URLSessionConfiguration = .default) {
        self.config = configuration
        self.interceptors = interceptors
        self.networkUtils = networkUtils
        let urlConfig = sessionConfiguration
        urlConfig.timeoutIntervalForRequest = configuration.timeout
        urlConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlConfig.httpAdditionalHeaders = configuration.defaultHeaders
        if let proxy = configuration.proxy {
            urlConfig.connectionProxyDictionary = proxy.dictionary
        }
        
        self.sessionDelegate = NetworkSessionDelegate(policy: configuration.sslPinning)
        self.session = URLSession(configuration: urlConfig, delegate: sessionDelegate, delegateQueue: nil)
    }
    
    // MARK: GET
    
    /// Perform a GET request.
    /// - Parameters:
    ///   - path: Path to append to `baseURL`.
    ///   - query: Optional `Encodable` object converted to URL query items.
    ///   - headers: Per-call headers merged on top of defaults.
    /// - Returns: A decoded `T`.
    /// - Throws: `NetworkError` for proxy, transport, HTTP status, or decoding failures.
    public func get<Q: Encodable, T: Decodable>(_ path: String,
                                                query: Q? = nil,
                                                headers: [String: String] = [:]) async throws -> T {
        var req = try makeRequest(path: path, method: .GET, headers: headers)
        if let q = query {
            try appendQuery(&req, query: q)
        }
        let data = try await send(req)
        return try decode(data, as: T.self)
    }
    
    // MARK: HEAD
    
    /// Perform a HEAD request.
    /// - Parameters:
    ///   - path: Path to append to `baseURL`.
    ///   - query: Optional `Encodable` query object.
    ///   - headers: Per-call headers merged on top of defaults.
    /// - Returns: The resulting `HTTPURLResponse` (no body is read or required to succeed).
    /// - Throws: `NetworkError` on proxy, transport, or non-2xx status.
    @discardableResult
    public func head<Q: Encodable>( _ path: String,
                                    query: Q? = nil,
                                    headers: [String: String] = [:]) async throws -> HTTPURLResponse {
        var req = try makeRequest(path: path, method: .HEAD, headers: headers)
        if let q = query {
            try appendQuery(&req, query: q)
        }
        _ = try await send(req, expectBody: false)
        guard let http = lastHTTPURLResponse else { throw NetworkError.invalidURL } // defensive
        return http
    }
    
    // MARK: POST (JSON)
    
    /// Perform a JSON POST.
    /// - Parameters:
    ///   - path: Path to append to `baseURL`.
    ///   - body: `Encodable` payload encoded with `configuration.jsonEncoder`.
    ///   - headers: Per-call headers merged on top of defaults.
    /// - Returns: A decoded `T`.
    /// - Throws: `.serialization` if encoding the body fails; otherwise the standard `NetworkError` cases.
    public func post<B: Encodable, T: Decodable>(_ path: String,
                                                 body: B,
                                                 headers: [String: String] = [:]) async throws -> T {
        var req = try makeRequest(path: path, method: .POST, headers: headers)
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try config.jsonEncoder.encode(AnyEncodable(body))
        } catch {
            throw NetworkError.serialization(error)
        }
        let data = try await send(req)
        return try decode(data, as: T.self)
    }
    
    // MARK: Upload (multipart/form-data)
    
    /// Upload using `multipart/form-data`.
    /// - Parameters:
    ///   - path: Path appended to `baseURL`.
    ///   - parts: Multipart parts assembled via `MultipartForm` helper.
    ///   - headers: Per-call headers merged on top of defaults.
    /// - Returns: Decoded `T`.
    public func uploadMultipart<T: Decodable>(_ path: String,
                                              parts: [MultipartForm.Part],
                                              headers: [String: String] = [:]) async throws -> T {
        var req = try makeRequest(path: path, method: .POST, headers: headers)
        let (body, contentType) = MultipartForm.buildBody(parts: parts)
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let data = try await send(req)
        return try decode(data, as: T.self)
    }
    
    // MARK: - Core send/receive
    
    private var lastHTTPURLResponse: HTTPURLResponse?
    
    /// Applies each interceptor's `adapt` in-order to the request.
    private func applyRequestInterceptors(_ request: URLRequest) async throws -> URLRequest {
        var req = request
        for interceptor in interceptors {
            req = try await interceptor.adapt(req)
        }
        return req
    }
    
    /// Sends the request and enforces error semantics.
    /// - Parameter expectBody: If `false`, a body is not required and won’t be surfaced on success.
    @discardableResult
    private func send(_ originalRequest: URLRequest, expectBody: Bool = true) async throws -> Data {
        
        let isOkayToProceedWithProxy = config.allowProxy || !networkUtils.isUsingProxy()
        guard isOkayToProceedWithProxy else {
            throw NetworkError.proxyNotAllowed
        }
        // Apply request interceptors in order
        let adapted: URLRequest = try await applyRequestInterceptors(originalRequest)
        
        do {
            let (data, response) = try await session.data(for: adapted)
            lastHTTPURLResponse = response as? HTTPURLResponse
            // Response interceptors (notify all)
            await notifyInterceptors(.success((data, response)), for: adapted)
            
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.transport(URLError(.badServerResponse))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkError.server(statusCode: http.statusCode, data: expectBody ? data : nil, response: http)
            }
            return expectBody ? data : Data()
        } catch {
            // Notify interceptors about failure
            await notifyInterceptors(.failure(error), for: adapted)
            if (error as? URLError) != nil {
                throw NetworkError.transport(error)
            }
            throw error
        }
    }
    
    /// Decodes `Data` into `T` using `configuration.jsonDecoder`, wrapping any failure in `.decoding`.
    private func decode<T: Decodable>(_ data: Data, as: T.Type) throws -> T {
        do {
            return try config.jsonDecoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error, data: data)
        }
    }
    
    /// Notifies all interceptors of the result in-order. Failures do not short-circuit notifications.
    private func notifyInterceptors(_ result: Result<(Data, URLResponse), Error>, for request: URLRequest) async {
        // Fire-and-forget; maintain order
        for interceptor in interceptors {
            await interceptor.receive(result, for: request)
        }
    }
    
    // MARK: - Request building
    
    /// Builds a `URLRequest` with merged default/override headers and an HTTP method.
    private func makeRequest(path: String, method: HTTPMethod, headers: [String: String]) throws -> URLRequest {
        guard let components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        // Components' queryItems will be appended later if needed
        guard let url = components.url else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        // Default headers from session config are applied automatically, but merge here too
        for (k, v) in config.defaultHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        return request
    }
    
    /// Encodes the `query` into URL query parameters and updates the `URLRequest` in-place.
    private func appendQuery<Q: Encodable>(_ request: inout URLRequest, query: Q) throws {
        guard var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        let items = try QueryEncoder().encode(query)
        components.percentEncodedQuery = items.isEmpty ? nil : items.map { $0.name + "=" + ($0.value ?? "") }.joined(separator: "&")
        if let newURL = components.url {
            request.url = newURL
        } else {
            throw NetworkError.invalidURL
        }
    }
}

// MARK: - Session Delegate with SSL Pinning

/// `URLSessionDelegate` that enforces the configured SSL pinning policy.
internal final class NetworkSessionDelegate: NSObject, URLSessionDelegate {
    private let policy: SSLPinning
    
    init(policy: SSLPinning) {
        self.policy = policy
    }
    
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return completionHandler(.performDefaultHandling, nil)
        }
        
        switch policy {
        case .none:
            completionHandler(.performDefaultHandling, nil)
            
        case .certificates(let pinnedCerts):
            var secError: CFError?
            let ok = SecTrustEvaluateWithError(trust, &secError)
            guard ok else {
                return completionHandler(.cancelAuthenticationChallenge, nil) }
            
            // Compare leaf (index 0) certificate data to any pinned
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let leaf = chain.first else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            let serverData = SecCertificateCopyData(leaf) as Data
            if pinnedCerts.contains(serverData) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            
        case .publicKeys(let pinnedKeys):
            var secError: CFError?
            let ok = SecTrustEvaluateWithError(trust, &secError)
            guard ok else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let leaf = chain.first,
                  let serverKey = publicKey(for: leaf) else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            let serverKeyData = SecKeyCopyExternalRepresentation(serverKey, nil) as Data? ?? Data()
            if pinnedKeys.contains(serverKeyData) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
    
    private func publicKey(for certificate: SecCertificate) -> SecKey? {
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
        guard status == errSecSuccess, let t = trust else { return nil }
        return SecTrustCopyKey(t)
    }
}

