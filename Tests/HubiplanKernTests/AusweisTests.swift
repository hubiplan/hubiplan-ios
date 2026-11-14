import XCTest
@testable import HubiplanKern

final class MemoryCards: CardStore, @unchecked Sendable {
    private let lock = NSLock()
    private var cards: [Int: StoredCard] = [:]

    func load(accessId: Int) -> StoredCard? { lock.withLock { cards[accessId] } }
    func save(accessId: Int, card: StoredCard) { lock.withLock { cards[accessId] = card } }
    func delete(accessId: Int) { lock.withLock { cards[accessId] = nil } }
    func clear() { lock.withLock { cards = [:] } }
}

final class AusweisTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let active = #"{"state":"active","url":"https://verein.example.de/ausweis/pruefen/abc","display":{"first_name":"Erika","last_name":"Musterfrau","status":"active","status_label":"Aktives Mitglied","member_type":"Vollmitglied","club":"Schützenverein Musterstadt","department_label":"Zug","departments":["Zug 1","Kapelle"],"club_number":"0042","photo_url":"/api/portal/3/card/photo/","logo_url":"/api/portal/3/card/logo/","theme":{"primary":"0E7C66","on_primary":"FFFFFF"},"neu":1},"wallet":{"apple":true}}"#

    override func tearDown() { Texte.language = "de" }

    func testAusweisLesen() async throws {
        let net = FakeTransport([FakeTransport.json(200, active)])
        let card = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).card(accessId: 3)
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/portal/3/card/")
        XCTAssertTrue(card.showable)
        XCTAssertEqual(card.display?.name, "Erika Musterfrau")
        XCTAssertEqual(card.display?.firstLine, "Erika")
        XCTAssertEqual(card.display?.departments, ["Zug 1", "Kapelle"])
        XCTAssertEqual(card.display?.theme?.onPrimary, "FFFFFF")
        XCTAssertEqual(card.wallet?.apple, true)
        XCTAssertEqual(card.wallet?.google, false)
    }

    func testLeereAntwortUndOrganisation() throws {
        let none = try JSONDecoder().decode(CardState.self, from: Data("{}".utf8))
        XCTAssertEqual(none.state, "none")
        XCTAssertFalse(none.showable)
        // Aktiv, aber ohne Prüfadresse: nicht vorzeigbar
        let blank = try JSONDecoder().decode(CardState.self, from: Data(#"{"state":"active","url":" ","display":{}}"#.utf8))
        XCTAssertFalse(blank.showable)
        let org = try JSONDecoder().decode(CardDisplay.self, from: Data(#"{"kind":"organization","last_name":"Musterbau GmbH"}"#.utf8))
        XCTAssertTrue(org.isOrganization)
        XCTAssertEqual(org.name, "Musterbau GmbH")
        XCTAssertEqual(org.firstLine, "Organisationsmitglied")
        XCTAssertEqual(org.status, "inactive")
        Texte.language = "en"
        XCTAssertEqual(org.firstLine, "Organisation member")
    }

    func testAbrufenLegtAusweisMitBildernAb() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, active),
            .success(HttpResponse(status: 200, body: Data([1, 2, 3]))),
            FakeTransport.json(404, "{}"),
        ])
        let store = MemoryCards()
        let now = Date(timeIntervalSince1970: 1_795_197_600)
        let stored = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).refreshCard(accessId: 3, store: store, now: now)
        XCTAssertEqual(net.seen.map(\.url), [
            "https://verein.example.de/api/portal/3/card/",
            "https://verein.example.de/api/portal/3/card/photo/",
            "https://verein.example.de/api/portal/3/card/logo/",
        ])
        // Bilder mit Geräteschlüssel, aber ohne JSON-Wunsch
        XCTAssertEqual(net.seen[1].headers["Authorization"], "Bearer hpd_a")
        XCTAssertNil(net.seen[1].headers["Accept"])
        XCTAssertEqual(net.seen[0].headers["Accept"], "application/json")
        XCTAssertEqual(stored.photo, Data([1, 2, 3]))
        XCTAssertNil(stored.logo)
        XCTAssertEqual(store.load(accessId: 3), stored)
        // Ablage übersteht Schreiben und Lesen
        let copy = try XCTUnwrap(StoredCard.decode(try XCTUnwrap(stored.encoded())))
        XCTAssertEqual(copy, stored)
        XCTAssertNil(StoredCard.decode(Data("kaputt".utf8)))
    }

    func testBildNurVonDerEigenenInstanz() async throws {
        let net = FakeTransport([.success(HttpResponse(status: 200, body: Data([1])))])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let foreign = await api.image("https://fremd.example.org/bild.png")
        XCTAssertNil(foreign)
        let double = await api.image("//fremd.example.org/bild.png")
        XCTAssertNil(double)
        XCTAssertEqual(net.seen.count, 0)
    }

    func testGesperrterAusweisWirdGeloescht() async throws {
        let store = MemoryCards()
        let api = Api(server: server, transport: FakeTransport([
            FakeTransport.json(200, active),
            FakeTransport.json(404, "{}"),
            FakeTransport.json(404, "{}"),
            FakeTransport.json(200, #"{"state":"revoked"}"#),
        ]), tokens: FakeTokens("hpd_a"))
        _ = try await api.refreshCard(accessId: 3, store: store)
        XCTAssertNotNil(store.load(accessId: 3))
        let revoked = try await api.refreshCard(accessId: 3, store: store)
        XCTAssertNil(store.load(accessId: 3))
        XCTAssertEqual(CardAnzeige.from(stored: revoked, offline: false), .revoked)
    }

    func testOhneNetzBleibtDieAblage() async throws {
        let store = MemoryCards()
        let api = Api(server: server, transport: FakeTransport([
            FakeTransport.json(200, active),
            FakeTransport.json(404, "{}"),
            FakeTransport.json(404, "{}"),
            .failure(URLError(.notConnectedToInternet)),
        ]), tokens: FakeTokens("hpd_a"))
        _ = try await api.refreshCard(accessId: 3, store: store)
        do {
            _ = try await api.refreshCard(accessId: 3, store: store)
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.code, "offline")
        }
        XCTAssertNotNil(store.load(accessId: 3))
    }

    func testAnzeige() throws {
        let now = Date(timeIntervalSince1970: 1_795_197_600)
        XCTAssertEqual(CardAnzeige.from(stored: nil, offline: false), .loading)
        XCTAssertEqual(CardAnzeige.from(stored: nil, offline: true), .offlineEmpty)
        let card = try JSONDecoder().decode(CardState.self, from: Data(active.utf8))
        let fresh = StoredCard(card: card, savedAt: now)
        XCTAssertEqual(CardAnzeige.from(stored: fresh, offline: false, now: now), .card(fresh, note: false))
        XCTAssertEqual(CardAnzeige.from(stored: fresh, offline: true, now: now), .card(fresh, note: true))
        // Nach mehr als einem Tag steht der Stand dabei
        XCTAssertEqual(CardAnzeige.from(stored: fresh, offline: false, now: now.addingTimeInterval(25 * 3600)), .card(fresh, note: true))
        XCTAssertEqual(CardAnzeige.from(stored: fresh, offline: false, now: now.addingTimeInterval(23 * 3600)), .card(fresh, note: false))
        let none = try JSONDecoder().decode(CardState.self, from: Data(#"{"state":"none"}"#.utf8))
        XCTAssertEqual(CardAnzeige.from(stored: StoredCard(card: none, savedAt: now), offline: false), CardAnzeige.none)
    }

    func testFarbe() throws {
        let green = try XCTUnwrap(Farbe.rgb(" 0E7C66 "))
        XCTAssertEqual(green.red, 14.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(green.green, 124.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(green.blue, 102.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(Farbe.rgb("\u{23}ffffff")?.red, 1)
        XCTAssertNil(Farbe.rgb(nil))
        XCTAssertNil(Farbe.rgb("fff"))
        XCTAssertNil(Farbe.rgb("zzzzzz"))
        XCTAssertNil(Farbe.rgb("+12345"))
    }
}
