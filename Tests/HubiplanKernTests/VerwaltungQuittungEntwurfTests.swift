import XCTest
@testable import HubiplanKern

final class VerwaltungQuittungEntwurfTests: XCTestCase {
    private let server = "https://verein.example.de"
    private struct KeinNetz: Error {}
    private let offline: Result<HttpResponse, Error> = .failure(KeinNetz())
    private let konten = #"[{"id":2,"name":"Barkasse","kind":"cash"},{"id":3,"name":"Girokonto","kind":"bank"}]"#
    private let kategorien = #"[{"id":5,"name":"Feste","kind":"expense"},{"id":6,"name":"Spenden","kind":"income"}]"#

    override func setUp() {
        Texte.language = "de"
    }

    private func decode<T: Decodable>(_ text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    private func verwaltung(_ net: FakeTransport, unit: Int = 4) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: AdminUnit(id: unit, name: "Verein"))
    }

    private func auswahl(unterschrift: Bool = true) throws -> ReceiptChoices {
        let cash: [FinanceAccount] = try decode(konten)
        return ReceiptChoices(
            accounts: cash.filter { $0.kind == "cash" },
            categories: try decode(kategorien),
            signature: unterschrift ? try decode(#"{"w":1000,"h":300,"s":[[1,2,30,40]]}"#) : nil
        )
    }

    private func blatt(_ key: String) -> ReceiptDraft {
        var draft = ReceiptDraft(key: key, finalizeKey: key + "-abschluss")
        draft.name = " Max Mustermann "
        draft.amount = "25"
        draft.purpose = "Auslagen Blumen"
        draft.account = 2
        draft.category = 5
        draft.counterparty = SignatureStrokes(width: 300, height: 120, strokes: [[[1, 2], [30, 40]]])
        draft.counterpartyAt = "2026-11-14T19:30:00+01:00"
        return draft
    }

    private func quittung(_ key: String, unit: Int = 4) throws -> StoredReceipt {
        try XCTUnwrap(StoredReceipt(blatt(key), unit: AdminUnit(id: unit, name: "Verein"), choices: try auswahl(), date: "2026-11-14"))
    }

    func testQuittungAusBlatt() throws {
        let stored = try quittung("q-1")
        XCTAssertEqual(stored.id, "q-1")
        XCTAssertEqual(stored.unitId, 4)
        XCTAssertEqual(stored.accountName, "Barkasse")
        XCTAssertEqual(stored.categoryName, "Feste")
        XCTAssertEqual(stored.line, "14.11.2026 · 25,00\u{00A0}€ · Quittung · Max Mustermann")
        // Ohne Angabe gilt der heutige Tag; alte Dateien ohne Tag bleiben lesbar
        XCTAssertEqual(StoredReceipt(blatt("q-0"), unit: AdminUnit(id: 4, name: "Verein"), choices: try auswahl())?.date, Zeit.day(Date()))
        var alt = stored
        alt.date = nil
        XCTAssertEqual(alt.line, "25,00\u{00A0}€ · Quittung · Max Mustermann")
        XCTAssertEqual(try JSONDecoder().decode(StoredReceipt.self, from: try JSONEncoder().encode(alt)), alt)
        let unit = AdminUnit(id: 4, name: "Verein")
        // Ohne hinterlegte Unterschrift muss der Kassierer selbst unterschrieben haben
        XCTAssertNil(StoredReceipt(blatt("q-2"), unit: unit, choices: try auswahl(unterschrift: false)))
        var selbst = blatt("q-2")
        selbst.treasurer = SignatureStrokes(width: 200, height: 100, strokes: [[[5, 5], [9, 9]]])
        XCTAssertNotNil(StoredReceipt(selbst, unit: unit, choices: try auswahl(unterschrift: false)))
        // Ohne Gegenseite oder mit fehlenden Angaben: nichts zu speichern
        var ohne = blatt("q-3")
        ohne.counterparty = nil
        XCTAssertNil(StoredReceipt(ohne, unit: unit, choices: try auswahl()))
        var leer = blatt("q-4")
        leer.purpose = " "
        XCTAssertNil(StoredReceipt(leer, unit: unit, choices: try auswahl()))
        // Korrigieren: Unterschriften bleiben, Fehler erledigt
        var failed = stored
        failed.error = "Diese Kategorie gibt es nicht mehr."
        let neu: [FinanceCategory] = try decode(#"[{"id":8,"name":"Sonstiges","kind":"both"}]"#)
        let fixed = failed.fixed(account: try auswahl().accounts[0], category: neu[0])
        XCTAssertEqual(fixed.draft.category, 8)
        XCTAssertEqual(fixed.categoryName, "Sonstiges")
        XCTAssertNil(fixed.error)
        XCTAssertEqual(fixed.draft.counterparty, stored.draft.counterparty)
    }

    func testAblageVerschluesselt() throws {
        let files = MemoryFiles()
        let box = DraftBox(files: files, secrets: MemoryStore())
        XCTAssertTrue(box.save(try quittung("q-1")))
        XCTAssertTrue(box.save(try quittung("q-2", unit: 9)))
        XCTAssertEqual(files.names(), ["q-1.quittung", "q-2.quittung"])
        let sealed = try XCTUnwrap(files.read("q-1.quittung"))
        XCTAssertNil(sealed.range(of: Data("Mustermann".utf8)))
        XCTAssertNil(sealed.range(of: Data("strokes".utf8)))
        XCTAssertEqual(box.receipts().map(\.id), ["q-1", "q-2"])
        XCTAssertEqual(box.receipts(unit: 9).map(\.id), ["q-2"])
        XCTAssertEqual(box.receipts().first, try quittung("q-1"))
        // Buchungen und Quittungen zählen zusammen, stören sich aber nicht
        XCTAssertEqual(box.count, 2)
        XCTAssertEqual(box.list(), [])
        XCTAssertFalse(box.save(try quittung("../")))
        // Unlesbare bleiben liegen und werden gezählt
        XCTAssertTrue(files.write("kaputt.quittung", Data([1, 2, 3])))
        XCTAssertEqual(box.count, 3)
        XCTAssertEqual(box.unreadable, 1)
        XCTAssertEqual(box.discardUnreadable(), 1)
        box.deleteReceipt("q-2")
        XCTAssertEqual(files.names(), ["q-1.quittung"])
        // Auswahl je Einheit, ebenfalls verschlüsselt; zählt nicht als Entwurf
        XCTAssertNil(box.choices(unit: 4))
        box.saveChoices(try auswahl(), unit: 4)
        XCTAssertEqual(box.choices(unit: 4), try auswahl())
        XCTAssertNil(box.choices(unit: 9))
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(box.unreadable, 0)
        XCTAssertNil(try XCTUnwrap(files.read("auswahl-4.dat")).range(of: Data("Barkasse".utf8)))
        box.clear()
        XCTAssertEqual(files.names(), [])
    }

    func testAuswahlMitUndOhneNetz() async throws {
        let box = DraftBox(files: MemoryFiles(), secrets: MemoryStore())
        // Ohne Netz und ohne gemerkte Auswahl
        let nichts = try await verwaltung(FakeTransport([offline])).receiptChoices(box: box)
        XCTAssertNil(nichts.choices)
        XCTAssertTrue(nichts.offline)
        // Mit Netz: nur Barkassen, Auswahl wird gemerkt
        let net = FakeTransport([
            FakeTransport.json(200, konten), FakeTransport.json(200, kategorien),
            FakeTransport.json(200, #"{"signature":{"w":1000,"h":300,"s":[[1,2,30,40]]}}"#),
        ])
        let frisch = try await verwaltung(net).receiptChoices(box: box)
        XCTAssertFalse(frisch.offline)
        XCTAssertEqual(frisch.choices?.accounts.map(\.name), ["Barkasse"])
        XCTAssertEqual(frisch.choices?.categories.count, 2)
        XCTAssertNotNil(frisch.choices?.signature)
        // Danach geht es auch ohne Netz
        let gemerkt = try await verwaltung(FakeTransport([offline])).receiptChoices(box: box)
        XCTAssertTrue(gemerkt.offline)
        XCTAssertEqual(gemerkt.choices, frisch.choices)
        // Andere Fehler werden gemeldet
        do {
            _ = try await verwaltung(FakeTransport([FakeTransport.json(403, #"{"detail":"Keine Berechtigung."}"#)])).receiptChoices(box: box)
            XCTFail("403 erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 403)
        }
    }

    func testAbschliessenMitUndOhneNetz() async throws {
        let files = MemoryFiles()
        let box = DraftBox(files: files, secrets: MemoryStore())
        let fertig = #"{"id":7,"status":"final","number":"Q-2026-0004","account_name":"Barkasse","amount":"25.00"}"#
        // Mit Netz: abgeschlossen, nichts bleibt liegen
        let net = FakeTransport([
            FakeTransport.json(201, #"{"id":7,"status":"draft"}"#), FakeTransport.json(200, "{}"),
            FakeTransport.json(200, "{}"), FakeTransport.json(200, fertig),
        ])
        var seen: [Int] = []
        let outcome = try await verwaltung(net).submit(try quittung("q-1"), box: box) { seen.append($0) }
        guard case let .finished(item) = outcome else { return XCTFail("abgeschlossen erwartet") }
        XCTAssertEqual(item.number, "Q-2026-0004")
        XCTAssertEqual(seen, [7])
        XCTAssertEqual(box.count, 0)
        // Ohne Netz: bleibt liegen
        let kept = try await verwaltung(FakeTransport([offline])).submit(try quittung("q-2"), box: box)
        XCTAssertEqual(kept, .kept)
        XCTAssertEqual(box.receipts().map(\.id), ["q-2"])
        XCTAssertNil(box.receipts().first?.draft.serverId)
        // Netz bricht nach dem Anlegen ab: Kennung auf dem Server ist gemerkt
        let halb = FakeTransport([FakeTransport.json(201, #"{"id":8,"status":"draft"}"#), offline])
        let mitten = try await verwaltung(halb).submit(try quittung("q-3"), box: box)
        XCTAssertEqual(mitten, .kept)
        XCTAssertEqual(box.receipts().map(\.draft.serverId), [nil, 8])
        // Server lehnt ab: nichts bleibt liegen, Fehler wird gemeldet
        do {
            _ = try await verwaltung(FakeTransport([FakeTransport.json(400, #"{"detail":"Die Kategorie passt nicht."}"#)])).submit(try quittung("q-4"), box: box)
            XCTFail("400 erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
        }
        XCTAssertEqual(box.receipts().map(\.id), ["q-2", "q-3"])
        // Lässt sich nichts sichern, wird der Verbindungsfehler gezeigt statt die Quittung zu verlieren
        files.failWrites = true
        do {
            _ = try await verwaltung(FakeTransport([offline])).submit(try quittung("q-5"), box: box)
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertTrue(error.isOffline)
        }
    }

    func testLiegengebliebeneSenden() async throws {
        let box = DraftBox(files: MemoryFiles(), secrets: MemoryStore())
        XCTAssertTrue(box.save(try quittung("q-1")))
        var zweite = try quittung("q-2")
        zweite.draft.serverId = 8
        XCTAssertTrue(box.save(zweite))
        XCTAssertTrue(box.save(try quittung("q-3")))
        XCTAssertTrue(box.save(try quittung("q-fremd", unit: 9)))
        let net = FakeTransport([
            // q-1: Server lehnt das Anlegen ab
            FakeTransport.json(400, #"{"detail":"Diese Kategorie gibt es nicht mehr."}"#),
            // q-2: macht auf dem Server weiter
            FakeTransport.json(200, #"{"id":8,"status":"draft"}"#), FakeTransport.json(200, "{}"),
            FakeTransport.json(200, "{}"), FakeTransport.json(200, "{}"),
            FakeTransport.json(200, #"{"id":8,"status":"final","number":"Q-2026-0006"}"#),
            // q-3: Netz weg
            offline,
        ])
        let sent = try await verwaltung(net).send(receipts: box)
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(net.seen.map(\.method), ["POST", "GET", "PATCH", "PUT", "PUT", "POST", "POST"])
        XCTAssertEqual(box.receipts().map(\.id), ["q-1", "q-3", "q-fremd"])
        XCTAssertEqual(box.receipts().first?.error, "Diese Kategorie gibt es nicht mehr.")
        XCTAssertNil(box.receipts()[1].error)
        // 401: neu freischalten, nichts wird als Fehler gemerkt
        do {
            _ = try await verwaltung(FakeTransport([FakeTransport.json(401, #"{"detail":"Bitte neu freischalten."}"#)]), unit: 9).send(receipts: box)
            XCTFail("401 erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 401)
        }
        XCTAssertNil(box.receipts(unit: 9).first?.error)
    }
}
