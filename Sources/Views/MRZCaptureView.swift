import SwiftUI
import AVFoundation
import Vision

/// Step 2: read the printed MRZ (the two lines at the bottom of the photo
/// page) with the camera. The document number, date of birth and expiry date
/// derive the BAC/PACE key that unlocks the chip. Manual entry fallback —
/// also the default in the Simulator (no camera) and UI tests.
struct MRZCaptureView: View {
    @Environment(AppModel.self) private var model
    @State private var manualEntry = false

    private var cameraAvailable: Bool {
        !model.isUITest && AVCaptureDevice.default(for: .video) != nil
    }

    var body: some View {
        Group {
            if manualEntry || !cameraAvailable {
                ManualMRZEntryView()
            } else {
                VStack(spacing: 0) {
                    MRZCameraRepresentable { parsed in
                        model.mrzCaptured(parsed.key)
                    }
                    VStack(spacing: 12) {
                        Text("Frame the two lines of letters and numbers at the bottom of your passport's photo page.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Enter details manually") { manualEntry = true }
                            .accessibilityIdentifier("mrz.manualButton")
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Scan passport page")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Manual fallback: the three MRZ-key fields.
struct ManualMRZEntryView: View {
    @Environment(AppModel.self) private var model
    @State private var documentNumber = ""
    @State private var dateOfBirth = ""
    @State private var dateOfExpiry = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Document number", text: $documentNumber)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .accessibilityIdentifier("mrz.docNumberField")
                TextField("Date of birth (YYMMDD)", text: $dateOfBirth)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("mrz.dobField")
                TextField("Expiry date (YYMMDD)", text: $dateOfExpiry)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("mrz.expiryField")
            } header: {
                Text("Passport details")
            } footer: {
                Text("Exactly as printed in the machine-readable zone. These derive the key that unlocks the chip — they never leave your device.")
            }

            if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }

            Button("Continue") {
                let key = MRZKey(
                    documentNumber: documentNumber.trimmingCharacters(in: .whitespaces).uppercased(),
                    dateOfBirth: dateOfBirth.trimmingCharacters(in: .whitespaces),
                    dateOfExpiry: dateOfExpiry.trimmingCharacters(in: .whitespaces)
                )
                if key.bacKeyString == nil {
                    error = "Check the values: dates must be six digits (YYMMDD) and the document number may only contain letters and digits."
                } else {
                    model.mrzCaptured(key)
                }
            }
            .disabled(documentNumber.isEmpty || dateOfBirth.count != 6 || dateOfExpiry.count != 6)
            .accessibilityIdentifier("mrz.continueButton")
        }
    }
}

/// Camera preview + Vision text recognition tuned for TD3 MRZ lines.
private struct MRZCameraRepresentable: UIViewControllerRepresentable {
    let onMRZ: @MainActor (ParsedMRZ) -> Void

    func makeUIViewController(context: Context) -> MRZCameraViewController {
        let controller = MRZCameraViewController()
        controller.onMRZ = onMRZ
        return controller
    }

    func updateUIViewController(_ controller: MRZCameraViewController, context: Context) {}
}

final class MRZCameraViewController: UIViewController {
    /// Called on the main actor with the first checksum-valid parse.
    var onMRZ: (@MainActor (ParsedMRZ) -> Void)?
    private var deliveredResult = false

    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "org.jeswr.podpassport.mrz-video")
    private var delegate: MRZFrameDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        // SE-0434: a @MainActor closure may capture main-actor state and be @Sendable.
        let deliver: @MainActor @Sendable (ParsedMRZ) -> Void = { [weak self] parsed in
            guard let self, !self.deliveredResult else { return }
            self.deliveredResult = true
            self.onMRZ?(parsed)
        }
        let delegate = MRZFrameDelegate(onMRZ: deliver)
        self.delegate = delegate
        output.setSampleBufferDelegate(delegate, queue: videoQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // AVCaptureSession is thread-safe for start/stop but not Sendable-annotated.
        nonisolated(unsafe) let session = self.session
        videoQueue.async { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        nonisolated(unsafe) let session = self.session
        videoQueue.async { session.stopRunning() }
    }
}

/// Runs Vision OCR on a throttled subset of frames and looks for a pair of
/// 44-character TD3 lines whose check digits validate.
private final class MRZFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onMRZ: @MainActor @Sendable (ParsedMRZ) -> Void
    // Only touched on the single serial video queue.
    private var lastProcessed = Date.distantPast
    private var found = false

    init(onMRZ: @escaping @MainActor @Sendable (ParsedMRZ) -> Void) {
        self.onMRZ = onMRZ
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !found, Date().timeIntervalSince(lastProcessed) > 0.4 else { return }
        lastProcessed = Date()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return }

        let candidates = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .map(MRZParser.normalizeOCRLine)
            .filter { $0.count == 44 && $0.unicodeScalars.allSatisfy(MRZParser.allowedCharacters.contains) }

        guard candidates.count >= 2 else { return }
        for i in 0..<(candidates.count - 1) {
            if let parsed = try? MRZParser.parseTD3(line1: candidates[i], line2: candidates[i + 1]) {
                found = true
                let deliver = onMRZ
                Task { await deliver(parsed) }
                return
            }
        }
    }
}
