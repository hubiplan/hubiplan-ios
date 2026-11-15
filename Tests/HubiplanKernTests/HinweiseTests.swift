import XCTest
@testable import HubiplanKern

/// Hinweis „Rückmeldung fehlt“: 30 Stunden vor dem Anmeldeschluss (wie Android). Erfundene Daten.
final class HinweiseTests: XCTestCase {
    func testPlanung() throws {
        let json = #"""
        {"items":[
        {"key":"1","event_id":1,"title":"Zugversammlung","starts_at":"2026-11-20T19:00:00+01:00","ends_at":"2026-11-20T21:00:00+01:00","rsvp_enabled":true,"rsvp_deadline":"2026-11-18T23:59:00+01:00","my_response":null},
        {"key":"2","event_id":2,"title":"Schon zugesagt","starts_at":"2026-11-20T19:00:00+01:00","ends_at":"2026-11-20T21:00:00+01:00","rsvp_enabled":true,"rsvp_deadline":"2026-11-18T23:59:00+01:00","my_response":"yes"},
        {"key":"3","event_id":3,"title":"Frist vorbei","starts_at":"2026-11-16T19:00:00+01:00","ends_at":"2026-11-16T21:00:00+01:00","rsvp_enabled":true,"rsvp_deadline":"2026-11-15T08:00:00+01:00","my_response":null},
        {"key":"4:2026-11-16","event_id":4,"title":"Bald fällig","starts_at":"2026-11-17T19:00:00+01:00","ends_at":"2026-11-17T21:00:00+01:00","rsvp_enabled":true,"rsvp_deadline":"2026-11-16T12:00:00+01:00","my_response":null},
        {"key":"5","event_id":5,"title":"Abgesagt","starts_at":"2026-11-20T19:00:00+01:00","ends_at":"2026-11-20T21:00:00+01:00","is_cancelled":true,"rsvp_enabled":true,"rsvp_deadline":"2026-11-18T23:59:00+01:00","my_response":null},
        {"key":"6","event_id":6,"title":"Ohne Frist","starts_at":"2026-11-20T19:00:00+01:00","ends_at":"2026-11-20T21:00:00+01:00","rsvp_enabled":true,"my_response":null}
        ]}
        """#
        struct Liste: Decodable { var items: [Occurrence] }
        let events = try JSONDecoder().decode(Liste.self, from: Data(json.utf8)).items
        let now = try XCTUnwrap(Zeit.parse("2026-11-15T12:00:00+01:00"))
        let hints = RueckmeldeHinweis.plan(events, accessId: 3, account: "kapelle", now: now)
        XCTAssertEqual(hints.map(\.eventId), [4, 1])
        // Frist in 24 Stunden: sofort
        XCTAssertEqual(hints[0].fireAt, now.addingTimeInterval(5))
        XCTAssertEqual(hints[0].id, "rsvp-kapelle-3-4:2026-11-16")
        // Frist in gut drei Tagen: 30 Stunden vorher
        XCTAssertEqual(hints[1].fireAt, Zeit.parse("2026-11-17T17:59:00+01:00"))
        XCTAssertTrue(hints.allSatisfy { $0.id.hasPrefix(RueckmeldeHinweis.prefix(account: "kapelle")) })
        XCTAssertEqual(RueckmeldeHinweis.prefix(account: ""), "rsvp---")
        XCTAssertFalse(RueckmeldeHinweis.prefix(account: "").isEmpty)
    }

    func testHoechstensZwanzig() throws {
        let rows = (1...30).map { n in
            #"{"key":"\#(n)","event_id":\#(n),"title":"T\#(n)","starts_at":"2026-12-\#(String(format: "%02d", n))T19:00:00+01:00","ends_at":"2026-12-\#(String(format: "%02d", n))T21:00:00+01:00","rsvp_enabled":true,"rsvp_deadline":"2026-12-\#(String(format: "%02d", n))T12:00:00+01:00"}"#
        }
        struct Liste: Decodable { var items: [Occurrence] }
        let events = try JSONDecoder().decode(Liste.self, from: Data(("{\"items\":[" + rows.joined(separator: ",") + "]}").utf8)).items
        let hints = RueckmeldeHinweis.plan(events, accessId: 1, account: "", now: Zeit.parse("2026-11-15T12:00:00+01:00")!)
        XCTAssertEqual(hints.count, RueckmeldeHinweis.limit)
        XCTAssertEqual(hints.first?.eventId, 1)
    }
}
