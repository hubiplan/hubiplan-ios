import AuthenticationServices
import HubiplanKern
import SwiftUI

/// Erster Bildschirm: mit der HUBIplan-Instanz des Vereins verbinden.
struct VerbindenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var link = ""
    @State private var scanning = false
    @State private var server = ""
    @Environment(\.webAuthenticationSession) private var webAuthentication

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tr("Mit deinem Verein verbinden")).font(.title2.bold())
                    Text(tr("Öffne HUBIplan im Browser: Mein Konto › App & andere Instanzen › App auf dem Telefon. Scanne den QR-Code mit der Kamera oder füge den Link hier ein."))
                }
                if QrScanner.available {
                    Section {
                        Button {
                            scanning = true
                        } label: {
                            Label(tr("QR-Code scannen"), systemImage: "qrcode.viewfinder")
                        }
                    }
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
                // Passkey: Anmeldung im eingebetteten Browser der Instanz (docs/app.md in hubiplan)
                Section {
                    TextField(tr("Adresse von HUBIplan"), text: $server, prompt: Text("verein.example.de"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .accessibilityIdentifier("server")
                    Button {
                        Task { await passkey() }
                    } label: {
                        Label(tr("Mit Passkey anmelden"), systemImage: "person.badge.key")
                    }
                    .disabled(server.trimmingCharacters(in: .whitespaces).isEmpty || model.loading)
                    .accessibilityIdentifier("passkey")
                } footer: {
                    Text(tr("Öffnet die Anmeldeseite deines Vereins. Melde dich dort mit deinem Passkey an und tippe auf „Verbinden“."))
                }
                Section {
                    Text(tr("Version {version}", ["version": AppModel.version]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("HUBIplan")
            .overlay { if model.loading { ProgressView() } }
            .sheet(isPresented: $scanning) {
                QrScanner { text in
                    scanning = false
                    model.offer(link: text)
                }
                .ignoresSafeArea()
            }
            .toolbar {
                if model.adding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Abbrechen")) { model.adding = false }
                    }
                }
            }
            .verbindenFrage(aktiv: true)
        }
    }

    /// Anmeldeseite der Instanz öffnen; mit dem zurückgegebenen Einmalcode gleich verbinden.
    private func passkey() async {
        guard let url = BrowserLogin.url(server: server) else {
            model.linkError = tr("Bitte die Adresse von HUBIplan angeben, z. B. verein.example.de.")
            return
        }
        do {
            // Ohne gemeinsame Cookies mit Safari: es bleibt keine Browser-Sitzung zurück
            let callback = try await webAuthentication.authenticate(
                using: url,
                callbackURLScheme: PairingLink.scheme,
                preferredBrowserSession: .ephemeral
            )
            guard let link = BrowserLogin.pairing(callback: callback, server: server) else {
                model.linkError = tr("Die Anmeldung kam nicht von dieser Adresse zurück. Bitte erneut versuchen.")
                return
            }
            // Selbst angestoßen und an die eingegebene Adresse gebunden: ohne weitere Rückfrage
            model.offer(link: callback.absoluteString)
            if model.pending == link { await model.connect() }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Abgebrochen: nichts tun
        } catch {
            model.linkError = tr("Die Anmeldeseite ließ sich nicht öffnen. Bitte erneut versuchen.")
        }
    }
}

/// Vor dem Verbinden die Adresse der Instanz zeigen und nachfragen.
private struct VerbindenFrage: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let aktiv: Bool

    func body(content: Content) -> some View {
        content.alert(
            tr("Mit {server} verbinden?", ["server": model.pending?.server ?? ""]),
            isPresented: Binding(get: { aktiv && model.pending != nil }, set: { if !$0 { model.pending = nil } })
        ) {
            Button(tr("Verbinden")) { Task { await model.connect() } }
            Button(tr("Abbrechen"), role: .cancel) { model.pending = nil }
        } message: {
            Text(tr("Die App spricht danach nur mit dieser Adresse. Verbinde dich nur, wenn das die Adresse deines Vereins ist."))
        }
    }
}

extension View {
    /// `aktiv` ist nur an der Stelle wahr, die gerade sichtbar ist (sonst fragten zwei Stellen zugleich).
    func verbindenFrage(aktiv: Bool) -> some View { modifier(VerbindenFrage(aktiv: aktiv)) }
}
