import XCTest
@testable import HubiplanKern

final class VerwaltungQuittungTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() {
        Texte.language = "de"
    }

    private func decode<T: Decodable>(_ text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    private func verwaltung(_ net: FakeTransport) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: AdminUnit(id: 4, name: "Verein"))
    }

    private func sorted(_ request: HttpRequest) -> String {
        guard let body = request.body, let object = try? JSONSerialization.jsonObject(with: body),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func fertig() -> ReceiptDraft {
        var draft = ReceiptDraft(key: "k-anlegen", finalizeKey: "k-abschluss")
        draft.name = " Max Mustermann "
        draft.amount = "25"
        draft.purpose = "Auslagen Blumen"
        draft.account = 2
        draft.category = 3
        draft.counterparty = SignatureStrokes(width: 300, height: 120, strokes: [[[1, 2], [30, 40]]])
        draft.counterpartyAt = "2026-11-14T19:30:00+01:00"
        return draft
    }

    func testUnterschriftAusLinien() throws {
        XCTAssertNil(SignatureStrokes(width: 300, height: 120, lines: [[(1, 1)]]))
        XCTAssertNil(SignatureStrokes(width: 5, height: 120, lines: [[(1, 1), (2, 2)]]))
        let strokes = try XCTUnwrap(SignatureStrokes(width: 300.7, height: 120.2, lines: [[(1.9, 2.1), (30.5, 40.4)], [(7, 7)]]))
        XCTAssertEqual(strokes, SignatureStrokes(width: 300, height: 120, strokes: [[[1, 2], [30, 40]]]))
        XCTAssertEqual(strokes.lines.first?.last?.x, 30)
        let shape: SignatureShape = try decode(#"{"w":1000,"h":400,"s":[[10,20,30,40,50],[]]}"#)
        XCTAssertEqual(shape.lines.count, 2)
        XCTAssertEqual(shape.lines[0].map(\.y), [20, 40])
        XCTAssertTrue(shape.lines[1].isEmpty)
        let stored: StoredSignature = try decode(#"{"signature":null}"#)
        XCTAssertNil(stored.signature)
        XCTAssertEqual(Zeit.stamp(Date(timeIntervalSince1970: 1_794_681_000), timeZone: TimeZone(identifier: "Europe/Berlin")!), "2026-11-14T19:30:00+01:00")
    }

    func testBereitschaftUndTexte() {
        var draft = ReceiptDraft()
        XCTAssertFalse(draft.formReady)
        XCTAssertTrue(draft.treasurerReady(stored: true))
        XCTAssertFalse(draft.treasurerReady(stored: false))
        XCTAssertFalse(draft.counterpartyReady)
        draft = fertig()
        XCTAssertTrue(draft.formReady)
        XCTAssertTrue(draft.counterpartyReady)
        XCTAssertEqual(draft.kind, "expense")
        XCTAssertEqual(draft.treasurerText, "25,00\u{00A0}€ an Max Mustermann ausgezahlt. Zweck: Auslagen Blumen")
        XCTAssertEqual(draft.counterpartyText(unitName: "Schützenverein Musterstadt"), "Ich habe 25,00\u{00A0}€ von Schützenverein Musterstadt erhalten. Zweck: Auslagen Blumen")
        draft.receives = true
        XCTAssertEqual(draft.kind, "income")
        XCTAssertEqual(draft.treasurerText, "25,00\u{00A0}€ von Max Mustermann erhalten. Zweck: Auslagen Blumen")
        XCTAssertEqual(draft.counterpartyText(unitName: "Verein"), "Ich habe 25,00\u{00A0}€ an Verein gezahlt. Zweck: Auslagen Blumen")
        // Ändern sich die Angaben, gelten die Unterschriften nicht mehr
        draft.signedChanged()
        XCTAssertFalse(draft.counterpartyReady)
        draft.declined = " hat es eilig "
        XCTAssertTrue(draft.counterpartyReady)
        draft.receives = false
        XCTAssertFalse(draft.counterpartyReady)
    }

    func testQuittungInVierSchritten() async throws {
        let net = FakeTransport([
            FakeTransport.json(201, #"{"id":7,"status":"draft"}"#),
            FakeTransport.json(200, "{}"),
            FakeTransport.json(200, "{}"),
            FakeTransport.json(200, #"{"id":7,"status":"final","number":"Q-2026-0004","account_name":"Barkasse","amount":"25.00"}"#),
        ])
        var seen: [Int] = []
        let done = try await verwaltung(net).submitReceipt(fertig()) { seen.append($0) }
        XCTAssertEqual(done.number, "Q-2026-0004")
        XCTAssertEqual(seen, [7])
        XCTAssertEqual(net.seen.map(\.method), ["POST", "PUT", "PUT", "POST"])
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/cash-receipts/")
        XCTAssertEqual(net.seen[0].headers["Idempotency-Key"], "k-anlegen")
        XCTAssertEqual(sorted(net.seen[0]), #"{"account":2,"amount":"25.00","category":3,"counterparty_name":"Max Mustermann","direction":"out","email":"","purpose":"Auslagen Blumen"}"#)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/cash-receipts/7/signatures/treasurer/")
        XCTAssertEqual(sorted(net.seen[1]), #"{"use_stored":true}"#)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/cash-receipts/7/signatures/counterparty/")
        XCTAssertEqual(sorted(net.seen[2]), #"{"height":120,"signed_at":"2026-11-14T19:30:00+01:00","strokes":[[[1,2],[30,40]]],"width":300}"#)
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/cash-receipts/7/finalize/")
        XCTAssertEqual(net.seen[3].headers["Idempotency-Key"], "k-abschluss")
        XCTAssertEqual(sorted(net.seen[3]), #"{"confirmed":true,"send":false}"#)
    }

    func testNeuerVersuchMachtAufDemServerWeiter() async throws {
        var draft = fertig()
        draft.serverId = 7
        draft.receives = true
        draft.counterparty = nil
        draft.declined = "hat es eilig"
        draft.email = "max@example.org"
        draft.treasurer = SignatureStrokes(width: 200, height: 100, strokes: [[[5, 5], [9, 9]]])
        draft.treasurerAt = "2026-11-14T19:29:00+01:00"
        let net = FakeTransport([
            FakeTransport.json(200, #"{"id":7,"status":"draft"}"#),
            FakeTransport.json(200, "{}"), FakeTransport.json(200, "{}"), FakeTransport.json(200, "{}"),
            FakeTransport.json(200, #"{"id":7,"status":"final","number":"Q-2026-0005"}"#),
            FakeTransport.json(200, #"{"id":7,"status":"final","number":"Q-2026-0005"}"#),
        ])
        let client = verwaltung(net)
        let done = try await client.submitReceipt(draft) { _ in XCTFail("schon angelegt") }
        XCTAssertEqual(done.number, "Q-2026-0005")
        XCTAssertEqual(net.seen.map(\.method), ["GET", "PATCH", "PUT", "PUT", "POST"])
        XCTAssertEqual(sorted(net.seen[1]), #"{"account":2,"category":3}"#)
        XCTAssertEqual(sorted(net.seen[2]), #"{"height":100,"signed_at":"2026-11-14T19:29:00+01:00","strokes":[[[5,5],[9,9]]],"width":200}"#)
        XCTAssertEqual(sorted(net.seen[3]), #"{"declined":"hat es eilig"}"#)
        XCTAssertEqual(sorted(net.seen[4]), #"{"confirmed":true,"send":true}"#)
        // Schon abgeschlossen: nichts mehr senden
        let again = try await client.submitReceipt(draft) { _ in }
        XCTAssertEqual(again.number, "Q-2026-0005")
        XCTAssertEqual(net.seen.count, 6)
    }

    func testOhneUnterschriftDerGegenseiteUndFehlerDesServers() async throws {
        var draft = fertig()
        draft.counterparty = nil
        let net = FakeTransport([FakeTransport.json(201, #"{"id":8}"#), FakeTransport.json(400, #"{"detail":"Die Barkasse ist gesperrt."}"#)])
        let client = verwaltung(net)
        do {
            _ = try await client.submitReceipt(draft) { _ in }
            XCTFail("Fehler erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.message, "Die Unterschrift der Gegenseite fehlt.")
        }
        XCTAssertEqual(net.seen.count, 1)
        do {
            _ = try await client.submitReceipt(fertig()) { _ in }
            XCTFail("400 erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.message, "Die Barkasse ist gesperrt.")
        }
        var leer = ReceiptDraft()
        leer.name = "x"
        do {
            _ = try await client.submitReceipt(leer) { _ in }
            XCTFail("Fehler erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.code, "format")
        }
    }

    func testHinterlegteUnterschrift() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"signature":{"w":1000,"h":300,"s":[[1,2,3,4]]},"updated_at":"2026-11-01T10:00:00+01:00"}"#)])
        let stored = try await verwaltung(net).storedSignature()
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/signature/")
        XCTAssertEqual(stored.signature?.h, 300)
    }
}
