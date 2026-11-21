import Foundation
import HubiplanKern
import Network
import SwiftUI
import UIKit

/// Änderung der Verwaltung, die sich noch zurücknehmen lässt.
struct AdminUndo: Equatable {
    let unit: AdminUnit
    let changeSet: String
    /// Aufgabe, zu der die Änderung gehört (eigener Rückweg)
    var task: Int?
}

/// Konto, das der Server abgemeldet hat, und das Konto, das die App jetzt zeigt.
struct SignedOutInfo: Equatable {
    var dropped: String
    var now: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts = AccountList()
    /// Ein weiteres Konto wird gerade verbunden (Blatt über „Mein Konto“)
    @Published var adding = false
    /// Alte Vorgänge in der Quarantäne (älter als 90 Tage): Rückfrage mit Export (FQ24, APP-04)
    @Published var staleQuarantine = 0
    @Published var accesses: [PortalAccess] = []
    @Published var accessId: Int?
    @Published var events: [Occurrence] = []
    /// Rückmeldungen: Fehler und Bestätigung je Termin, Termine mit laufender Anfrage
    @Published var rsvpErrors = RueckmeldungsFehler()
    @Published var rsvpNotices: [Int: String] = [:]
    @Published var rsvpBusy: Set<Int> = []
    @Published var circulars: [CircularItem] = []
    /// Ungelesene Mitteilungen des gewählten Zugangs, nur auf diesem Gerät gemerkt (IOS-22)
    @Published var unreadCirculars: Set<Int> = []
    /// Termine und Mitteilungen sind der Stand von diesem Zeitpunkt, weil HUBIplan gerade nicht
    /// erreichbar ist (IOS-24); nil, solange alles frisch ist
    @Published var offlineSince: Date?
    /// Ein Konto wurde vom Server abgemeldet, die App zeigt jetzt ein anderes (wie Android AND-16)
    @Published var signedOut: SignedOutInfo?
    /// Zeitpunkt des letzten vollständigen Abrufs von Terminen und Mitteilungen
    private var loadedAt: Date?
    private let pathMonitor = NWPathMonitor()
    /// Einheiten, an die dieses Konto Kurzmitteilungen senden darf (leer: kein Knopf)
    @Published var senders: Senders?
    /// Ausweis des gewählten Zugangs, wie er zuletzt kam (auch ohne Netz)
    @Published var card: StoredCard?
    /// Der Ausweis ließ sich zuletzt nicht abrufen
    @Published var cardOffline = false
    /// Eigene Daten und Rechnungen des gewählten Zugangs
    @Published var profile: Profile?
    @Published var invoices: MyInvoices?
    /// Lastschriftmandat (nur ansehen); `nil` ohne Rechnungen oder bei älteren Ständen
    @Published var mandate: MandateState?
    /// Versammlungen und Dokumente des gewählten Zugangs (soweit eingeschaltet)
    @Published var meetings: MyMeetings?
    @Published var documents: MyDocuments?
    /// Umfragen des gewählten Zugangs (soweit eingeschaltet)
    @Published var surveys: SurveyList?
    /// Pinnwand des gewählten Zugangs (soweit eingeschaltet)
    @Published var pinboard: PinboardList?
    /// Sammelbestellungen des gewählten Zugangs (soweit eingeschaltet)
    @Published var orders: OrderCampaignList?
    /// Auslagen des gewählten Zugangs (soweit eingeschaltet)
    @Published var expenses: ExpenseOverview?
    @Published var feeProofs: FeeProofOverview?
    /// Datei, die gerade zum Ansehen offen ist (liegt nur kurz im Zwischenspeicher)
    @Published var preview: URL?
    @Published var previewBusy = false
    /// Aufgaben und Helferdienste des gewählten Zugangs; Hinweis nach einer Aktion
    @Published var todos: [MemberTodo] = []
    @Published var helpers: HelperOverview?
    @Published var taskNotice: String?
    /// Notenmappen des gewählten Zugangs (nur mit Musikerprofil)
    @Published var scores: ScoreFolders?
    /// Verwaltung: Einheiten mit Rechten, Schlüssel im Tresor, Schlüssel gerade offen
    @Published private(set) var adminOverview: AdminOverview?
    /// Die Übersicht wurde für dieses Konto schon einmal abgefragt (vorher: Ladeanzeige)
    @Published private(set) var adminLoaded = false
    @Published private(set) var adminSealed = false
    @Published private(set) var adminOpen = false
    @Published private(set) var adminBusy = false
    @Published var adminError: String?
    /// Hinweis nach einer Änderung in der Verwaltung und das Paket für „Rückgängig“
    @Published var adminNotice: String?
    @Published private(set) var adminUndo: AdminUndo?
    @Published var loading = false
    @Published var error: String?
    /// Link, den die App zum Verbinden bekommen hat und der noch bestätigt werden muss
    @Published var pending: PairingLink?
    /// Geheimnis zum Prüfwert, mit dem die App den Code im Browser angefordert hat (APP-01);
    /// gilt nur für den Rückruf derselben Adresse.
    var pendingVerifier: (server: String, verifier: String)?
    /// Link `hubiplan://anmelden` einer Adresse: vor dem Öffnen der Anmeldeseite nachfragen.
    @Published var browserStart: String?
    @Published var linkError: String?
    /// Geteilte Kalenderdatei (.ics): „Neuer Termin“ in der Verwaltung vorausfüllen (W4)
    @Published var sharedEvent: IcsTermin?
    /// Vom Server abgemeldet: so viele nicht gesendete Vorgänge liegen beiseite (IOS-08)
    @Published var retiredDrafts = 0
    /// Gerätekalender: eingeschaltet, Erinnerung in Minuten, Zugriff verweigert
    @Published private(set) var calendarOn = KalenderEinstellung.on
    @Published private(set) var reminder = KalenderEinstellung.reminder
    @Published var calendarDenied = false
    /// Hinweis „Rückmeldung fehlt“ an; Mitteilungen in den Geräteeinstellungen verboten
    @Published private(set) var hintsOn = Hinweise.on
    @Published var hintsDenied = false
    /// Das Gerät hat noch nie nach Mitteilungen gefragt (IOS-16): dann bieten die Termine „Erinnern lassen“ an
    @Published var hintsUndecided = false
    /// „Nicht jetzt“ beim Angebot „Erinnern lassen“
    @Published var hintOfferDismissed = UserDefaults.standard.bool(forKey: "hinweis_angebot_weg")
    /// Zählt hoch, wenn die App über einen Kalendereintrag geöffnet wurde (dann Reiter „Termine“)
    @Published var showEvents = 0

    private let transport: Transport = Demo.active ? DemoTransport() : UrlSessionTransport()
    private var session: DeviceSession?
    /// Geräteschlüssel noch in Software (vor APP-03 verbunden): Hinweis in „Konten“
    @Published var softwareKey = false

    func checkDeviceKey() async {
        softwareKey = Demo.active ? false : (await session?.usesSoftwareKey ?? false)
    }
    private var cards: CardStore = DemoCards()
    /// Zählt jeden Kontowechsel; Antworten für ein früheres Konto werden verworfen
    private var epoch = 0
    /// Letzter Abgleich mit dem Gerätekalender je Konto
    private var calendarSynced: [String: Date] = [:]
    /// Geladene Notenblätter, nur im Arbeitsspeicher (Schlüssel: Datei und Fassung)
    private var sheetCache: [String: Data] = [:]
    /// Vorstandsschlüssel, nur im Arbeitsspeicher und höchstens fünf Minuten ohne Bedienung
    private var adminAccess: AdminAccess?
    private var adminUsed = ContinuousClock.now
    private var backgroundSince: ContinuousClock.Instant?

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Buildnummer (CFBundleVersion): zählt für die Mindestversion der Instanz (APP-11)
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    init() {
        Texte.language = Texte.pick(preferred: Locale.preferredLanguages)
        Self.clearViews()
        Self.clearExports()
        if !Demo.active { Self.purgeQuarantine() }
        accounts = Demo.active ? Demo.accounts : Konten.load()
        activate()
        watchNetwork()
    }

    /// Ablage für den Offline-Stand und die gelesenen Mitteilungen (nicht im Vorführmodus)
    var offlineBox: OfflineBox? {
        guard !Demo.active, let account else { return nil }
        return OfflineBox(files: EntwurfsOrdner.offline(account: account.id), secrets: Konten.secrets(account.id))
    }

    /// Kommt das Netz zurück, während der gespeicherte Stand zu sehen ist: selbst neu laden (IOS-24).
    private func watchNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.offlineSince != nil, !self.loading else { return }
                await self.refresh()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "de.hubiplan.app.netz"))
    }

    /// Ohne Netz: Termine und Mitteilungen aus dem zuletzt gespeicherten Stand zeigen.
    private func showOffline() {
        if !events.isEmpty || !circulars.isEmpty {
            offlineSince = loadedAt ?? offlineSince
            if offlineSince != nil { return }
        }
        guard let box = offlineBox else { return }
        let found: (id: Int, snapshot: OfflineSnapshot)?
        if let id = access?.id ?? accessId ?? savedAccessId {
            found = box.load(accessId: id).map { (id, $0) }
        } else {
            found = box.latest()
        }
        guard let found else { return }
        if accessId == nil { accessId = found.id }
        events = found.snapshot.events
        circulars = found.snapshot.circulars
        unreadCirculars = box.unread(accessId: found.id, ids: circulars.map(\.id))
        offlineSince = found.snapshot.savedAt
    }

    /// Mitteilung geöffnet: gilt als gelesen.
    func circularOpened(_ item: CircularItem) {
        guard let id = access?.id ?? accessId else { return }
        offlineBox?.markRead(accessId: id, id: item.id)
        unreadCirculars.remove(item.id)
    }

    /// Das gezeigte Konto
    var account: AccountEntry? { accounts.active }
    /// Standzugänge, die dieses iPhone für das gezeigte Konto angelegt hat (im Vorführmodus keine Ablage)
    var standStore: StandStore? {
        guard !Demo.active, let account else { return nil }
        return StandStore(store: Konten.secrets(account.id))
    }

    /// Buchungen der Kasse, die noch nicht gesendet sind (verschlüsselt auf diesem Gerät)
    var draftBox: DraftBox? {
        if Demo.active { return Demo.box }
        guard let account else { return nil }
        return DraftBox(files: EntwurfsOrdner(account: account.id), secrets: Konten.secrets(account.id))
    }

    private func makeSession(server: String, id: String) -> DeviceSession {
        let store: SecretStore = Demo.active ? DemoStore() : Konten.secrets(id)
        // Neue Verbindungen: Geräteschlüssel in der Secure Enclave (APP-03); ältere behalten
        // ihren Software-Schlüssel bis zum nächsten Verbinden
        return DeviceSession(server: server, store: store, transport: transport, keys: EnclaveDeviceKeys())
    }

    private func save() {
        if !Demo.active { Konten.save(accounts) }
    }

    /// Sitzung und Ablage auf das gezeigte Konto stellen; Daten des vorigen Kontos verschwinden.
    private func activate(session ready: DeviceSession? = nil) {
        epoch += 1
        if let account {
            session = ready ?? makeSession(server: account.server, id: account.id)
            cards = Demo.active ? DemoCards() : FileCardStore(account: account.id)
        } else {
            session = nil
        }
        accesses = []
        accessId = nil
        events = []
        rsvpErrors = RueckmeldungsFehler()
        rsvpNotices = [:]
        rsvpBusy = []
        circulars = []
        unreadCirculars = []
        offlineSince = nil
        loadedAt = nil
        senders = nil
        card = nil
        profile = nil
        invoices = nil
        mandate = nil
        meetings = nil
        documents = nil
        surveys = nil
        pinboard = nil
        orders = nil
        expenses = nil
        feeProofs = nil
        scores = nil
        sheetCache = [:]
        adminOverview = nil
        adminLoaded = false
        adminSealed = false
        adminOpen = false
        adminBusy = false
        adminError = nil
        adminNotice = nil
        adminUndo = nil
        adminAccess = nil
        todos = []
        helpers = nil
        taskNotice = nil
        cardOffline = false
        error = nil
    }

    var access: PortalAccess? { accesses.first { $0.id == accessId } ?? accesses.first }

    /// Zuletzt gewählter Zugang des gezeigten Kontos (IOS-25)
    private var savedAccessId: Int? {
        guard let account = accounts.activeId, !Demo.active else { return nil }
        return Zustand.gespeicherterZugang(account: account)
    }

    // MARK: Verbinden

    /// Link aus QR-Code, Eingabefeld oder `hubiplan://verbinden…`; verbunden wird erst nach Rückfrage.
    func offer(link: String) {
        if CalendarMark.isEventLink(link) {
            showEvents += 1
            return
        }
        guard !accounts.full else {
            linkError = tr("Mehr als {anzahl} Konten lassen sich nicht verbinden. Melde zuerst ein Konto auf diesem Gerät ab.", ["anzahl": "\(AccountList.limit)"])
            return
        }
        if let server = BrowserLogin.parseStart(link) {
            // Ohne Code: die App fordert ihn selbst mit Prüfwert an (APP-01)
            if !accounts.accounts.isEmpty { adding = true }
            browserStart = server
            linkError = nil
        } else if let parsed = PairingLink.parse(link) {
            pending = parsed
            linkError = nil
        } else {
            linkError = tr("Das ist kein Link zum Verbinden. Er beginnt mit https:// und endet auf /app/verbinden#code=…")
        }
    }

    /// Kalenderdatei aus Mail oder Kalender („Öffnen in“ bzw. Teilen an HUBIplan).
    func open(calendarFile url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        guard accounts.accounts.isEmpty == false else {
            linkError = tr("Bitte zuerst die App mit deinem Verein verbinden.")
            return
        }
        guard let data, data.count <= IcsLeser.maxBytes,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let termin = IcsLeser.lesen(text)
        else {
            linkError = tr("In der Datei ist kein Termin, den HUBIplan übernehmen kann.")
            return
        }
        sharedEvent = termin
    }

    /// Schon mit dieser Adresse verbunden? Dann öffnet `hubiplan://anmelden` ohne Rückfrage.
    func isKnown(server: String) -> Bool {
        accounts.accounts.contains { $0.server == server }
    }

    func connect() async {
        guard let link = pending else { return }
        pending = nil
        let verifier = pendingVerifier.flatMap { $0.server == link.server ? $0.verifier : nil } ?? ""
        pendingVerifier = nil
        await pair(server: link.server) { new in
            try await new.connect(
                code: link.code, deviceName: UIDevice.current.name, appVersion: Self.build, verifier: verifier
            )
        }
    }

    /// Anmeldung mit E-Mail und Passwort, die auf den zweiten Faktor wartet (IOS-06)
    @Published var pendingLogin: (server: String, session: String)?

    /// Mit E-Mail und Passwort verbinden (UX-Audit 16.11., IOS-06, wie Android). Verlangt das
    /// Konto einen zweiten Faktor, steht danach `pendingLogin` und die App fragt den Code ab.
    func login(server input: String, email: String, password: String) async {
        guard let server = normalizeServer(input) else {
            linkError = tr("Bitte die Adresse von HUBIplan angeben, z. B. verein.example.de.")
            return
        }
        guard !accounts.full else {
            linkError = tr("Mehr als {anzahl} Konten lassen sich nicht verbinden. Melde zuerst ein Konto auf diesem Gerät ab.", ["anzahl": "\(AccountList.limit)"])
            return
        }
        await pair(server: server) { new in
            switch try await new.login(email: email, password: password, appVersion: Self.build) {
            case .done(let token):
                return try await new.connect(sessionToken: token, deviceName: UIDevice.current.name, appVersion: Self.build)
            case .needsCode(let token):
                self.pendingLogin = (server, token)
                return nil
            }
        }
    }

    /// Zweiter Faktor zur Anmeldung mit Passwort.
    func loginCode(_ code: String) async {
        guard let waiting = pendingLogin else { return }
        await pair(server: waiting.server) { new in
            do {
                let paired = try await new.connect(
                    sessionToken: waiting.session, code: code, deviceName: UIDevice.current.name, appVersion: Self.build
                )
                self.pendingLogin = nil
                return paired
            } catch let failure as ApiError where failure.status == 401 || failure.status == 409 {
                // Sitzung abgelaufen: von vorn anmelden
                self.pendingLogin = nil
                throw failure
            }
        }
    }

    /// Gemeinsamer Ablauf aller Wege zum Verbinden: neues Konto anlegen, Gerät koppeln, zeigen.
    /// `work` gibt nil zurück, wenn noch ein Schritt fehlt (zweiter Faktor).
    private func pair(server: String, _ work: @MainActor (DeviceSession) async throws -> Paired?) async {
        loading = true
        let id = accounts.freeId()
        let new = makeSession(server: server, id: id)
        do {
            guard let paired = try await work(new) else {
                loading = false
                linkError = nil
                return
            }
            let entry = AccountEntry(id: id, server: server, display: paired.user.display, email: paired.user.email)
            // Dasselbe Konto noch einmal verbunden: der alte Eintrag weicht dem neuen
            if let replaced = accounts.add(entry) { await forget(replaced) }
            save()
            activate(session: new)
            if !Demo.active { Self.adopt(server: server, email: paired.user.email, account: id) }
            linkError = nil
            adding = false
            loading = false
            await refresh()
        } catch let failure as ApiError {
            await new.forget()
            loading = false
            linkError = failure.text
        } catch {
            await new.forget()
            loading = false
            linkError = ApiError(status: 0, code: "offline").text
        }
    }

    /// Geheimnisse und Ablage eines Kontos auf dem Gerät löschen.
    private func forget(_ entry: AccountEntry) async {
        guard !Demo.active else { return }
        // Auch beim Server abmelden, nicht nur hier vergessen (Gesamtaudit 15.11., APP-02)
        await makeSession(server: entry.server, id: entry.id).signOut()
        VerwaltungTresor(account: entry.id).clear()
        FileCardStore(account: entry.id).clear()
    }

    /// Anderes verbundenes Konto zeigen.
    func switchAccount(_ id: String) async {
        guard id != accounts.activeId, accounts.select(id) else { return }
        save()
        activate()
        await refresh()
    }

    /// Das gezeigte Konto vergessen; gibt es weitere, kommt das nächste nach vorn.
    /// `revoked`: Der Server hat das Gerät abgemeldet (nicht bewusst getrennt). Dann gehen
    /// unversandte Entwürfe in die Quarantäne statt verloren (Gesamtaudit 15.11., APP-04).
    func disconnect(revoked: Bool = false) async {
        guard let account else { return }
        if revoked {
            await session?.forget()  // schon abgemeldet: nichts mehr beim Server
        } else {
            // Push und Gerät beim Server abmelden; ohne Netz höchstens kurz warten (APP-02)
            await session?.signOut()
        }
        if !Demo.active { VerwaltungTresor(account: account.id).clear() }
        if !Demo.active { StandStore(store: Konten.secrets(account.id)).clear() }
        if !Demo.active {
            let drafts = DraftBox(files: EntwurfsOrdner(account: account.id), secrets: Konten.secrets(account.id))
            if revoked {
                retiredDrafts = drafts.count
                Self.retire(drafts, server: account.server, email: account.email)
            }
            drafts.clear()
        }
        cards.clear()
        offlineBox?.clear()
        Self.clearViews()
        preview = nil
        if !Demo.active { Geraetekalender.shared.remove(prefix: CalendarMark.prefix(server: account.server)) }
        if !Demo.active { await Hinweise.clear(account: account.id) }
        calendarSynced[account.id] = nil
        accounts.remove(account.id)
        // Speicher der eingebetteten Webansicht (Standmodus) nicht über die Abmeldung hinaus
        // behalten (Gesamtaudit 19.11.2026, S-09)
        if !Demo.active {
            let rest = accounts.accounts.map(\.server)
            await SichtschutzFenster.loescheWebDaten(Sichtschutz.webDaten(server: account.server, uebrige: rest))
        }
        save()
        activate()
        // Vom Server abgemeldet und ein anderes Konto rückt nach: sagen statt still wechseln
        if revoked, let now = self.account {
            signedOut = SignedOutInfo(dropped: Self.label(account), now: Self.label(now))
        }
        if self.account != nil { await refresh() }
    }

    /// Name und Adresse eines Kontos für Hinweise.
    static func label(_ entry: AccountEntry) -> String {
        entry.display.isEmpty ? entry.host : "\(entry.display) (\(entry.host))"
    }

    /// Vor dem Trennen (UX-Audit 16.11., IOS-08): nicht gesendete Buchungen und Quittungen senden.
    /// nil, wenn danach nichts mehr liegt; sonst ein Satz, warum es nicht ging.
    func sendDraftsBeforeDisconnect() async -> String? {
        guard let box = draftBox, box.count > 0 else { return nil }
        guard adminOpen, let units = adminOverview?.units else {
            return tr("Die Verwaltung ist gesperrt. Bitte unter „Verwaltung“ entsperren und dann noch einmal abmelden.")
        }
        let ids = Set(box.list().map(\.unitId) + box.receipts().map(\.unitId))
        for unit in units where ids.contains(unit.id) {
            _ = await verwaltung(unit) { client -> Int in
                try await client.send(drafts: box) + (try await client.send(receipts: box))
            }
            if let failure = adminError { return failure }
        }
        let left = box.count
        guard left > 0 else { return nil }
        return trn(
            "1 Vorgang konnte nicht gesendet werden (z. B. ohne Verbindung oder mit Fehler). Bitte unter Verwaltung › Kasse prüfen.",
            "{n} Vorgänge konnten nicht gesendet werden (z. B. ohne Verbindung oder mit Fehler). Bitte unter Verwaltung › Kasse prüfen.",
            left
        )
    }

    // MARK: Quarantäne (APP-04)

    private static func quarantineBox(_ id: String) -> DraftBox {
        DraftBox(files: EntwurfsOrdner(quarantine: id), secrets: KeychainStore(service: "de.hubiplan.app.quarantaene.\(id)"))
    }

    /// Unversandte Entwürfe eines vom Server abgemeldeten Kontos beiseitelegen.
    static func retire(_ drafts: DraftBox, server: String, email: String) {
        guard !email.isEmpty else { return }
        let id = DraftQuarantine.id(server: server, email: email)
        let box = quarantineBox(id)
        DraftQuarantine.retire(drafts, into: box, owner: .init(server: server, email: email, since: Date()))
    }

    /// Nach dem Verbinden: Entwürfe desselben Kontos auf derselben Instanz zurückholen.
    static func adopt(server: String, email: String, account: String) {
        let box = quarantineBox(DraftQuarantine.id(server: server, email: email))
        let drafts = DraftBox(files: EntwurfsOrdner(account: account), secrets: Konten.secrets(account))
        DraftQuarantine.adopt(box, into: drafts, server: server, email: email)
    }

    /// Beim Start: abgelaufene Quarantänen (älter als 120 Tage) löschen.
    static func purgeQuarantine() {
        for id in EntwurfsOrdner.quarantineIds() {
            let box = quarantineBox(id)
            if DraftQuarantine.expired(box) { box.clear() }
        }
    }

    private static var quarantineBoxes: [DraftBox] { EntwurfsOrdner.quarantineIds().map(quarantineBox) }

    /// Rückfrage zu alten Vorgängen: wie viele und wann sie endgültig gelöscht werden.
    var staleQuarantineText: String {
        let date = DraftQuarantine.finalDeletion(Self.quarantineBoxes).map {
            $0.formatted(date: .numeric, time: .omitted)
        } ?? ""
        return tr(
            "{anzahl} nicht gesendete Vorgänge liegen seit über 90 Tagen auf diesem Gerät, weil die Verbindung beendet wurde. Sie werden am {datum} gelöscht. Vorher exportieren?",
            ["anzahl": "\(staleQuarantine)", "datum": date]
        )
    }

    func checkStaleQuarantine() {
        staleQuarantine = Demo.active ? 0 : DraftQuarantine.staleCount(Self.quarantineBoxes)
    }

    /// Alte Vorgänge als Datei zum Teilen. Die Datei ist entschlüsselt: Sie wird gelöscht, wenn
    /// das Teilen geschlossen wird, spätestens beim nächsten Start (`clearExports`). Die
    /// Vorgänge selbst bleiben wie bei Android bis zum Löschen oder nach 120 Tagen.
    func exportStaleQuarantine() -> URL? {
        guard let export = DraftQuarantine.exportStale(Self.quarantineBoxes) else { return nil }
        let data = export.0
        Self.clearExports()
        let url = DraftQuarantine.exportURL(in: FileManager.default.temporaryDirectory)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    /// Entschlüsselte Exportdatei löschen (Teilen geschlossen, App gestartet).
    static func clearExports() {
        DraftQuarantine.clearExports(in: FileManager.default.temporaryDirectory)
    }

    /// Nach Zustimmung: alte Vorgänge jetzt löschen.
    func deleteStaleQuarantine() {
        for box in Self.quarantineBoxes where DraftQuarantine.staleCount([box]) > 0 { box.clear() }
        staleQuarantine = 0
    }

    // MARK: Daten

    private func run(_ work: @MainActor (Api) async throws -> Void) async {
        guard let session else { return }
        let epoch = self.epoch
        loading = true
        defer { loading = false }
        do {
            try await work(session.api())
            if epoch == self.epoch { error = nil }
        } catch let failure as ApiError {
            guard epoch == self.epoch else { return }
            if failure.mustReconnect {
                await disconnect(revoked: true)
                linkError = failure.text
            } else {
                error = failure.text
            }
        } catch {
            if epoch == self.epoch { self.error = ApiError(status: 0, code: "offline").text }
        }
    }

    func refresh() async {
        let epoch = self.epoch
        await run { api in
            let me = try await api.me()
            guard epoch == self.epoch else { return }
            if let id = self.accounts.activeId, let shown = self.account,
               shown.display != me.user.display || shown.email != me.user.email {
                self.accounts.update(id, display: me.user.display, email: me.user.email)
                self.save()
            }
            self.accesses = me.portal
            // Zuletzt gewählten Zugang wieder zeigen (IOS-25), sonst den ersten
            if self.accessId == nil || !me.portal.contains(where: { $0.id == self.accessId }) {
                self.accessId = Zustand.zugang(saved: self.savedAccessId, available: me.portal.map(\.id))
            }
            guard let access = self.access else {
                self.events = []
                self.circulars = []
                return
            }
            let now = Date()
            let end = Calendar.current.date(byAdding: .month, value: 6, to: now) ?? now
            let (events, eventsJson) = try await api.eventsWithJson(accessId: access.id, from: Zeit.day(now), to: Zeit.day(end))
            let (circulars, circularsJson) = try await api.circularsWithJson(accessId: access.id)
            guard epoch == self.epoch else { return }
            self.events = events
            self.rsvpErrors.keep(only: events)
            self.circulars = circulars
            self.loadedAt = now
            self.offlineSince = nil
            if let box = self.offlineBox {
                box.save(accessId: access.id, eventsJson: eventsJson, circularsJson: circularsJson, at: now)
                self.unreadCirculars = box.unread(accessId: access.id, ids: circulars.map(\.id))
            }
        }
        if epoch == self.epoch, error != nil, session != nil { showOffline() }
        if epoch == self.epoch { await planHints() }
        if epoch == self.epoch { await refreshSenders() }
        if epoch == self.epoch { await refreshIch() }
        if epoch == self.epoch { await refreshTasks() }
        if epoch == self.epoch { await syncCalendar() }
    }

    /// Nur „Meine Daten“ neu laden (z. B. nach einer Kündigung).
    func reloadProfile() async {
        if case .success(let fresh) = await portalCall({ api, access in try await api.profile(accessId: access) }) {
            profile = fresh
        }
    }

    /// Reiter „Ich“: Ausweis, eigene Daten und Rechnungen (soweit das Modul eingeschaltet ist).
    func refreshIch() async {
        await refreshCard()
        guard let session, let access else { return }
        let id = access.id
        let epoch = self.epoch
        let api = session.api()
        let profile = try? await api.profile(accessId: id)
        var invoices: MyInvoices?
        var mandate: MandateState?
        if access.has(module: "billing", fallback: true) {
            invoices = try? await api.myInvoices(accessId: id)
            mandate = try? await api.myMandate(accessId: id)
        }
        var meetings: MyMeetings?
        if access.hasMeetings { meetings = try? await api.myMeetings(accessId: id) }
        var documents: MyDocuments?
        if access.hasDocs { documents = try? await api.myDocuments(accessId: id) }
        var surveys: SurveyList?
        if access.hasSurveys { surveys = try? await api.memberSurveys(accessId: id) }
        var pinboard: PinboardList?
        // Nur nachsehen: „neu“ bleibt stehen, bis die Pinnwand geöffnet wird
        if access.hasPinboard { pinboard = try? await api.memberPinboard(accessId: id, seen: false) }
        var orders: OrderCampaignList?
        if access.hasOrders { orders = try? await api.memberOrders(accessId: id) }
        var expenses: ExpenseOverview?
        if access.hasExpenses { expenses = try? await api.memberExpenses(accessId: id) }
        var feeProofs: FeeProofOverview?
        if access.hasFeeProofs { feeProofs = try? await api.memberFeeProofs(accessId: id) }
        guard epoch == self.epoch, self.access?.id == id else { return }
        if let profile { self.profile = profile }
        self.invoices = invoices ?? self.invoices
        self.mandate = mandate ?? self.mandate
        self.meetings = access.hasMeetings ? (meetings ?? self.meetings) : nil
        self.documents = access.hasDocs ? (documents ?? self.documents) : nil
        self.surveys = access.hasSurveys ? (surveys ?? self.surveys) : nil
        self.pinboard = access.hasPinboard ? (pinboard ?? self.pinboard) : nil
        self.orders = access.hasOrders ? (orders ?? self.orders) : nil
        self.expenses = access.hasExpenses ? (expenses ?? self.expenses) : nil
        self.feeProofs = access.hasFeeProofs ? (feeProofs ?? self.feeProofs) : nil
        await loadAdmin()
    }

    // MARK: Verwaltung

    private var tresor: VerwaltungTresor? {
        guard !Demo.active, let account else { return nil }
        return VerwaltungTresor(account: account.id)
    }

    /// Einheiten mit Verwaltungsrechten und ob dieses Gerät freigeschaltet ist.
    func loadAdmin() async {
        guard let session else {
            adminLoaded = true
            return
        }
        let epoch = self.epoch
        let overview = try? await session.api().adminOverview()
        guard epoch == self.epoch else { return }
        adminLoaded = true
        if Demo.active {
            adminOverview = overview
            adminSealed = overview?.unlocked == true
            if adminSealed, adminAccess == nil {
                adminAccess = AdminAccess(token: "hpa_demo", key: nil)
                adminUsed = .now
                adminOpen = true
            }
            return
        }
        guard let overview else { return }
        adminOverview = overview
        let filled = tresor?.filled == true
        // Im Browser gesperrt oder abgelaufen: der Schlüssel im Tresor ist wertlos
        if !overview.unlocked, filled { tresor?.clear() }
        adminSealed = overview.unlocked && filled
        if !adminSealed { lockAdminNow() }
    }

    /// Freischalten mit Passwort und Zwei-Faktor-Code; der neue Schlüssel kommt in den Tresor.
    func unlockAdmin(password: String, code: String) async {
        await unlockAdminWith { api, adminKey in
            try await api.unlockAdmin(
                password: password, code: code.trimmingCharacters(in: .whitespaces), adminKey: adminKey
            )
        }
    }

    /// Freischalten mit Passkey über den eingebetteten Browser (`/app/freischalten`).
    /// `authenticate` öffnet die Seite und liefert den Rückruf `hubiplan://freischalten…`;
    /// nil heißt abgebrochen.
    func unlockAdminInBrowser(authenticate: @escaping (URL) async throws -> URL?) async {
        guard let server = account?.server else { return }
        await unlockAdminWith { api, adminKey in
            let start = try await api.startBrowserUnlock(adminKey: adminKey)
            guard let url = start.url(server: server) else { throw ApiError(status: 0, code: "offline") }
            guard let callback = try await authenticate(url) else { return nil }
            guard start.matches(callback: callback) else {
                throw ApiError(status: 400, code: "", message: tr("Die Freischaltung kam nicht von dieser Adresse zurück. Bitte erneut versuchen."))
            }
            return try await api.unlockAdmin(browserTicket: start.ticket, adminKey: adminKey)
        }
    }

    private func unlockAdminWith(_ call: (Api, String) async throws -> AdminUnlock?) async {
        guard let session, let tresor, !adminBusy else { return }
        let epoch = self.epoch
        adminBusy = true
        adminError = nil
        defer { adminBusy = false }
        let api = session.api()
        // Härtung H7: neues Vorstands-Schlüsselpaar, liegt nur im Tresor
        let key = P256.Signing.PrivateKey()
        do {
            guard let result = try await call(api, SignedFormat.publicKey(key.publicKey)) else { return }
            let access = AdminAccess(token: result.token, key: result.signed ? key : nil)
            guard epoch == self.epoch else {
                // Inzwischen anderes Konto: den neuen Schlüssel gleich wieder sperren
                try? await api.lockAdmin()
                return
            }
            guard tresor.save(access.stored) else {
                try? await api.lockAdmin()
                adminError = tr("Für die Verwaltung braucht das Gerät einen Gerätecode. Bitte in den Einstellungen einrichten.")
                return
            }
            adminAccess = access
            adminUsed = .now
            adminOpen = true
            adminSealed = true
            await loadAdmin()
        } catch let failure as ApiError {
            if epoch == self.epoch { adminError = failure.text }
        } catch {
            if epoch == self.epoch { adminError = ApiError(status: 0, code: "offline").text }
        }
    }

    /// Schlüssel nach Face ID, Touch ID oder Gerätecode aus dem Tresor holen.
    func openAdmin() async {
        guard let tresor, adminSealed, !adminOpen, !adminBusy else { return }
        let epoch = self.epoch
        adminBusy = true
        defer { adminBusy = false }
        let result = await tresor.open(reason: tr("Verwaltung öffnen"))
        guard epoch == self.epoch else { return }
        switch result {
        case let .offen(stored):
            guard let access = AdminAccess(stored: stored) else {
                tresor.clear()
                adminSealed = false
                adminError = tr("Bitte die Verwaltung neu freischalten.")
                return
            }
            adminAccess = access
            adminUsed = .now
            adminOpen = true
            adminError = nil
        case .abgebrochen:
            adminError = tr("Bitte mit Face ID, Touch ID oder Gerätecode entsperren.")
        case .weg:
            tresor.clear()
            adminSealed = false
            adminError = tr("Bitte die Verwaltung neu freischalten.")
        }
    }

    /// Nach einer Änderung: Hinweis zeigen und „Rückgängig“ anbieten, soweit möglich.
    func adminChanged(_ unit: AdminUnit, text: String, change: AdminChange) {
        adminNotice = text
        adminUndo = change.changeSet.map { AdminUndo(unit: unit, changeSet: $0, task: change.task) }
    }

    /// Erledigt, ohne „Rückgängig“ (z. B. gebucht: Ändern und Storno im Browser).
    func adminDone(_ text: String) {
        adminNotice = text
        adminUndo = nil
    }

    /// Letzte Änderung zurücknehmen; true, wenn es geklappt hat.
    func undoAdmin() async -> Bool {
        guard let undo = adminUndo else { return false }
        let done: Bool? = await verwaltung(undo.unit) { client in
            try await client.undo(undo.changeSet, task: undo.task)
            return true
        }
        guard done == true else { return false }
        adminUndo = nil
        adminNotice = tr("Rückgängig gemacht")
        return true
    }

    /// Bild ohne Anmeldung laden (Foto auf der Prüfseite eines Ausweises).
    func publicImage(_ path: String) async -> Data? {
        guard let server = account?.server else { return nil }
        return await Api(server: server, transport: transport, language: Texte.language).image(path)
    }

    /// Schlüssel aus dem Arbeitsspeicher nehmen (neu entsperren); der Tresor bleibt.
    func lockAdminNow() {
        adminAccess = nil
        adminNotice = nil
        adminUndo = nil
        if adminOpen { adminOpen = false }
    }

    /// Nach mehr als fünf Minuten ohne Bedienung neu entsperren.
    func checkAdminIdle() {
        guard adminAccess != nil, !Demo.active else { return }
        if AdminPause.locked(sinceUse: seconds(since: adminUsed)) { lockAdminNow() }
    }

    /// Echte Bedienung verlängert die fünf Minuten.
    func adminTouched() {
        checkAdminIdle()
        if adminAccess != nil { adminUsed = .now }
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let passed = ContinuousClock.now - start
        return Double(passed.components.seconds)
    }

    /// App im Hintergrund: nach mehr als einer Minute ist die Verwaltung gesperrt.
    func sceneChanged(active: Bool) {
        if !active {
            if backgroundSince == nil { backgroundSince = .now }
            return
        }
        if let since = backgroundSince, !Demo.active, AdminPause.lockedAfterBackground(seconds(since: since)) {
            lockAdminNow()
        }
        backgroundSince = nil
        checkAdminIdle()
    }

    /// Verwaltung auf diesem Gerät sperren (das Gerät bleibt angemeldet).
    func lockAdmin() async {
        guard let session else { return }
        let epoch = self.epoch
        let tresor = self.tresor
        try? await session.api().lockAdmin()
        tresor?.clear()
        guard epoch == self.epoch else { return }
        lockAdminNow()
        adminSealed = false
        await loadAdmin()
    }

    /// Eine Anfrage der Verwaltung; nil mit Meldung in `adminError`, wenn sie nicht ging.
    func verwaltung<T>(_ unit: AdminUnit, _ work: @MainActor (AdminClient) async throws -> T) async -> T? {
        checkAdminIdle()
        guard let session, let access = adminAccess else { return nil }
        let epoch = self.epoch
        adminUsed = .now
        do {
            let value = try await work(AdminClient(api: session.api().verwaltung(access), unit: unit))
            guard epoch == self.epoch else { return nil }
            adminError = nil
            return value
        } catch let failure as ApiError {
            guard epoch == self.epoch else { return nil }
            if failure.mustReconnect {
                await disconnect(revoked: true)
                linkError = failure.text
            } else if failure.status == 401 {
                // Abgelaufen oder im Browser gesperrt: neu freischalten
                tresor?.clear()
                lockAdminNow()
                adminSealed = false
                adminError = tr("Bitte die Verwaltung neu freischalten.")
                await loadAdmin()
            } else {
                adminError = failure.text
            }
        } catch {
            if epoch == self.epoch { adminError = ApiError(status: 0, code: "offline").text }
        }
        return nil
    }

    // MARK: Versammlungen und Dokumente

    /// Antrag zu einer Versammlung einreichen; `true`, wenn er angekommen ist.
    func submitMotion(_ meeting: UpcomingMeeting, title: String, text: String) async -> Bool {
        guard let access else { return false }
        var sent = false
        taskNotice = nil
        await run { api in
            let motions = try await api.submitMotion(accessId: access.id, meetingId: meeting.id, title: title, text: text)
            if let index = self.meetings?.upcoming.firstIndex(where: { $0.id == meeting.id }) {
                self.meetings?.upcoming[index].motions = motions
            }
            self.taskNotice = tr("Antrag eingereicht. Dein Verein entscheidet, ob er auf die Tagesordnung kommt.")
            sent = true
        }
        return sent
    }

    func withdraw(_ motion: OwnMotion) async {
        guard let session, let access else { return }
        taskNotice = nil
        await run { api in
            try await api.withdrawMotion(accessId: access.id, motionId: motion.id)
            self.taskNotice = tr("Antrag zurückgezogen.")
        }
        if let fresh = try? await session.api().myMeetings(accessId: access.id), self.access?.id == access.id {
            meetings = fresh
        }
    }

    // MARK: Kurzmitteilung senden

    /// Ob und wohin dieses Konto Kurzmitteilungen senden darf; Fehler lassen den Knopf weg.
    func refreshSenders() async {
        guard let session else { return }
        let epoch = self.epoch
        let fresh = try? await session.api().senders()
        if epoch == self.epoch { senders = fresh }
    }

    /// Vorschau (`confirm` false) oder Senden; Fehlertext bei Problemen.
    func sendShort(_ sender: Sender, subject: String, body: String, confirm: Bool) async -> Result<SendResult, ApiError>? {
        await portalCall { api, _ in
            try await api.sendShort(sender, subject: subject, body: body, confirm: confirm)
        }
    }

    // MARK: Versammlung live

    /// Aufruf im eigenen Mitgliederbereich ohne die Ladeanzeige der ganzen App (z. B. die
    /// laufende Versammlung, die alle paar Sekunden nachfragt). `nil`, wenn das Konto inzwischen
    /// gewechselt oder getrennt wurde.
    func portalCall<T: Sendable>(_ work: @escaping (Api, Int) async throws -> T) async -> Result<T, ApiError>? {
        guard let session, let access else { return nil }
        let epoch = self.epoch
        do {
            let value = try await work(session.api(), access.id)
            return epoch == self.epoch && self.access?.id == access.id ? .success(value) : nil
        } catch let failure as ApiError {
            guard epoch == self.epoch else { return nil }
            if failure.mustReconnect {
                await disconnect(revoked: true)
                linkError = failure.text
                return nil
            }
            return .failure(failure)
        } catch {
            return epoch == self.epoch ? .failure(ApiError(status: 0, code: "offline")) : nil
        }
    }

    func liveCall(_ work: @escaping (Api, Int) async throws -> MeetingLive) async -> Result<MeetingLive, ApiError>? {
        await portalCall(work)
    }

    // MARK: Auslagen

    /// Auslagen neu laden (nach einer Aktion oder beim Öffnen).
    func reloadExpenses() async {
        guard let access, access.hasExpenses else { return }
        await run { api in
            let fresh = try await api.memberExpenses(accessId: access.id)
            if self.access?.id == access.id { self.expenses = fresh }
        }
    }

    // MARK: Beitragsnachweise

    /// Stand der Beitragsnachweise neu laden (nach dem Einreichen oder beim Öffnen).
    func reloadFeeProofs() async {
        guard let access, access.hasFeeProofs else { return }
        await run { api in
            let fresh = try await api.memberFeeProofs(accessId: access.id)
            if self.access?.id == access.id { self.feeProofs = fresh }
        }
    }

    // MARK: Pinnwand

    /// Pinnwand neu laden; gilt als gelesen (Zähler „neu“ geht auf 0).
    func reloadPinboard() async {
        guard let access, access.hasPinboard else { return }
        await run { api in
            let fresh = try await api.memberPinboard(accessId: access.id)
            if self.access?.id == access.id { self.pinboard = fresh }
        }
    }

    func pin(_ notice: PinNotice, pinned: Bool) async {
        guard let access else { return }
        await run { api in
            _ = try await api.pinPinNotice(accessId: access.id, notice: notice, pinned: pinned)
        }
        await reloadPinboard()
    }

    /// Beitrag löschen; `true`, wenn es geklappt hat.
    func removePin(_ notice: PinNotice) async -> Bool {
        guard let access else { return false }
        var done = false
        await run { api in
            try await api.deletePinNotice(accessId: access.id, id: notice.id)
            done = true
        }
        await reloadPinboard()
        return done
    }

    /// Bild aus dem eigenen Mitgliederbereich (mit Geräteschlüssel).
    func portalImage(_ path: String) async -> Data? {
        guard let session else { return nil }
        return await session.api().image(path)
    }

    // MARK: Bestellungen

    /// Sammelbestellungen neu laden (nach einer Aktion oder beim Öffnen).
    func reloadOrders() async {
        guard let access, access.hasOrders else { return }
        await run { api in
            let fresh = try await api.memberOrders(accessId: access.id)
            if self.access?.id == access.id { self.orders = fresh }
        }
    }

    /// Einzelansicht mit Artikeln zum Bestellen; `nil` bei Fehler (steht dann in `error`).
    func orderCampaign(_ id: Int) async -> OrderCampaign? {
        guard let access else { return nil }
        var found: OrderCampaign?
        await run { api in found = try await api.memberOrderCampaign(accessId: access.id, id: id) }
        return found
    }

    /// Eine Aktion zu einer Sammelbestellung; danach Liste neu. `true`, wenn sie geklappt hat.
    private func orderAction(_ notice: String, _ work: @escaping (Api, Int) async throws -> OrderCampaign) async -> Bool {
        guard let access else { return false }
        var done = false
        taskNotice = nil
        await run { api in
            _ = try await work(api, access.id)
            self.taskNotice = notice
            done = true
        }
        if done { await reloadOrders() }
        return done
    }

    func placeOrder(_ campaign: OrderCampaign, lines: [OrderInput], note: String) async -> Bool {
        await orderAction(tr("Danke, deine Bestellung ist gespeichert.")) { api, access in
            try await api.placeOrder(accessId: access, id: campaign.id, lines: lines, note: note)
        }
    }

    func withdrawOrder(_ campaign: OrderCampaign) async -> Bool {
        await orderAction(tr("Bestellung zurückgezogen.")) { api, access in
            try await api.withdrawOrder(accessId: access, id: campaign.id)
        }
    }

    // MARK: Umfragen

    /// Umfragen neu laden (nach einer Aktion oder beim Öffnen).
    func reloadSurveys() async {
        guard let access, access.hasSurveys else { return }
        await run { api in
            let fresh = try await api.memberSurveys(accessId: access.id)
            if self.access?.id == access.id { self.surveys = fresh }
        }
    }

    /// Eine Aktion zu einer Umfrage; danach Liste neu. `true`, wenn sie geklappt hat.
    private func surveyAction(_ notice: String, _ work: @escaping (Api, Int) async throws -> MemberSurvey) async -> Bool {
        guard let access else { return false }
        var done = false
        taskNotice = nil
        await run { api in
            _ = try await work(api, access.id)
            self.taskNotice = notice
            done = true
        }
        if done { await reloadSurveys() }
        return done
    }

    func answer(_ survey: MemberSurvey, draft: [Int: SurveyAnswerRow]) async -> Bool {
        await surveyAction(tr("Danke, deine Antwort ist gespeichert.")) { api, access in
            try await api.answerSurvey(accessId: access, surveyId: survey.id, payload: survey.answerPayload(draft))
        }
    }

    func withdraw(_ survey: MemberSurvey) async {
        _ = await surveyAction(tr("Antwort zurückgezogen.")) { api, access in
            try await api.withdrawSurvey(accessId: access, surveyId: survey.id)
        }
    }

    func follow(_ survey: MemberSurvey) async {
        _ = await surveyAction(tr("Zusage gespeichert.")) { api, access in
            try await api.followSurvey(accessId: access, surveyId: survey.id)
        }
    }

    /// Ordner für Dateien zum Ansehen; wird bei jedem Öffnen, beim Start und beim Trennen geleert.
    private static var viewDir: URL { FileManager.default.temporaryDirectory.appendingPathComponent("ansicht", isDirectory: true) }

    static func clearViews() { try? FileManager.default.removeItem(at: viewDir) }

    /// Datei laden und zum Ansehen öffnen. Die App behält sie nicht.
    private func view(name: String, _ load: @escaping (Api) async throws -> Data) async {
        guard !previewBusy else { return }
        previewBusy = true
        defer { previewBusy = false }
        await run { api in
            let data = try await load(api)
            Self.clearViews()
            try? FileManager.default.createDirectory(at: Self.viewDir, withIntermediateDirectories: true)
            let file = Self.viewDir.appendingPathComponent(Ansicht.safeName(name))
            do {
                try data.write(to: file, options: [.atomic, .completeFileProtection])
            } catch {
                throw ApiError(status: 0, code: "format")
            }
            self.preview = file
        }
    }

    /// Quittung einer Barzahlung aus der Verwaltung laden und zum Ansehen öffnen (dort auch teilen).
    func openCashReceipt(_ unit: AdminUnit, payment: Int, name: String) async {
        guard !previewBusy else { return }
        previewBusy = true
        defer { previewBusy = false }
        guard let loaded = await verwaltung(unit, { await $0.cashReceipt(payment: payment) }) else { return }
        guard let data = loaded else {
            adminError = tr("Die Quittung ließ sich nicht laden.")
            return
        }
        Self.clearViews()
        try? FileManager.default.createDirectory(at: Self.viewDir, withIntermediateDirectories: true)
        let file = Self.viewDir.appendingPathComponent(Ansicht.safeName(name))
        guard (try? data.write(to: file, options: [.atomic, .completeFileProtection])) != nil else {
            adminError = tr("Die Quittung ließ sich nicht laden.")
            return
        }
        preview = file
    }

    func openMinutes(_ meeting: PastMeeting) async {
        guard let access else { return }
        await view(name: "protokoll-\(meeting.id).pdf") { api in
            try await api.minutesPdf(accessId: access.id, meetingId: meeting.id)
        }
    }

    func openDocument(_ document: MyDocument) async {
        guard let access, let version = document.current else { return }
        await view(name: version.name) { api in
            try await api.documentFile(accessId: access.id, path: version.url)
        }
    }

    /// Anhang einer Mitteilung in der App ansehen statt im Browser (IOS-22).
    func openCircularAttachment(_ item: CircularItem, _ file: CircularFile) async {
        guard let access else { return }
        await view(name: file.name) { api in
            try await api.circularAttachment(accessId: access.id, circularId: item.id, attachmentId: file.id)
        }
    }

    /// Rechnung oder Stornorechnung als PDF ansehen (nur online, wird nicht gespeichert).
    func openInvoice(_ invoice: MyInvoice, cancellation: Bool = false) async {
        guard let access else { return }
        let name = Ansicht.safeName((cancellation ? "storno-" : "rechnung-") + invoice.number + ".pdf", fallback: "rechnung.pdf")
        await view(name: name) { api in
            try await api.invoicePdf(accessId: access.id, invoiceId: invoice.id, cancellation: cancellation)
        }
    }

    /// Eintrittskarten einer Anmeldung ansehen (nur online, wird nicht gespeichert).
    func openTickets(eventId: Int, registration: MyRegistration) async {
        guard let access else { return }
        let name = Ansicht.safeName("eintrittskarten-" + registration.number + ".pdf", fallback: "eintrittskarten.pdf")
        await view(name: name) { api in
            try await api.registrationTickets(accessId: access.id, eventId: eventId, registrationId: registration.id)
        }
    }

    func choose(access id: Int) async {
        guard id != access?.id else { return }
        accessId = id
        if let account = accounts.activeId, !Demo.active { Zustand.merke(zugang: id, account: account) }
        events = []
        circulars = []
        unreadCirculars = []
        offlineSince = nil
        loadedAt = nil
        rsvpErrors = RueckmeldungsFehler()
        rsvpNotices = [:]
        card = nil
        profile = nil
        invoices = nil
        mandate = nil
        meetings = nil
        documents = nil
        surveys = nil
        pinboard = nil
        orders = nil
        expenses = nil
        feeProofs = nil
        scores = nil
        sheetCache = [:]
        todos = []
        helpers = nil
        taskNotice = nil
        await refresh()
    }

    /// Ausweis des gewählten Zugangs: erst aus der Ablage zeigen, dann frisch holen.
    func refreshCard() async {
        guard let session, let access else { return }
        let id = access.id
        let epoch = self.epoch
        if card == nil { card = cards.load(accessId: id) }
        do {
            let fresh = try await session.api().refreshCard(accessId: id, store: cards)
            guard epoch == self.epoch, self.access?.id == id else { return }
            card = fresh
            cardOffline = false
        } catch let failure as ApiError {
            guard epoch == self.epoch else { return }
            if failure.mustReconnect {
                await disconnect(revoked: true)
                linkError = failure.text
            } else {
                cardOffline = true
            }
        } catch {
            if epoch == self.epoch { cardOffline = true }
        }
    }

    // MARK: Hinweis „Rückmeldung fehlt“

    /// Hinweise für den gezeigten Zugang neu planen (nach jedem Abgleich und jeder Rückmeldung).
    func planHints() async {
        guard !Demo.active, let account, let access else { return }
        await refreshHintPermission()
        let hints = RueckmeldeHinweis.plan(events, accessId: access.id, account: account.id)
        await Hinweise.plan(hints, account: account.id, unit: access.clubName)
    }

    /// Erlaubnis frisch lesen, z. B. beim Öffnen von „Mein Konto“ (in den Einstellungen geändert?).
    func refreshHintPermission() async {
        let state = await Hinweise.erlaubnis()
        hintsDenied = state == .verweigert
        hintsUndecided = state == .offen
    }

    /// Angebot „Erinnern lassen“ bei den Terminen: nur, solange das Gerät noch nicht gefragt hat
    /// und ein Termin ohne Rückmeldung mit Anmeldeschluss wartet.
    var offerHints: Bool {
        guard !Demo.active, hintsOn, hintsUndecided, !hintOfferDismissed, let account, let access else { return false }
        return !RueckmeldeHinweis.plan(events, accessId: access.id, account: account.id).isEmpty
    }

    func dismissHintOffer() {
        hintOfferDismissed = true
        UserDefaults.standard.set(true, forKey: "hinweis_angebot_weg")
    }

    /// Schalter in „Mein Konto“; beim Einschalten fragt das Gerät einmal nach der Erlaubnis.
    func setHints(on: Bool) async {
        Hinweise.on = on
        hintsOn = on
        if on {
            hintsDenied = !(await Hinweise.erlauben())
            hintsUndecided = false
            await planHints()
        } else if let account {
            await Hinweise.clear(account: account.id)
        }
    }

    /// Zusage oder Absage aus der Mitteilung; nur für das gezeigte Konto (sonst öffnet sich nur die App).
    func respondFromHint(account id: String, accessId: Int, eventId: Int, status: String) async {
        guard let session, account?.id == id else { return }
        let epoch = self.epoch
        do {
            try await session.api().respond(accessId: accessId, eventId: eventId, status: status)
        } catch {
            // Am Termin zeigen, nicht als allgemeinen Ladefehler (IOS-01)
            if epoch == self.epoch {
                rsvpErrors.failed(eventId, (error as? ApiError)?.text ?? ApiError(status: 0, code: "offline").text)
                showEvents += 1
            }
            return
        }
        if epoch == self.epoch { rsvpNotices[eventId] = Rueckmeldung.gespeichert(status) }
        if epoch == self.epoch {
            calendarSynced[id] = nil
            await refresh()
        }
    }

    /// Zu- oder Absage, Vielleicht oder Zurücknehmen (`status` nil). Ein Fehler bleibt am Termin
    /// stehen, auch über den folgenden Abgleich hinweg (UX-Audit 16.11., IOS-01); eine gelungene
    /// Rückmeldung bekommt einen Satz am Termin (IOS-02). Gibt den Termin danach zurück.
    @discardableResult
    func respond(_ event: Occurrence, status: String?, guests: Int = 0, note: String = "") async -> EventDetail? {
        guard let access else { return nil }
        let id = event.eventId
        rsvpErrors.start(id)
        rsvpNotices[id] = nil
        rsvpBusy.insert(id)
        defer { rsvpBusy.remove(id) }
        let result = await portalCall { (api: Api, access: Int) async throws -> EventDetail? in
            if let status {
                return try await api.respond(accessId: access, eventId: id, status: status, guests: guests, note: note)
            }
            return try await api.withdraw(accessId: access, eventId: id)
        }
        guard self.access?.id == access.id else { return nil }
        switch result {
        case .success(let detail):
            rsvpNotices[id] = Rueckmeldung.gespeichert(status)
            if let accountId = accounts.activeId { calendarSynced[accountId] = nil }
            // Nur die Liste neu holen, nicht alles: Der Satz am Termin bleibt stehen
            await reloadEvents()
            await planHints()
            await syncCalendar()
            return detail
        case .failure(let failure):
            rsvpErrors.failed(id, failure.text)
            return nil
        case nil:
            return nil
        }
    }

    /// Ein Termin mit allen Angaben für die Detailseite.
    func eventDetail(_ event: Occurrence) async -> Result<EventDetail, ApiError>? {
        await portalCall { api, access in try await api.event(accessId: access, eventId: event.eventId) }
    }

    /// Anhang eines Termins zum Ansehen öffnen.
    func openAttachment(_ event: EventDetail, _ file: EventFile) async {
        guard let access else { return }
        await view(name: file.shownName) { api in
            try await api.eventAttachment(accessId: access.id, eventId: event.id, attachmentId: file.id)
        }
    }

    /// Nur die Terminliste des gewählten Zugangs neu laden.
    func reloadEvents() async {
        guard let access else { return }
        let id = access.id
        let now = Date()
        let end = Calendar.current.date(byAdding: .month, value: 6, to: now) ?? now
        if case .success(let fresh) = await portalCall({ api, access in
            try await api.events(accessId: access, from: Zeit.day(now), to: Zeit.day(end))
        }), self.access?.id == id {
            events = fresh
            rsvpErrors.keep(only: fresh)
        }
    }

    // MARK: Aufgaben und Helferdienste

    func refreshTasks() async {
        guard let session, let access else { return }
        let id = access.id
        let epoch = self.epoch
        let api = session.api()
        var todos: [MemberTodo]?
        var helpers: HelperOverview?
        if access.hasTodos { todos = try? await api.memberTodos(accessId: id) }
        if access.hasHelpers { helpers = try? await api.helpers(accessId: id) }
        guard epoch == self.epoch, self.access?.id == id else { return }
        if let todos { self.todos = todos } else if !access.hasTodos { self.todos = [] }
        if let helpers { self.helpers = helpers } else if !access.hasHelpers { self.helpers = nil }
    }

    /// Aufgabe übernehmen ("claim"), freigeben ("release") oder erledigen/wieder öffnen ("status").
    func change(_ todo: MemberTodo, action: String) async {
        guard let access else { return }
        taskNotice = nil
        await run { api in
            let fresh: MemberTodo
            let notice: String
            switch action {
            case "claim":
                fresh = try await api.claimTodo(accessId: access.id, id: todo.id, version: todo.version, claim: true)
                notice = tr("Aufgabe übernommen.")
            case "release":
                fresh = try await api.claimTodo(accessId: access.id, id: todo.id, version: todo.version, claim: false)
                notice = tr("Übernahme freigegeben.")
            default:
                fresh = try await api.completeTodo(accessId: access.id, id: todo.id, version: todo.version, done: !todo.done)
                notice = fresh.done ? tr("Aufgabe erledigt.") : tr("Aufgabe wieder geöffnet.")
            }
            if let index = self.todos.firstIndex(where: { $0.id == fresh.id }) { self.todos[index] = fresh }
            self.taskNotice = notice
        }
        await refreshTasks()
    }

    func signup(_ shift: HelperShift) async {
        guard let access else { return }
        taskNotice = nil
        await run { api in
            try await api.signupShift(accessId: access.id, shiftId: shift.id)
            self.taskNotice = tr("Du bist eingetragen.")
        }
        await refreshTasks()
    }

    func cancelShift(_ shift: MyShift) async {
        guard let access else { return }
        taskNotice = nil
        await run { api in
            try await api.cancelShift(accessId: access.id, assignmentId: shift.id)
            self.taskNotice = tr("Dienst abgesagt.")
        }
        await refreshTasks()
    }

    // MARK: Noten

    func refreshScores() async {
        guard let access, access.hasScores else {
            scores = nil
            return
        }
        let id = access.id
        let epoch = self.epoch
        await run { api in
            let fresh = try await api.scoreFolders(accessId: id)
            guard epoch == self.epoch, self.access?.id == id else { return }
            self.scores = fresh
        }
    }

    /// Notenblätter eines Stücks in Spielreihenfolge (PDF oder Bild); `nil`, wenn eines fehlt.
    /// Die App behält sie nur im Arbeitsspeicher, bis das Konto oder der Verein wechselt.
    func sheets(of piece: FolderItem) async -> [Data]? {
        guard let session, let access else { return nil }
        let epoch = self.epoch
        let api = session.api()
        var result: [Data] = []
        for file in piece.sheets {
            let key = "\(access.id)-\(file.id)-\(file.version)"
            if let known = sheetCache[key] {
                result.append(known)
                continue
            }
            do {
                let data = try await api.scoreFile(accessId: access.id, file: file)
                guard epoch == self.epoch else { return nil }
                if sheetCache.count >= 60 { sheetCache = [:] }
                sheetCache[key] = data
                result.append(data)
                error = nil
            } catch let failure as ApiError {
                if failure.mustReconnect {
                    await disconnect(revoked: true)
                    linkError = failure.text
                } else {
                    error = failure.text
                }
                return nil
            } catch {
                self.error = ApiError(status: 0, code: "offline").text
                return nil
            }
        }
        return result
    }

    // MARK: Gerätekalender

    func setCalendar(on: Bool) async {
        if on {
            var granted = Demo.active
            if !granted { granted = await Geraetekalender.shared.request() }
            guard granted else {
                calendarDenied = true
                return
            }
        } else if !Demo.active {
            Geraetekalender.shared.remove()
        }
        calendarDenied = false
        calendarOn = on
        calendarSynced = [:]
        if !Demo.active { KalenderEinstellung.on = on }
        await syncCalendar()
    }

    func setReminder(_ minutes: Int?) async {
        reminder = minutes
        calendarSynced = [:]
        if !Demo.active { KalenderEinstellung.reminder = minutes }
        await syncCalendar()
    }

    /// Termine aller Einheiten des gezeigten Kontos in den Gerätekalender schreiben
    /// (höchstens alle 15 Minuten, sofort nach einer Rückmeldung oder geänderter Einstellung).
    private func syncCalendar() async {
        guard calendarOn, !Demo.active, let session, let account else { return }
        guard Geraetekalender.allowed else {
            // Zugriff in den Einstellungen des Geräts entzogen
            calendarOn = false
            KalenderEinstellung.on = false
            return
        }
        if let last = calendarSynced[account.id], Date().timeIntervalSince(last) < 15 * 60 { return }
        let epoch = self.epoch
        let api = session.api()
        let now = Date()
        let from = Zeit.day(now.addingTimeInterval(-30 * 86400))
        let to = Zeit.day(now.addingTimeInterval(400 * 86400))
        var keep = Set<String>()
        var complete = true
        for access in accesses where access.eventsEnabled {
            let name = CalendarMark.name(server: account.server, accessId: access.id)
            keep.insert(name)
            let title = access.clubDisplayName.isEmpty ? access.clubName : access.clubDisplayName
            do {
                let items = try await api.events(accessId: access.id, from: from, to: to)
                guard epoch == self.epoch, calendarOn else { return }
                let wanted = items.compactMap { $0.calendarEntry(unitTitle: title, reminderMinutes: reminder) }
                try Geraetekalender.shared.sync(name: name, title: title, wanted: wanted)
            } catch {
                complete = false
            }
        }
        guard epoch == self.epoch else { return }
        if complete {
            Geraetekalender.shared.remove(prefix: CalendarMark.prefix(server: account.server), keep: keep)
            calendarSynced[account.id] = now
        }
    }
}
