import XCTest
@testable import HubiplanKern

/// Gestaltung „Frisch mobil“, Etappen U2 und U3: Reiter „Start“ und Terminliste nach Monaten
/// (wie `ReiterTest` der Android-App).
final class StartTests: XCTestCase {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func termin(
        _ key: String, rsvp: Bool = false, antwort: String? = nil, abgesagt: Bool = false,
        start: String = "2027-06-12T15:00:00+02:00"
    ) throws -> Occurrence {
        let antwortJson = antwort.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"key":"\(key)","event_id":7,"title":"Sommerfest","starts_at":"\(start)","ends_at":"\(start)",
         "all_day":false,"is_cancelled":\(abgesagt),"rsvp_enabled":\(rsvp),"my_response":\(antwortJson)}
        """
        return try JSONDecoder().decode(Occurrence.self, from: Data(json.utf8))
    }

    func testNaechsterTerminUndWasWartet() throws {
        let liste = [
            try termin("a", abgesagt: true), try termin("b", rsvp: true), try termin("c", rsvp: true),
            try termin("d", rsvp: true, antwort: "yes"),
        ]
        XCTAssertEqual(Startseite.naechsterTermin(liste)?.key, "b")
        XCTAssertNil(Startseite.naechsterTermin([try termin("a", abgesagt: true)]))
        XCTAssertEqual(Startseite.offeneRueckmeldungen(liste), 2)
        XCTAssertEqual(Startseite.offeneRueckmeldungen(liste, ohne: liste[1]), 1)
    }

    func testStartseiteVomServer() throws {
        let json = """
        {"next_event":{"key":"7-20270612T130000Z","event_id":7,"title":"Sommerfest","starts_at":"2027-06-12T15:00:00+02:00",
         "ends_at":"2027-06-12T22:00:00+02:00","rsvp_enabled":true,"my_response":null,"neu":1},
         "todo":[{"key":"rsvp","title":"2 Termine warten auf deine Rückmeldung","count":2,"target":"events"},
                 {"key":"surveys","title":"1 Umfrage wartet auf deine Antwort","count":1,"target":"surveys"},
                 {"key":"leer","title":"Nichts","count":0,"target":"orders"},
                 {"key":"spaeter","title":"Etwas Neues","count":3,"target":"unbekannt"}],
         "tiles":[{"key":"pinnwand","title":"Pinnwand","shown":true}],"mehr":true}
        """
        let seite = try JSONDecoder().decode(StartSeite.self, from: Data(json.utf8))
        XCTAssertEqual(seite.nextEvent?.title, "Sommerfest")
        XCTAssertEqual(seite.todo.count, 4)
        XCTAssertEqual(seite.tiles.map(\.key), ["pinnwand"])
        let leer = try JSONDecoder().decode(StartSeite.self, from: Data(#"{"next_event":null}"#.utf8))
        XCTAssertNil(leer.nextEvent)
        XCTAssertEqual(leer.todo, [])
        // Rückmeldungen zählt die App aus ihrer Terminliste; unbekannte Ziele und leere Zeilen fallen weg
        let liste = [try termin("b", rsvp: true), try termin("c")]
        let zeilen = Startseite.zeilen(server: seite.todo, termine: liste)
        XCTAssertEqual(zeilen.map(\.key), ["rsvp", "surveys"])
        XCTAssertEqual(zeilen[0], StartTodo(key: "rsvp", title: "1 Termin wartet auf deine Rückmeldung", count: 1, target: "events"))
        XCTAssertEqual(Startseite.zeilen(server: seite.todo, termine: liste, ohne: liste[0]).map(\.key), ["surveys"])
        // Älterer Stand ohne „start“: nur, was die Terminliste hergibt
        XCTAssertEqual(Startseite.zeilen(server: [], termine: [try termin("c")]), [])
        XCTAssertEqual(Startseite.symbol("pinboard"), .pinnwand)
        XCTAssertEqual(Startseite.symbol("events"), .zuErledigen)
    }

    func testAbrufUndAeltererStand() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"next_event":null,"todo":[],"tiles":[]}"#),
            FakeTransport.json(404, #"{"detail":"Nicht gefunden."}"#),
        ])
        let api = Api(server: "https://verein.example.de", transport: net, tokens: FakeTokens("hpd_a"))
        let seite = try await api.start(accessId: 5)
        XCTAssertEqual(seite?.todo, [])
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/portal/5/start/")
        // Älterer HUBIplan-Stand kennt den Abruf nicht
        let keine = try await api.start(accessId: 5)
        XCTAssertNil(keine)
    }

    func testTerminlisteNachMonaten() throws {
        XCTAssertEqual(
            Startseite.monatTitel(try termin("a", start: "2026-11-14T19:00:00+01:00"), timeZone: berlin, englisch: false),
            "November 2026"
        )
        XCTAssertEqual(
            Startseite.monatTitel(try termin("a", start: "2027-03-03T10:00:00+01:00"), timeZone: berlin, englisch: false),
            "März 2027"
        )
        XCTAssertEqual(
            Startseite.monatTitel(try termin("a", start: "2027-03-03T10:00:00+01:00"), timeZone: berlin, englisch: true),
            "March 2027"
        )
        // 23:30 UTC am Monatsletzten ist in Berlin schon der nächste Monat
        XCTAssertEqual(
            Startseite.monatTitel(try termin("a", start: "2026-11-30T23:30:00Z"), timeZone: berlin, englisch: false),
            "Dezember 2026"
        )
        XCTAssertEqual(Startseite.monatTitel(try termin("a", start: "kein Datum")), "")
        let gruppen = Startseite.monate(
            [
                try termin("a", start: "2027-06-12T15:00:00+02:00"), try termin("b", start: "2027-06-20T15:00:00+02:00"),
                try termin("c", start: "2027-07-01T15:00:00+02:00"),
            ],
            timeZone: berlin, englisch: false
        )
        XCTAssertEqual(gruppen.map(\.termine.count), [2, 1])
        XCTAssertEqual(gruppen.map(\.titel), ["Juni 2027", "Juli 2027"])
    }
}
