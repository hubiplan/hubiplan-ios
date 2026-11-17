import XCTest
@testable import HubiplanKern

/// UX-Audit 16.11.2026, X-01 und AND-27, gleiche Fälle wie `BegriffeTest` in der Android-App:
/// ein Wort je Sache (`hubiplan/docs/begriffe.md`) und ganztägige Termine ohne Zeitzonenfehler.
final class BegriffeTests: XCTestCase {
    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    /// Muster, erlaubte Texte (Bestand, darf nur sinken), stattdessen.
    private let verboten: [(String, Int, String)] = [
        ("Telefon(?!nummer)", 1, "„Gerät“ (nur das Feld „Telefon“ für die Rufnummer bleibt)"),
        ("iPhone", 0, "„Gerät“ (auch auf dem iPad)"),
        ("Wappen", 0, "„Logo“"),
        ("abgleichen|abgeglichen", 0, "„Aktualisieren“ und „Stand: …“"),
        ("vom Gerät abmelden|Verbindung trennen|[Tt]renne|[Tt]rennst", 0, "„Auf diesem Gerät abmelden“"),
        ("[Dd]ieses Schreiben", 0, "„Mitteilung“"),
        ("Mitgliedskarte", 0, "„Ausweis“"),
        ("To-do", 0, "„Aufgabe“"),
    ]

    func testVerboteneNebenwoerterFehlen() throws {
        for (muster, erlaubt, stattdessen) in verboten {
            let regex = try NSRegularExpression(pattern: muster)
            let treffer = Texte.english.keys.filter {
                regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
            }.sorted()
            XCTAssertLessThanOrEqual(treffer.count, erlaubt, "\(muster): stattdessen \(stattdessen): \(treffer)")
        }
    }

    func testEnglischFolgtDemGlossar() throws {
        Texte.language = "en"
        XCTAssertEqual(tr("Auf diesem Gerät abmelden …"), "Sign out on this device …")
        XCTAssertEqual(tr("Abmelden"), "Sign out")
        let phone = try NSRegularExpression(pattern: #"\b(phones?|iPhones?)\b"#, options: .caseInsensitive)
        for (de, en) in Texte.english where de.contains("Gerät") {
            XCTAssertNil(phone.firstMatch(in: en, range: NSRange(en.startIndex..., in: en)), "„\(de)“: device statt phone")
        }
    }

    private func tag(_ date: Date, _ zone: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let p = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", p.year!, p.month!, p.day!, p.hour!, p.minute!)
    }

    /// AND-27: ganztägige Termine stehen in jeder Gerätezeitzone am selben Kalendertag.
    func testGanztaegigOhneZeitzone() throws {
        for zone in ["Europe/Berlin", "UTC", "America/Los_Angeles", "Asia/Tokyo"] {
            let tz = try XCTUnwrap(TimeZone(identifier: zone))
            let days = try XCTUnwrap(Zeit.ganztaegig("2027-07-11T00:00:00+02:00", "2027-07-14T00:00:00+02:00", timeZone: tz))
            XCTAssertEqual(tag(days.first, zone), "2027-07-11 00:00", zone)
            XCTAssertEqual(tag(days.last, zone), "2027-07-14 00:00", zone)
            // auch wenn der Server in UTC liefert
            let utc = try XCTUnwrap(Zeit.ganztaegig("2027-07-10T22:00:00Z", "2027-07-13T22:00:00Z", timeZone: tz))
            XCTAssertEqual(tag(utc.first, zone), "2027-07-11 00:00", zone)
            XCTAssertEqual(Design.datumKaestchen("2027-07-10T22:00:00Z", allDay: true, timeZone: tz, englisch: false)?.tag, "11", zone)
        }
        // Ohne lesbares Ende zählt der erste Tag
        let single = try XCTUnwrap(Zeit.ganztaegig("2027-07-11T00:00:00+02:00", "", timeZone: .init(identifier: "UTC")!))
        XCTAssertEqual(single.first, single.last)
    }

    /// AND-27: im Gerätekalender dieselben Tage, auch in Los Angeles.
    func testKalenderGanztaegigAufReisen() throws {
        let item = try JSONDecoder().decode(Occurrence.self, from: Data(
            #"{"key":"9","event_id":9,"title":"Sommerfest","starts_at":"2026-08-28T00:00:00+02:00","ends_at":"2026-08-30T00:00:00+02:00","all_day":true}"#.utf8
        ))
        let zone = "America/Los_Angeles"
        let entry = try XCTUnwrap(item.calendarEntry(unitTitle: "Verein", reminderMinutes: nil, timeZone: TimeZone(identifier: zone)!))
        XCTAssertEqual(tag(entry.start, zone), "2026-08-28 00:00")
        XCTAssertEqual(tag(entry.end, zone), "2026-08-30 00:00")
    }

    /// AND-27: Uhrzeiten bleiben Gerätezeit, mit Zusatz, sobald das Gerät woanders steht.
    func testUhrzeitMitZusatzInAndererZeitzone() {
        let abend = "2026-11-13T19:00:00+01:00"
        XCTAssertEqual(Zeit.geraeteHinweis(abend, timeZone: TimeZone(identifier: "Europe/Berlin")!), "")
        XCTAssertEqual(Zeit.geraeteHinweis(abend, timeZone: TimeZone(identifier: "Europe/Vienna")!), "", "gleicher Abstand")
        XCTAssertEqual(Zeit.geraeteHinweis(abend, timeZone: TimeZone(identifier: "UTC")!), " (Zeit an deinem Gerät)")
        Texte.language = "en"
        XCTAssertEqual(Zeit.geraeteHinweis(abend, timeZone: TimeZone(identifier: "UTC")!), " (time on your device)")
    }
}
