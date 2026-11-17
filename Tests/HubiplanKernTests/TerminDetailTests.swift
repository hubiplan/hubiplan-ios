import XCTest
@testable import HubiplanKern

/// Termin-Detail mit Vielleicht, Begleitung, Bemerkung (UX-Audit 16.11., IOS-04, IOS-05, IOS-01);
/// gleiche Fälle wie in der Android-App.
final class TerminDetailTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let detail = #"""
    {"id":12,"title":"Zugversammlung","description":"Wir planen das Sommerfest.","location":"Vereinsheim","address":"Musterweg 1, 41468 Musterstadt",
    "directions":"Parkplätze hinter der Halle.","latitude":51.2,"longitude":6.68,"map_links":{"osm":"https://www.openstreetmap.org/x","google":null},
    "starts_at":"2026-11-20T19:00:00+01:00","ends_at":"2026-11-20T21:00:00+01:00","is_cancelled":false,"cancel_note":"","owner":"Zug 1",
    "attachments":[{"id":4,"name":"Tagesordnung","size":1200,"content_type":"application/pdf","file_name":"tagesordnung.pdf"}],
    "rsvp":{"enabled":true,"deadline":"2026-11-19T18:00:00+01:00","capacity":40,"free":28,"guests_allowed":true,"max_guests":2,
    "maybe_allowed":true,"note_allowed":true,"note_question":"Bringst du einen Salat mit?","can_respond":true,"reason":"",
    "mine":{"status":"yes","guests":1,"note":"Nudelsalat","source":"member"}},"neu":1}
    """#

    override func tearDown() { Texte.language = "de" }

    func testDetailLesen() async throws {
        let net = FakeTransport([FakeTransport.json(200, detail)])
        let event = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).event(accessId: 3, eventId: 12)
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/portal/3/events/12/")
        XCTAssertEqual(event.title, "Zugversammlung")
        XCTAssertEqual(event.directions, "Parkplätze hinter der Halle.")
        XCTAssertEqual(event.latitude, 51.2)
        XCTAssertEqual(event.mapLinks.osm, "https://www.openstreetmap.org/x")
        XCTAssertNil(event.mapLinks.google)
        XCTAssertEqual(event.attachments.first?.shownName, "tagesordnung.pdf")
        XCTAssertTrue(event.rsvp.maybeAllowed)
        XCTAssertTrue(event.rsvp.noteAllowed)
        XCTAssertEqual(event.rsvp.noteQuestion, "Bringst du einen Salat mit?")
        XCTAssertEqual(event.rsvp.free, 28)
        XCTAssertEqual(event.rsvp.mine, MyResponse(status: "yes", guests: 1, note: "Nudelsalat"))
        XCTAssertEqual(Rueckmeldung.stand(event.rsvp.mine), "Du hast zugesagt (mit 1 Begleitung).")
    }

    func testAeltererStandOhneRueckmeldungsfelder() throws {
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(#"{"id":5,"title":"Probe","starts_at":"x","ends_at":"y"}"#.utf8))
        XCTAssertFalse(event.rsvp.enabled)
        XCTAssertFalse(event.rsvp.canRespond)
        XCTAssertEqual(event.rsvp.maxGuests, 10)
        XCTAssertEqual(event.attachments, [])
    }

    func testVielleichtMitBegleitungUndBemerkung() async throws {
        let net = FakeTransport([FakeTransport.json(200, detail), FakeTransport.json(200, detail)])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let lang = String(repeating: "x", count: 250)
        let after = try await api.respond(accessId: 3, eventId: 12, status: "maybe", guests: 2, note: lang)
        XCTAssertEqual(after?.id, 12)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[0].body)) as? [String: Any])
        XCTAssertEqual(sent["status"] as? String, "maybe")
        XCTAssertEqual(sent["guests"] as? Int, 2)
        // Bemerkung höchstens 200 Zeichen wie Android und Server
        XCTAssertEqual((sent["note"] as? String)?.count, 200)
        let withdrawn = try await api.withdraw(accessId: 3, eventId: 12)
        XCTAssertEqual(withdrawn?.rsvp.mine?.status, "yes")
        XCTAssertEqual(net.seen[1].method, "DELETE")
    }

    /// IOS-01: Der Server lehnt mit einer Liste ab (DRF ValidationError); der Text kommt an.
    func testAblehnungZeigtDenTextDesServers() async throws {
        let net = FakeTransport([FakeTransport.json(400, #"["Der Anmeldeschluss ist vorbei."]"#)])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        do {
            try await api.respond(accessId: 3, eventId: 12, status: "yes")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.text, "Der Anmeldeschluss ist vorbei.")
        }
    }

    /// IOS-01: Der Fehler bleibt über den Abgleich stehen, nur für Termine, die es noch gibt.
    func testFehlerUeberlebtDenAbgleich() throws {
        let list = try JSONDecoder().decode(EventList.self, from: Data(#"{"items":[{"key":"12","event_id":12,"title":"A","starts_at":"x","ends_at":"y"},{"key":"13","event_id":13,"title":"B","starts_at":"x","ends_at":"y"}]}"#.utf8)).items
        var errors = RueckmeldungsFehler()
        errors.failed(12, "Der Anmeldeschluss ist vorbei.")
        errors.failed(99, "Alt")
        errors.keep(only: list)
        XCTAssertEqual(errors[12], "Der Anmeldeschluss ist vorbei.")
        XCTAssertNil(errors[99])
        errors.start(12)
        XCTAssertNil(errors[12])
        XCTAssertTrue(errors.isEmpty)
    }

    /// IOS-05: dieselben Wörter wie in der Android-App
    func testAbzeichenWieAndroid() {
        XCTAssertEqual(Rueckmeldung.abzeichen(abgesagt: false, rsvp: true, antwort: "yes"), "Zugesagt")
        XCTAssertEqual(Rueckmeldung.abzeichen(abgesagt: false, rsvp: true, antwort: "no"), "Nicht dabei")
        XCTAssertEqual(Rueckmeldung.abzeichen(abgesagt: false, rsvp: true, antwort: "maybe"), "Vielleicht")
        XCTAssertEqual(Rueckmeldung.abzeichen(abgesagt: false, rsvp: true, antwort: nil), "Noch offen")
        XCTAssertEqual(Rueckmeldung.abzeichen(abgesagt: true, rsvp: true, antwort: "yes"), "Abgesagt")
        XCTAssertNil(Rueckmeldung.abzeichen(abgesagt: false, rsvp: false, antwort: nil))
        Texte.language = "en"
        XCTAssertEqual(Rueckmeldung.abzeichen(abgesagt: false, rsvp: true, antwort: "yes"), "Attending")
        XCTAssertEqual(Rueckmeldung.abzeichen(abgesagt: false, rsvp: true, antwort: "no"), "Not attending")
        XCTAssertEqual(Rueckmeldung.abzeichen(abgesagt: false, rsvp: true, antwort: nil), "Not answered yet")
    }

    func testBestaetigungen() {
        XCTAssertEqual(Rueckmeldung.gespeichert("yes"), "Deine Zusage ist gespeichert.")
        XCTAssertEqual(Rueckmeldung.gespeichert("no"), "Deine Absage ist gespeichert.")
        XCTAssertEqual(Rueckmeldung.gespeichert("maybe"), "Deine Antwort „Vielleicht“ ist gespeichert.")
        XCTAssertEqual(Rueckmeldung.gespeichert(nil), "Deine Rückmeldung ist zurückgenommen.")
        XCTAssertEqual(Rueckmeldung.stand(nil), "Du hast dich noch nicht zurückgemeldet.")
        XCTAssertEqual(Rueckmeldung.stand(MyResponse(status: "yes", guests: 2)), "Du hast zugesagt (mit 2 Begleitungen).")
        XCTAssertEqual(Rueckmeldung.stand(MyResponse(status: "no")), "Du hast abgesagt.")
    }

    func testAnhangLaden() async throws {
        let net = FakeTransport([.success(HttpResponse(status: 200, body: Data("%PDF".utf8)))])
        let data = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).eventAttachment(accessId: 3, eventId: 12, attachmentId: 4)
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/portal/3/events/12/attachments/4/")
        XCTAssertEqual(data, Data("%PDF".utf8))
    }

    func testFehlertexteDesServers() {
        func text(_ body: String) -> String { Api.errorFields(Data(body.utf8)).message }
        XCTAssertEqual(text(#"{"detail":"Nicht erlaubt."}"#), "Nicht erlaubt.")
        XCTAssertEqual(text(#"["Ausgebucht."]"#), "Ausgebucht.")
        XCTAssertEqual(text(#"{"non_field_errors":["Zu spät."]}"#), "Zu spät.")
        XCTAssertEqual(text(#"{"note":["Höchstens 200 Zeichen."],"guests":["Höchstens 2."]}"#), "Höchstens 2. Höchstens 200 Zeichen.")
        XCTAssertEqual(Api.errorFields(Data(#"{"code":"device_renew","detail":"x"}"#.utf8)).code, "device_renew")
        XCTAssertEqual(text("kein json"), "")
    }
}
