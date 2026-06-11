import SwiftUI

/// Step 4: show exactly what was read and what will be sent before uploading.
struct ReviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let summary = model.chipResult?.summary {
                Section("Passport") {
                    HStack(spacing: 16) {
                        photo(summary.photoJPEG)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.fullName)
                                .font(.headline)
                                .accessibilityIdentifier("review.fullName")
                            Text(summary.nationality)
                                .foregroundStyle(.secondary)
                        }
                    }
                    row("Document number", summary.documentNumber, id: "review.documentNumber")
                    row("Date of birth", formatMRZDate(summary.dateOfBirth))
                    row("Expiry date", formatMRZDate(summary.dateOfExpiry))
                }
            }

            if let bundle = model.chipResult?.bundle {
                Section {
                    filesRow(bundle)
                } header: {
                    Text("What will be sent")
                } footer: {
                    Text("These chip files go to the issuer endpoint below — and nowhere else — so it can verify your passport's digital signature and issue your credential.")
                }

                if let session = model.session {
                    Section("Destination") {
                        row("Issuer endpoint", session.endpoint.absoluteString)
                        row("Session", session.sessionId)
                    }
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // Pinned primary action: on a credential-capture screen the
            // "send" decision must always be reachable, never scrolled away
            // below a long files/destination list.
            Button {
                model.confirmedForUpload()
            } label: {
                Text("Send to issuer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
            .accessibilityIdentifier("review.sendButton")
            .accessibilityHint("Sends the chip files shown above to the issuer endpoint.")
        }
    }

    private func photo(_ jpeg: Data?) -> some View {
        Group {
            if let jpeg, let image = UIImage(data: jpeg) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 84)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(jpeg == nil ? "No passport photo on chip" : "Passport photo from the chip")
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String, id: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let id {
                Text(value)
                    .accessibilityIdentifier(id)
                    .accessibilityLabel("\(label): \(value)")
            } else {
                Text(value)
                    .accessibilityLabel("\(label): \(value)")
            }
        }
    }

    private func filesRow(_ bundle: ChipBundle) -> some View {
        let files: [(String, String, Data?)] = [
            ("DG1", "Machine-readable zone", bundle.lds.dg1),
            ("DG2", "Facial photo", bundle.lds.dg2),
            ("DG11", "Additional personal details", bundle.lds.dg11),
            ("DG14", "Chip security info", bundle.lds.dg14),
            ("SOD", "Document security object (signature)", bundle.lds.sod),
        ]
        return ForEach(files.filter { $0.2 != nil }, id: \.0) { file in
            HStack {
                Text(file.0).font(.callout.monospaced())
                Text(file.1).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("\(file.2?.count ?? 0) B")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(file.0), \(file.1), \(file.2?.count ?? 0) bytes")
        }
    }

    /// `YYMMDD` → e.g. `12 Aug 1974` (century window: ≥ current YY+1 ⇒ 1900s for DOB-style dates).
    private func formatMRZDate(_ yymmdd: String) -> String {
        guard yymmdd.count == 6, yymmdd.allSatisfy(\.isNumber) else { return yymmdd }
        let yy = Int(yymmdd.prefix(2))!
        let mm = Int(yymmdd.dropFirst(2).prefix(2))!
        let dd = Int(yymmdd.dropFirst(4))!
        let currentYY = Calendar.current.component(.year, from: .now) % 100
        let year = yy <= currentYY + 10 ? 2000 + yy : 1900 + yy
        var components = DateComponents()
        components.year = year; components.month = mm; components.day = dd
        guard let date = Calendar.current.date(from: components) else { return yymmdd }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
