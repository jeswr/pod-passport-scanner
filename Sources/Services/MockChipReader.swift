import Foundation

/// Simulator / UI-test chip reader: loads the bundled synthetic eMRTD bundle
/// (`SamplePassport/emrtd-bundle.json` — same structure as the issuer-side
/// test fixture) instead of touching NFC. Ignores the MRZ key.
struct MockChipReader: ChipReader {
    /// Delay between stages so the progress UI is visible. Zero in UI tests.
    var stageDelay: Duration = .milliseconds(600)

    func readChip(
        mrzKey: MRZKey,
        progress: @escaping @Sendable (ChipReadStage) -> Void
    ) async throws -> ChipReadResult {
        let bundle = try Self.loadSampleBundle()

        for stage in [ChipReadStage.waitingForTag, .authenticating, .readingData] {
            progress(stage)
            try await Task.sleep(for: stageDelay)
        }

        guard let mrz = bundle.mrzFromDG1,
              let parsed = try? MRZParser.parseTD3(contiguous: mrz) else {
            throw ChipReaderError.missingMandatoryFile("DG1 (sample bundle has no parseable MRZ)")
        }

        let summary = PassportSummary(
            fullName: parsed.fullName,
            documentNumber: parsed.documentNumber,
            nationality: parsed.nationality,
            dateOfBirth: parsed.dateOfBirth,
            dateOfExpiry: parsed.dateOfExpiry,
            photoJPEG: nil // the synthetic DG2 is not a real image
        )

        progress(.done)
        return ChipReadResult(bundle: bundle, summary: summary)
    }

    static func loadSampleBundle() throws -> ChipBundle {
        guard let url = Bundle.main.url(
            forResource: "emrtd-bundle", withExtension: "json", subdirectory: nil
        ) else {
            throw ChipReaderError.readFailed("Sample bundle emrtd-bundle.json missing from app bundle")
        }
        return try JSONDecoder().decode(ChipBundle.self, from: Data(contentsOf: url))
    }
}
