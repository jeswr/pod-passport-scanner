import Foundation
#if canImport(CoreNFC)
import CoreNFC
import NFCPassportReader
import UIKit

/// Real chip reader backed by AndyQ/NFCPassportReader (MIT).
/// Performs PACE with BAC fallback, then reads DG1, DG2, DG11, DG14
/// (each only when listed in the chip's COM) and the SOD.
///
/// Only usable on a physical iPhone — the Simulator has no NFC hardware;
/// use `MockChipReader` there.
struct NFCChipReader: ChipReader {
    func readChip(
        mrzKey: MRZKey,
        progress: @escaping @Sendable (ChipReadStage) -> Void
    ) async throws -> ChipReadResult {
        guard NFCTagReaderSession.readingAvailable else {
            throw ChipReaderError.nfcUnavailable
        }
        guard let bacKey = mrzKey.bacKeyString else {
            throw ChipReaderError.invalidMRZKey
        }

        progress(.waitingForTag)
        let reader = PassportReader()
        let passport: NFCPassportModel
        do {
            progress(.authenticating)
            passport = try await reader.readPassport(
                mrzKey: bacKey,
                tags: [.DG1, .DG2, .DG11, .DG14, .SOD]
            )
        } catch let error as NFCPassportReaderError {
            if case .UserCanceled = error { throw ChipReaderError.cancelled }
            throw ChipReaderError.readFailed(String(describing: error))
        } catch {
            throw ChipReaderError.readFailed(error.localizedDescription)
        }

        progress(.readingData)
        guard let dg1 = passport.getDataGroup(.DG1)?.data else {
            throw ChipReaderError.missingMandatoryFile("DG1")
        }
        guard let sod = passport.getDataGroup(.SOD)?.data else {
            throw ChipReaderError.missingMandatoryFile("SOD (Document Security Object)")
        }

        let bundle = ChipBundle(lds: .init(
            dg1: Data(dg1),
            dg2: passport.getDataGroup(.DG2).map { Data($0.data) },
            dg11: passport.getDataGroup(.DG11).map { Data($0.data) },
            dg14: passport.getDataGroup(.DG14).map { Data($0.data) },
            sod: Data(sod)
        ))

        let summary = PassportSummary(
            fullName: [passport.firstName, passport.lastName]
                .filter { !$0.isEmpty }.joined(separator: " "),
            documentNumber: passport.documentNumber,
            nationality: passport.nationality,
            dateOfBirth: passport.dateOfBirth,
            dateOfExpiry: passport.documentExpiryDate,
            photoJPEG: passport.passportImage?.jpegData(compressionQuality: 0.85)
        )

        progress(.done)
        return ChipReadResult(bundle: bundle, summary: summary)
    }
}
#endif
