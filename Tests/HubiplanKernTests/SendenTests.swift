import XCTest
@testable import HubiplanKern

/// Kurzmitteilung aus der App senden (wie Android). Erfundene Daten.
final class SendenTests: XCTestCase {
    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    func testVorschauUndSenden() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"senders":[{"key":"org-1","name":"Schützenverein Musterstadt","type":"org","id":1},{"key":"dept-9","name":"Zug 1","type":"dept","id":9,"club":"Schützenverein Musterstadt"}],"max_body":400}"#),
            FakeTransport.json(200, #"{"counts":{"app":31,"mail":12,"letter":0},"sender":"Zug 1"}"#),
            FakeTransport.json(201, #"{"id":5,"sent":{"app":31,"mail":12}}"#),
            FakeTransport.json(400, #"{"body":["Höchstens 400 Zeichen."]}"#),
            FakeTransport.json(429, #"{"detail":"Heute sind schon zehn Kurzmitteilungen gesendet."}"#),
        ])
        let api = Api(server: "https://verein.example.de", transport: net, tokens: FakeTokens("hpd_a"))
        let list = try await api.senders()
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/send/")
        XCTAssertEqual(list.maxBody, 400)
        XCTAssertEqual(list.senders.map(\.label), ["Schützenverein Musterstadt", "Zug 1 (Schützenverein Musterstadt)"])

        let zug = list.senders[1]
        let preview = try await api.sendShort(zug, subject: "Antreten", body: "Heute 18 Uhr", confirm: false)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/send/dept/9/")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[1].body ?? Data()) as? [String: Any])
        XCTAssertEqual(sent["subject"] as? String, "Antreten")
        XCTAssertEqual(sent["body"] as? String, "Heute 18 Uhr")
        XCTAssertEqual(sent["confirm"] as? Bool, false)
        XCTAssertEqual(Empfaenger.total(preview.counts), 43)
        XCTAssertEqual(Empfaenger.summary(preview.counts), "geht an 43 Mitglieder, davon 31 per App, 12 per E-Mail")

        let done = try await api.sendShort(zug, subject: "Antreten", body: "Heute 18 Uhr", confirm: true)
        XCTAssertEqual(done.sent["app"], 31)

        do {
            _ = try await api.sendShort(zug, subject: "Antreten", body: "lang", confirm: false)
            XCTFail("400 erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.text, "Höchstens 400 Zeichen.")
        }
        do {
            _ = try await api.sendShort(zug, subject: "Antreten", body: "noch eine", confirm: true)
            XCTFail("429 erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.text, "Heute sind schon zehn Kurzmitteilungen gesendet.")
        }
    }

    func testEmpfaengerInWorten() {
        XCTAssertEqual(Empfaenger.summary([:]), "geht an niemanden")
        XCTAssertEqual(Empfaenger.summary(["portal": 1]), "geht an 1 Mitglied, davon 1 nur im Mitgliederbereich")
        Texte.language = "en"
        XCTAssertEqual(Empfaenger.summary(["app": 2, "mail": 1]), "goes to 3 members, of which 2 via app, 1 by email")
    }
}
