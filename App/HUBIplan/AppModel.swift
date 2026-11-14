import Foundation
import HubiplanKern
import SwiftUI
import UIKit

/// Änderung der Verwaltung, die sich noch zurücknehmen lässt.
struct AdminUndo: Equatable {
    let unit: AdminUnit
    let changeSet: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts = AccountList()
    /// Ein weiteres Konto wird gerade verbunden (Blatt über „Mein Konto“)
    @Published var adding = false
    @Published var accesses: [PortalAccess] = []
    @Published var accessId: Int?
    @Published var events: [Occurrence] = []
    @Published var circulars: [CircularItem] = []
    /// Ausweis des gewählten Zugangs, wie er zuletzt kam (auch ohne Netz)
    @Published var card: StoredCard?
    /// Der Ausweis ließ sich zuletzt nicht abrufen
    @Published var cardOffline = false
    /// Eigene Daten und Rechnungen des gewählten Zugangs
    @Published var profile: Profile?
    @Published var invoices: MyInvoices?
    /// Versammlungen und Dokumente des gewählten Zugangs (soweit eingeschaltet)
    @Published var meetings: MyMeetings?
    @Published var documents: MyDocuments?
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
    @Published var linkError: String?
    /// Gerätekalender: eingeschaltet, Erinnerung in Minuten, Zugriff verweigert
    @Published private(set) var calendarOn = KalenderEinstellung.on
    @Published private(set) var reminder = KalenderEinstellung.reminder
    @Published var calendarDenied = false
    /// Zählt hoch, wenn die App über einen Kalendereintrag geöffnet wurde (dann Reiter „Termine“)
    @Published var showEvents = 0

    private let transport: Transport = Demo.active ? DemoTransport() : UrlSessionTransport()
    private var session: DeviceSession?
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

    init() {
        Texte.language = Texte.pick(preferred: Locale.preferredLanguages)
        Self.clearViews()
        accounts = Demo.active ? Demo.accounts : Konten.load()
        activate()
    }

    /// Das gezeigte Konto
    var account: AccountEntry? { accounts.active }

    private func makeSession(server: String, id: String) -> DeviceSession {
        let store: SecretStore = Demo.active ? DemoStore() : Konten.secrets(id)
        return DeviceSession(server: server, store: store, transport: transport)
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
        circulars = []
        card = nil
        profile = nil
        invoices = nil
        meetings = nil
        documents = nil
        scores = nil
        sheetCache = [:]
        adminOverview = nil
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

    // MARK: Verbinden

    /// Link aus QR-Code, Eingabefeld oder `hubiplan://verbinden…`; verbunden wird erst nach Rückfrage.
    func offer(link: String) {
        if CalendarMark.isEventLink(link) {
            showEvents += 1
            return
        }
        guard !accounts.full else {
            linkError = tr("Mehr als {anzahl} Konten lassen sich nicht verbinden. Trenne zuerst ein Konto.", ["anzahl": "\(AccountList.limit)"])
            return
        }
        if let parsed = PairingLink.parse(link) {
            pending = parsed
            linkError = nil
        } else {
            linkError = tr("Das ist kein Link zum Verbinden. Er beginnt mit https:// und endet auf /app/verbinden#code=…")
        }
    }

    func connect() async {
        guard let link = pending else { return }
        pending = nil
        loading = true
        let id = accounts.freeId()
        let new = makeSession(server: link.server, id: id)
        do {
            let paired = try await new.connect(code: link.code, deviceName: UIDevice.current.name, appVersion: Self.version)
            let entry = AccountEntry(id: id, server: link.server, display: paired.user.display, email: paired.user.email)
            // Dasselbe Konto noch einmal verbunden: der alte Eintrag weicht dem neuen
            if let replaced = accounts.add(entry) { await forget(replaced) }
            save()
            activate(session: new)
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
        await makeSession(server: entry.server, id: entry.id).forget()
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
    func disconnect() async {
        guard let account else { return }
        await session?.forget()
        if !Demo.active { VerwaltungTresor(account: account.id).clear() }
        cards.clear()
        Self.clearViews()
        preview = nil
        if !Demo.active { Geraetekalender.shared.remove(prefix: CalendarMark.prefix(server: account.server)) }
        calendarSynced[account.id] = nil
        accounts.remove(account.id)
        save()
        activate()
        if self.account != nil { await refresh() }
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
                await disconnect()
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
            if self.access == nil { self.accessId = me.portal.first?.id }
            guard let access = self.access else {
                self.events = []
                self.circulars = []
                return
            }
            let now = Date()
            let end = Calendar.current.date(byAdding: .month, value: 6, to: now) ?? now
            let events = try await api.events(accessId: access.id, from: Zeit.day(now), to: Zeit.day(end))
            let circulars = try await api.circulars(accessId: access.id)
            guard epoch == self.epoch else { return }
            self.events = events
            self.circulars = circulars
        }
        if epoch == self.epoch { await refreshIch() }
        if epoch == self.epoch { await refreshTasks() }
        if epoch == self.epoch { await syncCalendar() }
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
        if access.has(module: "billing", fallback: true) {
            invoices = try? await api.myInvoices(accessId: id)
        }
        var meetings: MyMeetings?
        if access.hasMeetings { meetings = try? await api.myMeetings(accessId: id) }
        var documents: MyDocuments?
        if access.hasDocs { documents = try? await api.myDocuments(accessId: id) }
        guard epoch == self.epoch, self.access?.id == id else { return }
        if let profile { self.profile = profile }
        self.invoices = invoices ?? self.invoices
        self.meetings = access.hasMeetings ? (meetings ?? self.meetings) : nil
        self.documents = access.hasDocs ? (documents ?? self.documents) : nil
        await loadAdmin()
    }

    // MARK: Verwaltung

    private var tresor: VerwaltungTresor? {
        guard !Demo.active, let account else { return nil }
        return VerwaltungTresor(account: account.id)
    }

    /// Einheiten mit Verwaltungsrechten und ob dieses Gerät freigeschaltet ist.
    func loadAdmin() async {
        guard let session else { return }
        let epoch = self.epoch
        let overview = try? await session.api().adminOverview()
        guard epoch == self.epoch else { return }
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
        guard let session, let tresor, !adminBusy else { return }
        let epoch = self.epoch
        adminBusy = true
        adminError = nil
        defer { adminBusy = false }
        let api = session.api()
        // Härtung H7: neues Vorstands-Schlüsselpaar, liegt nur im Tresor
        let key = P256.Signing.PrivateKey()
        do {
            let result = try await api.unlockAdmin(
                password: password, code: code.trimmingCharacters(in: .whitespaces),
                adminKey: SignedFormat.publicKey(key.publicKey)
            )
            let access = AdminAccess(token: result.token, key: result.signed ? key : nil)
            guard epoch == self.epoch else {
                // Inzwischen anderes Konto: den neuen Schlüssel gleich wieder sperren
                try? await api.lockAdmin()
                return
            }
            guard tresor.save(access.stored) else {
                try? await api.lockAdmin()
                adminError = tr("Für die Verwaltung braucht das iPhone einen Gerätecode. Bitte in den Einstellungen einrichten.")
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
        adminUndo = change.changeSet.map { AdminUndo(unit: unit, changeSet: $0) }
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
            try await client.undo(undo.changeSet)
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
                await disconnect()
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
            self.taskNotice = tr("Antrag eingereicht. Der Vorstand entscheidet, ob er auf die Tagesordnung kommt.")
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

    func choose(access id: Int) async {
        accessId = id
        card = nil
        profile = nil
        invoices = nil
        meetings = nil
        documents = nil
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
                await disconnect()
                linkError = failure.text
            } else {
                cardOffline = true
            }
        } catch {
            if epoch == self.epoch { cardOffline = true }
        }
    }

    func respond(_ event: Occurrence, status: String) async {
        guard let access else { return }
        await run { api in
            try await api.respond(accessId: access.id, eventId: event.eventId, status: status)
        }
        if let id = accounts.activeId { calendarSynced[id] = nil }
        await refresh()
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
                    await disconnect()
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
