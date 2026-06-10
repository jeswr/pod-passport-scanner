import Foundation

enum UploadError: Error, LocalizedError, Equatable {
    /// 401 — the bearer secret was rejected. Not retried.
    case invalidSecret
    /// 410 — the issuer session expired. Not retried; rescan the QR code.
    case sessionExpired
    /// Unexpected HTTP status after exhausting retries.
    case serverError(status: Int)
    /// Network-level failure after exhausting retries.
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidSecret:
            return "The issuer rejected this upload (invalid secret). Rescan the QR code in your browser and try again."
        case .sessionExpired:
            return "This issuer session has expired. Refresh the page in your browser and scan the new QR code."
        case .serverError(let status):
            return "The issuer returned an unexpected response (HTTP \(status)). Please try again."
        case .network(let message):
            return "Could not reach the issuer: \(message)"
        }
    }
}

/// Abstraction over the upload so the flow is testable and runs in the
/// Simulator / UI tests against `MockBundleUploader`.
protocol BundleUploader: Sendable {
    /// Uploads the chip bundle to the issuer session's endpoint.
    /// Returns normally on HTTP 204; throws `UploadError` otherwise.
    func upload(_ bundle: ChipBundle, to session: IssuerSession) async throws
}

/// Implements the fixed hand-off contract:
/// `PUT <endpoint>` with `Authorization: Bearer <secret>` and the JSON chip
/// bundle as body. 204 = success; 401/410 are terminal; network errors and
/// 5xx are retried with exponential backoff.
struct HTTPBundleUploader: BundleUploader {
    var urlSession: URLSession = .shared
    var maxAttempts: Int = 3
    /// Base backoff; attempt n waits `baseDelay * 2^(n-1)`. Tests shrink this.
    var baseDelay: Duration = .milliseconds(500)

    func upload(_ bundle: ChipBundle, to session: IssuerSession) async throws {
        var request = URLRequest(url: session.endpoint)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(session.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(bundle)

        var lastError: UploadError = .serverError(status: -1)
        for attempt in 1...max(1, maxAttempts) {
            if attempt > 1 {
                try await Task.sleep(for: baseDelay * (1 << (attempt - 2)))
            }
            do {
                let (_, response) = try await urlSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = .network("Non-HTTP response")
                    continue
                }
                switch http.statusCode {
                case 204, 200:
                    return
                case 401:
                    throw UploadError.invalidSecret
                case 410:
                    throw UploadError.sessionExpired
                default:
                    lastError = .serverError(status: http.statusCode)
                    continue // retry 5xx and anything else unexpected
                }
            } catch let error as UploadError {
                throw error
            } catch {
                lastError = .network(error.localizedDescription)
                continue
            }
        }
        throw lastError
    }
}

/// UI-test / preview uploader.
struct MockBundleUploader: BundleUploader {
    var result: Result<Void, UploadError> = .success(())

    func upload(_ bundle: ChipBundle, to session: IssuerSession) async throws {
        try await Task.sleep(for: .milliseconds(300))
        if case .failure(let error) = result { throw error }
    }
}
