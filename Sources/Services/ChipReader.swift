import Foundation

/// Coarse progress stages surfaced in the in-app UI while the chip is read.
/// (On a real device the system NFC sheet also shows fine-grained progress.)
enum ChipReadStage: String, Equatable, Sendable, CaseIterable {
    case waitingForTag = "Hold your iPhone on the passport"
    case authenticating = "Establishing secure session (PACE/BAC)"
    case readingData = "Reading chip data"
    case done = "Read complete"
}

enum ChipReaderError: Error, LocalizedError {
    case invalidMRZKey
    case nfcUnavailable
    case missingMandatoryFile(String)
    case readFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidMRZKey:
            return "The document number, date of birth or expiry date is invalid. Check the values and try again."
        case .nfcUnavailable:
            return "NFC is not available on this device. A real iPhone (7 or later) is required to read the chip."
        case .missingMandatoryFile(let f):
            return "The chip did not return the mandatory \(f) file."
        case .readFailed(let message):
            return message
        case .cancelled:
            return "Reading was cancelled."
        }
    }
}

/// Abstraction over the NFC chip read so the full flow runs in the Simulator
/// (which has no NFC) against `MockChipReader`.
protocol ChipReader: Sendable {
    /// Reads DG1, SOD and — when present — DG2/DG11/DG14 from the chip.
    /// `progress` may be called from any executor.
    func readChip(
        mrzKey: MRZKey,
        progress: @escaping @Sendable (ChipReadStage) -> Void
    ) async throws -> ChipReadResult
}
