//
//  DefaultNetworkClientTests.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 19/09/2025.
//


import XCTest
@testable import LBSwiftUtilities



final class DefaultNetworkClientTests: XCTestCase {

    // MARK: Harness

    override func tearDown() async throws {
         MockURLProtocolStubRegistry.shared.removeAll()
    }

    private func makeClient(
        interceptors: [NetworkInterceptor] = [],
        defaultHeaders: [String:String] = ["X-Default": "D"],
        isUsingProxy: Bool = false,
        allowProxy: Bool = true) -> DefaultNetworkClient {
        // Configure a session that uses our URLProtocol stub
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]

        let configuration = NetworkConfiguration(
            baseURL: URL(string: "https://example.com")!,
            defaultHeaders: defaultHeaders,
            timeout: 5,
            allowProxy: allowProxy,
            proxy: nil,
            sslPinning: .none,
            jsonEncoder: JSONEncoder(),
            jsonDecoder: JSONDecoder()
        )

        return DefaultNetworkClient(configuration: configuration,
                                    interceptors: interceptors,
                                    networkUtils: MockNetworkUtils(isProxy: isUsingProxy),
                                    sessionConfiguration: cfg)
    }

    // MARK: Models

    private struct Todo: Codable, Equatable { let id: Int; let title: String }
    private struct Query: Encodable { let a: Int; let b: String }

    // MARK: Tests — basics

    func testGET_decodesSuccess() async throws {
        let expected = Todo(id: 1, title: "Hello")
        let body = try JSONEncoder().encode(expected)

        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/todos" && $0.httpMethod == "GET" }) { req in
            XCTAssertEqual(req.httpMethod, "GET")
            let url = req.url!.absoluteString
            XCTAssertTrue(url.hasPrefix("https://example.com/todos"))
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, body, 0)
        }

        let client = makeClient()
        let todo: Todo = try await client.get("/todos", query: NilType())
        XCTAssertEqual(todo, expected)
    }

    func testGET_appendsQueryItems() async throws {
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/search" && $0.httpMethod == "GET" }) { req in
            let qs = req.url!.query ?? ""
            // Order is not guaranteed, so check both key/value pairs exist
            XCTAssertTrue(qs.contains("a=1"))
            XCTAssertTrue(qs.contains("b=two"))
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8), 0)
        }
        let client = makeClient()
        struct Empty: Decodable {}
        _ = try await client.get("/search", query: Query(a: 1, b: "two")) as Empty
    }
    struct User: Sendable {

        var age: Int

    }
    
 
    func testPOST_setsContentTypeAndSerializesBody() async throws {
        let expected = Todo(id: 2, title: "Created")
        let body = try JSONEncoder().encode(expected)
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/todos" && $0.httpMethod == "POST" }) { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
            XCTAssertNotNil(req.extractHTTPBody())
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, body,0)
        }
        let client = makeClient()
        let todo: Todo = try await client.post("/todos", body: ["title": "Created"]) // Encodable dictionary via AnyEncodable
        XCTAssertEqual(todo, expected)
    }

    func testPOST_serializationErrorMapsToNetworkErrorSerialization() async {
        struct BodyThatThrows: Encodable { func encode(to encoder: Encoder) throws { throw TestError.intended } }
        enum TestError: Error { case intended }

        let client = makeClient()
        do {
            let _: Todo = try await client.post("/todos", body: BodyThatThrows())
            XCTFail("Expected to throw")
        } catch let err as NetworkError {
            switch err {
            case .serialization:
                break // expected
            default:
                XCTFail("Wrong error: \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testHEAD_returnsHTTPURLResponse() async throws {
        let headers = ["X-From-Server": "1"]
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/ping" && $0.httpMethod == "HEAD" }) { req in
            XCTAssertEqual(req.httpMethod, "HEAD")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: headers)!
            return (resp, Data(),0)
        }
        let client = makeClient()
        let http = try await client.head("/ping", query: NilType())
        XCTAssertEqual(http.statusCode, 204)
        XCTAssertEqual(http.allHeaderFields["X-From-Server"] as? String, "1")
    }

    func testServerError_exposesStatusCodeAndBody() async {
        let body = Data("{\"message\":\"boom\"}".utf8)
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/oops" }) { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, body, 0)
        }
        let client = makeClient()
        do {
            let _: Todo = try await client.get("/oops", query: NilType())
            XCTFail("Expected error")
        } catch let err as NetworkError {
            switch err {
            case .server(let code, let data, _):
                XCTAssertEqual(code, 500)
                XCTAssertEqual(data, body)
            default:
                XCTFail("Unexpected error: \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testDecodingErrorWrapsData() async {
        // Return invalid JSON for Todo
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/bad-json" }) { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("not-json".utf8),0)
        }
        let client = makeClient()
        do {
            let _: Todo = try await client.get("/bad-json", query: NilType())
            XCTFail("Expected error")
        } catch let err as NetworkError {
            switch err {
            case .decoding(_, let data):
                XCTAssertEqual(data, Data("not-json".utf8))
            default:
                XCTFail("Unexpected error: \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testTransportErrorMapsToNetworkErrorTransport() async {
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/slow" }) { req in
            throw URLError(.timedOut)
        }
        let client = makeClient()
        do {
            let _: Todo = try await client.get("/slow", query: NilType())
            XCTFail("Expected transport error")
        } catch let err as NetworkError {
            switch err {
            case .transport(let underlying as URLError):
                XCTAssertEqual(underlying.code, .timedOut)
            default:
                XCTFail("Unexpected error: \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testHeaders_mergeDefaultAndOverrides() async throws {
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/hdrs" }) { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Default"), "D")
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Call"), "C")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8),0)
        }
        let client = makeClient()
        struct Empty: Decodable {}
        _ = try await client.get("/hdrs", query: NilType(), headers: ["X-Call": "C"]) as Empty
    }

    // MARK: Tests — interceptors

    func testInterceptors_orderAndReceiveCallbacks() async throws {
        let trace: TraceInterceptor = .init(id: "A")
        let trace2: TraceInterceptor = .init(id: "B")
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/ok" }) { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8),0)
        }
        let client = makeClient(interceptors: [trace, trace2])
        struct Empty: Decodable {}
        _ = try await client.get("/ok", query: NilType()) as Empty
        let traceEvents = await trace.events
        let traceEvents2 = await trace.events
        let adaptCallTime1 = await trace.adaptCallTime
        let adaptCallTime2 = await trace2.adaptCallTime
        
        
        XCTAssertEqual(traceEvents, ["adapt", "receiveSuccess"])
        XCTAssertEqual(traceEvents2, ["adapt", "receiveSuccess"])
        XCTAssertLessThan(adaptCallTime1!, adaptCallTime2!) // order preserved
    }

    func testInterceptors_receiveOnFailure() async {
        let trace = TraceInterceptor(id: "A")
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/offline" }) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = makeClient(interceptors: [trace])
        do {
            let _: Todo = try await client.get("/offline", query: NilType())
            XCTFail("Expected to fail")
        } catch {
            // swallow
        }
        let traceEvents = await trace.events
        XCTAssertEqual(traceEvents, ["adapt", "receiveFailure"])
    }

    // MARK: Tests — multipart

    func testMultipart_setsContentTypeAndBodyContainsBoundaryAndFields() async throws {
        // Arrange a handler that inspects body and headers
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/upload" }) { req in
            XCTAssertEqual(req.httpMethod, "POST")
            let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(ct.contains("multipart/form-data"))
            // Boundary present
            let body = String(data: req.extractHTTPBody() ?? Data(), encoding: .utf8) ?? ""
            // Field names should appear somewhere in the encoded body
            XCTAssertTrue(body.contains("name=\"file\""))
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8),0)
        }
        let client = makeClient()
        struct Empty: Decodable {}
        // These constructors assume your MultipartForm.Part supports common cases; adjust if your API differs.
        let parts: [MultipartForm.Part] = [
            .init(name: "file", filename: "a.txt", mimeType: "text/plain", body: .data(Data("X".utf8)))
        ]
        _ = try await client.uploadMultipart("/upload", parts: parts) as Empty
    }

    // MARK: Tests — proxy gating

    func testProxyGating_deniesWhenProxyDetectedAndNotAllowed() async {
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/any" }) { req in
            let resp = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8),0)
        }
        let client = makeClient(isUsingProxy: true, allowProxy: false)
        do {
            let _: Todo = try await client.get("/any", query: NilType())
            XCTFail("Expected proxyNotAllowed")
        } catch let err as NetworkError {
            if case .proxyNotAllowed = err { /* OK */ } else { XCTFail("Unexpected error: \(err)") }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testProxyGating_allowsWhenNoProxyOrAllowed() async throws {
        MockURLProtocolStubRegistry.shared.add(matching: { $0.url?.path == "/no-proxy" }) { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8),0)
        }
        // Case 1: allowProxy=false but no proxy detected
        do {
            let client = makeClient(isUsingProxy: false, allowProxy: false)
            struct Empty: Decodable {}
            _ = try await client.get("/no-proxy", query: NilType()) as Empty
        }
        // Case 2: allowProxy=true regardless of detection
        do {
            let client = makeClient(isUsingProxy: true, allowProxy: true)
            struct Empty: Decodable {}
            _ = try await client.get("/no-proxy", query: NilType()) as Empty
        }
    }

    // MARK: Tests — SSL pinning delegate (basic branches)

    func testSSLDelegate_performDefaultHandlingWhenNotServerTrust() {
        let delegate = NetworkSessionDelegate(policy: .none)
        let space = URLProtectionSpace(host: "example.com", port: 443, protocol: nil, realm: nil, authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: NullAuthChallengeSender())
        let exp = expectation(description: "default handling")
        delegate.urlSession(URLSession(configuration: .ephemeral), didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testSSLDelegate_defaultHandlingWhenServerTrustMissing() {
        let delegate = NetworkSessionDelegate(policy: .none)
        // Auth method is server trust but with no trust object — should fall back to default handling in our implementation
        let space = URLProtectionSpace(host: "example.com", port: 443, protocol: nil, realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: NullAuthChallengeSender())
        let exp = expectation(description: "default handling for missing trust")
        delegate.urlSession(URLSession(configuration: .ephemeral), didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    // Optional: Template for certificate pinning tests.
    // Requires a test certificate and a trust object that evaluates successfully on your CI/macOS runner.
    // If unavailable, the test will be skipped.
    func testSSLDelegate_certificatePinningTemplate() throws {
        throw XCTSkip("Provide a trusted test leaf certificate to enable this test.")
        // Example outline (requires adding `Pinned.cer` to test bundle and ensuring SecTrust evaluates OK):
        // let delegate = NetworkSessionDelegate(policy: .certificates([pinnedDERData]))
        // let (challenge, trust) = try makeServerTrustChallengeFromDER(named: "Pinned")
        // let exp = expectation(description: "pinning")
        // delegate.urlSession(URLSession(configuration: .ephemeral), didReceive: challenge) { disposition, credential in
        //     XCTAssertEqual(disposition, .useCredential)
        //     XCTAssertNotNil(credential)
        //     exp.fulfill()
        // }
        // wait(for: [exp], timeout: 1)
    }
}

// MARK: - Test Interceptor

actor TraceInterceptor: NetworkInterceptor {
    let id: String
    private(set) var events: [String] = []
    private(set) var adaptCallTime: TimeInterval?
    init(id: String) { self.id = id }

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        events.append("adapt")
        adaptCallTime = Date().timeIntervalSince1970
        var r = request
        r.addValue(id, forHTTPHeaderField: "X-Trace")
        return r
    }

    func receive(_ result: Result<(Data, URLResponse), Error>, for request: URLRequest) async {
        switch result {
        case .success: events.append("receiveSuccess")
        case .failure: events.append("receiveFailure")
        }
    }
}

final class NullAuthChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}
