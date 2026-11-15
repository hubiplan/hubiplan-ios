import XCTest
@testable import HubiplanKern

/// Ergebnisse, Ranglisten, Lastschrift, Mitarbeiter, Rechnungs-PDF und Wallet-Pass (wie Android).
/// Erfundene Daten.
final class MeinBereichMehrTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    func testErgebnisZeilen() throws {
        let results = try decode(MyResults.self, #"{"starts":[{"competition":2,"title":"Vereinsmeisterschaft","date":"2026-09-12","status":"vorlaeufig","status_label":"vorläufig","unit_name":"Zug 1","results":[{"scoring":"Einzel","place":2,"field":14,"value_text":"287","unit_label":"Ringe"},{"scoring":"Mannschaft","value_text":"812"},{"scoring":"Teiler","value_text":"35,2 Teiler"},{"scoring":"Pokal"}]},{"competition":1,"title":"Königsschießen","date":"2026-06-14","status":"endgueltig","status_label":"endgültig"}],"grants":[{"id":1,"year":2025,"full_title":"Vereinsmeisterin 2025"},{"id":2,"year":2026,"trophy_name":"Wanderpokal"}]}"#)
        XCTAssertFalse(results.isEmpty)
        let lines = results.starts[0].results.map(\.line)
        XCTAssertEqual(lines, ["Einzel: 2. Platz von 14 · 287 Ringe", "Mannschaft: Wert 812", "Teiler: 35,2 Teiler", "Pokal: ohne Wertung"])
        XCTAssertEqual(results.starts[0].meta, "12.09.2026 · Zug 1 · vorläufig")
        XCTAssertEqual(results.starts[1].meta, "14.06.2026")
        XCTAssertEqual(results.grants.map(\.line), ["Vereinsmeisterin 2025", "Wanderpokal 2026"])
        Texte.language = "en"
        XCTAssertEqual(results.starts[0].results[0].line, "Einzel: Place 2 of 14 · 287 Ringe")
        XCTAssertEqual(results.starts[0].results[1].line, "Mannschaft: Value 812")
    }

    func testRanglisten() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"competitions":[{"id":"msv-2","title":"Vereinsmeisterschaft","date":"2026-09-12","location":"Schießstand","live":true},{"id":"bsv 1","title":"Bezirk","own":false,"organizer":"Bezirk Nord","provisional":true}],"poll_seconds":15}"#),
            FakeTransport.json(200, #"{"id":"msv-2","title":"Vereinsmeisterschaft","live":true,"version":"7","poll_seconds":2,"titles":[{"title":"Vereinsmeisterin","name":"Erika M."}],"prizes":[{"name":"Kopf","fallen":true,"winner":"Max M.","unit":"Zug 1","shot":37},{"name":"Zepter"},{"name":"Apfel","fallen":true}],"scorings":[{"name":"Einzel","complete":false,"rows":[{"place":1,"name":"Max M.","unit":"Zug 1","club":"SV Musterstadt","value":"291","prize":true},{"name":"","value":"280","out_of_competition":true,"note":"Gast"}]}]}"#),
            FakeTransport.json(200, #"{"version":"8","final":true}"#),
            FakeTransport.json(404, #"{"detail":"Nicht gefunden."}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let list = try await api.rankings(accessId: 3)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/rankings/")
        XCTAssertEqual(list.competitions.map(\.line), ["12.09.2026 · Schießstand · läuft", "Bezirk Nord · vorläufig"])

        let detail = try await api.ranking(accessId: 3, id: "msv-2")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/3/rankings/msv-2/")
        XCTAssertEqual(detail.pollEvery, 5)
        XCTAssertEqual(detail.prizes.map(\.line), ["Kopf: Max M. (Zug 1), 37. Schuss", "Zepter: noch dran", "Apfel: gefallen"])
        XCTAssertEqual(detail.scorings[0].rows.map(\.line), ["1. Max M. (Zug 1, SV Musterstadt) · 291", "ohne Namen · 280 · außer Konkurrenz · Gast"])
        XCTAssertFalse(detail.scorings[0].complete)

        let version = try await api.rankingVersion(accessId: 3, id: "bsv 1")
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/portal/3/rankings/bsv%201/?version=1")
        XCTAssertTrue(version.final)

        // Ältere Stände ohne Ranglisten: leer statt Fehler
        let none = try await api.rankings(accessId: 3)
        XCTAssertTrue(none.competitions.isEmpty)
    }

    func testLastschriftUndMitarbeiter() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"available":true,"club_name":"SV Musterstadt","creditor_id":"DE98ZZZ09999999999","mandate":{"reference":"MSV-0042","scheme_label":"SEPA-Basislastschrift","status_label":"aktiv","holder":"Erika Musterfrau","iban_masked":"DE89 •••• 00","signed_on":"2019-03-01"}}"#),
            FakeTransport.json(200, #"{"available":false}"#),
            FakeTransport.json(200, #"{"can_report":true,"companies":[{"id":4,"name":"Muster GmbH","members":[{"link":1,"name":"Max Mustermann","since":"2025-01-01","pays_via":true},{"link":2,"name":"Petra Beispiel","since":"2024-01-01","until":"2026-12-31"}]}]}"#),
            FakeTransport.json(201, #"{"ok":true}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let mandate = try await api.myMandate(accessId: 3)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/mandate/")
        XCTAssertTrue(mandate.shown)
        XCTAssertEqual(mandate.mandate?.lines, ["SEPA-Basislastschrift · aktiv", "Mandatsreferenz: MSV-0042", "Konto: DE89 •••• 00", "Kontoinhaber: Erika Musterfrau", "Erteilt am 01.03.2019"])
        let none = try await api.myMandate(accessId: 3)
        XCTAssertFalse(none.shown)

        let companies = try await api.myCompanies(accessId: 3)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/portal/3/company/")
        XCTAssertTrue(companies.canReport)
        XCTAssertEqual(companies.companies[0].members.map(\.line), ["seit 01.01.2025 · über die Firma", "seit 01.01.2024 · bis 31.12.2026"])

        try await api.reportEmployee(accessId: 3, company: 4, firstName: "Paul", lastName: "Probe", email: "paul@example.org")
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/portal/3/company/4/report/")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[3].body ?? Data()) as? [String: String])
        XCTAssertEqual(sent, ["first_name": "Paul", "last_name": "Probe", "email": "paul@example.org"])
    }

    func testRechnungsPdfUndWallet() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"invoices":[{"id":7,"number":"R-1","status":"cancelled","has_cancellation_pdf":true}],"collective":[{"id":2,"number":"S-1","date":"2026-03-01","department_name":"Zug 1","amount":"60.00","status_label":"bezahlt"}]}"#),
            .success(HttpResponse(status: 200, body: Data("%PDF-1.4".utf8))),
            .success(HttpResponse(status: 200, body: Data("%PDF-1.4".utf8))),
            .success(HttpResponse(status: 200, body: Data("PK".utf8))),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let list = try await api.myInvoices(accessId: 3)
        XCTAssertTrue(list.invoices[0].hasCancellationPdf)
        XCTAssertEqual(list.collective[0].title, "S-1")
        XCTAssertEqual(list.collective[0].line, "Zug 1 · 01.03.2026 · 60,00\u{00A0}€ · bezahlt")

        _ = try await api.invoicePdf(accessId: 3, invoiceId: 7)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/3/invoices/7/pdf/")
        _ = try await api.invoicePdf(accessId: 3, invoiceId: 7, cancellation: true)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/portal/3/invoices/7/pdf/?storno=1")
        let pass = try await api.walletPass(accessId: 3)
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/portal/3/card/wallet/apple/")
        XCTAssertEqual(pass, Data("PK".utf8))
    }

    func testZugangKenntErgebnisseUndFirma() throws {
        let old = try decode(PortalAccess.self, #"{"id":1,"club_name":"SV","competitions_enabled":true,"company":true}"#)
        XCTAssertTrue(old.hasResults)
        XCTAssertTrue(old.company)
        let modern = try decode(PortalAccess.self, #"{"id":1,"club_name":"SV","modules":["events"],"competitions_enabled":true}"#)
        XCTAssertFalse(modern.hasResults)
        XCTAssertFalse(modern.company)
    }
}
