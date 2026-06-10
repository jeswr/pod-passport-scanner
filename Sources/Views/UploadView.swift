import SwiftUI

/// Step 5: PUT the chip bundle to the issuer endpoint.
struct UploadView: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?
    @State private var uploading = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if uploading {
                ProgressView()
                    .controlSize(.large)
                Text("Sending to the issuer…")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("upload.progressLabel")
            } else if let error {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Upload failed")
                    .font(.title3.bold())
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("upload.errorLabel")

                Button {
                    upload()
                } label: {
                    Text("Retry")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .accessibilityIdentifier("upload.retryButton")
            }

            Spacer()
        }
        .navigationTitle("Upload")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(uploading)
        .task { upload() }
    }

    private func upload() {
        guard let bundle = model.chipResult?.bundle, let session = model.session else { return }
        uploading = true
        error = nil
        let uploader = model.uploader
        Task {
            do {
                try await uploader.upload(bundle, to: session)
                uploading = false
                model.uploadSucceeded()
            } catch {
                uploading = false
                self.error = error.localizedDescription
            }
        }
    }
}
