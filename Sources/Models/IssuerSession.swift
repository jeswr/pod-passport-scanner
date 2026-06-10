import Foundation

/// An upload session handed to the app by the Credential Issuer web app,
/// either via QR code or manual entry.
///
/// QR payload contract (fixed, version 1):
/// `{"v":1,"endpoint":"<absolute uploadUrl>","sessionId":"...","secret":"..."}`
struct IssuerSession: Equatable, Sendable {
    let endpoint: URL
    let sessionId: String
    let secret: String
}

enum QRPayloadError: Error, LocalizedError, Equatable {
    case notJSON
    case unsupportedVersion(Int)
    case missingField(String)
    case invalidEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .notJSON:
            return "That QR code is not a Pod Passport issuer code."
        case .unsupportedVersion(let v):
            return "Unsupported issuer QR version \(v). This app understands version 1 — please update the app."
        case .missingField(let f):
            return "The issuer QR code is missing the \"\(f)\" field."
        case .invalidEndpoint(let s):
            return "The issuer QR code contains an invalid upload URL: \(s)"
        }
    }
}

enum QRPayloadDecoder {
    private struct Payload: Decodable {
        let v: Int
        let endpoint: String?
        let sessionId: String?
        let secret: String?
    }

    /// Decodes the JSON string carried in the issuer QR code.
    static func decode(_ string: String) throws -> IssuerSession {
        guard let data = string.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw QRPayloadError.notJSON
        }
        guard payload.v == 1 else { throw QRPayloadError.unsupportedVersion(payload.v) }
        guard let endpoint = payload.endpoint, !endpoint.isEmpty else {
            throw QRPayloadError.missingField("endpoint")
        }
        guard let sessionId = payload.sessionId, !sessionId.isEmpty else {
            throw QRPayloadError.missingField("sessionId")
        }
        guard let secret = payload.secret, !secret.isEmpty else {
            throw QRPayloadError.missingField("secret")
        }
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", // http permitted for local development issuers
              url.host() != nil else {
            throw QRPayloadError.invalidEndpoint(endpoint)
        }
        return IssuerSession(endpoint: url, sessionId: sessionId, secret: secret)
    }
}
