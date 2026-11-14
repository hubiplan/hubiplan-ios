import XCTest
@testable import HubiplanKern

final class KalenderTests: XCTestCase {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func occurrence(_ json: String) throws -> Occurrence {
        try JSONDecoder().decode(Occurrence.self, from: Data(json.utf8))
    }

    override func setUp() { Texte.language = "de" }

    func testTerminMitUhrzeit() throws {
        let item = try occurrence(#"{"key":"7-2026-12-01","event_id":7,"title":"Zugversammlung","starts_at":"2026-12-01T19:30:00+01:00","ends_at":"2026-12-01T21:30:00+01:00","location":"Vereinsheim","address":"Musterweg 1, 41468 Musterstadt","note":"Bitte pünktlich","owner":"Zug 1","rsvp_enabled":true,"my_response":"yes"}"#)
        let entry = try XCTUnwrap(item.calendarEntry(unitTitle: "Schützenverein Musterstadt", reminderMinutes: 120, timeZone: berlin))
        XCTAssertEqual(entry.title, "✓ Zugversammlung")
        XCTAssertEqual(entry.start, Zeit.parse("2026-12-01T19:30:00+01:00"))
        XCTAssertEqual(entry.end, Zeit.parse("2026-12-01T21:30:00+01:00"))
        XCTAssertFalse(entry.allDay)
        XCTAssertEqual(entry.location, "Vereinsheim, Musterweg 1, 41468 Musterstadt")
        XCTAssertEqual(entry.notes, "Zug 1\nBitte pünktlich\nDu hast zugesagt.\nAus HUBIplan (Schützenverein Musterstadt)")
        XCTAssertEqual(entry.reminderMinutes, 120)
    }

    func testGanztaegigUeberMehrereTage() throws {
        let item = try occurrence(#"{"key":"9","event_id":9,"title":"Schützenfest","starts_at":"2026-08-28T00:00:00+02:00","ends_at":"2026-08-31T00:00:00+02:00","all_day":true}"#)
        let entry = try XCTUnwrap(item.calendarEntry(unitTitle: "Verein", reminderMinutes: nil, timeZone: berlin))
        XCTAssertTrue(entry.allDay)
        XCTAssertEqual(entry.start, Zeit.parse("2026-08-28T00:00:00+02:00"))
        XCTAssertEqual(entry.end, Zeit.parse("2026-08-31T00:00:00+02:00"))
        XCTAssertEqual(entry.notes, "Aus HUBIplan (Verein)")
    }

    func testAbgesagtUndAbsageOhneErinnerung() throws {
        let cancelled = try occurrence(#"{"key":"1","event_id":1,"title":"Probe","starts_at":"2026-12-01T19:00:00+01:00","ends_at":"2026-12-01T18:00:00+01:00","is_cancelled":true,"rsvp_enabled":true}"#)
        let entry = try XCTUnwrap(cancelled.calendarEntry(unitTitle: "Verein", reminderMinutes: 120, timeZone: berlin))
        XCTAssertEqual(entry.title, "Abgesagt: Probe")
        XCTAssertNil(entry.reminderMinutes)
        XCTAssertTrue(entry.cancelled)
        // Ende vor dem Anfang: der Eintrag endet am Anfang
        XCTAssertEqual(entry.end, entry.start)

        let declined = try occurrence(#"{"key":"2","event_id":2,"title":"Probe","starts_at":"2026-12-01T19:00:00+01:00","ends_at":"2026-12-01T21:00:00+01:00","rsvp_enabled":true,"my_response":"no"}"#)
        let no = try XCTUnwrap(declined.calendarEntry(unitTitle: "Verein", reminderMinutes: 120, timeZone: berlin))
        XCTAssertEqual(no.title, "✗ Probe")
        XCTAssertNil(no.reminderMinutes)
        XCTAssertTrue(no.notes.contains("Du hast abgesagt."))

        let open = try occurrence(#"{"key":"3","event_id":3,"title":"Probe","starts_at":"2026-12-01T19:00:00+01:00","ends_at":"2026-12-01T21:00:00+01:00","rsvp_enabled":true}"#)
        let waiting = try XCTUnwrap(open.calendarEntry(unitTitle: "Verein", reminderMinutes: 120, timeZone: berlin))
        XCTAssertTrue(waiting.notes.contains("Rückmeldung offen"))

        let broken = try occurrence(#"{"key":"4","event_id":4,"title":"Probe","starts_at":"morgen","ends_at":"2026-12-01T21:00:00+01:00"}"#)
        XCTAssertNil(broken.calendarEntry(unitTitle: "Verein", reminderMinutes: nil, timeZone: berlin))
    }

    func testFingerabdruckBleibtGleichUndAendertSich() throws {
        let item = try occurrence(#"{"key":"1","event_id":1,"title":"Probe","starts_at":"2026-12-01T19:00:00+01:00","ends_at":"2026-12-01T21:00:00+01:00"}"#)
        let entry = try XCTUnwrap(item.calendarEntry(unitTitle: "Verein", reminderMinutes: nil, timeZone: berlin))
        // Fester Wert: der Fingerabdruck darf sich zwischen App-Starts nicht ändern
        XCTAssertEqual(entry.fingerprint, "2d770ba11f99220c")
        var same = entry
        same.eventId = 99
        XCTAssertEqual(same.fingerprint, entry.fingerprint)
        var moved = entry
        moved.location = "Vereinsheim"
        XCTAssertNotEqual(moved.fingerprint, entry.fingerprint)
        var reminded = entry
        reminded.reminderMinutes = 120
        XCTAssertNotEqual(reminded.fingerprint, entry.fingerprint)
    }

    func testAbgleichsplan() throws {
        func entry(_ key: String, _ title: String) -> CalendarEntry {
            CalendarEntry(
                key: key, eventId: 1, title: title, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600),
                allDay: false, location: "", notes: "", cancelled: false, reminderMinutes: nil
            )
        }
        let a = entry("a", "A"), b = entry("b", "B"), c = entry("c", "C")
        let plan = SyncPlan(wanted: [a, b, c], existing: ["a": a.fingerprint, "b": "alt", "x": "1", "w": "2"])
        XCTAssertEqual(plan.insert, [c])
        XCTAssertEqual(plan.update, [b])
        XCTAssertEqual(plan.delete, ["w", "x"])
        let nothing = SyncPlan(wanted: [a], existing: ["a": a.fingerprint])
        XCTAssertTrue(nothing.insert.isEmpty && nothing.update.isEmpty && nothing.delete.isEmpty)
    }

    func testKennungen() {
        XCTAssertEqual(CalendarMark.name(server: "https://verein.example.de", accessId: 4), "hubiplan:verein.example.de:4")
        XCTAssertTrue(CalendarMark.name(server: "https://verein.example.de", accessId: 4)
            .hasPrefix(CalendarMark.prefix(server: "https://verein.example.de")))
        XCTAssertFalse(CalendarMark.name(server: "https://verein.example.de.example.org", accessId: 4)
            .hasPrefix(CalendarMark.prefix(server: "https://verein.example.de")))

        let url = CalendarMark.url(key: "7-2026-12-01 & mehr", fingerprint: "abc123")
        let mark = CalendarMark.parse(url)
        XCTAssertEqual(mark?.key, "7-2026-12-01 & mehr")
        XCTAssertEqual(mark?.fingerprint, "abc123")
        XCTAssertTrue(CalendarMark.isEventLink(url))
        XCTAssertNil(CalendarMark.parse("https://example.org/?k=1"))
        XCTAssertNil(CalendarMark.parse("hubiplan://verbinden?k=1"))
        XCTAssertFalse(CalendarMark.isEventLink("hubiplan://verbinden#code=abc"))
    }

    func testErinnerung() {
        XCTAssertEqual(Erinnerung.label(nil), "keine")
        XCTAssertEqual(Erinnerung.label(120), "2 Stunden vorher")
        XCTAssertEqual(Erinnerung.label(45), "45 Minuten vorher")
        Texte.language = "en"
        XCTAssertEqual(Erinnerung.label(24 * 60), "1 day before")
        Texte.language = "de"
    }
}
