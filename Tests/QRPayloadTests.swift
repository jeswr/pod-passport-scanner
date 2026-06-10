import XCTest
@testable import PodPassportScanner

final class QRPayloadTests: XCTestCase {
    func testDecodesValidPayload() throws {
        let json = #"{"v":1,"endpoint":"https://issuer.example/api/emrtd/sessions/abc123","sessionId":"abc123","secret":"s3cr3t"}"#
        let session = try QRPayloadDecoder.decode(json)
        XCTAssertEqual(session.endpoint, URL(string: "https://issuer.example/api/emrtd/sessions/abc123"))
        XCTAssertEqual(session.sessionId, "abc123")
        XCTAssertEqual(session.secret, "s3cr3t")
    }

    func testAllowsHTTPForLocalDevelopment() throws {
        let json = #"{"v":1,"endpoint":"http://localhost:3000/api/emrtd/sessions/x","sessionId":"x","secret":"y"}"#
        XCTAssertNoThrow(try QRPayloadDecoder.decode(json))
    }

    func testRejectsNonJSON() {
        XCTAssertThrowsError(try QRPayloadDecoder.decode("https://example.com/not-our-qr")) {
            XCTAssertEqual($0 as? QRPayloadError, .notJSON)
        }
    }

    func testRejectsUnsupportedVersion() {
        let json = #"{"v":2,"endpoint":"https://e.example/u","sessionId":"a","secret":"b"}"#
        XCTAssertThrowsError(try QRPayloadDecoder.decode(json)) {
            XCTAssertEqual($0 as? QRPayloadError, .unsupportedVersion(2))
        }
    }

    func testRejectsMissingFields() {
        let json = #"{"v":1,"endpoint":"https://e.example/u","sessionId":"a"}"#
        XCTAssertThrowsError(try QRPayloadDecoder.decode(json)) {
            XCTAssertEqual($0 as? QRPayloadError, .missingField("secret"))
        }
    }

    func testRejectsInvalidEndpointScheme() {
        let json = #"{"v":1,"endpoint":"ftp://e.example/u","sessionId":"a","secret":"b"}"#
        XCTAssertThrowsError(try QRPayloadDecoder.decode(json)) {
            XCTAssertEqual($0 as? QRPayloadError, .invalidEndpoint("ftp://e.example/u"))
        }
    }

    func testRejectsRelativeEndpoint() {
        let json = #"{"v":1,"endpoint":"/api/emrtd/sessions/abc","sessionId":"a","secret":"b"}"#
        XCTAssertThrowsError(try QRPayloadDecoder.decode(json)) {
            XCTAssertEqual($0 as? QRPayloadError, .invalidEndpoint("/api/emrtd/sessions/abc"))
        }
    }
}
