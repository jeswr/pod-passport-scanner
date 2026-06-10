import Foundation
import Observation

/// The linear issuance flow.
enum FlowStep: Hashable, Sendable {
    case scanQR
    case mrzCapture
    case nfcRead
    case review
    case upload
    case done
}

/// Central state for the flow, owned by the root `NavigationStack`.
@MainActor
@Observable
final class AppModel {
    var path: [FlowStep] = []

    // Collected along the flow.
    var session: IssuerSession?
    var mrzKey: MRZKey?
    var chipResult: ChipReadResult?

    // Service injection points (protocols so the Simulator runs the full flow).
    var chipReader: any ChipReader
    var uploader: any BundleUploader

    /// Debug-only "Use sample passport": swaps in `MockChipReader` and skips
    /// real MRZ-derived keying. Toggleable from the Home screen in DEBUG.
    var useSamplePassport: Bool {
        didSet { chipReader = Self.makeChipReader(mock: useSamplePassport, fast: isUITest) }
    }

    let isUITest: Bool

    init(processInfo: ProcessInfo = .processInfo) {
        let arguments = processInfo.arguments
        let isUITest = arguments.contains("--uitest")
        var mockChip = arguments.contains("--mock-chip") || isUITest
        let mockUpload = arguments.contains("--mock-upload") || isUITest
        #if targetEnvironment(simulator)
        mockChip = true // the Simulator has no NFC
        #endif

        self.isUITest = isUITest
        self.useSamplePassport = mockChip
        self.chipReader = Self.makeChipReader(mock: mockChip, fast: isUITest)
        self.uploader = mockUpload ? MockBundleUploader() : HTTPBundleUploader()
    }

    private static func makeChipReader(mock: Bool, fast: Bool) -> any ChipReader {
        #if canImport(CoreNFC) && !targetEnvironment(simulator)
        if !mock { return NFCChipReader() }
        #endif
        return MockChipReader(stageDelay: fast ? .zero : .milliseconds(600))
    }

    // MARK: Flow transitions

    func start() {
        session = nil
        mrzKey = nil
        chipResult = nil
        path = [.scanQR]
    }

    func sessionCaptured(_ session: IssuerSession) {
        self.session = session
        path.append(.mrzCapture)
    }

    func mrzCaptured(_ key: MRZKey) {
        self.mrzKey = key
        path.append(.nfcRead)
    }

    func chipRead(_ result: ChipReadResult) {
        self.chipResult = result
        path.append(.review)
    }

    func confirmedForUpload() {
        path.append(.upload)
    }

    func uploadSucceeded() {
        path.append(.done)
    }

    func reset() {
        path = []
        session = nil
        mrzKey = nil
        chipResult = nil
    }
}
