import XCTest
@testable import HubiplanKern

/// Belegung, Kündigung, Meldungen und Abwesenheiten wie in der Android-App
/// (MitgliedAnfragenTest). Erfundene Daten.
final class MitgliedAnfragenTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    private func body(_ request: HttpRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]) ?? [:]
    }

    private func flag(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        return (value as? NSNumber)?.boolValue
    }

    private func date(_ text: String) -> Date { Zeit.parse(text)! }

    func testBereicheNurMitSchalter() throws {
        let none = try decode(PortalAccess.self, #"{"id":5,"club_name":"Musterstadt","modules":["billing"]}"#)
        XCTAssertFalse(none.hasBookings)
        XCTAssertFalse(none.hasEntries)
        XCTAssertFalse(none.hasAbsences)
        let all = try decode(PortalAccess.self, #"{"id":5,"club_name":"Musterstadt","modules":["entries","music"],"bookings_enabled":true,"musician":true}"#)
        XCTAssertTrue(all.hasBookings)
        XCTAssertTrue(all.hasEntries)
        XCTAssertTrue(all.hasAbsences)
        // Ältere Instanz ohne Modulliste: der einzelne Schalter
        let old = try decode(PortalAccess.self, #"{"id":5,"club_name":"Musterstadt","entries_enabled":true}"#)
        XCTAssertTrue(old.hasEntries)
    }

    func testAnfrageZeiten() {
        // Ganztägig: erster und letzter Tag 0:00 deutscher Zeit
        let all = Belegung.requestTimes(start: date("2026-11-20T15:00:00+01:00"), end: date("2026-11-22T09:00:00+01:00"), allDay: true, timeZone: berlin)
        XCTAssertEqual(all?.from, "2026-11-20T00:00:00+01:00")
        XCTAssertEqual(all?.to, "2026-11-22T00:00:00+01:00")
        let evening = Belegung.requestTimes(start: date("2026-11-20T18:00:00+01:00"), end: date("2026-11-20T23:00:00+01:00"), allDay: false, timeZone: berlin)
        XCTAssertEqual(evening?.from, "2026-11-20T18:00:00+01:00")
        XCTAssertEqual(evening?.to, "2026-11-20T23:00:00+01:00")
        XCTAssertNil(Belegung.requestTimes(start: date("2026-11-20T18:00:00+01:00"), end: date("2026-11-20T17:00:00+01:00"), allDay: false))
        XCTAssertNil(Belegung.requestTimes(start: date("2026-11-21T10:00:00+01:00"), end: date("2026-11-20T10:00:00+01:00"), allDay: true, timeZone: berlin))
        XCTAssertEqual(Zeit.day(Belegung.monday(date("2026-11-20T12:00:00+01:00"), timeZone: berlin), timeZone: berlin), "2026-11-16")
        XCTAssertEqual(Zeit.day(Belegung.monday(date("2026-11-16T08:00:00+01:00"), timeZone: berlin), timeZone: berlin), "2026-11-16")
        XCTAssertEqual(Zeit.day(Belegung.monday(date("2026-11-22T20:00:00+01:00"), timeZone: berlin), timeZone: berlin), "2026-11-16")
        // Ganztägig: angezeigt bis zum letzten Tag
        XCTAssertEqual(Belegung.shownEnd("2026-11-22T00:00:00+01:00", allDay: true), "2026-11-21T23:59:59+01:00")
        XCTAssertEqual(Belegung.shownEnd("2026-11-22T00:00:00+01:00", allDay: false), "2026-11-22T00:00:00+01:00")
    }

    func testBelegungPfadeUndVersion() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"items":[{"id":3,"kind":"facility","title":"Schützenhaus","facility":null,"horizon_days":365}],"occurrences":[{"item":3,"title":"Belegt","starts_at":"2026-11-21T00:00:00+01:00","ends_at":"2026-11-22T00:00:00+01:00","all_day":true,"own":false}],"own":[{"id":8,"item":3,"item_title":"Schützenhaus","title":"Geburtstag","starts_at":"2026-11-27T18:00:00+01:00","ends_at":"2026-11-27T23:00:00+01:00","status":"requested","version":1}]}"#),
            FakeTransport.json(201, #"{"id":9,"item":3,"title":"Probe","starts_at":"2026-11-20T18:00:00+01:00","ends_at":"2026-11-20T20:00:00+01:00","status":"requested","version":1}"#),
            FakeTransport.json(200, #"{"id":8,"starts_at":"2026-11-27T18:00:00+01:00","ends_at":"2026-11-27T23:00:00+01:00","status":"cancelled","version":2}"#),
            FakeTransport.json(400, #"{"starts_at":["So weit im Voraus ist dieses Objekt nicht buchbar."]}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let week = try await api.bookings(accessId: 5, monday: "2026-11-16")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/5/bookings/?start=2026-11-16")
        XCTAssertEqual(week.items.first?.horizonDays, 365)
        XCTAssertEqual(week.busy(3).count, 1)
        let own = try XCTUnwrap(week.own.first)
        XCTAssertTrue(own.cancellable)
        XCTAssertEqual(own.statusLabel, "angefragt")
        _ = try await api.requestBooking(accessId: 5, item: 3, title: "Probe", note: "", startsAt: "2026-11-20T18:00:00+01:00", endsAt: "2026-11-20T20:00:00+01:00", allDay: false)
        XCTAssertEqual(net.seen[1].method, "POST")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/5/bookings/")
        XCTAssertEqual(body(net.seen[1])["item"] as? Int, 3)
        XCTAssertEqual(flag(body(net.seen[1])["all_day"]), false)
        let cancelled = try await api.cancelBooking(accessId: 5, booking: own)
        XCTAssertEqual(cancelled.status, "cancelled")
        XCTAssertFalse(cancelled.cancellable)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/portal/5/bookings/8/cancel/")
        XCTAssertEqual(body(net.seen[2])["version"] as? Int, 1)
        do {
            _ = try await api.requestBooking(accessId: 5, item: 3, title: "Feier", note: "", startsAt: "2028-11-20T18:00:00+01:00", endsAt: "2028-11-20T20:00:00+01:00", allDay: false)
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.message, "So weit im Voraus ist dieses Objekt nicht buchbar.")
        }
    }

    func testKuendigung() async throws {
        let profile = try decode(Profile.self, #"{"first_name":"Anke","last_name":"Annahmer","cancellation":{"enabled":true,"possible":false,"earliest_date":"2027-12-31","rule":"mit einer Frist von 3 Monaten zum Ende des Geschäftsjahres","planned_exit":null,"requests":[{"id":4,"exit_date":"2027-12-31","status":"pending","status_label":"offen","created_at":"2026-11-15T10:00:00+01:00"},{"id":2,"exit_date":"2026-12-31","status":"withdrawn","status_label":"zurückgenommen"}]}}"#)
        let info = try XCTUnwrap(profile.cancellation)
        XCTAssertTrue(info.shown)
        XCTAssertEqual(info.pending?.id, 4)
        XCTAssertTrue(info.tooEarly("2027-12-30"))
        XCTAssertFalse(info.tooEarly("2027-12-31"))
        // Ältere Instanz: kein Abschnitt
        XCTAssertNil(try decode(Profile.self, #"{"first_name":"Anke"}"#).cancellation)
        let net = FakeTransport([
            FakeTransport.json(201, #"{"id":5,"exit_date":"2027-12-31","status":"pending"}"#),
            FakeTransport.json(200, #"{"id":5,"status":"withdrawn"}"#),
            FakeTransport.json(400, #"{"exit_date":["Frühestens zum 31.12.2027."]}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        _ = try await api.cancelMembership(accessId: 5, exitDate: "2027-12-31", message: "Umzug")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/5/cancellation/")
        XCTAssertEqual(flag(body(net.seen[0])["confirm"]), true)
        XCTAssertEqual(body(net.seen[0])["exit_date"] as? String, "2027-12-31")
        let back = try await api.withdrawCancellation(accessId: 5, id: 5)
        XCTAssertEqual(back.status, "withdrawn")
        XCTAssertEqual(net.seen[1].method, "DELETE")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/5/cancellation/5/")
        do {
            _ = try await api.cancelMembership(accessId: 5, exitDate: "2027-01-31", message: "")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.message, "Frühestens zum 31.12.2027.")
        }
    }

    func testMeldungenInWorten() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":1,"title":"Kreisschießen","organizer":"Kreisverband Musterland","date":"2026-12-05","location":"Musterdorf","event":null,"group":"Mannschaft 1","position":"Schütze 2","substitute":true,"confirmed":true},{"id":2,"title":"Pokal","organizer":"","date":"2026-01-10","location":"","group":"Liste","position":"","substitute":false,"confirmed":false}]"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let list = try await api.myEntries(accessId: 5)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/5/entries/")
        XCTAssertFalse(list[0].past(today: "2026-11-15"))
        XCTAssertTrue(list[1].past(today: "2026-11-15"))
        XCTAssertEqual(list[0].line, "Gemeldet in Mannschaft 1 als Schütze 2 (Ersatz), vom Veranstalter bestätigt")
        XCTAssertEqual(list[0].meta, "05.12.2026 · Musterdorf · Veranstalter: Kreisverband Musterland")
        XCTAssertEqual(list[1].line, "Gemeldet in Liste")
        Texte.language = "en"
        XCTAssertEqual(list[0].line, "Entered in Mannschaft 1 as Schütze 2 (reserve), confirmed by the organiser")
    }

    func testAbwesenheitMitSchluessel() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"enabled":true,"items":[{"id":7,"musician":3,"starts_at":"2026-12-01T00:00:00+01:00","ends_at":"2026-12-08T23:59:00+01:00"}]}"#),
            FakeTransport.json(200, #"{"id":7,"musician":3,"starts_at":"2026-12-02T00:00:00+01:00","ends_at":"2026-12-08T23:59:00+01:00"}"#),
            FakeTransport.json(200, #"{"id":8,"musician":3,"starts_at":"2026-12-02T00:00:00+01:00","ends_at":"2026-12-03T00:00:00+01:00"}"#),
            FakeTransport.json(200, #"{"ok":true}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let own = try await api.myAbsences(accessId: 5)
        XCTAssertTrue(own.enabled)
        XCTAssertEqual(own.items.map(\.id), [7])
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/5/music/absences/")
        XCTAssertFalse(try decode(OwnAbsences.self, #"{"enabled":false}"#).enabled)
        _ = try await api.saveAbsence(accessId: 5, id: 7, startsAt: "2026-12-02T00:00:00+01:00", endsAt: "2026-12-08T23:59:00+01:00", key: "6f1c2a8e-0b7d-4c5e-9a3f-2d4e6b8c0a12")
        XCTAssertEqual(body(net.seen[1])["action"] as? String, "save")
        XCTAssertEqual(body(net.seen[1])["id"] as? Int, 7)
        XCTAssertEqual(net.seen[1].headers["Idempotency-Key"], "6f1c2a8e-0b7d-4c5e-9a3f-2d4e6b8c0a12")
        _ = try await api.saveAbsence(accessId: 5, id: nil, startsAt: "2026-12-02T00:00:00+01:00", endsAt: "2026-12-03T00:00:00+01:00", key: "1a1c2a8e-0b7d-4c5e-9a3f-2d4e6b8c0a12")
        XCTAssertNil(body(net.seen[2])["id"])
        try await api.deleteAbsence(accessId: 5, id: 7, key: "2b1c2a8e-0b7d-4c5e-9a3f-2d4e6b8c0a12")
        XCTAssertEqual(body(net.seen[3])["action"] as? String, "delete")
        XCTAssertEqual(net.seen[3].headers["Idempotency-Key"], "2b1c2a8e-0b7d-4c5e-9a3f-2d4e6b8c0a12")
    }
}
