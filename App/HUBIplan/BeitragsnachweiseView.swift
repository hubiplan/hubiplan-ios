import HubiplanKern
import SwiftUI
import UniformTypeIdentifiers

// „Ich“ › Beitragsnachweise, wie in der Android-App: Stand je Beitragsjahr sehen und den
// Nachweis für einen ermäßigten Beitrag als Foto oder PDF einreichen. Fotos werden verkleinert
// und ohne Aufnahmedaten gesendet (BelegBild), nichts bleibt auf dem Gerät.

struct BeitragsnachweiseView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let overview = model.feeProofs ?? FeeProofOverview()
        List {
            if let message = model.error {
                Section { Text(message).foregroundStyle(.red) }
            }
            Section {
                Text(tr("Für einen ermäßigten Beitrag braucht der Verein jedes Jahr einen aktuellen Nachweis, zum Beispiel eine Immatrikulationsbescheinigung. Ohne Nachweis gilt der normale Beitrag."))
                    .foregroundStyle(.secondary)
            }
            if overview.states.isEmpty {
                Text(tr("Gerade ist kein Nachweis nötig."))
            }
            ForEach(overview.states) { state in
                NachweisJahr(state: state)
            }
            if !overview.proofs.isEmpty {
                Section {
                    ForEach(overview.proofs) { proof in
                        VStack(alignment: .leading, spacing: 4) {
                            Text([proof.discountName, proof.yearLabel, proof.receivedOn.map(Zeit.plainDate) ?? "", proof.fileName]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                            Text(proof.statusLabel).font(.footnote).foregroundStyle(.secondary)
                            if !proof.note.isEmpty {
                                Text(proof.note).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(tr("Eingereichte Nachweise"))
                }
            }
        }
        .navigationTitle(tr("Beitragsnachweise"))
        .task { await model.reloadFeeProofs() }
        .refreshable { await model.reloadFeeProofs() }
    }
}

/// Ein Beitragsjahr einer Ermäßigung: Stand, Frist und (solange nicht anerkannt) Einreichen.
private struct NachweisJahr: View {
    @EnvironmentObject private var model: AppModel
    let state: FeeYearState
    @State private var photo: Data?
    @State private var pdf: (name: String, data: Data)?
    @State private var kind = ""
    @State private var note = ""
    @State private var choosingPdf = false
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?

    var body: some View {
        Section {
            Text(state.sentence)
            if let notice {
                Text(notice).foregroundStyle(.green)
            }
            if state.canSubmit {
                if let photo, let image = UIImage(data: photo) {
                    HStack {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 72, height: 72)
                            .accessibilityLabel(tr("Nachweis"))
                        Spacer()
                        Button(tr("Entfernen"), role: .destructive) { self.photo = nil }
                    }
                } else if let pdf {
                    HStack {
                        Label(pdf.name, systemImage: "doc")
                        Spacer()
                        Button(tr("Entfernen"), role: .destructive) { self.pdf = nil }
                    }
                } else {
                    BelegWahl(again: false) { jpeg in
                        failure = nil
                        photo = jpeg
                    } failed: { message in
                        failure = message
                    }
                    Button {
                        choosingPdf = true
                    } label: {
                        Label(tr("PDF wählen"), systemImage: "doc")
                    }
                }
                if !state.kinds.isEmpty {
                    Picker(tr("Art des Nachweises"), selection: $kind) {
                        Text(tr("ohne Angabe")).tag("")
                        ForEach(state.kinds, id: \.self) { Text($0).tag($0) }
                    }
                }
                TextField(tr("Bemerkung (freiwillig)"), text: $note, axis: .vertical)
                if let failure {
                    Text(failure).foregroundStyle(.red)
                }
                Button(tr("Nachweis einreichen")) { Task { await send() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || (photo == nil && pdf == nil))
            }
        } header: {
            Text("\(state.discountName) · \(state.yearLabel)")
        } footer: {
            Text(state.label)
        }
        .fileImporter(isPresented: $choosingPdf, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                load(url)
            case .failure:
                failure = tr("Die Datei ließ sich nicht öffnen.")
            }
        }
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            failure = tr("Die Datei ließ sich nicht öffnen.")
            return
        }
        guard data.count <= feeProofMaxBytes else {
            failure = tr("Die Datei ist zu groß (höchstens 10 MB).")
            return
        }
        failure = nil
        pdf = (url.lastPathComponent, data)
    }

    private func send() async {
        let file: (name: String, type: String, data: Data)
        if let photo {
            file = ("nachweis.jpg", "image/jpeg", photo)
        } else if let pdf {
            file = (pdf.name, "application/pdf", pdf.data)
        } else {
            return
        }
        busy = true
        failure = nil
        defer { busy = false }
        let discount = state.discount
        let year = state.year
        let chosenKind = kind
        let text = note
        switch await model.portalCall({ api, access in
            try await api.submitFeeProof(accessId: access, discount: discount, year: year,
                                         kind: chosenKind, note: text, fileName: file.name, type: file.type, data: file.data)
        }) {
        case .success(let fresh):
            photo = nil
            pdf = nil
            note = ""
            notice = tr("Danke! Dein Nachweis ist eingegangen.")
            model.feeProofs = fresh
        case .failure(let error):
            failure = error.status == 0
                ? tr("Ohne Verbindung: Die Angaben bleiben hier stehen. Bitte später erneut senden.")
                : error.text
        case nil:
            break
        }
    }
}
