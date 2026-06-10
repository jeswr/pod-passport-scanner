import SwiftUI

/// Final step: the issuer has the bundle; the user continues in the browser.
struct DoneView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Passport sent")
                .font(.title.bold())
                .accessibilityIdentifier("done.title")

            Text("Return to your browser to continue. The issuer is verifying your passport and will mint the credential into your Solid pod.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                model.reset()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding()
            .accessibilityIdentifier("done.resetButton")
        }
        .navigationBarBackButtonHidden(true)
    }
}
