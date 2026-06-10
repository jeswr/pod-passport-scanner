import SwiftUI

/// Step 3: read the chip. Shows guidance (iPhone on passport) and coarse
/// progress; on a real device the system NFC sheet sits on top of this.
struct NFCReadView: View {
    @Environment(AppModel.self) private var model
    @State private var stage: ChipReadStage?
    @State private var error: String?
    @State private var reading = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            GuidanceAnimation(active: reading)

            VStack(spacing: 8) {
                Text("Read the chip")
                    .font(.title2.bold())
                Text("Close the passport, remove any thick case, and rest the top half of your iPhone flat on the front cover.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            if let stage {
                Label(stage.rawValue, systemImage: stage == .done ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.callout)
                    .foregroundStyle(stage == .done ? .green : .secondary)
                    .accessibilityIdentifier("nfc.progressLabel")
            }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("nfc.errorLabel")
            }

            Spacer()

            Button {
                read()
            } label: {
                Text(reading ? "Reading…" : (error == nil ? "Start reading" : "Try again"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(reading)
            .accessibilityIdentifier("nfc.startButton")
            .padding()
        }
        .navigationTitle("Chip")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func read() {
        guard let mrzKey = model.mrzKey else { return }
        reading = true
        error = nil
        let reader = model.chipReader
        Task {
            do {
                let result = try await reader.readChip(mrzKey: mrzKey) { stage in
                    Task { @MainActor in self.stage = stage }
                }
                reading = false
                model.chipRead(result)
            } catch {
                reading = false
                stage = nil
                self.error = error.localizedDescription
            }
        }
    }
}

/// Simple looping "rest your iPhone on the passport" animation.
private struct GuidanceAnimation: View {
    let active: Bool
    @State private var lowered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.45, green: 0.12, blue: 0.22))
                .frame(width: 150, height: 200)
                .overlay(alignment: .top) {
                    Text("PASSPORT")
                        .font(.caption2.bold())
                        .kerning(2)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 22)
                }
                .overlay {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.85))
                }

            Image(systemName: "iphone.gen3")
                .font(.system(size: 90))
                .foregroundStyle(.primary)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                .offset(y: lowered ? -20 : -90)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: lowered)
        }
        .frame(height: 240)
        .onAppear { lowered = true }
        .accessibilityHidden(true)
    }
}
