import XCTest
@testable import HubiplanKern

final class VerwaltungKasseTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() {
        Texte.language = "de"
    }

    private func decode<T: Decodable>(_ text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    private func verwaltung(_ net: FakeTransport, unit: AdminUnit = AdminUnit(id: 4, name: "Verein")) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: unit)
    }

    func testRechteUndBereich() {
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["members.view"], stufen: true).showsFinance)
        let lesen = AdminUnit(id: 1, name: "A", permissions: ["finance.view"], stufen: true)
        XCTAssertTrue(lesen.showsFinance)
        XCTAssertFalse(lesen.canEditFinance)
        XCTAssertEqual(lesen.sections, [.tasks, .finance])
        XCTAssertTrue(AdminUnit(id: 1, name: "A", permissions: ["finance.edit"], stufen: true).canEditFinance)
    }

    func testBetragAusDerEingabe() {
        XCTAssertEqual(Geld.parseInput("23,40"), "23.40")
        XCTAssertEqual(Geld.parseInput("23.4"), "23.40")
        XCTAssertEqual(Geld.parseInput("1.234,50"), "1234.50")
        XCTAssertEqual(Geld.parseInput(" 12 € "), "12.00")
        XCTAssertEqual(Geld.parseInput("0,05"), "0.05")
        XCTAssertEqual(Geld.parseInput("99999999,99"), "99999999.99")
        XCTAssertNil(Geld.parseInput("100000000"))
        XCTAssertNil(Geld.parseInput("0"))
        XCTAssertNil(Geld.parseInput("-5"))
        XCTAssertNil(Geld.parseInput("1,234"))
        XCTAssertNil(Geld.parseInput("zehn"))
        XCTAssertNil(Geld.parseInput(""))
        // Englisch: Komma trennt Tausender; ein einzelnes Komma vor ein oder zwei Ziffern bleibt Dezimalkomma
        Texte.language = "en"
        XCTAssertEqual(Geld.parseInput("€1,234.50"), "1234.50")
        XCTAssertEqual(Geld.parseInput("1,234"), "1234.00")
        XCTAssertEqual(Geld.parseInput("23.4"), "23.40")
        XCTAssertEqual(Geld.parseInput("23,40"), "23.40")
        XCTAssertEqual(Geld.parseInput("12 €"), "12.00")
        XCTAssertNil(Geld.parseInput("1.234,50"))
        XCTAssertEqual(Geld.inputText("60"), "60.00")
        Texte.language = "de"
        XCTAssertEqual(Geld.inputText("60"), "60,00")
    }

    func testKontenAlsFeldOderSeitenweiseNurAktive() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":1,"name":"Girokonto","kind":"bank","kind_label":"Bankkonto","balance":"1234.50"},{"id":2,"name":"Barkasse","kind":"cash","kind_label":"Barkasse","balance":"87.10"},{"id":3,"name":"Alt","is_active":false}]"#),
            FakeTransport.json(200, #"{"count":3,"results":[{"id":1,"name":"Getränke","kind":"expense"},{"id":2,"name":"Spenden","kind":"income"},{"id":3,"name":"Sonstiges","kind":"both"},{"id":4,"name":"Alt","kind":"expense","is_active":false}]}"#),
        ])
        let client = verwaltung(net)
        let accounts = try await client.accounts()
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/accounts/")
        XCTAssertEqual(accounts.map(\.name), ["Girokonto", "Barkasse"])
        XCTAssertEqual(FinanceAccount.preferred(accounts)?.id, 2)
        XCTAssertEqual(FinanceAccount.preferred(Array(accounts.prefix(1)))?.id, 1)
        XCTAssertEqual(Geld.format(accounts[0].balance), "1.234,50\u{00A0}€")
        let categories = try await client.categories()
        XCTAssertEqual(categories.count, 3)
        XCTAssertEqual(FinanceCategory.matching(categories, kind: "expense").map(\.id), [1, 3])
        XCTAssertEqual(FinanceCategory.matching(categories, kind: "income").map(\.id), [2, 3])
    }

    func testBuchungenListeUndZeilen() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"""
        {"count":41,"next":"x","results":[
        {"id":9,"display_number":"2026-0031","date":"2026-11-12","kind":"expense","kind_label":"Ausgabe","amount":"23.40","account_name":"Barkasse","category_name":"Getränke","text":"Getränke Zugversammlung","counterparty":"Getränkemarkt Beispiel","receipts":[{"id":5,"name":"beleg.jpg","content_type":"image/jpeg"}]},
        {"id":8,"display_number":"2026-0030","date":"2026-11-10","kind":"income","kind_label":"Einnahme","amount":"150.00","account_name":"Girokonto","text":""},
        {"id":7,"display_number":"2026-0029","date":"2026-11-09","kind":"transfer","kind_label":"Umbuchung","amount":"200.00","account_name":"Girokonto","to_account_name":"Barkasse","text":"Wechselgeld","receipts":[{"id":4,"name":"auszug.pdf","content_type":"application/pdf"}]}
        ]}
        """#), FakeTransport.json(200, #"{"results":[]}"#)])
        let client = verwaltung(net)
        let page = try await client.bookings()
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/bookings/?page=1&page_size=30")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.count, 41)
        let rows = page.results
        XCTAssertEqual(rows[0].head, "12.11.2026 · Nr. 2026-0031")
        XCTAssertEqual(rows[0].signedAmount, "−23,40\u{00A0}€")
        XCTAssertEqual(rows[0].detail, "Getränke · Getränkemarkt Beispiel · Barkasse")
        XCTAssertEqual(rows[0].facts, "Nr. 2026-0031 · 12.11.2026 · Getränke · Barkasse · Getränkemarkt Beispiel")
        XCTAssertTrue(rows[0].receipts[0].isImage)
        XCTAssertEqual(rows[1].title, "Einnahme")
        XCTAssertEqual(rows[1].signedAmount, "+150,00\u{00A0}€")
        XCTAssertEqual(rows[1].detail, "Girokonto · ohne Beleg")
        XCTAssertEqual(rows[2].signedAmount, "200,00\u{00A0}€")
        XCTAssertEqual(rows[2].detail, "Girokonto → Barkasse")
        XCTAssertFalse(rows[2].receipts[0].isImage)
        let ohne = try await client.bookings(page: 2, withoutReceipt: true)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/bookings/?page=2&page_size=30&ohne_beleg=1")
        XCTAssertFalse(ohne.hasMore)
    }

    func testFormularMitDatei() {
        let form = Multipart(fields: [("kind", "expense"), ("text", "Getränke")], file: Data([0xFF, 0xD8, 0xFF]), fileName: "beleg.jpg", fileType: "image/jpeg", boundary: "grenze")
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=grenze")
        var expected = Data("--grenze\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\nexpense\r\n--grenze\r\nContent-Disposition: form-data; name=\"text\"\r\n\r\nGetränke\r\n--grenze\r\nContent-Disposition: form-data; name=\"file\"; filename=\"beleg.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        expected.append(Data([0xFF, 0xD8, 0xFF]))
        expected.append(Data("\r\n--grenze--\r\n".utf8))
        XCTAssertEqual(form.body, expected)
    }

    func testNeueBuchungFelder() throws {
        let categories: [FinanceCategory] = try decode(#"[{"id":1,"name":"Getränke","kind":"expense"},{"id":2,"name":"Spenden","kind":"income"}]"#)
        var draft = BookingDraft(key: "k1")
        XCTAssertNil(draft.fields(categories: categories))
        draft.amount = "23,4"
        draft.date = "12.11.2026"
        draft.text = "  Getränke Zugversammlung "
        draft.account = 2
        // Kategorie fehlt, obwohl es welche für Ausgaben gibt
        XCTAssertNil(draft.fields(categories: categories))
        // Kategorie einer Einnahme passt nicht zur Ausgabe
        draft.category = 2
        XCTAssertNil(draft.fields(categories: categories))
        draft.category = 1
        draft.counterparty = " Getränkemarkt Beispiel "
        let fields = try XCTUnwrap(draft.fields(categories: categories))
        XCTAssertEqual(fields.map(\.name), ["date", "kind", "amount", "account", "category", "text", "counterparty"])
        XCTAssertEqual(fields.map(\.value), ["2026-11-12", "expense", "23.40", "2", "1", "Getränke Zugversammlung", "Getränkemarkt Beispiel"])
        // Ohne Kategorien in der Einheit geht es ohne
        draft.category = nil
        draft.counterparty = ""
        XCTAssertEqual(draft.fields(categories: [])?.map(\.name), ["date", "kind", "amount", "account", "text"])
        draft.date = "31.02.2026"
        XCTAssertNil(draft.fields(categories: []))
        XCTAssertNotEqual(BookingDraft().key, BookingDraft().key)
    }

    func testBuchenMitBelegUndSchutzVorDoppeltemBuchen() async throws {
        let net = FakeTransport([
            FakeTransport.json(201, #"{"id":10,"display_number":"2026-0032","kind":"expense","amount":"23.40"}"#),
            FakeTransport.json(400, #"{"detail":"Das Buchungsjahr ist abgeschlossen."}"#),
            .success(HttpResponse(status: 201, body: Data("{}".utf8))),
            FakeTransport.json(413, #"{"detail":"Die Datei ist zu groß."}"#),
        ])
        let client = verwaltung(net)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let booked = try await client.book(fields: [("kind", "expense")], jpeg: jpeg, key: "k1")
        XCTAssertEqual(booked.displayNumber, "2026-0032")
        let sent = net.seen[0]
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url, "https://verein.example.de/api/app/v1/admin/u/4/finance/app-booking/")
        XCTAssertEqual(sent.headers["Idempotency-Key"], "k1")
        XCTAssertEqual(sent.headers["Authorization"], "Bearer hpa_erfunden")
        XCTAssertEqual(sent.headers["X-Hubiplan-Device"], "hpd_a")
        XCTAssertTrue(sent.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=hubiplan-") == true)
        let body = try XCTUnwrap(sent.body)
        XCTAssertNotNil(body.range(of: Data("name=\"file\"; filename=\"beleg.jpg\"".utf8)))
        XCTAssertNotNil(body.range(of: jpeg))
        do {
            _ = try await client.book(fields: [], jpeg: jpeg, key: "k2")
            XCTFail("400 erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.message, "Das Buchungsjahr ist abgeschlossen.")
        }
        try await client.addReceipt(booking: 9, jpeg: jpeg)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/bookings/9/receipts/")
        XCTAssertNil(net.seen[2].headers["Idempotency-Key"])
        do {
            try await client.addReceipt(booking: 9, jpeg: jpeg)
            XCTFail("413 erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.status, 413)
        }
    }

    func testBelegbildLaden() async {
        let net = FakeTransport([.success(HttpResponse(status: 200, body: Data([1, 2, 3]))), FakeTransport.json(404, "{}")])
        let client = verwaltung(net)
        let image = await client.receipt(5)
        XCTAssertEqual(image, Data([1, 2, 3]))
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/finance/receipts/5/")
        let missing = await client.receipt(6)
        XCTAssertNil(missing)
    }
}
