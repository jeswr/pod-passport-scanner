import SwiftUI
import VisionKit

/// Step 1: capture the issuer session from the QR code shown in the browser,
/// with a manual-entry fallback (also the default where the camera/DataScanner
/// is unavailable, e.g. the Simulator).
struct QRScanView: View {
    @Environment(AppModel.self) private var model
    @State private var manualEntry = false
    @State private var scanError: String?

    private var scannerAvailable: Bool {
        !model.isUITest
            && DataScannerViewController.isSupported
            && DataScannerViewController.isAvailable
    }

    var body: some View {
        Group {
            if manualEntry || !scannerAvailable {
                ManualSessionEntryView()
            } else {
                VStack(spacing: 0) {
                    QRScannerRepresentable { payload in
                        handle(payload)
                    }
                    .ignoresSafeArea(edges: .horizontal)

                    VStack(spacing: 12) {
                        if let scanError {
                            Text(scanError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                        Text("Point the camera at the QR code on the issuer page.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Enter details manually") { manualEntry = true }
                            .accessibilityIdentifier("qr.manualButton")
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Scan issuer code")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handle(_ payload: String) {
        do {
            let session = try QRPayloadDecoder.decode(payload)
            model.sessionCaptured(session)
        } catch {
            scanError = error.localizedDescription
        }
    }
}

/// Manual fallback for the same three fields the QR code carries.
struct ManualSessionEntryView: View {
    @Environment(AppModel.self) private var model
    @State private var endpoint = ""
    @State private var sessionId = ""
    @State private var secret = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Upload URL (https://…)", text: $endpoint)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("qr.endpointField")
                TextField("Session ID", text: $sessionId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("qr.sessionIdField")
                TextField("Secret", text: $secret)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("qr.secretField")
            } header: {
                Text("Issuer session")
            } footer: {
                Text("The issuer page shows these values next to the QR code.")
            }

            if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }

            Button("Continue") {
                submit()
            }
            .disabled(endpoint.isEmpty || sessionId.isEmpty || secret.isEmpty)
            .accessibilityIdentifier("qr.continueButton")
        }
    }

    private func submit() {
        // Route through the same decoder so validation is identical to QR.
        let payload: [String: Any] = [
            "v": 1,
            "endpoint": endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            "sessionId": sessionId.trimmingCharacters(in: .whitespacesAndNewlines),
            "secret": secret.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        do {
            let json = try JSONSerialization.data(withJSONObject: payload)
            let session = try QRPayloadDecoder.decode(String(decoding: json, as: UTF8.self))
            model.sessionCaptured(session)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// VisionKit DataScanner limited to QR codes.
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var delivered = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    delivered = true
                    onScan(value)
                    return
                }
            }
        }
    }
}
