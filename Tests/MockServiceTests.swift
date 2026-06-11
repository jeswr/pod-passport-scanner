import XCTest
@testable import PodPassportScanner

/// Exercises the Simulator/UI-test service doubles end-to-end so the mocked
/// chip-read and upload paths the app relies on in the Simulator are covered.
final class MockServiceTests: XCTestCase {
    func testMockChipReaderEmitsAllStagesAndParsesSample() async throws {
        let reader = MockChipReader(stageDelay: .zero)
        actor StageLog { var stages: [ChipReadStage] = []; func add(_ s: ChipReadStage) { stages.append(s) } }
        let log = StageLog()

        let result = try await reader.readChip(
            mrzKey: MRZKey(documentNumber: "L898902C3", dateOfBirth: "740812", dateOfExpiry: "120415")
        ) { stage in Task { await log.add(stage) } }

        // The bundle is the canonical synthetic "JANE DOE" fixture.
        XCTAssertEqual(result.summary.fullName, "JANE DOE")
        XCTAssertEqual(result.summary.documentNumber, "L898902C3")
        XCTAssertEqual(result.bundle.format, ChipBundle.ldsFormat)
        XCTAssertNotNil(result.bundle.lds.dg2)

        // Give the detached progress tasks a moment, then assert the stages.
        try await Task.sleep(for: .milliseconds(50))
        let stages = await log.stages
        XCTAssertTrue(stages.contains(.waitingForTag))
        XCTAssertTrue(stages.contains(.authenticating))
        XCTAssertTrue(stages.contains(.readingData))
        XCTAssertEqual(stages.last, .done)
    }

    func testMockUploaderSuccess() async throws {
        let uploader = MockBundleUploader(result: .success(()))
        try await uploader.upload(sampleBundle(), to: sampleSession())
    }

    func testMockUploaderFailurePropagates() async {
        let uploader = MockBundleUploader(result: .failure(.invalidSecret))
        do {
            try await uploader.upload(sampleBundle(), to: sampleSession())
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? UploadError, .invalidSecret)
        }
    }

    private func sampleBundle() -> ChipBundle {
        ChipBundle(lds: .init(dg1: Data("dg1".utf8), sod: Data("sod".utf8)))
    }

    private func sampleSession() -> IssuerSession {
        IssuerSession(
            endpoint: URL(string: "https://issuer.example/api/emrtd/sessions/x")!,
            sessionId: "x", secret: "y"
        )
    }
}
