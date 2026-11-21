import XCTest
@testable import HubiplanKern

/// Training und Schießbuch unter „Ich“, gleiche Fälle wie `TrainingTest` in Android. Alle Daten erfunden.
final class TrainingTests: XCTestCase {
    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let text = #"""
    {"attendance":[{"session":5,"date":"2099-11-18","title":"Übungsabend Luftgewehr","kind":"practice",
       "kind_label":"Übungsabend","department_name":"","source":"code"}],
     "count_year":14,"count_12":16,
     "checkin":[{"id":7,"department":null,"department_name":"","event":null,"date":"2099-11-20",
       "starts_at":"19:00","ends_at":"21:00","hours":2.0,"title":"Training Sportpistole","kind":"training",
       "kind_label":"Training","location":"","leader":"","note":"","shooting":true,"discipline":"Sportpistole",
       "weapon_class":"short","caliber":".22 lr","permit_required":true,"checkin_open":true,"count":3,
       "version":1,"present":false}],
     "shooting_enabled":true,"targets":[],
     "shooting":{"entries":[{"id":31,"membership":4,"date":"2099-11-15","discipline":"Sportpistole",
         "weapon_class":"short","weapon_class_label":"Kurzwaffe","caliber":".22 lr","permit_required":true,
         "own_weapon":true,"competition":false,"place":"Schießstand Beispielhausen","external":true,"note":"",
         "status":"reported","status_label":"gemeldet","source":"member","source_label":"vom Mitglied gemeldet",
         "from_training":false,"confirmed_by":"","confirmed_at":null}],
       "evaluation":{"on":"2099-11-20","start_12":"2098-11-21","start_24":"2097-11-21","member_since":"2090-03-01",
         "acquisition":{"ok":true,"member_12_months":true,"by_months":false,"by_count":true,"count":22,"needed":18,
           "months":[],"longest_gap_days":140,"gap_ok":false,"external":2,"internal":20,"mostly_own_club":true},
         "possession":[{"weapon_class":"short","label":"Kurzwaffe","count":22,"ok":true,"by_quarters":true,
           "by_six":true,"quarters":[],"years":[]}],"pending":1},
       "disciplines":[{"name":"Sportpistole","weapon_class":"short","caliber":".22 lr","permit_required":true}]}}
    """#

    func testLiestDieAntwort() throws {
        let t = try JSONDecoder().decode(MemberTraining.self, from: Data(text.utf8))
        XCTAssertEqual(t.countYear, 14)
        XCTAssertEqual(t.attendance.count, 1)
        let log = try XCTUnwrap(t.shooting)
        XCTAssertTrue(log.entries[0].canWithdraw)
        XCTAssertEqual(log.entries[0].details, "Kurzwaffe · .22 lr · Schießstand Beispielhausen · anderer Verein")
        XCTAssertEqual(t.summary, "Einchecken ist offen")
        let lines = try XCTUnwrap(log.evaluation).lines
        XCTAssertEqual(lines.first, "Erwerb (Abs. 3): letzte 12 Monate: erfüllt")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Längere Pause: 140 Tage") })
        XCTAssertTrue(lines.contains("Besitz (Abs. 4), Kurzwaffe: letzte 24 Monate: erfüllt"))
        XCTAssertEqual(lines.last, "1 gemeldete Termine warten auf die Bestätigung des Vereins.")
    }

    func testQrCodeLesenUndBauen() throws {
        let link = try XCTUnwrap(TrainingLink.parse("https://verein.example.org/mein-bereich/training/da/7?v=3&c=59841234-0123456789abcdef"))
        XCTAssertEqual(link.sessionId, 7)
        XCTAssertEqual(link.clubId, 3)
        XCTAssertEqual(link.server, "https://verein.example.org")
        // Versammlungscode, fremdes Schema oder kaputter Code: kein Einchecken
        XCTAssertNil(TrainingLink.parse("https://verein.example.org/mein-bereich/versammlungen/da/7?v=3&c=59841234-0123456789abcdef"))
        XCTAssertNil(TrainingLink.parse("http://verein.example.org/mein-bereich/training/da/7?v=3&c=59841234-0123456789abcdef"))
        XCTAssertNil(TrainingLink.parse("https://verein.example.org/mein-bereich/training/da/7?v=3&c=abc"))
        let built = TrainingLink.build(server: "https://verein.example.org/", code: TrainingCode(code: "59841234-0123456789abcdef", refreshIn: 12, session: 7, club: 3))
        XCTAssertEqual(built, "https://verein.example.org/mein-bereich/training/da/7?v=3&c=59841234-0123456789abcdef")
        XCTAssertEqual(TrainingLink.parse(built), link)
    }

    func testScanPruefen() {
        let ok = "https://verein.example.org/mein-bereich/training/da/7?v=3&c=59841234-0123456789abcdef"
        XCTAssertNotNil(TrainingLink.from(scan: ok, server: "https://verein.example.org", clubId: 3).link)
        XCTAssertEqual(TrainingLink.from(scan: ok, server: "https://andere.example.org", clubId: 3).problem,
                       "Der QR-Code gehört zu einer anderen HUBIplan-Adresse.")
        XCTAssertNil(TrainingLink.from(scan: ok, server: "https://verein.example.org", clubId: 4).link)
        XCTAssertEqual(TrainingLink.from(scan: "Hallo", server: "https://verein.example.org", clubId: 3).problem,
                       "Das ist kein QR-Code zum Einchecken ins Training.")
    }

    func testNurMitModul() throws {
        let on = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV","training_enabled":true,"training_checkin":1}"#.utf8))
        XCTAssertTrue(on.hasTraining)
        XCTAssertEqual(on.trainingHint, "Einchecken ist offen")
        let off = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV"}"#.utf8))
        XCTAssertFalse(off.hasTraining)
    }

    func testUebungsleitung() throws {
        let d = try JSONDecoder().decode(TrainingDetail.self, from: Data(#"""
        {"id":7,"date":"2099-11-20","title":"Training","checkin_open":true,"checkin_possible":true,
         "attendance":[{"membership":1,"name":"Erika Beispiel","present":true,"source":"code","shooting":true},
                       {"membership":2,"name":"Max Muster","present":false,"source":null,"shooting":false}],
         "version":2}
        """#.utf8))
        XCTAssertEqual(d.presentCount, 1)
        XCTAssertEqual(trainingTime("19:00", "21:00"), "19:00–21:00")
        XCTAssertEqual(trainingTime("19:00", nil), "19:00")
        XCTAssertEqual(trainingTime(nil, "21:00"), "")
        let draft = ShootingDraft(date: "2099-11-15", discipline: " Sportpistole ")
        XCTAssertEqual(draft.json["discipline"] as? String, "Sportpistole")
        XCTAssertEqual(draft.json["external"] as? Bool, true)
    }
}
