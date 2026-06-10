import Foundation

/// The exact payload PUT to the issuer's upload endpoint (and the structure of
/// the issuer-side test fixture `emrtd-bundle.json`):
///
/// ```json
/// {
///   "format": "icao-9303-lds1",
///   "lds": {
///     "dg1": "<b64>", "dg2": "<b64, optional>",
///     "dg11": "<b64, optional>", "dg14": "<b64, optional>",
///     "sod": "<b64>"
///   }
/// }
/// ```
///
/// `Data` fields encode/decode as base64 strings via `Codable`'s default
/// `Data` strategy, which matches the contract.
struct ChipBundle: Codable, Equatable, Sendable {
    static let ldsFormat = "icao-9303-lds1"

    struct LDS: Codable, Equatable, Sendable {
        let dg1: Data
        let dg2: Data?
        let dg11: Data?
        let dg14: Data?
        let sod: Data

        init(dg1: Data, dg2: Data? = nil, dg11: Data? = nil, dg14: Data? = nil, sod: Data) {
            self.dg1 = dg1
            self.dg2 = dg2
            self.dg11 = dg11
            self.dg14 = dg14
            self.sod = sod
        }
    }

    let format: String
    let lds: LDS

    init(lds: LDS) {
        self.format = Self.ldsFormat
        self.lds = lds
    }

    /// Extracts the 88-character TD3 MRZ string from the raw DG1 bytes
    /// (`61 L 5F1F L <mrz>`). Used to populate the review screen.
    var mrzFromDG1: String? {
        guard lds.dg1.count >= 88 else { return nil }
        let tail = lds.dg1.suffix(88)
        return String(data: tail, encoding: .ascii)
    }
}

/// Human-readable summary of what was read, shown on the review screen
/// before anything is uploaded.
struct PassportSummary: Equatable, Sendable {
    let fullName: String
    let documentNumber: String
    let nationality: String
    let dateOfBirth: String // YYMMDD
    let dateOfExpiry: String // YYMMDD
    let photoJPEG: Data?
}

/// Everything a `ChipReader` hands back after a successful read.
struct ChipReadResult: Equatable, Sendable {
    let bundle: ChipBundle
    let summary: PassportSummary
}
