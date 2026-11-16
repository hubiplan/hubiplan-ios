import XCTest
@testable import HubiplanKern

/// Auslagen unter „Ich“ (HUBIplan Auslagen erstatten), gleiche Fälle wie `AuslagenTest` in
/// Android. Alle Daten erfunden.
final class AuslagenTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let list = #"""
    {"claims":[
      {"id":4,"number":"A2099-0001","kind":"expense","status":"question","status_label":"Rückfrage",
       "purpose":"Hemden für die Jugend","total":"45.90","amount_due":"45.90","version":2,
       "lines":[{"id":1,"amount":"45.90","text":""}],"files":[{"id":9,"name":"beleg.jpg"}],
       "events":[{"kind":"submitted","label":"eingereicht","who":"Anna Muster","text":"","at":"2099-01-02T10:00:00Z"},
                 {"kind":"question","label":"Rückfrage","who":"Kasse","text":"Für welche Gruppe?","at":"2099-01-03T10:00:00Z"}],
       "can_edit":true,"can_withdraw":true,"unknown_field":1},
      {"id":5,"number":"","kind":"expense","status":"draft","purpose":"","total":"0","amount_due":"0"}
    ],
    "options":{"may_submit":true,"mileage_enabled":true,"km_rate":"0.30",
               "payee":{"holder":"Anna Muster","iban":"DE89370400440532013000"}}}
    """#

    private func fields(_ list: [(name: String, value: String)]) -> [String: String] {
        Dictionary(list.map { ($0.name, $0.value) }, uniquingKeysWith: { $1 })
    }

    func testLiestDieListe() throws {
        let o = try JSONDecoder().decode(ExpenseOverview.self, from: Data(list.utf8))
        let c = o.claims[0]
        XCTAssertTrue(c.asksMe)
        XCTAssertEqual(c.question, "Für welche Gruppe?")
        XCTAssertTrue(c.canAddFile)
        XCTAssertFalse(c.isLooseDraft)
        XCTAssertTrue(o.claims[1].isLooseDraft)
        XCTAssertEqual(o.options.payee?.iban, "DE89370400440532013000")
        XCTAssertEqual(o.summary, "1 Rückfrage der Kasse")
        XCTAssertEqual(ExpenseOverview().summary, "Selbst Bezahltes erstattet bekommen")
    }

    func testIchZeigtAuslagenNurMitModul() throws {
        let on = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV","expenses_enabled":true,"expenses_questions":2}"#.utf8))
        XCTAssertTrue(on.hasExpenses)
        XCTAssertEqual(on.expensesQuestions, 2)
        let off = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV"}"#.utf8))
        XCTAssertFalse(off.hasExpenses)
        let contact = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV","expenses_enabled":true,"member_kind":"organization","member_name":"Muster GmbH"}"#.utf8))
        XCTAssertFalse(contact.hasExpenses)
    }

    func testKilometerUndIban() {
        XCTAssertEqual(parseKm("12,5"), "12.5")
        XCTAssertEqual(parseKm(" 120 "), "120")
        XCTAssertEqual(parseKm("42,0"), "42")
        XCTAssertNil(parseKm("0"))
        XCTAssertNil(parseKm("abc"))
        XCTAssertNil(parseKm("9000"))
        XCTAssertEqual(cleanIban("de89 3704 0044 0532 0130 00"), "DE89370400440532013000")
    }

    func testFormularfelderEinerAuslage() throws {
        var d = ExpenseDraft(date: "2099-01-02", payee: ExpensePayee(holder: "Anna Muster", iban: "de89 3704 0044 0532 0130 00"))
        d.purpose = " Hemden für die Jugend "
        d.amounts = ["45,90", "", "x"]
        let f = fields(d.fields(submit: true))
        XCTAssertEqual(f["kind"], "expense")
        XCTAssertEqual(f["purpose"], "Hemden für die Jugend")
        XCTAssertEqual(f["source"], "app")
        XCTAssertEqual(f["submit"], "true")
        XCTAssertEqual(f["purchase_date"], "2099-01-02")
        XCTAssertEqual(f["lines"], #"[{"amount":"45.90","text":""}]"#)
        XCTAssertEqual(f["payee"], #"{"holder":"Anna Muster","iban":"DE89370400440532013000"}"#)
        d.payout = "cash"
        let bar = fields(d.fields(submit: false))
        XCTAssertEqual(bar["payee"], "")
        XCTAssertNil(bar["submit"])
    }

    func testFormularfelderEinerFahrt() {
        var d = ExpenseDraft(date: "2099-01-02")
        d.kind = "mileage"
        d.purpose = "Fahrt"
        d.route = "Musterstadt – Beispielhausen"
        d.km = "42,0"
        let f = fields(d.fields(submit: false))
        XCTAssertEqual(f["km"], "42")
        XCTAssertEqual(f["route"], "Musterstadt – Beispielhausen")
        XCTAssertNil(f["lines"])
    }

    func testMehrereBelegeInEinemFormular() {
        let form = Multipart(fields: [("kind", "expense")], files: [
            (name: "beleg-1.jpg", data: Data([1]), type: "image/jpeg"),
            (name: "beleg-2.jpg", data: Data([2]), type: "image/jpeg"),
        ], boundary: "grenze")
        var expected = Data("--grenze\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\nexpense\r\n--grenze\r\nContent-Disposition: form-data; name=\"file\"; filename=\"beleg-1.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        expected.append(Data([1]))
        expected.append(Data("\r\n--grenze\r\nContent-Disposition: form-data; name=\"file\"; filename=\"beleg-2.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        expected.append(Data([2]))
        expected.append(Data("\r\n--grenze--\r\n".utf8))
        XCTAssertEqual(form.body, expected)
    }

    func testEinreichenMitSchluesselUndFeldfehler() async throws {
        let claim = #"{"id":4,"number":"A2099-0001","status":"submitted","purpose":"Hemden"}"#
        let net = FakeTransport([
            FakeTransport.json(201, claim),
            FakeTransport.json(400, #"{"purpose":["Bitte angeben, wofür das war."]}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("t1"))
        var d = ExpenseDraft(date: "2099-01-02")
        d.purpose = "Hemden"
        d.amounts = ["45,90"]
        let made = try await api.createExpense(accessId: 9, draft: d, submit: true, photos: [Data([0xFF])], key: "k1")
        XCTAssertEqual(made.number, "A2099-0001")
        let sent = net.seen[0]
        XCTAssertEqual(sent.method, "POST")
        XCTAssertTrue(sent.url.hasSuffix("/api/portal/9/expenses/"))
        XCTAssertEqual(sent.headers["Idempotency-Key"], "k1")
        XCTAssertTrue(sent.headers["Content-Type"]?.hasPrefix("multipart/form-data") ?? false)
        do {
            _ = try await api.createExpense(accessId: 9, draft: ExpenseDraft(), submit: true, photos: [], key: "k2")
            XCTFail("Feldfehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.message, "Bitte angeben, wofür das war.")
        }
    }
}
