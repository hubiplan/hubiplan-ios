import XCTest
@testable import HubiplanKern

final class VerwaltungRechnungenTests: XCTestCase {
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

    private let offen = #"{"id":7,"number":"RE-2026-0042","status":"open","status_label":"offen","recipient_name":"Erika Musterfrau\nz. Hd. Max Mustermann","department_name":"Zug 1","subject":"Jahresbeitrag 2026","date":"2026-11-01","due_date":"2026-11-15","total":"60.00","paid":"20.00","outstanding":"40.00","overdue":true,"lines":[{"text":"Beitrag","detail":"Erwachsene","amount":"60.00"}],"payments":[{"id":3,"date":"2026-11-05","amount":"20.00","method":"cash","method_label":"Bar","account_name":"Barkasse","booking_number":"2026-0030"}]}"#

    func testRechteUndBereich() {
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["finance.view"], stufen: true).showsBilling)
        let lesen = AdminUnit(id: 1, name: "A", permissions: ["billing.view"], stufen: true)
        XCTAssertTrue(lesen.showsBilling)
        XCTAssertFalse(lesen.canEditBilling)
        XCTAssertEqual(lesen.sections, [.tasks, .billing])
        let alles = AdminUnit(id: 1, name: "A", permissions: ["members.view", "finance.view", "billing.edit"], stufen: true)
        XCTAssertTrue(alles.canEditBilling)
        XCTAssertEqual(alles.sections, [.tasks, .members, .occasions, .finance, .billing])
    }

    func testRechnungInListeUndAufDerSeite() throws {
        let invoice: InvoiceItem = try decode(offen)
        XCTAssertEqual(invoice.payer, "Erika Musterfrau")
        XCTAssertEqual(invoice.listDetail, "RE-2026-0042 · Jahresbeitrag 2026 · Zug 1")
        XCTAssertEqual(invoice.headline, "RE-2026-0042 · Jahresbeitrag 2026")
        XCTAssertEqual(invoice.listAmount, "40,00\u{00A0}€")
        XCTAssertEqual(invoice.listStatus, "überfällig")
        XCTAssertEqual(invoice.dates, "vom 01.11.2026 · fällig 15.11.2026 · überfällig")
        XCTAssertTrue(invoice.hasPaid)
        XCTAssertTrue(invoice.canPayCash)
        XCTAssertEqual(invoice.lines.first?.detail, "Erwachsene")
        XCTAssertEqual(invoice.payments.first?.detail, "05.11.2026 · Bar · Barkasse · Nr. 2026-0030")
        XCTAssertEqual(invoice.payments.first?.isCash, true)
        XCTAssertEqual(invoice.receiptName(payment: 3), "Quittung-RE-2026-0042-3.pdf")

        let bezahlt: InvoiceItem = try decode(#"{"id":8,"number":"RE 2026/41","status":"paid","status_label":"bezahlt","recipient_name":"Musterbau GmbH","total":"120.00","paid":"120.00","outstanding":"0.00","overdue":true}"#)
        XCTAssertEqual(bezahlt.listAmount, "120,00\u{00A0}€")
        XCTAssertEqual(bezahlt.listStatus, "bezahlt")
        XCTAssertFalse(bezahlt.canPayCash)
        XCTAssertEqual(bezahlt.dates, "vom  · fällig  · bezahlt")
        XCTAssertEqual(bezahlt.listDetail, "RE 2026/41")
        XCTAssertEqual(bezahlt.receiptName(payment: 5), "Quittung-RE-2026-41-5.pdf")

        let entwurf: InvoiceItem = try decode(#"{"id":9}"#)
        XCTAssertEqual(entwurf.payer, "")
        XCTAssertFalse(entwurf.hasPaid)
        XCTAssertEqual(entwurf.receiptName(payment: 5), "Quittung-5.pdf")
    }

    func testBetragUndInhaltFuerBarKassiert() {
        XCTAssertEqual(Geld.inputText("40.00"), "40,00")
        XCTAssertEqual(Geld.inputText("1234.5"), "1234,50")
        XCTAssertEqual(Geld.inputText("x"), "")
        XCTAssertNil(CashDraft.amountError("40,00", outstanding: "40.00"))
        XCTAssertNil(CashDraft.amountError("0,01", outstanding: "40.00"))
        XCTAssertEqual(CashDraft.amountError("40,01", outstanding: "40.00"), "Offen sind nur noch 40,00\u{00A0}€.")
        XCTAssertEqual(CashDraft.amountError("0", outstanding: "40.00"), "Bitte einen Betrag über 0 eingeben.")
        XCTAssertEqual(CashDraft.amountError("viel", outstanding: "40.00"), "Bitte einen Betrag über 0 eingeben.")
        XCTAssertNil(CashDraft.amountError("5", outstanding: ""))

        var draft = CashDraft(outstanding: "40.00", key: "k1")
        XCTAssertEqual(draft.amount, "40,00")
        XCTAssertNil(draft.body(outstanding: "40.00"))
        draft.date = "14.11.2026"
        XCTAssertNil(draft.body(outstanding: "40.00"))
        draft.account = 2
        let body = draft.body(outstanding: "40.00")
        XCTAssertEqual(body?["account"] as? Int, 2)
        XCTAssertEqual(body?["amount"] as? String, "40.00")
        XCTAssertEqual(body?["date"] as? String, "2026-11-14")
        XCTAssertEqual(body?.count, 3)
        draft.amount = "15"
        XCTAssertEqual(draft.body(outstanding: "40.00")?["amount"] as? String, "15.00")
        draft.amount = "50"
        XCTAssertNil(draft.body(outstanding: "40.00"))
        draft.amount = "15"
        draft.date = "31.02.2026"
        XCTAssertNil(draft.body(outstanding: "40.00"))
        XCTAssertNotEqual(CashDraft(outstanding: "1.00").key, CashDraft(outstanding: "1.00").key)
    }

    func testRechnungenSuchenUndLaden() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"count":31,"next":"x","results":[\#(offen)]}"#),
            FakeTransport.json(200, #"{"count":0,"results":[]}"#),
            FakeTransport.json(200, offen),
            FakeTransport.json(200, #"{"accounts":[{"id":1,"name":"Girokonto","kind":"bank"},{"id":2,"name":"Barkasse","kind":"cash"}],"can_edit":true}"#),
        ])
        let client = verwaltung(net)
        let page = try await client.invoices(search: " Müller & Co ", page: 2)
        XCTAssertEqual(net.seen[0].method, "GET")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/billing/invoices/?suche=M%C3%BCller%20%26%20Co&page=2&offen=1")
        XCTAssertEqual(page.count, 31)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.results.map(\.id), [7])
        let all = try await client.invoices(search: "", openOnly: false)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/4/billing/invoices/?suche=&page=1")
        XCTAssertFalse(all.hasMore)
        let one = try await client.invoice(7)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/4/billing/invoices/7/")
        XCTAssertEqual(one.number, "RE-2026-0042")
        let info = try await client.billingInfo()
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/app/v1/admin/u/4/billing/settings/")
        XCTAssertTrue(info.canEdit)
        XCTAssertEqual(info.cashAccounts.map(\.id), [2])
    }

    func testBarKassiertMitSchutzVorDoppeltemBuchenUndRueckgaengig() async throws {
        let danach = offen.replacingOccurrences(of: #""outstanding":"40.00""#, with: #""outstanding":"25.00""#)
        let net = FakeTransport([
            .success(HttpResponse(
                status: 201, body: Data(#"{"invoice":\#(danach),"payment":12}"#.utf8),
                headers: ["X-Change-Set": "cs-9", "X-Change-Undoable": "1", "X-Change-Label": "Barzahlung"]
            )),
            FakeTransport.json(400, #"{"detail":"Der Betrag ist höher als der offene Betrag."}"#),
            .success(HttpResponse(status: 200, body: Data([0x25, 0x50, 0x44, 0x46]))),
            FakeTransport.json(404, "{}"),
        ])
        let client = verwaltung(net)
        let done = try await client.payCash(invoice: 7, body: ["account": 2, "amount": "15.00", "date": "2026-11-14"], key: "k1")
        XCTAssertEqual(done.result.payment, 12)
        XCTAssertEqual(done.result.invoice.outstanding, "25.00")
        XCTAssertEqual(done.change.changeSet, "cs-9")
        let sent = net.seen[0]
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url, "https://verein.example.de/api/app/v1/admin/u/4/billing/invoices/7/cash/")
        XCTAssertEqual(sent.headers["Idempotency-Key"], "k1")
        XCTAssertEqual(sent.headers["Authorization"], "Bearer hpa_erfunden")
        XCTAssertEqual(String(data: try XCTUnwrap(sent.body), encoding: .utf8), #"{"account":2,"amount":"15.00","date":"2026-11-14"}"#)
        do {
            _ = try await client.payCash(invoice: 7, body: ["account": 2, "amount": "99.00", "date": "2026-11-14"], key: "k2")
            XCTFail("400 erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.message, "Der Betrag ist höher als der offene Betrag.")
        }
        let pdf = await client.cashReceipt(payment: 12)
        XCTAssertEqual(pdf, Data([0x25, 0x50, 0x44, 0x46]))
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/4/billing/payments/12/receipt/")
        let missing = await client.cashReceipt(payment: 13)
        XCTAssertNil(missing)
    }
}
