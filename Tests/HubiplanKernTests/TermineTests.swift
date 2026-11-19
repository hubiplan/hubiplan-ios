import XCTest
@testable import HubiplanKern

final class TermineTests: XCTestCase {
    private let server = "https://verein.example.de"

    /// Termine „nur Vorstand“ sind gekennzeichnet; ältere Server ohne Angabe: kein Hinweis
    /// (gleicher Fall wie in der Android-App).
    func testVorstandsterminIstGekennzeichnet() throws {
        let occ = try JSONDecoder().decode(Occurrence.self, from: Data(#"{"key":"7","event_id":7,"title":"Vorstandssitzung","starts_at":"2099-03-05T19:30:00+01:00","ends_at":"2099-03-05T21:30:00+01:00","visibility":"board"}"#.utf8))
        XCTAssertTrue(occ.nurVorstand)
        let alt = try JSONDecoder().decode(Occurrence.self, from: Data(#"{"key":"8","event_id":8,"title":"Sommerfest","starts_at":"2099-06-13T14:00:00+02:00","ends_at":"2099-06-13T18:00:00+02:00"}"#.utf8))
        XCTAssertFalse(alt.nurVorstand)
        let detail = try JSONDecoder().decode(EventDetail.self, from: Data(#"{"id":7,"title":"Vorstandssitzung","visibility":"board"}"#.utf8))
        XCTAssertTrue(detail.nurVorstand)
    }

    func testTermineLesen() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"items":[{"key":"12:2026-11-20","event_id":12,"title":"Zugversammlung","starts_at":"2026-11-20T19:00:00+01:00","ends_at":"2026-11-20T21:00:00+01:00","location":"Vereinsheim","category":{"name":"Versammlung","color":"blau"},"owner":"Zug 1","rsvp_enabled":true,"my_response":null,"neu":true},{"key":"13","event_id":13,"title":"Schützenfest","starts_at":"2026-08-28T00:00:00+02:00","ends_at":"2026-08-31T23:59:59.999+02:00","all_day":true,"is_cancelled":true,"rsvp_enabled":true,"my_response":"yes"}]}"#)])
        let events = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).events(accessId: 3, from: "2026-11-01", to: "2027-05-01")
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/portal/3/events/?from=2026-11-01&to=2027-05-01")
        XCTAssertEqual(events.map(\.id), ["12:2026-11-20", "13"])
        XCTAssertEqual(events[0].category?.name, "Versammlung")
        XCTAssertTrue(events[0].responseMissing)
        XCTAssertFalse(events[1].responseMissing)
        XCTAssertTrue(events[1].allDay)
        XCTAssertEqual(events[0].start, Date(timeIntervalSince1970: 1_795_197_600))
        XCTAssertNotNil(events[1].end)
    }

    func testZusageUndZuruecknehmen() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"id":12,"rsvp":{"mine":{"status":"yes"}}}"#),
            .success(HttpResponse(status: 204, body: Data())),
            FakeTransport.json(403, #"{"detail":"Die Anmeldefrist ist abgelaufen."}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        try await api.respond(accessId: 3, eventId: 12, status: "yes")
        try await api.withdraw(accessId: 3, eventId: 12)
        XCTAssertEqual(net.seen.map(\.method), ["PUT", "DELETE"])
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/events/12/response/")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[0].body)) as? [String: Any])
        XCTAssertEqual(sent["status"] as? String, "yes")
        XCTAssertEqual(sent["guests"] as? Int, 0)
        XCTAssertNil(net.seen[1].body)
        do {
            try await api.respond(accessId: 3, eventId: 12, status: "no")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.text, "Die Anmeldefrist ist abgelaufen.")
        }
    }

    func testZeit() {
        XCTAssertEqual(Zeit.parse("2026-11-20T18:00:00Z"), Date(timeIntervalSince1970: 1_795_197_600))
        let fraction = Zeit.parse("2026-11-20T18:00:00.250Z")?.timeIntervalSince1970 ?? 0
        XCTAssertEqual(fraction, 1_795_197_600.25, accuracy: 0.01)
        XCTAssertNil(Zeit.parse("morgen"))
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        XCTAssertEqual(Zeit.day(Date(timeIntervalSince1970: 1_795_197_600), timeZone: berlin), "2026-11-20")
        // 23:30 UTC ist in Berlin schon der nächste Tag
        XCTAssertEqual(Zeit.day(Date(timeIntervalSince1970: 1_795_197_600 + 5.5 * 3600), timeZone: berlin), "2026-11-21")
    }
}
