import HubiplanKern
import SwiftUI

/// Erster Bildschirm: mit der HUBIplan-Instanz des Vereins verbinden.
struct VerbindenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var link = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tr("Öffne HUBIplan im Browser: Mein Konto › App & andere Instanzen › App auf dem Telefon. Scanne den QR-Code mit der Kamera oder füge den Link hier ein."))
                }
                Section {
                    TextField(tr("Link aus dem QR-Code"), text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("link")
                    if let message = model.linkError {
                        Text(message).foregroundStyle(.red)
                    }
                    Button(tr("Verbinden")) { model.offer(link: link) }
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || model.loading)
                        .accessibilityIdentifier("verbinden")
                }
                Section {
                    Text(tr("Version {version}", ["version": AppModel.version]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("Mit deinem Verein verbinden"))
            .overlay { if model.loading { ProgressView() } }
            // Vor dem Verbinden die Adresse der Instanz zeigen und nachfragen
            .alert(
                tr("Mit {server} verbinden?", ["server": model.pending?.server ?? ""]),
                isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })
            ) {
                Button(tr("Verbinden")) { Task { await model.connect() } }
                Button(tr("Abbrechen"), role: .cancel) { model.pending = nil }
            } message: {
                Text(tr("Die App spricht danach nur mit dieser Adresse. Verbinde dich nur, wenn das die Adresse deines Vereins ist."))
            }
        }
    }
}
