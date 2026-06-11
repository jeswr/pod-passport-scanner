import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Pod Passport Scanner")
                        .font(.largeTitle.bold())
                    Text("Prove your identity from your passport's chip and have a verifiable credential issued into your Solid pod.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    step(1, "Scan the QR code shown by the credential issuer in your browser.")
                    step(2, "Scan the machine-readable zone (MRZ) printed in your passport — it unlocks the chip.")
                    step(3, "Hold your iPhone on the passport to read the chip.")
                    step(4, "Review what was read, then send it to the issuer.")
                }

                GroupBox {
                    Label {
                        Text("Your passport data is sent **only** to the issuer endpoint you scanned — nowhere else. This app has no analytics and stores nothing after you finish.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                }

                #if DEBUG
                Toggle("Use sample passport (Simulator)", isOn: $model.useSamplePassport)
                    .font(.footnote)
                    .accessibilityIdentifier("home.sampleToggle")
                #endif

                Button {
                    model.start()
                } label: {
                    Text("Get started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("home.start")
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.bold())
                .frame(minWidth: 28, minHeight: 28) // grows with Dynamic Type
                .padding(4)
                .background(Circle().fill(.tint.opacity(0.15)))
            Text(text)
                .font(.callout)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}
