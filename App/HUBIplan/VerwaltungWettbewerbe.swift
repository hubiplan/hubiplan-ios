import HubiplanKern
import SwiftUI
import WebKit

/// Laufender Standmodus in der App (Adresse mit Standzugang, Instanz, Titel).
struct StandSitzung: Identifiable {
    let id = UUID()
    let url: String
    let server: String
    let title: String
}

private struct StandCode: Identifiable {
    let id = UUID()
    let title: String
    let link: String
}

/// Bereich „Wettbewerbe“: eigene, nicht abgeschlossene Wettbewerbe; Standmodus öffnen,
/// QR-Code für ein weiteres Gerät, Standzugang beenden.
struct WettbewerbeView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var rows: [AdminCompetition]?
    @State private var accesses: [Int: [StandAccess]] = [:]
    @State private var busy = false
    @State private var error: String?
    @State private var code: StandCode?
    @State private var stand: StandSitzung?
    @State private var scanning = false
    @State private var demoShown = false
    @State private var ending: (AdminCompetition, [StandAccess])?

    var body: some View {
        VerwaltungSchutz {
            List {
                Section {
                    if QrScanner.available {
                        Button {
                            scanning = true
                        } label: {
                            Label(tr("Stand-QR scannen"), systemImage: "qrcode.viewfinder")
                        }
                    } else {
                        KameraHinweis()
                    }
                } footer: {
                    Text(tr("Im Standmodus erfasst du Ergebnisse direkt vor Ort, auch ohne Empfang, und kannst ein Foto auswerten lassen. Neue Wettbewerbe legst du im Browser an."))
                }
                VerwaltungMeldung { await load() }
                if let error { Section { MeldungText(error, .fehler) } }
                if let rows {
                    if rows.isEmpty {
                        Section {
                            Text(tr("Keine offenen Wettbewerbe. Abgeschlossene Wettbewerbe stehen im Browser.")).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(rows) { competition in
                        let active = accesses[competition.id] ?? []
                        Section {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(competition.title).font(.hubi(.headline))
                                if !competition.line.isEmpty {
                                    Text(competition.line).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                }
                                if !active.isEmpty {
                                    Text(tr("Aktive Standzugänge: {n}", ["n": active.count])).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                }
                            }
                            Button(tr("Standmodus öffnen")) { Task { await open(competition) } }
                            Button(tr("QR-Code für weiteres Gerät")) { Task { await share(competition) } }
                            if !active.isEmpty {
                                // Rückfrage: Geräte am Stand verlieren sofort den Zugang (IOS-23)
                                Button(tr("Standzugang beenden"), role: .destructive) { ending = (competition, active) }
                            }
                        }
                        .disabled(busy)
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Wettbewerbe"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanning) {
            Group {
                StandScan { text in
                    scanning = false
                    scanned(text)
                }
            }
            .verwaltungsBlatt()
        }
        .sheet(item: $code) { code in Group { StandCodeBlatt(code: code) }.verwaltungsBlatt() }
        .fullScreenCover(item: $stand) { StandmodusView(session: $0) }
        .confirmationDialog(
            tr("Standzugang beenden?"),
            isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }),
            titleVisibility: .visible
        ) {
            Button(tr("Standzugang beenden"), role: .destructive) {
                if let target = ending { Task { await end(target.0, target.1) } }
                ending = nil
            }
            Button(tr("Abbrechen"), role: .cancel) { ending = nil }
        } message: {
            Text(tr("Geräte am Stand können danach nichts mehr erfassen."))
        }
    }

    private func load() async {
        error = nil
        let result = await model.verwaltung(unit) { client -> ([AdminCompetition], [Int: [StandAccess]]) in
            let open = AdminCompetition.open(try await client.competitions(), today: Zeit.day(Date()))
            var found: [Int: [StandAccess]] = [:]
            for competition in open {
                // Die Zahl der Zugänge ist nur ein Hinweis; ohne sie bleibt die Liste nutzbar
                found[competition.id] = (try? await client.standAccesses(competition: competition.id)) ?? []
            }
            return (open, found)
        }
        guard let result else { return }
        rows = result.0
        accesses = result.1
        // Vorführmodus: für das Bildschirmfoto gleich der QR-Code des ersten Wettbewerbs
        if Demo.active, Demo.section == "standcode", !demoShown, let first = result.0.first {
            demoShown = true
            await share(first)
        }
    }

    /// Gültigen Standzugang dieses iPhones nehmen oder neu anlegen.
    private func zugang(_ competition: AdminCompetition, label: String, reuse: Bool) async -> StandAccess? {
        let store = model.standStore
        if reuse, let store, let stored = store.get(unit: unit, competition: competition.id) {
            // Auf dem Server schon beendet: nicht weiter verwenden
            if accesses[competition.id]?.contains(where: { $0.id == stored.id }) ?? true { return stored }
            store.remove(unit: unit, competition: competition.id)
        }
        let id = competition.id
        guard let created = await model.verwaltung(unit, { try await $0.createStandAccess(competition: id, label: label) }) else { return nil }
        if reuse { store?.put(unit: unit, competition: id, access: created) }
        var listed = created
        listed.token = nil
        accesses[id, default: []].append(listed)
        return created
    }

    private func open(_ competition: AdminCompetition) async {
        guard !busy, let server = model.account?.server else { return }
        busy = true
        defer { busy = false }
        let label = tr("App ({name})", ["name": UIDevice.current.name])
        guard let access = await zugang(competition, label: label, reuse: true), let token = access.token else { return }
        stand = StandSitzung(url: StandLink.url(server: server, token: token), server: server, title: competition.title)
    }

    private func share(_ competition: AdminCompetition) async {
        guard !busy, let server = model.account?.server else { return }
        busy = true
        defer { busy = false }
        guard let access = await zugang(competition, label: tr("Weiteres Gerät"), reuse: false), let token = access.token else { return }
        code = StandCode(title: competition.title, link: StandLink.url(server: server, token: token))
    }

    private func end(_ competition: AdminCompetition, _ active: [StandAccess]) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let id = competition.id
        let done: Bool? = await model.verwaltung(unit) { client in
            for access in active { try await client.endStandAccess(competition: id, access: access.id) }
            return true
        }
        model.standStore?.remove(unit: unit, competition: id)
        if done == true {
            accesses[id] = []
            model.adminDone(tr("Standzugang beendet"))
        } else {
            let message = model.adminError
            await load()
            if model.adminError == nil { model.adminError = message }
        }
    }

    private func scanned(_ text: String) {
        guard let link = StandLink.parse(text) else {
            error = tr("Das ist kein Stand-QR-Code.")
            return
        }
        guard link.server == model.account?.server else {
            error = tr("Der QR-Code gehört zu einer anderen HUBIplan-Adresse.")
            return
        }
        error = nil
        stand = StandSitzung(url: link.url, server: link.server, title: tr("Standmodus"))
    }
}

/// QR-Code eines Standzugangs für ein weiteres Gerät; erscheint nur einmal.
private struct StandCodeBlatt: View {
    @Environment(\.dismiss) private var dismiss
    let code: StandCode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(tr("Mit dem anderen Gerät scannen (HUBIplan-App oder Kamera). Der Zugang gilt bis zum Ende des Wettbewerbstags und kann nur erfassen. Der Code erscheint nur jetzt."))
                    if let image = qrImage(code.link) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .padding(12)
                            .background(Color.white)
                            .accessibilityLabel(tr("QR-Code für den Standzugang"))
                    }
                }
                .padding()
            }
            .navigationTitle(code.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { dismiss() } }
            }
        }
    }
}

/// Stand-QR mit der Kamera lesen.
private struct StandScan: View {
    @Environment(\.dismiss) private var dismiss
    let found: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                QrScanner(found: found)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(tr("Halte die Kamera auf den QR-Code des Standzugangs."))
                    .font(.hubi(.footnote)).foregroundStyle(Color.secondary)
            }
            .padding()
            .navigationTitle(tr("Stand-QR scannen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
            }
        }
    }
}

/// Standmodus der Instanz im Vollbild: dieselbe Oberfläche wie im Browser. Die Ansicht lädt nur
/// Seiten der eigenen Instanz, gibt nur ihr die Kamera und hält den Bildschirm wach. Schließen
/// fragt nach, wenn noch Eingaben auf dem Gerät auf die Übertragung warten.
struct StandmodusView: View {
    @Environment(\.dismiss) private var dismiss
    let session: StandSitzung
    @StateObject private var page = StandSeite()
    @State private var pending: Int?

    var body: some View {
        NavigationStack {
            StandWeb(session: session, page: page)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(session.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            Task { await leave() }
                        } label: {
                            Label(tr("Standmodus schließen"), systemImage: "xmark")
                        }
                    }
                }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert(
            tr("Eingaben noch nicht übertragen"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button(tr("Weiter erfassen"), role: .cancel) { pending = nil }
            Button(tr("Trotzdem schließen"), role: .destructive) {
                pending = nil
                dismiss()
            }
        } message: {
            Text(trn(
                "Eine Eingabe wartet noch auf die Übertragung. Sie bleibt bis zu zwölf Stunden auf dem Gerät und wird beim nächsten Öffnen des Standmodus mit Empfang übertragen.",
                "{n} Eingaben warten noch auf die Übertragung. Sie bleiben bis zu zwölf Stunden auf dem Gerät und werden beim nächsten Öffnen des Standmodus mit Empfang übertragen.",
                pending ?? 0
            ))
        }
    }

    private func leave() async {
        let count = await page.waiting()
        if count > 0 { pending = count } else { dismiss() }
    }
}

/// Hält die Webansicht, damit „Schließen“ die Warteschlange des Standmodus fragen kann.
@MainActor
final class StandSeite: ObservableObject {
    weak var web: WKWebView?

    /// Zahl der Eingaben, die noch nicht übertragen sind (`window.hubiplanStand.pending()`).
    func waiting() async -> Int {
        guard let web else { return 0 }
        let script = "(function(){try{return window.hubiplanStand?window.hubiplanStand.pending():0}catch(e){return 0}})()"
        let result = try? await web.evaluateJavaScript(script)
        if let number = result as? NSNumber { return max(0, number.intValue) }
        return 0
    }
}

private struct StandWeb: UIViewRepresentable {
    let session: StandSitzung
    let page: StandSeite

    func makeCoordinator() -> Coordinator { Coordinator(server: session.server) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsLinkPreview = false
        page.web = web
        if let url = URL(string: session.url), StandLink.sameInstance(server: session.server, url: session.url) {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let server: String

        init(server: String) { self.server = server }

        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = action.request.url else {
                decisionHandler(.cancel)
                return
            }
            if StandLink.sameInstance(server: server, url: url.absoluteString) || url.scheme == "about" || url.scheme == "blob" {
                decisionHandler(.allow)
                return
            }
            // Fremde Links (Hilfe, Impressum anderer Seiten) im Browser öffnen
            if action.navigationType == .linkActivated, url.scheme == "https" { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }

        /// Neue Fenster gibt es nicht: Links der eigenen Instanz laden in derselben Ansicht.
        func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
            for action: WKNavigationAction, windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = action.request.url {
                if StandLink.sameInstance(server: server, url: url.absoluteString) {
                    webView.load(action.request)
                } else if url.scheme == "https" {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        /// Kamera nur für die eigene Instanz; das Mikrofon nie.
        func webView(
            _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            let port = origin.port == 0 ? "" : ":\(origin.port)"
            let own = StandLink.sameInstance(server: server, url: "\(origin.protocol)://\(origin.host)\(port)")
            decisionHandler(own && type == .camera && frame.isMainFrame ? .grant : .deny)
        }
    }
}
