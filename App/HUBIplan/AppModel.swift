import Foundation
import HubiplanKern
import SwiftUI
import UIKit

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

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    init() {
        Texte.language = Texte.pick(preferred: Locale.preferredLanguages)
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
        cards.clear()
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
        guard epoch == self.epoch, self.access?.id == id else { return }
        if let profile { self.profile = profile }
        self.invoices = invoices ?? self.invoices
    }

    func choose(access id: Int) async {
        accessId = id
        card = nil
        profile = nil
        invoices = nil
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
