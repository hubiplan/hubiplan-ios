import XCTest
@testable import HubiplanKern

final class VerwaltungTermineTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    override func setUp() {
        Texte.language = "de"
    }

    private func decode<T: Decodable>(_ text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    private func verwaltung(_ net: FakeTransport, unit: AdminUnit = AdminUnit(id: 4, name: "Verein")) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: unit)
    }

    /// Inhalt mit sortierten Schlüsseln, damit sich Anfragen als Text vergleichen lassen.
    private func sorted(_ values: [String: Any]?) -> String {
        guard let values, let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func json(_ request: HttpRequest?) -> String {
        guard let body = request?.body else { return "" }
        return sorted((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])
    }

    func testTerminlisteMitSerieUndRechten() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"""
        {"items":[
        {"key":"7:2026-12-01","event_id":7,"title":"Übungsabend","starts_at":"2026-12-01T19:00:00+01:00","ends_at":"2026-12-01T21:00:00+01:00","original_start":"2026-12-01T18:00:00Z","is_series":true,"location":"Vereinsheim","owner":"1. Zug","rsvp_enabled":true,"can_edit":true},
        {"event_id":8,"title":"Weihnachtsfeier","starts_at":"2026-12-19T18:00:00+01:00","is_cancelled":true}
        ],"can_manage":true,"rsvp_allowed":true,"neu":1}
        """#)])
        let list = try await verwaltung(net).events(from: "2026-11-14", to: "2027-05-16")
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/app/v1/admin/u/4/events/?from=2026-11-14&to=2027-05-16")
        XCTAssertTrue(list.canManage)
        XCTAssertTrue(list.rsvpAllowed)
        XCTAssertEqual(list.items[0].detail, "Vereinsheim · 1. Zug · Zu-/Absagen · Serie")
        XCTAssertEqual(list.items[0].occurrenceStart, "2026-12-01T18:00:00Z")
        XCTAssertEqual(list.items[0].rowKey, "7:2026-12-01")
        XCTAssertNil(list.items[1].occurrenceStart)
        XCTAssertEqual(list.items[1].rowKey, "8-2026-12-19T18:00:00+01:00")
        XCTAssertEqual(list.items[1].endsAt, list.items[1].startsAt)
        XCTAssertTrue(list.items[1].isCancelled)
        let leer: AdminEventList = try decode("{}")
        XCTAssertFalse(leer.canManage)
        XCTAssertTrue(leer.items.isEmpty)
    }

    func testSerieZeigtDenGewaehltenEinzeltermin() throws {
        let event: AdminEvent = try decode(#"""
        {"id":7,"title":"Übungsabend","starts_at":"2026-11-03T19:00:00+01:00","ends_at":"2026-11-03T21:30:00+01:00","repeat":"weekly","repeat_label":"wöchentlich",
        "location":"Vereinsheim","visibility_label":"Mitglieder","owner":"1. Zug","is_cancelled":false,
        "exceptions":[{"original_start":"2026-12-01T18:00:00Z","is_cancelled":true,"note":"Halle belegt"}],
        "rsvp":{"enabled":true,"can_view_list":true,"can_enter":true,"guests_allowed":true,"max_guests":2,"capacity":40,"free":26,"summary":{"yes":12,"no":3,"guests":2,"persons":14,"open":5}}}
        """#)
        XCTAssertTrue(event.isSeries)
        XCTAssertEqual(event.detail, "Vereinsheim · Mitglieder · wöchentlich · 1. Zug")
        let abgesagt = event.shown(occurrence: "2026-12-01T19:00:00+01:00")
        XCTAssertTrue(abgesagt.cancelled)
        XCTAssertEqual(abgesagt.note, "Halle belegt")
        XCTAssertEqual(abgesagt.single, "2026-12-01T19:00:00+01:00")
        XCTAssertEqual(abgesagt.end, "2026-12-01T20:30:00Z")
        let normal = event.shown(occurrence: "2026-12-08T19:00:00+01:00")
        XCTAssertFalse(normal.cancelled)
        XCTAssertEqual(normal.note, "")
        XCTAssertEqual(event.shown(occurrence: nil).start, "2026-11-03T19:00:00+01:00")
        XCTAssertEqual(event.rsvp.summary?.text, "12 Zusagen (14 Personen) · 3 Absagen · 5 offen")
        XCTAssertEqual(event.rsvp.free, 26)
    }

    func testEinzelterminOhneSerieUndOhneRueckmeldungen() throws {
        let event: AdminEvent = try decode(#"{"id":8,"title":"Feier","starts_at":"2026-12-19T18:00:00+01:00","is_cancelled":true,"cancel_note":"Sturm"}"#)
        XCTAssertFalse(event.isSeries)
        let shown = event.shown(occurrence: "2026-12-19T18:00:00+01:00")
        XCTAssertNil(shown.single)
        XCTAssertTrue(shown.cancelled)
        XCTAssertEqual(shown.note, "Sturm")
        XCTAssertFalse(event.rsvp.enabled)
        XCTAssertNil(event.rsvp.summary)
        XCTAssertEqual(RsvpCounts(yes: 1, no: 1, persons: 1).text, "1 Zusage · 1 Absage")
    }

    func testAbsagenUndZuruecknehmen() async throws {
        let ok = Result<HttpResponse, Error>.success(HttpResponse(status: 200, body: Data("{}".utf8), headers: ["X-Change-Set": "ab12", "X-Change-Undoable": "1"]))
        let net = FakeTransport([ok, ok, ok, FakeTransport.json(403, #"{"detail":"Keine Berechtigung."}"#)])
        let client = verwaltung(net)
        let change = try await client.cancelEvent(8, cancelled: true, note: "Sturm", notify: true)
        XCTAssertEqual(change.changeSet, "ab12")
        XCTAssertEqual(net.seen[0].method, "PATCH")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/events/8/")
        XCTAssertEqual(json(net.seen[0]), sorted(["is_cancelled": true, "cancel_note": "Sturm", "notify": true]))
        _ = try await client.cancelOccurrence(7, originalStart: "2026-12-01T18:00:00Z", cancelled: true, note: "Halle belegt")
        XCTAssertEqual(net.seen[1].method, "PUT")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/4/events/7/occurrence/")
        XCTAssertEqual(json(net.seen[1]), sorted(["original_start": "2026-12-01T18:00:00Z", "is_cancelled": true, "note": "Halle belegt"]))
        _ = try await client.cancelOccurrence(7, originalStart: "2026-12-01T18:00:00Z", cancelled: false)
        XCTAssertEqual(net.seen[2].method, "DELETE")
        XCTAssertEqual(json(net.seen[2]), sorted(["original_start": "2026-12-01T18:00:00Z"]))
        do {
            _ = try await client.cancelEvent(8, cancelled: false)
            XCTFail("403 erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.status, 403)
        }
    }

    func testRueckmeldungenLesenEintragenEntfernen() async throws {
        let ok = Result<HttpResponse, Error>.success(HttpResponse(status: 200, body: Data("{}".utf8), headers: ["X-Change-Set": "cd34", "X-Change-Undoable": "1"]))
        let net = FakeTransport([FakeTransport.json(200, #"""
        {"summary":{"yes":2,"no":1,"guests":1,"persons":3},"capacity":40,
        "items":[{"membership_id":1,"name":"Erika Musterfrau","departments":"1. Zug","status":"yes","guests":1,"note":"kommt später","source":"board"},
        {"membership_id":2,"name":"Max Mustermann","status":"yes"},
        {"membership_id":4,"name":"Lena Beispiel","status":"no","source":"member"}],
        "open":[{"membership_id":5,"name":"Jonas Probe","departments":"2. Zug"}]}
        """#), ok, .success(HttpResponse(status: 204, body: Data()))])
        let client = verwaltung(net)
        let r = try await client.responses(7)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/events/7/responses/")
        XCTAssertEqual(AdminResponses.Tab.allCases.map { r.count($0) }, [2, 1, 1])
        XCTAssertEqual(r.rows(.yes).map(\.title), ["Erika Musterfrau + 1", "Max Mustermann"])
        XCTAssertEqual(r.rows(.yes)[0].detail, "1. Zug · kommt später · vom Vorstand eingetragen")
        XCTAssertEqual(r.rows(.no).map(\.name), ["Lena Beispiel"])
        XCTAssertEqual(r.rows(.open).map(\.membershipId), [5])
        XCTAssertEqual(r.rows(.yes, search: " muster ").count, 2)
        XCTAssertEqual(r.rows(.yes, search: "max").map(\.membershipId), [2])
        XCTAssertTrue(r.rows(.open, search: "erika").isEmpty)
        let change = try await client.setResponse(7, membership: 5, status: "yes", guests: 1, note: "Anruf")
        XCTAssertEqual(change.changeSet, "cd34")
        XCTAssertEqual(net.seen[1].method, "PUT")
        XCTAssertEqual(json(net.seen[1]), sorted(["membership_id": 5, "status": "yes", "guests": 1, "note": "Anruf"]))
        let removed = try await client.deleteResponse(7, membership: 5)
        XCTAssertNil(removed.changeSet)
        XCTAssertEqual(net.seen[2].method, "DELETE")
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/4/events/7/responses/5/")
    }

    func testUhrzeitUndZeitraum() {
        XCTAssertEqual(EventTime.parseTime("9:05")?.hour, 9)
        XCTAssertEqual(EventTime.parseTime(" 19:30 ")?.minute, 30)
        XCTAssertNil(EventTime.parseTime("24:00"))
        XCTAssertNil(EventTime.parseTime("19:60"))
        XCTAssertNil(EventTime.parseTime("19"))
        XCTAssertNil(EventTime.parseTime("19:5"))
        XCTAssertNil(EventTime.parseTime("ab:cd"))

        let abend = EventTime.range(day: "21.11.2026", start: "19:00", end: "", allDay: false, timeZone: berlin)
        XCTAssertEqual(abend?.from, "2026-11-21T19:00:00+01:00")
        XCTAssertEqual(abend?.to, "2026-11-21T21:00:00+01:00")
        let sommer = EventTime.range(day: "2026-07-04", start: "15:00", end: "18:30", allDay: false, timeZone: berlin)
        XCTAssertEqual(sommer?.from, "2026-07-04T15:00:00+02:00")
        XCTAssertEqual(sommer?.to, "2026-07-04T18:30:00+02:00")
        // Ende vor dem Beginn: am nächsten Tag
        let nacht = EventTime.range(day: "31.12.2026", start: "20:00", end: "02:00", allDay: false, timeZone: berlin)
        XCTAssertEqual(nacht?.to, "2027-01-01T02:00:00+01:00")
        // Ganztägig: Mitternacht in deutscher Zeit, auch wenn das Telefon woanders ist
        let tag = EventTime.range(day: "06.06.2026", start: "", end: "", allDay: true, timeZone: TimeZone(identifier: "America/New_York")!)
        XCTAssertEqual(tag?.from, "2026-06-06T00:00:00+02:00")
        XCTAssertEqual(tag?.to, tag?.from)
        XCTAssertNil(EventTime.range(day: "31.02.2026", start: "19:00", end: "", allDay: false, timeZone: berlin))
        XCTAssertNil(EventTime.range(day: "21.11.2026", start: "abends", end: "", allDay: false, timeZone: berlin))
        XCTAssertNil(EventTime.range(day: "21.11.2026", start: "19:00", end: "spät", allDay: false, timeZone: berlin))

        XCTAssertTrue(EventTime.sameInstant("2026-12-01T19:00:00+01:00", "2026-12-01T18:00:00Z"))
        XCTAssertFalse(EventTime.sameInstant("2026-12-01T19:00:00+01:00", "2026-12-08T18:00:00Z"))
        XCTAssertTrue(EventTime.sameInstant("x", "x"))
        XCTAssertFalse(EventTime.sameInstant(nil, "x"))
        XCTAssertEqual(EventTime.shiftEnd(start: "x", end: "y", occurrence: "z"), "z")
    }

    func testNeuerTerminInhaltDerAnfrage() {
        var draft = EventDraft()
        XCTAssertNil(draft.body(rsvpAllowed: true, timeZone: berlin))
        draft.title = "  Zugversammlung "
        draft.day = "21.11.2026"
        draft.location = " Vereinsheim "
        let simple = draft.body(rsvpAllowed: true, timeZone: berlin)
        XCTAssertEqual(sorted(simple), sorted([
            "title": "Zugversammlung", "starts_at": "2026-11-21T19:00:00+01:00", "ends_at": "2026-11-21T21:00:00+01:00",
            "all_day": false, "location": "Vereinsheim", "description": "", "visibility": "members", "rsvp_enabled": false,
        ]))

        draft.rsvp = true
        draft.guests = true
        draft.deadline = "14.11.2026"
        draft.notify = true
        let full = draft.body(rsvpAllowed: true, timeZone: berlin)
        XCTAssertEqual(full?["rsvp_enabled"] as? Bool, true)
        XCTAssertEqual(full?["rsvp_guests"] as? Bool, true)
        XCTAssertEqual(full?["rsvp_deadline"] as? String, "2026-11-14T23:59:00+01:00")
        XCTAssertEqual(full?["notify"] as? Bool, true)

        // Ohne Erlaubnis oder nur für den Vorstand: keine Zu- und Absagen
        XCTAssertEqual(draft.body(rsvpAllowed: false, timeZone: berlin)?["rsvp_enabled"] as? Bool, false)
        XCTAssertNil(draft.body(rsvpAllowed: false, timeZone: berlin)?["notify"])
        draft.visibility = "board"
        XCTAssertFalse(draft.canRsvp(allowed: true))
        XCTAssertNil(draft.body(rsvpAllowed: true, timeZone: berlin)?["rsvp_deadline"])
        draft.visibility = "public"
        draft.deadline = "morgen"
        XCTAssertNil(draft.body(rsvpAllowed: true, timeZone: berlin))
        XCTAssertEqual(EventDraft.visibilities.map(\.key), ["members", "board", "public"])
    }

    func testTerminAnlegen() async throws {
        let net = FakeTransport([
            .success(HttpResponse(status: 201, body: Data(#"{"id":12,"title":"Zugversammlung","starts_at":"2026-11-21T19:00:00+01:00","ends_at":"2026-11-21T21:00:00+01:00"}"#.utf8), headers: ["X-Change-Set": "ef56", "X-Change-Undoable": "1"])),
            FakeTransport.json(400, #"{"detail":"Bitte einen Titel eingeben."}"#),
        ])
        let client = verwaltung(net)
        let result = try await client.createEvent(["title": "Zugversammlung"])
        XCTAssertEqual(result.event.id, 12)
        XCTAssertEqual(result.change.changeSet, "ef56")
        XCTAssertEqual(net.seen[0].method, "POST")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/events/")
        do {
            _ = try await client.createEvent([:])
            XCTFail("400 erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.status, 400)
        }
    }
}
