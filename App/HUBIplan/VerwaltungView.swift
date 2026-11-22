import AuthenticationServices
import HubiplanKern
import SwiftUI
import UIKit

/// Verwaltung für Vorstand und Zugführung: freischalten, entsperren, offene Punkte, Mitglieder.
/// Erreichbar über „Ich“. Der Inhalt ist nur sichtbar, solange der Vorstandsschlüssel offen ist.
struct VerwaltungView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var unitKey: String?
    /// Termin aus einer Kalenderdatei: statt der Übersicht die erste Einheit mit Terminrecht suchen
    var terminZiel: ((AdminUnit, Bool) -> Void)?

    var body: some View {
        Group {
            if let overview = model.adminOverview, !overview.allUnits.isEmpty {
                if !overview.twoFactor && !overview.passkey {
                    VerwaltungHinweis(
                        text: tr("Für die Verwaltung in der App ist die Zwei-Faktor-Anmeldung nötig. Bitte im Browser unter „Mein Konto › Anmeldung & Sicherheit“ einrichten, danach hier freischalten."),
                        action: tr("Mein Konto öffnen")
                    ) {
                        if let server = model.account?.server, let url = URL(string: server + "/mein-konto/anmeldung") { openURL(url) }
                    }
                } else if !model.adminSealed {
                    Freischalten(withCode: overview.twoFactor, withPasskey: overview.passkey)
                } else {
                    VerwaltungSchutz {
                        if let terminZiel {
                            TerminZielSuche(units: overview.allUnits, found: terminZiel)
                        } else {
                            VerwaltungStart(units: overview.allUnits, until: overview.until, unitKey: $unitKey)
                        }
                    }
                }
            } else if !model.adminLoaded {
                // Die Übersicht ist noch unterwegs: kein Fehlertext, bevor die Antwort da ist
                Laedt()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await model.loadAdmin() }
            } else {
                VerwaltungHinweis(
                    text: tr("Die Verwaltung ist gerade nicht verfügbar. Bitte Verbindung und Berechtigung prüfen."),
                    action: tr("Erneut versuchen")
                ) {
                    Task { await model.loadAdmin() }
                }
            }
        }
        .navigationTitle(tr("Verwaltung"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Auch bei offener Ansicht nach fünf Minuten Pause sperren
            while !Task.isCancelled {
                model.checkAdminIdle()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}

/// Erste Einheit, in der das Konto Termine anlegen darf (zuletzt gewählte zuerst wäre schöner,
/// die Reihenfolge der Übersicht genügt: Verein vor Untereinheiten).
private struct TerminZielSuche: View {
    @EnvironmentObject private var model: AppModel
    let units: [AdminUnit]
    let found: (AdminUnit, Bool) -> Void
    @State private var none = false

    var body: some View {
        Group {
            if none {
                Text(tr("Termine anlegen können nur Konten mit Verwaltungsrechten."))
                    .padding()
            } else {
                Laedt()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let today = Zeit.day(Date())
            for unit in units where unit.showsEvents {
                if let list = await model.verwaltung(unit, { try await $0.events(from: today, to: today) }), list.canManage {
                    found(unit, list.rsvpAllowed)
                    return
                }
            }
            none = true
        }
    }
}

private struct VerwaltungHinweis: View {
    let text: String
    let action: String
    let run: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                Button(action, action: run).buttonStyle(.bordered)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

/// Zeigt den Inhalt nur bei offenem Vorstandsschlüssel, sonst die Bitte zu entsperren.
/// Im App-Umschalter und bei inaktiver App ist der Inhalt verdeckt.
///
/// Sperrt die Verwaltung nach einer Pause, bleibt der Inhalt unter der Sperre erhalten und wird
/// nur abgedeckt (UX-Audit 16.11., IOS-10): Offene Blätter und Eingaben überstehen das
/// Entsperren. Blätter decken sich mit `verwaltungsBlatt()` selbst ab. Erst wenn der Schlüssel
/// ganz weg ist (Sperren auf dem Gerät, neu freischalten), fällt der Inhalt weg.
struct VerwaltungSchutz<Inhalt: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    @ViewBuilder let inhalt: () -> Inhalt
    /// Einmal geöffnet: Inhalt bleibt bei einer Pausensperre stehen
    @State private var geoeffnet = false

    var body: some View {
        if model.adminOpen || (geoeffnet && model.adminSealed) {
            inhalt()
                .simultaneousGesture(TapGesture().onEnded { model.adminTouched() })
                .allowsHitTesting(model.adminOpen)
                .accessibilityHidden(!model.adminOpen)
                .overlay {
                    if !model.adminOpen {
                        VerwaltungGesperrt()
                    } else if phase != .active && !Demo.active {
                        ZStack {
                            Color(.systemBackground)
                            Image(systemName: "lock.fill").font(.hubi(.largeTitle)).foregroundStyle(Color.secondary)
                        }
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    }
                }
                .onAppear { if model.adminOpen { geoeffnet = true } }
                .onChange(of: model.adminOpen) { _, open in if open { geoeffnet = true } }
        } else {
            VerwaltungGesperrt()
        }
    }
}

/// Bitte zu entsperren, deckend über dem Inhalt der Verwaltung.
struct VerwaltungGesperrt: View {
    @EnvironmentObject private var model: AppModel
    /// In einem Blatt: Schließen anbieten, wenn sich die Verwaltung nicht mehr entsperren lässt
    var close: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Zum Öffnen mit Face ID, Touch ID oder Gerätecode entsperren."))
                if let message = model.adminError { MeldungText(message, .fehler) }
                Button(tr("Entsperren")) { Task { await model.openAdmin() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.adminBusy || !model.adminSealed)
                if let close, !model.adminSealed {
                    Button(tr("Schließen"), action: close).buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color(.systemBackground))
        .task { await model.openAdmin() }
    }
}

/// Blatt der Verwaltung (IOS-10): bei gesperrter Verwaltung abgedeckt, Eingaben bleiben stehen.
/// Tippen und Schreiben im Blatt zählen als Bedienung und verlängern die fünf Minuten.
private struct VerwaltungsBlatt: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded { model.adminTouched() })
            .accessibilityHidden(!model.adminOpen)
            .overlay {
                if !model.adminOpen { VerwaltungGesperrt(close: { dismiss() }).ignoresSafeArea(.container, edges: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in model.adminTouched() }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification)) { _ in model.adminTouched() }
    }
}

extension View {
    /// Für Inhalte von `.sheet` und `.fullScreenCover` innerhalb der Verwaltung.
    func verwaltungsBlatt() -> some View { modifier(VerwaltungsBlatt()) }
}

private struct Freischalten: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.webAuthenticationSession) private var webAuthentication
    let withCode: Bool
    let withPasskey: Bool
    @State private var password = ""
    @State private var code = ""

    var body: some View {
        Form {
            if withPasskey {
                // Passkey über den eingebetteten Browser (iOS gibt ihn Apps nur für feste Adressen)
                Section {
                    Button {
                        Task {
                            await model.unlockAdminInBrowser { url in
                                do {
                                    return try await webAuthentication.authenticate(
                                        using: url,
                                        callbackURLScheme: PairingLink.scheme,
                                        preferredBrowserSession: .ephemeral
                                    )
                                } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                                    return nil
                                }
                            }
                        }
                    } label: {
                        if model.adminBusy { Laedt() } else { Label(tr("Mit Passkey freischalten"), systemImage: "person.badge.key") }
                    }
                    .disabled(model.adminBusy)
                } header: {
                    Text(tr("Verwaltung freischalten"))
                } footer: {
                    Text(tr("Öffnet die Anmeldeseite deines Vereins. Melde dich dort mit deinem Passkey an und tippe auf „Freischalten“."))
                }
            }
            if withCode {
                Section {
                    SecureField(tr("Passwort"), text: $password)
                        .weiterFeld()
                        .textContentType(.password)
                    TextField(tr("Code aus der Authenticator-App"), text: $code)
                        .submitLabel(.done)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: code) { _, value in
                            let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(8))
                            if digits != value { code = digits }
                        }
                } header: {
                    Text(withPasskey ? tr("Oder mit Passwort und Code") : tr("Verwaltung freischalten"))
                } footer: {
                    Text(tr("Für Mitglieder und offene Punkte in der App bitte mit Passwort und Zwei-Faktor-Code bestätigen. Die Freischaltung gilt 30 Tage auf diesem Gerät; geöffnet wird jedes Mal mit Face ID, Touch ID oder Gerätecode."))
                }
            }
            if let message = model.adminError {
                Section { MeldungText(message, .fehler) }
            }
            if !Demo.active && !VerwaltungTresor.deviceLock {
                Section {
                    Text(tr("Für die Verwaltung braucht das Gerät einen Gerätecode. Bitte in den Einstellungen einrichten."))
                        .foregroundStyle(.secondary)
                }
            }
            if withCode {
                Section {
                    Button {
                        let entered = (password, code)
                        password = ""
                        code = ""
                        Task { await model.unlockAdmin(password: entered.0, code: entered.1) }
                    } label: {
                        if model.adminBusy { Laedt() } else { Text(tr("Freischalten")) }
                    }
                    .disabled(model.adminBusy || password.isEmpty || code.count < 6)
                }
            }
        }
        .tastaturFuehrung()
    }
}

private struct VerwaltungStart: View {
    @EnvironmentObject private var model: AppModel
    let units: [AdminUnit]
    let until: String?
    @Binding var unitKey: String?
    @State private var open: Int?
    @State private var confirmLock = false
    /// Vorführmodus: für das Bildschirmfoto gleich in die Mitglieder
    @State private var showMembers = Demo.active && (["mitglieder"] + Demo.akteAbschnitte + Demo.aufnahmeAbschnitte).contains(Demo.section)
    @State private var showTasks = Demo.active && ["offen", "meldungen"].contains(Demo.section)
    @State private var showOccasions = Demo.active && Demo.section == "anlaesse"
    @State private var showEvents = Demo.active && ["vtermine", "vtermin", "neuertermin"].contains(Demo.section)
    @State private var showFinance = Demo.active && ["kasse", "buchung", "neuebuchung", "quittung", "entwuerfe"].contains(Demo.section)
    @State private var showTodos = Demo.active && ["vaufgaben", "vaufgabe", "neueaufgabe"].contains(Demo.section)
    @State private var showPartners = Demo.active && Demo.section == "partner"
    @State private var showQualifications = Demo.active && Demo.section == "qualifikationen"
    @State private var showObligations = Demo.active && ["fristen", "frist"].contains(Demo.section)
    @State private var showCompetitions = Demo.active && ["wettbewerbe", "standcode"].contains(Demo.section)
    @State private var showBilling = Demo.active && ["vrechnungen", "vrechnung"].contains(Demo.section)
    @State private var scanning = false
    @State private var check: Geprueft?

    private var unit: AdminUnit { units.first { $0.key == unitKey } ?? units[0] }

    var body: some View {
        List {
            Section {
                if units.count > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Einheit")).font(.hubi(.caption)).foregroundStyle(Color.secondary)
                        Picker(tr("Einheit"), selection: Binding(get: { unit.key }, set: { unitKey = $0 })) {
                            ForEach(units, id: \.key) { Text($0.name).tag($0.key) }
                        }
                        .labelsHidden()
                        .padding(.leading, -12)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Einheit")).font(.hubi(.caption)).foregroundStyle(Color.secondary)
                        Text(unit.name)
                    }
                }
            }
            VerwaltungMeldung()
            if unit.canCheckCards {
                Section {
                    Button {
                        scanning = true
                    } label: {
                        Label(tr("Ausweis prüfen"), systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            if !unit.isDepartment {
                Section {
                    KachelnUebersicht(
                        reloadKey: unit.key,
                        load: { await model.verwaltung(unit) { try await $0.tiles() } ?? nil },
                        save: { key, state in await model.verwaltung(unit) { try await $0.setTile(key: key, state: state) } ?? nil }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                if unit.sections.isEmpty {
                    Text(tr("Für deine Rolle gibt es in dieser Fassung der App noch keinen Bereich. Bitte nutze den Browser."))
                        .foregroundStyle(.secondary)
                }
                if unit.sections.contains(.tasks) {
                    NavigationLink {
                        OffenePunkteView(unit: unit)
                    } label: {
                        Bereich(
                            symbol: "tray.full",
                            title: open.map { tr("Zu erledigen ({count})", ["count": $0]) } ?? tr("Zu erledigen"),
                            hint: tr("Datenänderungen, Fotos und Termine, die auf dich warten")
                        )
                    }
                }
                if unit.sections.contains(.events) {
                    NavigationLink {
                        TermineVerwaltungView(unit: unit)
                    } label: {
                        Bereich(symbol: "calendar", title: tr("Termine"), hint: tr("Absagen, Rückmeldungen eintragen, neuer Termin"))
                    }
                }
                if unit.sections.contains(.todos) {
                    NavigationLink {
                        AufgabenVerwaltungView(unit: unit)
                    } label: {
                        Bereich(symbol: "checklist", title: tr("Aufgaben verteilen"), hint: tr("Aufgaben anlegen, erledigen und wieder öffnen"))
                    }
                }
                if unit.sections.contains(.obligations) {
                    NavigationLink {
                        FristenView(unit: unit)
                    } label: {
                        Bereich(symbol: "calendar.badge.exclamationmark", title: tr("Fristen"), hint: tr("Vereinspflichten mit Frist und Zuständigkeit"))
                    }
                }
                if unit.sections.contains(.members) {
                    NavigationLink {
                        MitgliederView(unit: unit)
                    } label: {
                        Bereich(symbol: "person.2", title: tr("Mitglieder"), hint: tr("Suchen, anrufen, Mitgliedsakte öffnen"))
                    }
                }
                if unit.sections.contains(.applications) {
                    NavigationLink {
                        AntraegeView(unit: unit)
                    } label: {
                        Bereich(symbol: "person.badge.plus", title: tr("Beitrittsanträge"), hint: tr("Anträge prüfen, zustimmen, aufnehmen oder ablehnen"))
                    }
                }
                if unit.sections.contains(.meetings) {
                    NavigationLink {
                        VersammlungenLeitenView(unit: unit)
                    } label: {
                        Bereich(symbol: "person.3", title: tr("Versammlung leiten"), hint: tr("Anwesenheit, Einlass per Ausweis, QR-Code, Abstimmungen"))
                    }
                }
                if unit.sections.contains(.bookings) {
                    NavigationLink {
                        BelegungFreigebenView(unit: unit)
                    } label: {
                        Bereich(symbol: "mappin.and.ellipse", title: tr("Belegung freigeben"), hint: tr("Anfragen für Räume und Plätze bestätigen oder ablehnen"))
                    }
                }
                if unit.sections.contains(.occasions) {
                    NavigationLink {
                        AnlaesseView(unit: unit)
                    } label: {
                        Bereich(symbol: "gift", title: tr("Jubiläen und Geburtstage"), hint: tr("Geburtstage und Jubiläen der nächsten Wochen"))
                    }
                }
                if unit.sections.contains(.qualifications) {
                    NavigationLink {
                        QualifikationenView(unit: unit)
                    } label: {
                        Bereich(symbol: "rosette", title: tr("Qualifikationen"), hint: tr("Nachweise, die bald ablaufen"))
                    }
                }
                if unit.sections.contains(.competitions) {
                    NavigationLink {
                        WettbewerbeView(unit: unit)
                    } label: {
                        Bereich(symbol: "trophy", title: tr("Wettbewerbe"), hint: tr("Ergebnisse am Stand erfassen, auch ohne Empfang"))
                    }
                }
                if unit.sections.contains(.finance) {
                    NavigationLink {
                        KassenbuchView(unit: unit)
                    } label: {
                        Bereich(symbol: "eurosign.circle", title: tr("Kassenbuch"), hint: tr("Kontostände, Buchungen, Beleg fotografieren"))
                    }
                }
                if unit.sections.contains(.billing) {
                    NavigationLink {
                        RechnungenView(unit: unit)
                    } label: {
                        Bereich(symbol: "doc.text", title: tr("Rechnungen"), hint: tr("Offene und bezahlte Rechnungen, bar kassieren"))
                    }
                }
                if unit.sections.contains(.partners) {
                    NavigationLink {
                        GeschaeftspartnerView(unit: unit)
                    } label: {
                        Bereich(symbol: "building.2", title: tr("Geschäftspartner"), hint: tr("Lieferanten, Sponsoren und Ansprechpartner nachschlagen"))
                    }
                }
            } header: {
                Text(tr("Was möchtest du tun?"))
            } footer: {
                Text(tr("Alles Weitere verwaltest du zurzeit im Browser."))
            }
            Section {
                Button(tr("Verwaltung auf diesem Gerät sperren"), role: .destructive) { confirmLock = true }
            } footer: {
                if let until, let date = Zeit.parse(until) {
                    Text(tr("Freigeschaltet bis {datum}", [
                        "datum": date.formatted(.dateTime.day().month().year().locale(Texte.locale)),
                    ]))
                }
            }
        }
        .navigationDestination(isPresented: $showMembers) { MitgliederView(unit: unit) }
        .navigationDestination(isPresented: $showTasks) { OffenePunkteView(unit: unit) }
        .navigationDestination(isPresented: $showOccasions) { AnlaesseView(unit: unit) }
        .navigationDestination(isPresented: $showEvents) { TermineVerwaltungView(unit: unit) }
        .navigationDestination(isPresented: $showFinance) { KassenbuchView(unit: unit) }
        .navigationDestination(isPresented: $showBilling) { RechnungenView(unit: unit) }
        .navigationDestination(isPresented: $showTodos) { AufgabenVerwaltungView(unit: unit) }
        .navigationDestination(isPresented: $showCompetitions) { WettbewerbeView(unit: unit) }
        .navigationDestination(isPresented: $showPartners) { GeschaeftspartnerView(unit: unit) }
        .navigationDestination(isPresented: $showQualifications) { QualifikationenView(unit: unit) }
        .navigationDestination(isPresented: $showObligations) { FristenView(unit: unit) }
        .sheet(isPresented: $scanning) {
            Group {
                AusweisScan(unit: unit) { result in
                    scanning = false
                    check = Geprueft(check: result)
                }
            }
            .verwaltungsBlatt()
        }
        .sheet(item: $check) { geprueft in Group { AusweisErgebnis(unit: unit, check: geprueft.check) }.verwaltungsBlatt() }
        .task {
            // Vorführmodus: für das Bildschirmfoto gleich das Ergebnis einer Prüfung
            guard Demo.active, Demo.section == "ausweispruefung" else { return }
            if let result = await model.verwaltung(unit, { try await $0.checkCard(code: "demo") }) { check = Geprueft(check: result) }
        }
        .refreshable { await load() }
        .task(id: unit.key) { await load() }
        // Kurzer Titel, Erklärung darunter (UX-Audit 16.11., IOS-23)
        .confirmationDialog(tr("Verwaltung sperren?"), isPresented: $confirmLock, titleVisibility: .visible) {
            Button(tr("Verwaltung sperren"), role: .destructive) { Task { await model.lockAdmin() } }
            Button(tr("Abbrechen"), role: .cancel) {}
        } message: {
            Text(tr("Danach musst du die Verwaltung mit Passwort und Zwei-Faktor-Code neu freischalten."))
        }
    }

    private func load() async {
        open = nil
        guard unit.sections.contains(.tasks) else { return }
        open = await model.verwaltung(unit) { try await $0.tasks().count }
    }
}

private struct Bereich: View {
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(hint).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }
}

/// Offene Punkte der Einheit wie auf der Startseite im Browser (nur lesen).
struct OffenePunkteView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var tasks: [AdminTask]?
    /// Vorführmodus: für das Bildschirmfoto gleich in die Datenänderungen
    @State private var showRequests = Demo.active && Demo.section == "meldungen"

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let tasks {
                    if tasks.isEmpty {
                        Text(tr("Nichts zu erledigen.")).foregroundStyle(.secondary)
                    } else {
                        Section {
                            ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                                switch task.target {
                                case .changeRequests:
                                    NavigationLink { AenderungenView(unit: unit) } label: { zeile(task) }
                                case let .member(id):
                                    NavigationLink { MitgliedView(unit: unit, id: id) } label: { zeile(task) }
                                case let .event(id):
                                    NavigationLink { TerminVerwaltungView(unit: unit, id: id, occurrence: nil) } label: { zeile(task) }
                                case let .application(id):
                                    NavigationLink { AntragView(unit: unit, id: id) } label: { zeile(task) }
                                case .bookings:
                                    NavigationLink { BelegungFreigebenView(unit: unit) } label: { zeile(task) }
                                case nil:
                                    zeile(task)
                                }
                            }
                        } footer: {
                            if tasks.contains(where: { $0.target == nil }) {
                                Text(tr("Punkte ohne Pfeil bearbeitest du zurzeit im Browser."))
                            }
                        }
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .navigationDestination(isPresented: $showRequests) { AenderungenView(unit: unit) }
        }
        .navigationTitle(tr("Zu erledigen"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func zeile(_ task: AdminTask) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !task.kindLabel.isEmpty {
                Text(task.kindLabel).font(.hubi(.caption)).foregroundStyle(Color.secondary)
            }
            Text(task.title)
            if !task.detail.isEmpty {
                Text(task.detail).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
            }
        }
    }

    private func load() async {
        if let loaded = await model.verwaltung(unit, { try await $0.tasks() }) { tasks = loaded }
    }
}

/// Mitglieder der Einheit suchen und die Akte öffnen (nur lesen).
struct MitgliederView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var search = ""
    @State private var former = false
    @State private var rows: [MemberRow]?
    @State private var count = 0
    @State private var page = 1
    @State private var more = false
    @State private var admitting = Demo.active && Demo.aufnahmeAbschnitte.contains(Demo.section)
    /// Vorführmodus: für das Bildschirmfoto gleich in eine Akte
    @State private var shown: Int? = Demo.active && Demo.akteAbschnitte.contains(Demo.section) ? 1 : nil

    var body: some View {
        VerwaltungSchutz {
            List {
                if !unit.isDepartment {
                    Picker(tr("Stand"), selection: $former) {
                        Text(tr("Aktuelle")).tag(false)
                        Text(tr("Ehemalige")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
                VerwaltungMeldung { await load(reset: true) }
                if let rows {
                    Section {
                        if rows.isEmpty {
                            Text(tr("Keine Mitglieder gefunden.")).foregroundStyle(.secondary)
                        }
                        ForEach(rows) { row in
                            NavigationLink {
                                MitgliedView(unit: unit, id: row.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.listName)
                                    if !row.listDetail.isEmpty {
                                        Text(row.listDetail).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        }
                        if more {
                            Button(tr("Weitere laden")) { Task { await load(reset: false) } }
                        }
                    } header: {
                        Text(trn("1 Mitglied", "{n} Mitglieder", count))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: tr("Name oder Mitgliedsnummer"))
            .task(id: "\(search)|\(former)") {
                // Beim Tippen kurz warten, damit nicht jeder Buchstabe eine Anfrage auslöst
                if rows != nil { try? await Task.sleep(for: .milliseconds(350)) }
                if !Task.isCancelled { await load(reset: true) }
            }
            .navigationDestination(item: $shown) { MitgliedView(unit: unit, id: $0) }
            .toolbar {
                if unit.canAdmitMembers {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            admitting = true
                        } label: {
                            Label(tr("Neues Mitglied"), systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $admitting) {
                Group {
                    AufnahmeBlatt(unit: unit) { member in
                        // Neue Akte gleich zeigen, Liste auffrischen
                        shown = member.id
                        Task { await load(reset: true) }
                    }
                }
                .verwaltungsBlatt()
            }
        }
        .navigationTitle(tr("Mitglieder"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load(reset: Bool) async {
        let wanted = reset ? 1 : page + 1
        let text = search
        let status = former ? "ehemalig" : "aktiv"
        guard let result = await model.verwaltung(unit, { try await $0.members(search: text, page: wanted, status: status) }) else { return }
        guard text == search, status == (former ? "ehemalig" : "aktiv") else { return }
        rows = reset ? result.results : (rows ?? []) + result.results
        count = result.count
        page = wanted
        more = result.hasMore
    }
}

/// Mitgliedsakte in Kurzform (nur lesen): Stammdaten, Zugehörigkeiten, Kontakt.
struct MitgliedView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let id: Int
    @State private var member: MemberDetail?
    @State private var photo: UIImage?
    @State private var pending: UIImage?
    @State private var busy = false
    @State private var editing = false
    @State private var vorgang: MitgliedVorgang?
    @State private var daten = AkteDaten()
    @State private var blatt: AkteBlatt?
    /// Vorführmodus: für das Bildschirmfoto nur die unteren Abschnitte der Akte
    private let nurMehr = Demo.active && Demo.section == "akte"

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let member, nurMehr {
                    AkteMehr(unit: unit, member: member, daten: daten, blatt: $blatt) { await load(full: true) }
                } else if let member {
                    if let pending, unit.canEditPhotos {
                        Section {
                            HStack(alignment: .top, spacing: 12) {
                                Image(uiImage: pending).resizable().scaledToFill()
                                    .frame(width: 105, height: 135).clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityLabel(tr("Neues Foto"))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(tr("Dieses Foto wartet auf deine Freigabe für den Ausweis."))
                                        .font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                    Button(tr("Freigeben")) { Task { await decide(approve: true) } }
                                        .buttonStyle(.borderedProminent)
                                    Button(tr("Ablehnen")) { Task { await decide(approve: false) } }
                                        .buttonStyle(.bordered)
                                }
                                .disabled(busy)
                            }
                        } header: {
                            Text(tr("Neues Foto"))
                        }
                    }
                    Section {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill()
                                .frame(width: 105, height: 135).clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel(tr("Foto"))
                        }
                        Text(member.name).font(.hubi(.title3).weight(.semibold))
                        if member.isFormer { Text(tr("Ehemaliges Mitglied")).foregroundStyle(.secondary) }
                        zeile(tr("Mitgliedsart"), member.typeName)
                        zeile(tr("Mitgliedsnummer"), member.clubNumber)
                        if !member.isOrganization { zeile(tr("Geburtsdatum"), Zeit.plainDate(member.birthDate)) }
                        zeile(tr("Mitglied seit"), Zeit.plainDate(member.entryDate))
                        zeile(tr("Untereinheiten"), member.departmentLabels(today: Zeit.day(Date())).joined(separator: ", "))
                    }
                    if let contact = member.contact {
                        Section(tr("Kontakt")) {
                            if !contact.phone.isEmpty {
                                verweis("phone", contact.phone, "tel:" + contact.phone.filter { $0.isNumber || $0 == "+" })
                            }
                            if !contact.email.isEmpty {
                                verweis("envelope", contact.email, "mailto:" + contact.email)
                            }
                            zeile(tr("Anschrift"), contact.addressLines.joined(separator: "\n"))
                        }
                    }
                    Section {
                        if unit.canEditMembers, !member.isFormer {
                            Button(unit.isDepartment ? tr("Kontaktdaten bearbeiten") : tr("Stammdaten und Kontakt ändern")) { editing = true }
                        }
                        if unit.canManageMembers, !member.isFormer {
                            Button(tr("Mitgliedsart wechseln")) { vorgang = .art }
                            Button(tr("Untereinheit wechseln")) { vorgang = .untereinheit }
                            // Schalter zeigt den Stand der Akte; umgelegt wird erst nach der Bestätigung
                            Toggle(tr("Zahlt Beitrag selbst"), isOn: Binding(
                                get: { member.paysFeeSelf },
                                set: { vorgang = $0 ? .beitragSelbst : .beitragFremd }
                            ))
                            Button(tr("Austritt eintragen"), role: .destructive) { vorgang = .austritt }
                        }
                        if unit.canManageMembers, member.isFormer {
                            Button(tr("Wiedereintritt eintragen")) { vorgang = .wiedereintritt }
                        }
                    } footer: {
                        Text(unit.isDepartment
                            ? tr("Alles Weitere ändert der Verein.")
                            : tr("Rechtsform, Ansprechpartner, Haushalte und alles Weitere änderst du zurzeit im Browser."))
                    }
                    AkteMehr(unit: unit, member: member, daten: daten, blatt: $blatt) { await load(full: true) }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .task {
                await load()
                // Vorführmodus: für das Bildschirmfoto gleich das Blatt zum Ändern
                if Demo.active, Demo.section == "stammdaten", member != nil { editing = true }
                if Demo.active, ["austritt", "folgen"].contains(Demo.section), member != nil { vorgang = .austritt }
                if Demo.active, member != nil {
                    switch Demo.section {
                    case "ehrung": blatt = .ehrung
                    case "zusatzfelder": blatt = .felder
                    case "bank": blatt = .bank
                    default: break
                    }
                }
            }
            .sheet(item: $blatt) { wanted in
                Group {
                    if let member {
                        AkteBlattView(unit: unit, member: member, blatt: wanted, fields: daten.fields) { await load() }
                    }
                }
                .verwaltungsBlatt()
            }
            .sheet(item: $vorgang) { wanted in
                Group {
                    if let member {
                        VorgangBlatt(unit: unit, member: member, vorgang: wanted) { updated in self.member = updated }
                    }
                }
                .verwaltungsBlatt()
            }
            .sheet(isPresented: $editing) {
                Group {
                    if let member {
                        StammdatenBlatt(unit: unit, member: member) { updated in self.member = updated }
                    }
                }
                .verwaltungsBlatt()
            }
        }
        .navigationTitle(tr("Mitgliedsakte"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func zeile(_ label: String, _ value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.hubi(.caption)).foregroundStyle(Color.secondary)
                Text(value)
            }
        }
    }

    @ViewBuilder
    private func verweis(_ symbol: String, _ text: String, _ link: String) -> some View {
        if let url = URL(string: link) {
            Link(destination: url) { Label(text, systemImage: symbol) }
        } else {
            Label(text, systemImage: symbol)
        }
    }

    private func load(full: Bool = false) async {
        let wanted = id
        guard let loaded = await model.verwaltung(unit, { try await $0.member(wanted) }) else { return }
        member = loaded
        // Ganze IBAN bleibt sichtbar, bis die Akte verlassen wird
        if let mehr = await AkteDaten.load(model, unit, member: wanted, full: full || daten.full) { daten = mehr }
        let paths = (loaded.photo, loaded.pendingPhoto)
        let images = await model.verwaltung(unit) { client -> (Data?, Data?) in
            var approved: Data?
            var waiting: Data?
            if let path = paths.0 { approved = await client.image(path) }
            if let path = paths.1 { waiting = await client.image(path) }
            return (approved, waiting)
        }
        photo = images?.0.flatMap { UIImage(data: $0) }
        pending = images?.1.flatMap { UIImage(data: $0) }
    }

    private func decide(approve: Bool) async {
        guard let member, !busy else { return }
        busy = true
        defer { busy = false }
        let wanted = id
        guard let change = await model.verwaltung(unit, { try await $0.decidePhoto(member: wanted, approve: approve) }) else { return }
        let text = approve
            ? tr("Foto von {name} freigegeben", ["name": member.name])
            : tr("Foto von {name} abgelehnt", ["name": member.name])
        model.adminChanged(unit, text: text, change: change)
        await load()
    }
}

/// Hinweis nach einer Änderung (mit „Rückgängig“) und Fehler, oben in den Listen der Verwaltung.
struct VerwaltungMeldung: View {
    @EnvironmentObject private var model: AppModel
    var reload: (() async -> Void)?

    var body: some View {
        if let message = model.adminError {
            Section {
                MeldungText(message, .fehler)
                if let reload { Button(tr("Erneut versuchen")) { Task { await reload() } } }
            }
        }
        if let notice = model.adminNotice {
            Section {
                MeldungText(notice, .gut)
                if model.adminUndo != nil {
                    Button(tr("Rückgängig")) {
                        Task {
                            if await model.undoAdmin(), let reload { await reload() }
                        }
                    }
                }
            }
        }
    }
}

/// Änderungsmeldungen der Mitglieder: übernehmen oder ablehnen.
struct AenderungenView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var items: [AdminChangeRequest]?
    @State private var busy = false
    @State private var conflict: Konflikt?

    private struct Konflikt: Identifiable {
        let request: AdminChangeRequest
        let text: String
        var id: Int { request.id }
    }

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let items {
                    if items.isEmpty {
                        Text(tr("Keine offenen Meldungen.")).foregroundStyle(.secondary)
                    }
                    ForEach(items) { request in
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.memberName).font(.hubi(.headline))
                                if let date = request.createdAt.flatMap(Zeit.parse) {
                                    Text(date.formatted(.dateTime.day().month().year().locale(Texte.locale)))
                                        .font(.hubi(.caption)).foregroundStyle(Color.secondary)
                                }
                                ForEach(request.lines, id: \.key) { Text($0.text) }
                                if !request.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(tr("„{text}“", ["text": request.message])).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                }
                            }
                            KnopfReihe(spacing: 12) {
                                Button(tr("Übernehmen")) { Task { await decide(request, accept: true) } }
                                    .buttonStyle(.borderedProminent)
                                Button(tr("Ablehnen")) { Task { await decide(request, accept: false) } }
                                    .buttonStyle(.bordered)
                            }
                            .disabled(busy)
                            NavigationLink(tr("Mitglied öffnen")) { MitgliedView(unit: unit, id: request.memberId) }
                        }
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .alert(tr("Inzwischen geändert"), isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } }), presenting: conflict) { open in
                Button(tr("Trotzdem übernehmen")) { Task { await decide(open.request, accept: true, overwrite: true) } }
                Button(tr("Abbrechen"), role: .cancel) {}
            } message: { open in
                Text(open.text)
            }
        }
        .navigationTitle(tr("Datenänderungen"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        if let loaded = await model.verwaltung(unit, { try await $0.changeRequests() }) { items = loaded }
    }

    private func decide(_ request: AdminChangeRequest, accept: Bool, overwrite: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        // 409 heißt: seit der Meldung im Verein geändert; dann erst nachfragen
        let result: Result<AdminChange, ApiError>? = await model.verwaltung(unit) { client in
            do {
                return .success(try await client.decide(request.id, accept: accept, overwrite: overwrite))
            } catch let failure as ApiError where failure.status == 409 {
                return .failure(failure)
            }
        }
        switch result {
        case let .success(change):
            let text = accept
                ? tr("Änderung von {name} übernommen", ["name": request.memberName])
                : tr("Änderung von {name} abgelehnt", ["name": request.memberName])
            model.adminChanged(unit, text: text, change: change)
            await load()
        case let .failure(failure):
            conflict = Konflikt(request: request, text: failure.message)
        case nil:
            break
        }
    }
}

/// Ergebnis einer Ausweisprüfung, für das Blatt.
struct Geprueft: Identifiable {
    let id = UUID()
    let check: CardCheck
}

/// QR-Code eines Mitgliedsausweises lesen und bei der Instanz prüfen.
private struct AusweisScan: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let found: (CardCheck) -> Void
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if QrScanner.available {
                    QrScanner { text in Task { await check(text) } }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(tr("Halte die Kamera auf den QR-Code des Mitgliedsausweises."))
                        .font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                } else {
                    KameraHinweis()
                    Spacer()
                }
                if busy { Laedt() }
                if let error { MeldungText(error, .fehler) }
            }
            .padding()
            .navigationTitle(tr("Ausweis prüfen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
            }
        }
    }

    private func check(_ code: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if let result = await model.verwaltung(unit, { try await $0.checkCard(code: code) }) {
            found(result)
        } else {
            error = model.adminError ?? tr("Der Ausweis ließ sich nicht prüfen. Bitte das Blatt schließen und erneut versuchen.")
        }
    }
}

/// Ergebnis der Ausweisprüfung: gültig oder nicht, mit Foto und Namen.
private struct AusweisErgebnis: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let check: CardCheck
    @State private var photo: UIImage?
    @State private var showMember = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Label(check.statusLabel, systemImage: check.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.hubi(.title2).weight(.semibold))
                        .foregroundStyle(check.valid ? Color.gutText : Color.fehlerText)
                    if let photo {
                        Image(uiImage: photo).resizable()
                            .aspectRatio(contentMode: check.isOrganization ? .fit : .fill)
                            .frame(width: check.isOrganization ? 180 : 140, height: check.isOrganization ? 120 : 180)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel(check.isOrganization ? tr("Logo") : tr("Foto"))
                    }
                    if check.isOrganization { Text(tr("Organisationsmitglied")).font(.hubi(.subheadline).weight(.semibold)) }
                    if !check.name.isEmpty { Text(check.name).font(.hubi(.title)) }
                    if !check.detail.isEmpty { Text(check.detail) }
                    if !check.departments.isEmpty {
                        Text(check.departments.joined(separator: ", ")).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                    }
                    if check.membership != nil, unit.showsMembers {
                        Button(tr("Akte öffnen")) { showMember = true }.buttonStyle(.bordered)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .navigationTitle(tr("Ausweis prüfen"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showMember) {
                if let id = check.membership { MitgliedView(unit: unit, id: id) }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Schließen")) { dismiss() } }
            }
            .task {
                if let path = check.photoUrl, let data = await model.publicImage(path) { photo = UIImage(data: data) }
            }
        }
    }
}


/// Blatt „Stammdaten und Kontakt“: gesendet werden nur geänderte Felder.
private struct StammdatenBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let member: MemberDetail
    let saved: (MemberDetail) -> Void
    @State private var values: [String: String] = [:]
    @State private var error: String?
    @State private var saving = false

    private var before: [String: String] { MasterData.values(member, department: unit.isDepartment) }
    private var keys: [String] { MasterData.keys(organization: member.isOrganization, department: unit.isDepartment) }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { MeldungText(error, .fehler) } }
                Section {
                    ForEach(keys, id: \.self) { key in
                        if key == "gender" {
                            Picker(tr("Geschlecht"), selection: binding(key)) {
                                Text(tr("keine Angabe")).tag("")
                                Text(tr("männlich")).tag("männlich")
                                Text(tr("weiblich")).tag("weiblich")
                                Text(tr("divers")).tag("divers")
                            }
                        } else {
                            BeschriftetesFeld(label: MasterData.label(key, organization: member.isOrganization), text: binding(key))
                                .keyboardType(keyboard(key))
                                .textInputAutocapitalization(key == "email" ? .never : .words)
                                .autocorrectionDisabled()
                        }
                    }
                } footer: {
                    if member.isOrganization, !unit.isDepartment {
                        Text(tr("Rechtsform, Zusatz und Ansprechpartner im Browser ändern."))
                    }
                }
            }
            .tastaturFuehrung()
            .disabled(saving)
            .navigationTitle(unit.isDepartment ? tr("Kontaktdaten") : tr("Stammdaten"))
            .navigationBarTitleDisplayMode(.inline)
            .eingabeschutz(!values.isEmpty && keys.contains { (values[$0] ?? "") != (before[$0] ?? "") }, disabled: saving)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Speichern")) { Task { await save() } }.disabled(saving)
                }
            }
            .onAppear { if values.isEmpty { values = before } }
        }
    }

    private func keyboard(_ key: String) -> UIKeyboardType {
        switch key {
        case "email": return .emailAddress
        case "phone": return .phonePad
        case "postal_code", "birth_date": return .numbersAndPunctuation
        default: return .default
        }
    }

    private func save() async {
        error = nil
        guard let changes = MasterData.changes(before: before, after: values) else {
            error = tr("Bitte das Geburtsdatum als TT.MM.JJJJ eingeben.")
            return
        }
        if changes.isEmpty {
            dismiss()
            return
        }
        saving = true
        defer { saving = false }
        let id = member.id
        guard let result = await model.verwaltung(unit, { try await $0.update(member: id, values: changes) }) else {
            error = model.adminError
            return
        }
        model.adminChanged(unit, text: tr("Gespeichert"), change: result.change)
        saved(result.member)
        dismiss()
    }
}

/// Geburtstage der nächsten 30 und Jubiläen der nächsten 90 Tage.
struct AnlaesseView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var birthdays: [BirthdayRow]?
    @State private var jubilees: [JubileeRow]?

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let birthdays, let jubilees {
                    Section(tr("Geburtstage (30 Tage)")) {
                        if birthdays.isEmpty { Text(tr("Keine.")).foregroundStyle(.secondary) }
                        ForEach(Array(birthdays.enumerated()), id: \.offset) { _, row in
                            NavigationLink {
                                MitgliedView(unit: unit, id: row.memberId)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                    Text(tr("{datum} · wird {alter}", ["datum": Zeit.plainDate(row.date), "alter": row.age]))
                                        .font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }
                    Section(tr("Jubiläen (90 Tage)")) {
                        if jubilees.isEmpty { Text(tr("Keine.")).foregroundStyle(.secondary) }
                        ForEach(Array(jubilees.enumerated()), id: \.offset) { _, row in
                            NavigationLink {
                                MitgliedView(unit: unit, id: row.memberId)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                    Text(tr("{datum} · {jahre} Jahre {einheit}", ["datum": Zeit.plainDate(row.date), "jahre": row.years, "einheit": row.organization])
                                        .trimmingCharacters(in: .whitespaces))
                                        .font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Jubiläen und Geburtstage"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let today = Date()
        let short = MasterData.upcoming(today: today, days: 30)
        let long = MasterData.upcoming(today: today, days: 90)
        let result = await model.verwaltung(unit) { client in
            (try await client.birthdays(from: short.from, to: short.to), try await client.jubilees(from: long.from, to: long.to))
        }
        if let result {
            birthdays = result.0
            jubilees = result.1
        }
    }
}
