import XCTest
@testable import PodPassportScanner

/// URLProtocol stub: scripted per-request outcomes, recorded requests.
final class StubURLProtocol: URLProtocol {
    enum Step {
        case status(Int)
        case networkError(URLError.Code)
    }

    struct RecordedRequest {
        let url: URL?
        let method: String?
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _script: [Step] = []
    nonisolated(unsafe) private static var _recorded: [RecordedRequest] = []

    static func reset(script: [Step]) {
        lock.lock(); defer { lock.unlock() }
        _script = script
        _recorded = []
    }

    static var recorded: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return _recorded
    }

    private static func consume(_ request: RecordedRequest) -> Step? {
        lock.lock(); defer { lock.unlock() }
        _recorded.append(request)
        return _script.isEmpty ? nil : _script.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            let bufferSize = 16 * 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                guard read > 0 else { break }
                body.append(buffer, count: read)
            }
        }
        let recordedRequest = RecordedRequest(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        )
        guard let step = Self.consume(recordedRequest) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        switch step {
        case .status(let code):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        case .networkError(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

final class UploaderTests: XCTestCase {
    private var uploader: HTTPBundleUploader!
    private let session = IssuerSession(
        endpoint: URL(string: "https://issuer.example/api/emrtd/sessions/abc123")!,
        sessionId: "abc123",
        secret: "topsecret"
    )
    private let bundle = ChipBundle(lds: .init(
        dg1: Data("dg1-bytes".utf8),
        dg2: Data("dg2-bytes".utf8),
        sod: Data("sod-bytes".utf8)
    ))

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        uploader = HTTPBundleUploader(
            urlSession: URLSession(configuration: config),
            maxAttempts: 3,
            baseDelay: .milliseconds(5)
        )
    }

    func testSuccessfulUploadSendsContractRequest() async throws {
        StubURLProtocol.reset(script: [.status(204)])

        try await uploader.upload(bundle, to: session)

        let requests = StubURLProtocol.recorded
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url, session.endpoint)
        XCTAssertEqual(request.headers["Authorization"], "Bearer topsecret")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")

        // Body matches the fixed contract shape.
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        XCTAssertEqual(json["format"] as? String, "icao-9303-lds1")
        let lds = try XCTUnwrap(json["lds"] as? [String: Any])
        XCTAssertEqual(lds["dg1"] as? String, Data("dg1-bytes".utf8).base64EncodedString())
        XCTAssertEqual(lds["dg2"] as? String, Data("dg2-bytes".utf8).base64EncodedString())
        XCTAssertEqual(lds["sod"] as? String, Data("sod-bytes".utf8).base64EncodedString())
        XCTAssertNil(lds["dg11"], "absent data groups must be omitted, not null")
    }

    func test401IsTerminalInvalidSecret() async {
        StubURLProtocol.reset(script: [.status(401)])
        do {
            try await uploader.upload(bundle, to: session)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? UploadError, .invalidSecret)
        }
        XCTAssertEqual(StubURLProtocol.recorded.count, 1, "401 must not be retried")
    }

    func test410IsTerminalSessionExpired() async {
        StubURLProtocol.reset(script: [.status(410)])
        do {
            try await uploader.upload(bundle, to: session)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? UploadError, .sessionExpired)
        }
        XCTAssertEqual(StubURLProtocol.recorded.count, 1, "410 must not be retried")
    }

    func testRetriesServerErrorsThenSucceeds() async throws {
        StubURLProtocol.reset(script: [.status(500), .status(503), .status(204)])
        try await uploader.upload(bundle, to: session)
        XCTAssertEqual(StubURLProtocol.recorded.count, 3)
    }

    func testRetriesNetworkErrorThenSucceeds() async throws {
        StubURLProtocol.reset(script: [.networkError(.networkConnectionLost), .status(204)])
        try await uploader.upload(bundle, to: session)
        XCTAssertEqual(StubURLProtocol.recorded.count, 2)
    }

    func testExhaustedRetriesThrowsLastError() async {
        StubURLProtocol.reset(script: [.status(500), .status(502), .status(503)])
        do {
            try await uploader.upload(bundle, to: session)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? UploadError, .serverError(status: 503))
        }
        XCTAssertEqual(StubURLProtocol.recorded.count, 3)
    }

    func testExhaustedNetworkRetriesThrowsNetworkError() async {
        StubURLProtocol.reset(script: [
            .networkError(.cannotConnectToHost),
            .networkError(.cannotConnectToHost),
            .networkError(.cannotConnectToHost),
        ])
        do {
            try await uploader.upload(bundle, to: session)
            XCTFail("expected throw")
        } catch let error as UploadError {
            guard case .network = error else { return XCTFail("expected .network, got \(error)") }
        } catch {
            XCTFail("expected UploadError, got \(error)")
        }
        XCTAssertEqual(StubURLProtocol.recorded.count, 3)
    }
}
