import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: FlowStep.self) { step in
                    switch step {
                    case .scanQR: QRScanView()
                    case .mrzCapture: MRZCaptureView()
                    case .nfcRead: NFCReadView()
                    case .review: ReviewView()
                    case .upload: UploadView()
                    case .done: DoneView()
                    }
                }
        }
    }
}
