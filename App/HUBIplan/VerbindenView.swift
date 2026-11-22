import AuthenticationServices
import HubiplanKern
import SwiftUI

/// Erster Bildschirm: mit der HUBIplan-Instanz des Vereins verbinden.
struct VerbindenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var link = ""
    @State private var scanning = false
    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var missing: [LoginField] = []
    @FocusState private var focus: Feld?
    @Environment(\.webAuthenticationSession) private var webAuthentication
    @Environment(\.openURL) private var openURL

    private enum Feld: Hashable { case link, server, email, password, code }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tr("Mit deinem Verein verbinden")).font(.hubi(.title2).bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(tr("Es gibt drei Wege. Nimm den, der für dich am einfachsten ist."))
                }
                if let message = model.linkError {
                    Section { MeldungText(message, .fehler) }
                }
                if model.pendingLogin != nil {
                    zweiterFaktor
                } else {
                    passwortWeg
                    browserWeg
                    qrWeg
                }
                UeberDieApp()
            }
            .tastaturFuehrung()
            .navigationTitle("HUBIplan")
            .disabled(model.loading)
            .alert(
                tr("Bei dieser Adresse anmelden?"),
                isPresented: Binding(
                    get: { model.browserStart.map { !model.isKnown(server: $0) } ?? false },
                    set: { if !$0 { model.browserStart = nil } }
                )
            ) {
                Button(tr("Ja, im Browser anmelden")) { startBrowser() }
                Button(tr("Abbrechen"), role: .cancel) { model.browserStart = nil }
            } message: {
                Text((model.browserStart ?? "").replacingOccurrences(of: "https://", with: "") + "\n\n"
                    + tr("Melde dich nur an, wenn das die Adresse deines Vereins ist und du den Link selbst gerade im Browser geöffnet hast."))
            }
            .onChange(of: model.browserStart) { _, start in
                // Schon verbundene Adresse: ohne Rückfrage
                if let start, model.isKnown(server: start) { startBrowser() }
            }
            .overlay { if model.loading { Laedt(text: tr("Wird verbunden …")) } }
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
                        Button(tr("Abbrechen")) {
                            model.pendingLogin = nil
                            model.adding = false
                        }
                    }
                }
            }
            .verbindenFrage(aktiv: true)
        }
    }

    /// Weg 1: E-Mail und Passwort (wie in der Android-App)
    @ViewBuilder
    private var passwortWeg: some View {
        Section {
            TextField(tr("Adresse von HUBIplan"), text: $server, prompt: Text("verein.example.de"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.next)
                .focused($focus, equals: .server)
                .onSubmit { focus = .email }
                .accessibilityIdentifier("server")
            if missing.contains(.server) {
                MeldungText(tr("Bitte die Adresse von HUBIplan angeben, z. B. verein.example.de."), .fehler).font(.hubi(.footnote))
            }
            TextField(tr("E-Mail"), text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .submitLabel(.next)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
            if missing.contains(.email) {
                MeldungText(tr("Bitte deine E-Mail-Adresse eingeben."), .fehler).font(.hubi(.footnote))
            }
            SecureField(tr("Passwort"), text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit { anmelden() }
            if missing.contains(.password) {
                MeldungText(tr("Bitte dein Passwort eingeben."), .fehler).font(.hubi(.footnote))
            }
            Button(tr("Anmelden")) { anmelden() }
                .accessibilityIdentifier("anmelden")
            if let reset = Anmeldung.passwordReset(server: server) {
                Button(tr("Passwort vergessen? Im Browser zurücksetzen")) { openURL(reset) }
                    .font(.hubi(.footnote))
            }
        } header: {
            Text(tr("Mit E-Mail und Passwort"))
        } footer: {
            Text(tr("Dieselben Zugangsdaten wie auf der Seite deines Vereins. Die App merkt sich dein Passwort nicht."))
        }
    }

    /// Zweiter Faktor nach der Anmeldung mit Passwort
    @ViewBuilder
    private var zweiterFaktor: some View {
        Section {
            Text(tr("Bitte den Code aus deiner Authenticator-App oder einen Wiederherstellungscode eingeben."))
            TextField(tr("Code"), text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .code)
                .onSubmit { pruefen() }
            Button(tr("Bestätigen")) { pruefen() }
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(tr("Zurück"), role: .cancel) {
                model.pendingLogin = nil
                code = ""
            }
        } header: {
            Text(tr("Zweiter Schritt"))
        }
        .onAppear { focus = .code }
    }

    /// Weg 2: Anmeldeseite des Vereins im Browser (Passwort oder Passkey)
    @ViewBuilder
    private var browserWeg: some View {
        Section {
            Button {
                Task { await passkey() }
            } label: {
                Label(tr("Im Browser anmelden"), systemImage: "safari")
            }
            .accessibilityIdentifier("passkey")
        } header: {
            Text(tr("Im Browser"))
        } footer: {
            Text(tr("Mit Passwort oder Passkey auf der Seite deines Vereins (Adresse oben eintragen); danach kommst du automatisch zurück."))
        }
    }

    /// Weg 3: QR-Code oder Link aus „Mein Konto“ im Browser
    @ViewBuilder
    private var qrWeg: some View {
        Section {
            if QrScanner.available {
                Button {
                    scanning = true
                } label: {
                    Label(tr("QR-Code von einem anderen Bildschirm scannen"), systemImage: "qrcode.viewfinder")
                }
            } else {
                KameraHinweis(alternative: tr("Oder füge den Link aus dem QR-Code hier ein."))
            }
            TextField(tr("Link aus dem QR-Code"), text: $link, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($focus, equals: .link)
                .onSubmit { model.offer(link: link) }
                .accessibilityIdentifier("link")
            Button(tr("Verbinden")) { model.offer(link: link) }
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("verbinden")
        } header: {
            Text(tr("Mit QR-Code"))
        } footer: {
            Text(tr("Öffne HUBIplan im Browser: Mein Konto › App & andere Instanzen. Scanne den QR-Code oder kopiere den Link. Nur ein Gerät? Öffne HUBIplan im Browser des Geräts und tippe dort auf „In der HUBIplan-App öffnen“."))
        }
    }

    private func anmelden() {
        missing = Anmeldung.missing(server: server, email: email, password: password)
        if let first = missing.first {
            switch first {
            case .server: focus = .server
            case .email: focus = .email
            case .password: focus = .password
            }
            return
        }
        focus = nil
        let secret = password
        Task {
            await model.login(server: server, email: email, password: secret)
            password = ""
        }
    }

    private func pruefen() {
        let entered = code
        code = ""
        Task { await model.loginCode(entered) }
    }

    /// Anmeldeseite der Adresse aus `hubiplan://anmelden` öffnen.
    private func startBrowser() {
        guard let start = model.browserStart else { return }
        model.browserStart = nil
        server = start.replacingOccurrences(of: "https://", with: "")
        Task { await passkey() }
    }

    /// Anmeldeseite der Instanz öffnen; mit dem zurückgegebenen Einmalcode gleich verbinden.
    private func passkey() async {
        // Prüfwert (Gesamtaudit 15.11., APP-01): den Code löst nur diese App ein
        let verifier = BrowserLogin.newVerifier()
        guard let url = BrowserLogin.url(server: server, challenge: BrowserLogin.challenge(verifier: verifier)),
              let origin = normalizeServer(server) else {
            missing = [.server]
            focus = .server
            return
        }
        model.linkError = nil
        model.pendingVerifier = (server: origin, verifier: verifier)
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
