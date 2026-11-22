import HubiplanKern
import SwiftUI

struct HauptView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    /// „Mein Konto“ liegt im Reiter „Ich“ (das iPhone zeigt höchstens fünf Reiter)
    @State private var tab = Demo.tab == "konto" ? "ausweis" : Demo.tab
    /// Zuletzt gewählter Reiter, übersteht das Beenden durch das System (UX-Audit 16.11., IOS-25)
    @SceneStorage("gewaehlterReiter") private var savedTab = ""

    private var availableTabs: [String] {
        var tabs = Zustand.festeReiter
        if model.accesses.contains(where: { $0.hasTodos || $0.hasHelpers }) { tabs.append("aufgaben") }
        if model.accesses.contains(where: { $0.hasScores }) { tabs.append("noten") }
        return tabs
    }
    @State private var exportURL: URL?

    var body: some View {
        TabView(selection: $tab) {
            TermineView()
                .tabItem { Label(tr("Termine"), systemImage: "calendar") }
                .tag("termine")
            MitteilungenView()
                .tabItem { Label(tr("Neues"), systemImage: "envelope") }
                // Zahl der ungelesenen Mitteilungen (IOS-22, wie Android AND-15)
                .badge(model.unreadCirculars.count)
                .tag("mitteilungen")
            if model.accesses.contains(where: { $0.hasTodos || $0.hasHelpers }) {
                AufgabenView()
                    .tabItem { Label(tr("Aufgaben"), systemImage: "checklist") }
                    .tag("aufgaben")
            }
            if model.accesses.contains(where: { $0.hasScores }) {
                NotenView()
                    .tabItem { Label(tr("Noten"), systemImage: "music.note.list") }
                    .tag("noten")
            }
            AusweisView()
                .tabItem { Label(tr("Ich"), systemImage: "person.text.rectangle") }
                .tag("ausweis")
        }
        .task {
            model.checkStaleQuarantine()
            await model.refresh()
            // Nur, solange niemand schon einen anderen Reiter gewählt hat
            if !Demo.active, tab == "termine" { tab = Zustand.reiter(savedTab, available: availableTabs, fallback: tab) }
        }
        .onChange(of: tab) { _, new in if !Demo.active { savedTab = new } }
        // Alte Vorgänge aus beendeten Verbindungen (APP-04, FQ24): exportieren oder löschen
        .alert(
            tr("Alte Vorgänge"),
            isPresented: Binding(get: { model.staleQuarantine > 0 && exportURL == nil }, set: { if !$0 { model.staleQuarantine = 0 } })
        ) {
            Button(tr("Exportieren")) { exportURL = model.exportStaleQuarantine() }
            Button(tr("Jetzt löschen"), role: .destructive) { model.deleteStaleQuarantine() }
            Button(tr("Später"), role: .cancel) { model.staleQuarantine = 0 }
        } message: {
            Text(model.staleQuarantineText)
        }
        // Die Exportdatei ist entschlüsselt: beim Schließen gleich löschen. Die Vorgänge bleiben
        // (wie Android), die Rückfrage erscheint danach wieder mit „Jetzt löschen“ und „Später“.
        .sheet(
            item: Binding(get: { exportURL.map(ExportFile.init) }, set: { if $0 == nil { exportURL = nil } }),
            onDismiss: { AppModel.clearExports() }
        ) { file in
            ShareLink(item: file.url) { Label(tr("Exportieren"), systemImage: "square.and.arrow.up") }
                .padding()
        }
        .onChange(of: model.showEvents) { _, _ in tab = "termine" }
        // Geteilte Kalenderdatei (W4): Einheit mit Terminrecht suchen, dann „Neuer Termin“ vorausgefüllt
        .sheet(isPresented: Binding(get: { model.sharedEvent != nil }, set: { if !$0 { model.sharedEvent = nil } })) {
            if let termin = model.sharedEvent {
                TerminAusDateiBlatt(termin: termin)
            }
        }
        // Vom Server abgemeldet, ein anderes Konto rückt nach: nicht still wechseln (wie Android AND-16)
        .alert(
            tr("Konto abgemeldet"),
            isPresented: Binding(get: { model.signedOut != nil && !model.adding }, set: { if !$0 { model.signedOut = nil } })
        ) {
            Button(tr("Neu verbinden")) {
                model.signedOut = nil
                model.adding = true
            }
            Button(tr("Schließen"), role: .cancel) { model.signedOut = nil }
        } message: {
            if let info = model.signedOut {
                Text(tr("{dropped} wurde auf diesem Gerät abgemeldet. Du siehst jetzt {now}.", ["dropped": info.dropped, "now": info.now]))
            }
        }
        // Verwaltung: nach mehr als einer Minute im Hintergrund neu entsperren
        .onChange(of: phase) { _, now in model.sceneChanged(active: now == .active) }
        // Link zum Verbinden kam von außen (hubiplan://…), während schon ein Konto verbunden ist
        .verbindenFrage(aktiv: !model.adding)
        // Kurzer Titel, der Fehlertext steht darunter (IOS-23)
        .alert(
            tr("Das hat nicht geklappt"),
            isPresented: Binding(get: { !model.adding && model.linkError != nil }, set: { if !$0 { model.linkError = nil } })
        ) {
            Button(tr("Schließen"), role: .cancel) {
                model.linkError = nil
                model.retiredDrafts = 0
            }
        } message: {
            Text([
                model.linkError ?? "",
                model.retiredDrafts > 0 ? trn(
                    "1 nicht gesendeter Vorgang der Kasse bleibt verschlüsselt auf diesem Gerät. Er kommt zurück, wenn du dasselbe Konto wieder verbindest.",
                    "{n} nicht gesendete Vorgänge der Kasse bleiben verschlüsselt auf diesem Gerät. Sie kommen zurück, wenn du dasselbe Konto wieder verbindest.",
                    model.retiredDrafts
                ) : "",
            ].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
    }
}

struct TermineView: View {
    @EnvironmentObject private var model: AppModel
    /// Vorführmodus: `-abschnitt termin` öffnet gleich das Detail eines Termins
    @State private var path: [String] = Demo.active && Demo.section == "termin" ? ["1"] : []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.offlineSince != nil {
                    OfflineStand()
                } else if let message = model.error {
                    Section {
                        MeldungText(message, .fehler)
                        Button(tr("Erneut versuchen")) { Task { await model.refresh() } }
                    }
                }
                if model.accesses.isEmpty && !model.loading && model.error == nil {
                    Text(tr("Du hast noch keinen Zugang zum Mitgliederbereich. Bitte wende dich an deinen Verein."))
                        .foregroundStyle(.secondary)
                } else if model.events.isEmpty && !model.loading && model.error == nil {
                    Text(tr("Keine Termine in den nächsten Monaten.")).foregroundStyle(.secondary)
                }
                if model.offerHints {
                    HinweisAngebot()
                }
                ForEach(model.events) { event in
                    TerminZeile(event: event)
                }
            }
            .navigationTitle(tr("Termine"))
            .navigationDestination(for: String.self) { key in
                if let event = model.events.first(where: { $0.key == key }) {
                    TerminDetailView(event: event, series: model.events.filter { $0.eventId == event.eventId }.count > 1)
                } else {
                    Text(tr("Diesen Termin gibt es nicht mehr.")).foregroundStyle(.secondary)
                }
            }
            .zugangsWahl()
            .refreshable { await model.refresh() }
            .lesebreite()
            .overlay { if model.loading && model.events.isEmpty { Laedt() } }
        }
    }
}

/// Wann ein Termin ist (Liste und Detail).
func terminWann(_ event: Occurrence) -> String {
    guard let start = event.start else { return event.startsAt }
    // Ganztägige Termine sind Kalendertage der Verwaltung, unabhängig von der Zeitzone (AND-27)
    if event.allDay { return terminZeit(event.startsAt, event.endsAt, allDay: true) }
    let day = start.formatted(.dateTime.weekday(.abbreviated).day().month().year().locale(Texte.locale))
    return day + " · " + start.formatted(.dateTime.hour().minute().locale(Texte.locale)) + Zeit.geraeteHinweis(event.startsAt)
}

/// Termin in der Liste: antippen öffnet das Detail mit allen Angaben und Antworten (IOS-04).
/// Fehlt die Rückmeldung noch, stehen „Zusagen“ und „Absagen“ gleich in der Zeile; Ergebnis
/// oder Fehler stehen darunter, an der Zeile (IOS-01, IOS-02).
struct TerminZeile: View {
    @EnvironmentObject private var model: AppModel
    let event: Occurrence

    private var status: String? {
        Rueckmeldung.abzeichen(abgesagt: event.isCancelled, rsvp: event.rsvpEnabled, antwort: event.myResponse)
    }

    private var statusSymbol: String? {
        guard !event.isCancelled else { return "xmark.octagon" }
        switch event.myResponse {
        case "yes": return "checkmark"
        case "no": return "xmark"
        case "maybe": return "questionmark"
        default: return event.rsvpEnabled ? "exclamationmark" : nil
        }
    }

    private var canRespond: Bool {
        event.responseMissing && model.offlineSince == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: event.key) {
                HStack(alignment: .top, spacing: 12) {
                    DatumKaestchen(iso: event.startsAt, allDay: event.allDay, gedaempft: event.isCancelled)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.hubi(.headline))
                            .strikethrough(event.isCancelled)
                        Text(terminWann(event)).font(.hubi(.subheadline))
                        if !event.location.isEmpty {
                            Text(event.location).font(.hubi(.subheadline)).foregroundStyle(.secondary)
                        }
                        if !event.owner.isEmpty {
                            Text(event.owner).font(.hubi(.footnote)).foregroundStyle(.secondary)
                        }
                        if let status {
                            Abzeichen(
                                status,
                                Design.zustand(abgesagt: event.isCancelled, antwort: event.myResponse),
                                symbol: statusSymbol
                            )
                        }
                        if event.nurVorstand && !event.isCancelled {
                            Abzeichen(tr("nur Vorstand"), .hinweis)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            // VoiceOver: Zusagen und Absagen als Aktionen der Terminzeile, ohne weitere Wischschritte
            // (UX-Audit 16.11., IOS-13)
            .accessibilityActions {
                if canRespond {
                    Button(tr("Zusagen")) { Task { await model.respond(event, status: "yes") } }
                    Button(tr("Absagen")) { Task { await model.respond(event, status: "no") } }
                }
            }
            // Ohne Netz (gespeicherter Stand) gehen keine Rückmeldungen
            if canRespond {
                KnopfReihe {
                    Button(tr("Zusagen")) { Task { await model.respond(event, status: "yes") } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(tr("Zusagen: {title}", ["title": event.title]))
                    Button(tr("Absagen")) { Task { await model.respond(event, status: "no") } }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(tr("Absagen: {title}", ["title": event.title]))
                }
                .disabled(model.rsvpBusy.contains(event.eventId))
                .padding(.top, 2)
            }
            if let failure = model.rsvpErrors[event.eventId] {
                MeldungText(failure, .fehler).font(.hubi(.footnote))
            } else if let notice = model.rsvpNotices[event.eventId] {
                MeldungText(notice, .gut).font(.hubi(.footnote))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Zugang (Verein und Person) wählen, in jedem Reiter oben links (UX-Audit 16.11., IOS-07).
/// Nur bei mehr als einem Zugang; zwei Zugänge desselben Vereins tragen den Namen der Person.
private struct ZugangsWahl: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content.toolbar {
            if model.accesses.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(tr("Zugang"), selection: Binding(
                            get: { model.access?.id ?? 0 },
                            set: { id in Task { await model.choose(access: id) } }
                        )) {
                            ForEach(model.accesses) { access in
                                Text(access.label).tag(access.id)
                            }
                        }
                    } label: {
                        Label(model.access?.title ?? tr("Zugang"), systemImage: "person.2.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel(tr("Zugang"))
                    .accessibilityValue(model.access?.label ?? "")
                    .accessibilityHint(tr("Wählt, für welchen Verein und welche Person die App Daten zeigt."))
                }
            }
        }
    }
}

extension View {
    func zugangsWahl() -> some View { modifier(ZugangsWahl()) }
}

/// „Mein Konto“: Konten, Trennen, Gerätekalender. Erreichbar über den Knopf im Reiter „Ich“.
/// Unterseiten von „Mein Konto“ wie in der Android-App (UX-Audit 16.11., AND-25 und IOS-17):
/// jede Einstellung in zwei Tipps statt in einer langen Seite.
enum KontoSeite: String, CaseIterable, Identifiable {
    case konto, einstellungen, ueber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .konto: return tr("Konto")
        case .einstellungen: return tr("Einstellungen")
        case .ueber: return tr("Über und Rechtliches")
        }
    }

    var hint: String {
        switch self {
        case .konto: return tr("Weitere Konten, Abmelden, Konto und Daten löschen")
        case .einstellungen: return tr("Gerätekalender, Hinweise")
        case .ueber: return tr("Hilfe, Datenschutz, Impressum, Lizenzen, Version")
        }
    }

    var symbol: String {
        switch self {
        case .konto: return "person.crop.circle"
        case .einstellungen: return "gearshape"
        case .ueber: return "info.circle"
        }
    }
}

struct KontoView: View {
    @EnvironmentObject private var model: AppModel
    /// Vorführmodus: für das Bildschirmfoto gleich zum Gerätekalender
    @State private var showSettings = Demo.active && Demo.section == "kalender"

    var body: some View {
            Form {
                Section {
                    Text(model.account?.display ?? "")
                    Text(model.account?.email ?? "").foregroundStyle(.secondary)
                    Text(model.account?.server ?? "").foregroundStyle(.secondary)
                } header: {
                    Text(tr("Verbunden als"))
                } footer: {
                    if let access = model.access { Text(access.signedInAs) }
                }
                Section {
                    ForEach(KontoSeite.allCases) { seite in
                        NavigationLink {
                            KontoUnterseite(seite: seite)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(seite.title)
                                    Text(seite.hint).font(.hubi(.footnote)).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: seite.symbol)
                            }
                        }
                    }
                }
            }
            .tastaturFuehrung()
            .navigationTitle(tr("Mein Konto"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showSettings) { KontoUnterseite(seite: .einstellungen) }
            .sheet(isPresented: $model.adding, onDismiss: {
                model.pending = nil
                model.linkError = nil
            }) {
                VerbindenView()
            }
    }
}

/// Eine Unterseite von „Mein Konto“.
private struct KontoUnterseite: View {
    let seite: KontoSeite
    @EnvironmentObject private var model: AppModel
    @State private var unsent = 0
    @State private var vorschauErlaubt = Sichtschutz.erlaubt()
    @State private var confirmDisconnect = false
    @State private var sendingFirst = false
    @State private var sendProblem: String?
    @State private var deleteInfo = false
    @Environment(\.openURL) private var openURL

    private var serverName: String { (model.account?.server ?? "").replacingOccurrences(of: "https://", with: "") }

    /// Immer nachfragen (UX-Audit 16.11., IOS-08); mit Entwürfen auch „Erst senden, dann abmelden“.
    private func askDisconnect() {
        unsent = model.draftBox?.count ?? 0
        sendProblem = nil
        confirmDisconnect = true
    }

    var body: some View {
            Form {
                switch seite {
                case .konto:
                    Section {
                    if let server = model.account?.server, let url = Rechtliches.myAccount(server: server) {
                        Button(tr("Mein Konto im Browser öffnen")) { openURL(url) }
                    }
                    }
                Section {
                    ForEach(model.accounts.accounts) { entry in
                        Button {
                            Task { await model.switchAccount(entry.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.accounts.label(entry)).foregroundStyle(Color.primary)
                                    Text(entry.email).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                if entry.id == model.accounts.activeId {
                                    Image(systemName: "checkmark").accessibilityLabel(tr("Wird gezeigt"))
                                }
                            }
                        }
                    }
                    Button {
                        model.linkError = nil
                        model.adding = true
                    } label: {
                        Label(tr("Weiteres Konto verbinden"), systemImage: "plus")
                    }
                    .disabled(model.accounts.full)
                } header: {
                    Text(tr("Konten"))
                } footer: {
                    Text(tr("Für mehrere Vereine, jeder mit eigener HUBIplan-Adresse. Tippe ein Konto an, um es zu zeigen."))
                }
                Section {
                    Button(tr("Auf diesem Gerät abmelden …"), role: .destructive) { askDisconnect() }
                        .disabled(sendingFirst)
                        .confirmationDialog(
                            tr("Auf diesem Gerät von {server} abmelden?", ["server": serverName]),
                            isPresented: $confirmDisconnect,
                            titleVisibility: .visible
                        ) {
                            if unsent > 0 {
                                Button(tr("Erst senden, dann abmelden")) {
                                    Task {
                                        sendingFirst = true
                                        sendProblem = await model.sendDraftsBeforeDisconnect()
                                        sendingFirst = false
                                        if sendProblem == nil { await model.disconnect() }
                                    }
                                }
                                Button(tr("Verwerfen und abmelden"), role: .destructive) { Task { await model.disconnect() } }
                            } else {
                                Button(tr("Abmelden"), role: .destructive) { Task { await model.disconnect() } }
                            }
                            Button(tr("Abbrechen"), role: .cancel) {}
                        } message: {
                            if unsent > 0 {
                                Text(trn(
                                    "Auf diesem Gerät liegt noch 1 nicht gesendete Buchung oder Quittung. Beim Abmelden ohne Senden geht sie verloren.",
                                    "Auf diesem Gerät liegen noch {n} nicht gesendete Buchungen oder Quittungen. Beim Abmelden ohne Senden gehen sie verloren.",
                                    unsent
                                ))
                            } else {
                                Text(tr("Die App vergisst dieses Konto, den gespeicherten Ausweis und den Kalender. Im Browser bleibt alles, wie es ist."))
                            }
                        }
                    if sendingFirst { Laedt(text: tr("Wird gesendet …")) }
                    if let sendProblem { MeldungText(sendProblem, .fehler) }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Die App vergisst dieses Konto, den gespeicherten Ausweis und den Kalender. Im Browser bleibt alles, wie es ist."))
                        if model.softwareKey {
                            // Gesamtaudit 15.11., APP-03: Wechsel in die Secure Enclave beim nächsten Verbinden
                            Text(tr("Dieses Konto ist noch mit einem älteren Geräteschlüssel verbunden. Wenn du es auf diesem Gerät abmeldest und neu verbindest, liegt der Schlüssel sicher im Chip des Geräts."))
                        }
                    }
                    .task { await model.checkDeviceKey() }
                }
                    Section {
                        // App Store und Google Play verlangen einen Weg zum Löschen von Konto und Daten in der App
                        Button(tr("Konto und Daten löschen")) { deleteInfo = true }
                    }
                case .einstellungen:
                Section {
                    Toggle(tr("Termine in den Kalender des Geräts übernehmen"), isOn: Binding(
                        get: { model.calendarOn },
                        set: { on in Task { await model.setCalendar(on: on) } }
                    ))
                    if model.calendarOn {
                        Picker(tr("Erinnerung"), selection: Binding(
                            get: { model.reminder ?? -1 },
                            set: { minutes in Task { await model.setReminder(minutes >= 0 ? minutes : nil) } }
                        )) {
                            ForEach(Erinnerung.choices, id: \.self) { minutes in
                                Text(Erinnerung.label(minutes)).tag(minutes ?? -1)
                            }
                        }
                    }
                    if model.calendarDenied {
                        Text(tr("Ohne Zugriff auf den Kalender bleiben die Termine nur in der App. Du kannst ihn in den Einstellungen des Geräts unter HUBIplan erlauben."))
                            .foregroundStyle(Color.fehlerText)
                        EinstellungenKnopf()
                    }
                } header: {
                    Text(tr("Gerätekalender"))
                } footer: {
                    Text(tr("Je Verein ein eigener Kalender „HUBIplan“. Er liegt dort, wo dein Kalender neue Termine ablegt (zum Beispiel in iCloud), und wird aktualisiert, wenn du die App öffnest, und nach jeder Rückmeldung."))
                }
                Section {
                    Toggle(tr("Hinweis, wenn eine Rückmeldung fehlt"), isOn: Binding(
                        // Steht nur auf „an“, wenn das Gerät Mitteilungen auch erlaubt (IOS-16)
                        get: { model.hintsOn && !model.hintsDenied && !model.hintsUndecided },
                        set: { on in Task { await model.setHints(on: on) } }
                    ))
                    if model.hintsDenied {
                        Text(tr("Mitteilungen sind für HUBIplan ausgeschaltet. Du kannst sie in den Einstellungen des Geräts unter HUBIplan erlauben."))
                            .foregroundStyle(Color.fehlerText)
                        EinstellungenKnopf()
                    }
                } header: {
                    Text(tr("Hinweise"))
                } footer: {
                    Text(tr("Etwa einen Tag vor dem Anmeldeschluss, mit den Knöpfen Zusage und Absage."))
                }
                .task { await model.refreshHintPermission() }
                Section {
                    Toggle(tr("Vorschau in der App-Übersicht zeigen"), isOn: Binding(
                        get: { vorschauErlaubt },
                        set: { on in
                            Sichtschutz.setze(erlaubt: on)
                            vorschauErlaubt = on
                        }
                    ))
                } header: {
                    Text(tr("Sichtschutz"))
                } footer: {
                    Text(tr("Aus: Beim Wechseln zwischen Apps ist der Inhalt von HUBIplan verdeckt. Der Verwaltungsbereich ist immer verdeckt."))
                }
                case .ueber:
                    Section {
                    if let server = model.account?.server {
                        if let url = Rechtliches.help(server: server) {
                            Button(tr("Hilfe und Anleitungen im Browser")) { openURL(url) }
                        }
                        if let url = Rechtliches.privacy(server: server, key: model.access?.imprintKey) {
                            Button(tr("Datenschutzhinweise")) { openURL(url) }
                        }
                        if let url = Rechtliches.imprint(server: server, key: model.access?.imprintKey) {
                            Button(tr("Impressum")) { openURL(url) }
                        }
                    }
                    }
                    UeberDieApp()
                }
            }
            .tastaturFuehrung()
            .alert(tr("Konto und Daten löschen"), isPresented: $deleteInfo) {
                if let url = Rechtliches.privacy(server: model.account?.server ?? "", key: model.access?.imprintKey) {
                    Button(tr("Datenschutzhinweise öffnen")) { openURL(url) }
                }
                Button(tr("Jetzt abmelden …"), role: .destructive) {
                    // Erst die Erklärung schließen, dann die Rückfrage zeigen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { askDisconnect() }
                }
                Button(tr("Abbrechen"), role: .cancel) {}
            } message: {
                Text(Rechtliches.deleteInfo(server: model.account?.server ?? ""))
            }
            .navigationTitle(seite.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Datei zum Teilen (für `.sheet(item:)`)
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}


/// Abschnitt „Über die App“ (UX-Audit 16.11., IOS-27): Version, Lizenz, Lizenzen, Datenschutz
/// der App, Quellcode. Steht auch auf dem Verbinden-Bildschirm, also ohne Konto.
struct UeberDieApp: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            NavigationLink(tr("Lizenzen")) { LizenzenView() }
            if let url = URL(string: Rechtliches.appPrivacy) {
                Button(tr("Datenschutzerklärung der App")) { openURL(url) }
            }
            if let url = URL(string: Rechtliches.sourceUrl(version: AppModel.version)) {
                Button(tr("Quellcode")) { openURL(url) }
            }
        } header: {
            Text(tr("Über die App"))
        } footer: {
            Text(Rechtliches.licenseLine(version: AppModel.version))
        }
    }
}

/// Lizenz der App. Die iOS-App enthält keine fremden Bibliotheken; sie nutzt nur Apples
/// Systembibliotheken (swift-crypto braucht nur der Kern unter Linux für die Tests). Die Schrift
/// Inter liegt mit ihrem Lizenztext bei.
struct LizenzenView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Text(tr("HUBIplan ist freie Software: Du kannst sie unter den Bedingungen der GNU Affero General Public License, Version 3 oder (nach deiner Wahl) jeder späteren Version, weitergeben und verändern."))
                Text(tr("Die App wird in der Hoffnung verbreitet, dass sie nützlich ist, aber ohne jede Gewährleistung."))
                if let url = URL(string: "https://www.gnu.org/licenses/agpl-3.0.html") {
                    Button(tr("Lizenztext (GNU AGPL 3.0)")) { openURL(url) }
                }
                if let url = URL(string: Rechtliches.sourceUrl(version: AppModel.version)) {
                    Button(tr("Quellcode")) { openURL(url) }
                }
            } header: {
                Text("HUBIplan")
            }
            Section {
                Text(tr("Die App enthält keine Bibliotheken anderer Anbieter. Sie nutzt nur die Bibliotheken des Betriebssystems von Apple."))
            } header: {
                Text(tr("Enthaltene Bibliotheken"))
            }
            Section {
                Text(tr("Die App verwendet die Schrift {name} (SIL Open Font License 1.1).", ["name": Design.schriftFamilie]))
                NavigationLink(tr("Lizenztext der Schrift anzeigen")) { SchriftLizenzView() }
            } header: {
                Text(tr("Schrift"))
            }
        }
        .navigationTitle(tr("Lizenzen"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Erinnerungen erst anbieten, wenn es einen Anlass gibt: ein Termin wartet auf deine Rückmeldung
/// (UX-Audit 16.11., IOS-16). Die Systemabfrage kommt erst nach „Erinnern lassen“.
struct HinweisAngebot: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(tr("Soll die App dich erinnern, wenn eine Rückmeldung fehlt?"), systemImage: "bell")
                    .font(.hubi(.subheadline).weight(.semibold))
                Text(tr("Etwa einen Tag vor dem Anmeldeschluss, mit den Knöpfen Zusage und Absage. Das Gerät fragt dich danach einmal nach der Erlaubnis."))
                    .font(.hubi(.footnote))
                    .foregroundStyle(Color.secondary)
                HStack(spacing: 12) {
                    Button(tr("Erinnern lassen")) { Task { await model.setHints(on: true) } }
                        .buttonStyle(.borderedProminent)
                    Button(tr("Nicht jetzt")) { model.dismissHintOffer() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Weg in die Einstellungen des Geräts, wenn eine Erlaubnis fehlt (IOS-16)
struct EinstellungenKnopf: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Button(tr("Einstellungen öffnen")) { openURL(url) }
        }
    }
}
