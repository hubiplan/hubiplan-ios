import XCTest
@testable import HubiplanKern

/// Verbindliche Anmeldung mit Teilnahmegebühr (HUBIplan A1–A5), gleiche Fälle wie
/// `AnmeldungenTest` in der Android-App. Alle Daten erfunden.
final class TeilnahmeTests: XCTestCase {
    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let antwort = #"""
    {"event_id":5,"can_cancel":true,
     "offer":{"id":1,"state":"open","state_text":"Anmeldung offen","closes_at":"2099-06-01T23:59:00+02:00",
      "is_open":true,"capacity":50,"free":47,"taken":3,"max_persons":4,"guests_allowed":true,"due_days":14,
      "category":null,"terms":"Stornierung nur bis zum Anmeldeschluss.",
      "prices":[
       {"id":11,"name":"Erwachsene","name_en":"Adults","applies":"all","age_from":null,"age_to":null,"capacity":null,
        "free":null,"vat_rate":null,"is_active":true,
        "current":{"id":21,"name":"Early Bird","amount":"29.00","until_date":"2099-03-01","remaining":null},
        "next":{"name":"Normal","amount":"35.00","until_date":null}},
       {"id":12,"name":"Kinder","name_en":"","applies":"members","age_from":6,"age_to":13,"capacity":10,
        "free":0,"vat_rate":null,"is_active":true,
        "current":{"id":22,"name":"","amount":"15.00","until_date":null,"remaining":null},"next":null},
       {"id":13,"name":"Gäste","name_en":"Guests","applies":"guests","age_from":null,"age_to":null,"capacity":null,
        "free":null,"vat_rate":null,"is_active":true,
        "current":{"id":23,"name":"","amount":"40.00","until_date":null,"remaining":null},"next":null}]},
     "persons":[{"membership_id":7,"name":"Anna Muster","self":true,"registered":false,"has_birth_date":true},
                {"membership_id":8,"name":"Kim Muster","self":false,"registered":true,"has_birth_date":false}],
     "mine":[{"id":3,"number":"A2099-0001","status":"registered","name":"Anna Muster","total":"15.00",
              "paid_state":"open","created_at":"2099-01-02T10:00:00+01:00","cancelled_at":null,
              "participants":[{"id":4,"name":"Kim Muster","membership_id":8,"price_id":12,"price_name":"Kinder",
                               "amount":"15.00","status":"active"}],
              "invoice":{"id":9,"number":"2099-0042","status":"open","total":"15.00","paid":"0.00","due_date":"2099-01-16"}}]}
    """#

    private func decode() throws -> MemberRegistration {
        try JSONDecoder().decode(MemberRegistration.self, from: Data(antwort.utf8))
    }

    func testAngebotUndEigeneAnmeldungLesen() throws {
        let d = try decode()
        XCTAssertEqual(d.offer.free, 47)
        Texte.language = "en"
        XCTAssertEqual(d.offer.prices[0].label, "Adults")
        XCTAssertEqual(d.offer.prices[1].label, "Kinder")
        Texte.language = "de"
        // Ausgebuchter Kindertarif und Gästetarif sind für Mitglieder nicht wählbar
        XCTAssertEqual(d.offer.prices(member: true).map(\.id), [11])
        XCTAssertEqual(d.offer.prices(member: false).map(\.id), [11, 13])
        XCTAssertTrue(d.offer.prices[1].hasAge)
        let mine = try XCTUnwrap(d.mine.first)
        XCTAssertTrue(mine.active)
        XCTAssertEqual(mine.invoice?.number, "2099-0042")
        XCTAssertEqual(mine.participants.first?.line, "Kim Muster: Kinder, 15,00\u{00A0}€")
        XCTAssertEqual(mine.paidText, "offen")
    }

    func testSummeNachAktuellerPreisstufe() throws {
        let d = try decode()
        let persons = [RegistrationChoice(membershipId: 7, priceId: 11), RegistrationChoice(membershipId: nil, name: "Gerd Gast", priceId: 13)]
        XCTAssertEqual(Teilnahme.sumCents(d.offer, persons), 6900)
        XCTAssertEqual(Teilnahme.priceLine(d.offer.prices[0]), "Erwachsene: 29,00\u{00A0}€ (Early Bird) · danach 35,00\u{00A0}€")
        XCTAssertEqual(Teilnahme.priceExtra(d.offer.prices[1]), "6 bis 13 Jahre · nur Mitglieder")
    }

    func testAnfrageMitGastUndKennzeichenApp() throws {
        let payload = Teilnahme.payload(
            [RegistrationChoice(membershipId: 7, name: "ignoriert", priceId: 11),
             RegistrationChoice(membershipId: nil, name: " Gerd Gast ", priceId: 13, birthDate: "2012-05-04")],
            note: " vegetarisch ",
            termsAccepted: true
        )
        let persons = try XCTUnwrap(payload["persons"] as? [[String: Any]])
        XCTAssertEqual(persons[0]["membership_id"] as? Int, 7)
        XCTAssertNil(persons[0]["name"])
        XCTAssertTrue(persons[1]["membership_id"] is NSNull)
        XCTAssertEqual(persons[1]["name"] as? String, "Gerd Gast")
        XCTAssertEqual(persons[1]["birth_date"] as? String, "2012-05-04")
        XCTAssertEqual(payload["note"] as? String, "vegetarisch")
        XCTAssertEqual(payload["terms_accepted"] as? Bool, true)
        XCTAssertEqual(payload["app"] as? Bool, true)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
    }

    func testLueckenVorDemAbschicken() throws {
        let offer = try decode().offer
        let none: (RegistrationChoice) -> Bool = { _ in false }
        XCTAssertEqual(Teilnahme.missing(offer, [], needsBirthDate: none, termsAccepted: true), .nobody)
        let five = (1...5).map { RegistrationChoice(membershipId: $0, priceId: 11) }
        XCTAssertEqual(Teilnahme.missing(offer, five, needsBirthDate: none, termsAccepted: true), .tooMany)
        XCTAssertEqual(Teilnahme.missing(offer, [RegistrationChoice(membershipId: nil, name: " ", priceId: 13)], needsBirthDate: none, termsAccepted: true), .name)
        XCTAssertEqual(Teilnahme.missing(offer, [RegistrationChoice(membershipId: 9, priceId: 12)], needsBirthDate: { _ in true }, termsAccepted: true), .birthDate)
        XCTAssertEqual(Teilnahme.missing(offer, [RegistrationChoice(membershipId: 7, priceId: 11)], needsBirthDate: none, termsAccepted: false), .terms)
        XCTAssertNil(Teilnahme.missing(offer, [RegistrationChoice(membershipId: 7, priceId: 11)], needsBirthDate: none, termsAccepted: true))
    }

    func testTerminMitAnmeldungUndAeltererServer() throws {
        let mit = #"""
        {"id":5,"title":"Sommerfest","starts_at":"2099-06-13T14:00:00+02:00","ends_at":"2099-06-13T18:00:00+02:00",
         "registration":{"enabled":true,"state":"open","state_text":"Anmeldung offen","closes_at":"2099-06-01T23:59:00+02:00",
           "free":47,"can_setup":false,"can_view_list":false,"can_register":true}}
        """#
        let e = try JSONDecoder().decode(EventDetail.self, from: Data(mit.utf8))
        XCTAssertEqual(e.registration?.canRegister, true)
        XCTAssertEqual(e.registration?.free, 47)
        let alt = #"{"id":5,"title":"Sommerfest","starts_at":"2099-06-13T14:00:00+02:00","ends_at":"2099-06-13T18:00:00+02:00"}"#
        XCTAssertNil(try JSONDecoder().decode(EventDetail.self, from: Data(alt.utf8)).registration)
        let ohne = #"{"id":5,"title":"Sommerfest","starts_at":"2099-06-13T14:00:00+02:00","ends_at":"2099-06-13T18:00:00+02:00","registration":null}"#
        XCTAssertNil(try JSONDecoder().decode(EventDetail.self, from: Data(ohne.utf8)).registration)
    }

    private let warteliste = #"""
    {"event_id":5,"can_cancel":true,
     "offer":{"id":1,"state":"full","state_text":"Alle Plätze sind vergeben.","closes_at":"2099-06-01T23:59:00+02:00",
      "capacity":2,"free":0,"taken":2,"max_persons":4,"guests_allowed":true,"terms":"","prices":[],
      "waitlist":true,"waiting":1,"substitute_allowed":true,"cancel_rules":[{"days":30,"percent":50}],
      "cancel_fee_fixed":"5.00","expire_unpaid_days":null},
     "persons":[],
     "mine":[{"id":3,"number":"A2099-0002","status":"waiting","total":"35.00","paid_state":"waiting",
              "participants":[{"id":4,"name":"Anna Muster","membership_id":7,"price_id":11,"price_name":"Erwachsene",
                               "amount":"35.00","status":"active"}],
              "invoice":null,"waitlist_position":1,"moved_up_at":null,"free_cancel_until":null,
              "cancel_fee":"0.00","fee_invoice":null,"can_cancel":true,"can_substitute":true}]}
    """#

    func testWartelisteUndStornostaffelLesen() throws {
        let d = try JSONDecoder().decode(MemberRegistration.self, from: Data(warteliste.utf8))
        XCTAssertTrue(d.offer.canJoin)
        XCTAssertTrue(d.offer.toWaitlist)
        XCTAssertEqual(d.offer.cancelRules.first?.percent, 50)
        let mine = try XCTUnwrap(d.mine.first)
        XCTAssertTrue(mine.active && mine.waiting)
        XCTAssertEqual(mine.waitlistPosition, 1)
        XCTAssertEqual(mine.canCancel, true)
        XCTAssertEqual(mine.activeParticipants.first?.priceId, 11)
        XCTAssertEqual(mine.paidText, "Warteliste")
        // Älterer Stand ohne Warteliste: voll heißt nicht anmeldbar, can_cancel fehlt
        var alt = try decode()
        XCTAssertNil(alt.mine.first?.canCancel)
        alt.offer.state = "full"
        XCTAssertFalse(alt.offer.canJoin)
    }

    func testGebuehrenvorschauUndAnfragen() throws {
        let q = try JSONDecoder().decode(FeeQuote.self, from: Data(#"{"base":"35.00","percent":50,"fee":"22.50","free_reason":""}"#.utf8))
        XCTAssertTrue(q.hasFee)
        XCTAssertEqual(q.text, "Stornogebühr: 22,50\u{00A0}€ (50 % von 35,00\u{00A0}€ nach den Teilnahmebedingungen).")
        let frei = try JSONDecoder().decode(FeeQuote.self, from: Data(#"{"base":"35.00","percent":0,"fee":"0.00","free_reason":"moved_up"}"#.utf8))
        XCTAssertFalse(frei.hasFee)
        XCTAssertEqual(frei.text, "Kostenfrei: innerhalb von 48 Stunden nach dem Nachrücken von der Warteliste.")
        XCTAssertEqual(Teilnahme.cancelQuery([]), "")
        XCTAssertEqual(Teilnahme.cancelQuery([4, 5]), "?participants=4,5")
        XCTAssertTrue(Teilnahme.cancelPayload([]).isEmpty)
        XCTAssertEqual(Teilnahme.cancelPayload([4])["participants"] as? [Int], [4])
        let gast = Teilnahme.substitutePayload(membershipId: nil, name: " Erna Ersatz ", birthDate: "1980-03-04")
        XCTAssertTrue(gast["membership_id"] is NSNull)
        XCTAssertEqual(gast["name"] as? String, "Erna Ersatz")
        XCTAssertEqual(gast["birth_date"] as? String, "1980-03-04")
        let familie = Teilnahme.substitutePayload(membershipId: 8, name: "ignoriert", birthDate: nil)
        XCTAssertEqual(familie["membership_id"] as? Int, 8)
        XCTAssertNil(familie["name"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(gast))
    }

    private let zusatz = #"""
    {"event_id":5,"can_cancel":true,
     "offer":{"id":1,"state":"open","state_text":"Anmeldung offen","max_persons":4,"guests_allowed":true,"terms":"",
      "prices":[{"id":11,"name":"Erwachsene","is_active":true,"current":{"id":21,"amount":"29.00"}}],
      "catering":false,"minors":true,"health_allowed":true,
      "addons":[{"id":1,"name":"Busfahrt","per":"person","choices":[{"id":2,"name":"Busfahrt","amount":"12.00","capacity":1,"free":0}]},
                {"id":3,"name":"Menü","kind":"meal","per":"person","required":true,
                 "choices":[{"id":4,"name":"Schnitzel","amount":"0.00"},{"id":5,"name":"Lachs","amount":"3.00"}]}],
      "questions":[{"id":7,"text":"Tischwunsch","kind":"text","per":"registration","required":true},
                   {"id":8,"text":"Allergien","kind":"health","per":"person"}]},
     "persons":[{"membership_id":8,"name":"Kim Muster","self":false,"registered":false,"has_birth_date":true,"minor":true}],
     "mine":[{"id":3,"number":"A2099-0003","status":"registered","total":"44.00","paid_state":"open",
              "participants":[{"id":4,"name":"Anna Muster","membership_id":7,"price_id":11,"price_name":"Erwachsene","amount":"29.00",
                               "bookings":[{"id":1,"choice_id":2,"addon_id":1,"name":"Busfahrt","amount":"12.00"},
                                           {"id":2,"choice_id":5,"addon_id":3,"name":"Menü: Lachs","amount":"3.00"}]}],
              "bookings":[]}]}
    """#

    func testZusatzleistungenFragenUndErziehungsberechtigte() throws {
        let d = try JSONDecoder().decode(MemberRegistration.self, from: Data(zusatz.utf8))
        let offer = d.offer
        XCTAssertTrue(offer.minors && offer.asksHealth)
        XCTAssertTrue(offer.addons[0].choices[0].full)
        XCTAssertEqual(offer.addons[1].choices[1].label, "Lachs (+3,00\u{00A0}€)")
        XCTAssertTrue(d.persons[0].minor)
        XCTAssertEqual(
            Booking.line(d.mine[0].participants[0].bookings),
            "Busfahrt (12,00\u{00A0}€), Menü: Lachs (3,00\u{00A0}€)"
        )
        let anna = RegistrationChoice(membershipId: 7, priceId: 11, extras: RegistrationExtras(addons: [3: 5], health: " Nüsse "))
        XCTAssertEqual(Teilnahme.sumCents(offer, [anna]), 3200)
        let none: (RegistrationChoice) -> Bool = { _ in false }
        // Pflichtfrage je Anmeldung fehlt, dann Einwilligung
        XCTAssertEqual(Teilnahme.missing(offer, [anna], needsBirthDate: none, termsAccepted: true), .answer)
        let reg = RegistrationExtras(answers: [7: .text("am Fenster")])
        XCTAssertEqual(Teilnahme.missing(offer, [anna], needsBirthDate: none, termsAccepted: true, extras: reg), .consent)
        XCTAssertNil(Teilnahme.missing(offer, [anna], needsBirthDate: none, termsAccepted: true, extras: reg, healthConsent: true))
        // Menü ist Pflicht, unter 18 Erziehungsberechtigte
        let kim = RegistrationChoice(membershipId: 8, priceId: 11, minor: true)
        XCTAssertEqual(Teilnahme.missing(offer, [kim], needsBirthDate: none, termsAccepted: true, extras: reg), .addon)
        var kimMenu = kim
        kimMenu.extras = RegistrationExtras(addons: [3: 4])
        XCTAssertEqual(Teilnahme.missing(offer, [kimMenu], needsBirthDate: none, termsAccepted: true, extras: reg), .guardian)
        var kimOk = kimMenu
        kimOk.extras.guardians = [Guardian(name: "Anna Muster", phone: "0123 456789", email: "anna@example.org")]
        XCTAssertNil(Teilnahme.missing(offer, [kimOk], needsBirthDate: none, termsAccepted: true, extras: reg))
        let payload = Teilnahme.payload([anna, kimOk], note: "", termsAccepted: true, extras: reg, healthConsent: true, asksHealth: true)
        let persons = try XCTUnwrap(payload["persons"] as? [[String: Any]])
        XCTAssertEqual((persons[0]["addons"] as? [String: Int])?["3"], 5)
        XCTAssertEqual(persons[0]["health"] as? String, "Nüsse")
        XCTAssertNil(persons[0]["guardians"])
        let guardians = try XCTUnwrap(persons[1]["guardians"] as? [[String: String]])
        XCTAssertEqual(guardians[0]["phone"], "0123 456789")
        XCTAssertEqual((payload["answers"] as? [String: Any])?["7"] as? String, "am Fenster")
        XCTAssertEqual(payload["health_consent"] as? Bool, true)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        XCTAssertTrue(Teilnahme.isMinor("2012-05-04", start: "2029-05-03T10:00:00+02:00"))
        XCTAssertFalse(Teilnahme.isMinor("2012-05-04", start: "2030-05-04T10:00:00+02:00"))
    }

    func testTerminMitAblauf() throws {
        let json = #"{"id":5,"title":"Sommerfest","starts_at":"2099-06-13T14:00:00+02:00","ends_at":"2099-06-13T18:00:00+02:00","programme":"14:00 Begrüßung"}"#
        XCTAssertEqual(try JSONDecoder().decode(EventDetail.self, from: Data(json.utf8)).programme, "14:00 Begrüßung")
    }

    func testEintrittskartenNurMitAngabeDesServers() async throws {
        XCTAssertFalse(try XCTUnwrap(decode().mine.first).hasTickets)
        let neu = antwort.replacingOccurrences(of: #""paid_state":"open""#, with: #""has_tickets":true,"paid_state":"open""#)
        let d = try JSONDecoder().decode(MemberRegistration.self, from: Data(neu.utf8))
        XCTAssertTrue(try XCTUnwrap(d.mine.first).hasTickets)
        let net = FakeTransport([.success(HttpResponse(status: 200, body: Data("%PDF-1.4".utf8)))])
        let api = Api(server: "https://verein.example.de", transport: net, tokens: FakeTokens("hpd_a"))
        _ = try await api.registrationTickets(accessId: 3, eventId: 5, registrationId: 9)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/events/5/registration/9/tickets/")
    }
}
