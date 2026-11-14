import Foundation
import HubiplanKern
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var account: Account?
    @Published var accesses: [PortalAccess] = []
    @Published var accessId: Int?
    @Published var events: [Occurrence] = []
    @Published var circulars: [CircularItem] = []
    @Published var loading = false
    @Published var error: String?
    /// Link, den die App zum Verbinden bekommen hat und der noch bestätigt werden muss
    @Published var pending: PairingLink?
    @Published var linkError: String?

    private let transport: Transport = Demo.active ? DemoTransport() : UrlSessionTransport()
    private var session: DeviceSession?

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    init() {
        Texte.language = Texte.pick(preferred: Locale.preferredLanguages)
        if Demo.active {
            account = Demo.account
            session = DeviceSession(server: Demo.account.server, store: DemoStore(), transport: transport)
        } else if let saved = Account.load() {
            account = saved
            session = makeSession(saved.server)
        }
    }

    private func makeSession(_ server: String) -> DeviceSession {
        DeviceSession(server: server, store: KeychainStore(service: "de.hubiplan.app.konto"), transport: transport)
    }

    var access: PortalAccess? { accesses.first { $0.id == accessId } ?? accesses.first }

    // MARK: Verbinden

    /// Link aus QR-Code, Eingabefeld oder `hubiplan://verbinden…`; verbunden wird erst nach Rückfrage.
    func offer(link: String) {
        guard account == nil else { return }
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
        defer { loading = false }
        let new = makeSession(link.server)
        do {
            let paired = try await new.connect(code: link.code, deviceName: UIDevice.current.name, appVersion: Self.version)
            let saved = Account(server: link.server, display: paired.user.display, email: paired.user.email)
            Account.save(saved)
            session = new
            account = saved
            linkError = nil
            await refresh()
        } catch let failure as ApiError {
            linkError = failure.text
        } catch {
            linkError = ApiError(status: 0, code: "offline").text
        }
    }

    func disconnect() async {
        await session?.forget()
        session = nil
        if !Demo.active { Account.save(nil) }
        account = nil
        accesses = []
        accessId = nil
        events = []
        circulars = []
        error = nil
    }

    // MARK: Daten

    private func run(_ work: @MainActor (Api) async throws -> Void) async {
        guard let session else { return }
        loading = true
        defer { loading = false }
        do {
            try await work(session.api())
            error = nil
        } catch let failure as ApiError {
            if failure.mustReconnect {
                await disconnect()
                linkError = failure.text
            } else {
                error = failure.text
            }
        } catch {
            self.error = ApiError(status: 0, code: "offline").text
        }
    }

    func refresh() async {
        await run { api in
            let me = try await api.me()
            self.accesses = me.portal
            if self.access == nil { self.accessId = me.portal.first?.id }
            guard let access = self.access else {
                self.events = []
                self.circulars = []
                return
            }
            let now = Date()
            let end = Calendar.current.date(byAdding: .month, value: 6, to: now) ?? now
            self.events = try await api.events(accessId: access.id, from: Zeit.day(now), to: Zeit.day(end))
            self.circulars = try await api.circulars(accessId: access.id)
        }
    }

    func choose(access id: Int) async {
        accessId = id
        await refresh()
    }

    func respond(_ event: Occurrence, status: String) async {
        guard let access else { return }
        await run { api in
            try await api.respond(accessId: access.id, eventId: event.eventId, status: status)
        }
        await refresh()
    }
}
