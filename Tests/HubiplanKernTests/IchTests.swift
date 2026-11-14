import XCTest
@testable import HubiplanKern

final class IchTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func tearDown() { Texte.language = "de" }

    func testEigeneDaten() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"first_name":"Erika","last_name":"Musterfrau","birth_date":"1984-03-07","club_number":"0042","member_type":"Vollmitglied","entry_date":"2010-01-01","departments":["Zug 1"],"contact":{"email":"erika@example.org","phone":"02131 000000","street":"Musterweg 1","postal_code":"41468","city":"Musterstadt"},"status":"active","neu":true}"#)])
        let profile = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).profile(accessId: 3)
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/portal/3/")
        XCTAssertEqual(profile.name, "Erika Musterfrau")
        XCTAssertEqual(profile.contact?.addressLines, ["Musterweg 1", "41468 Musterstadt"])
        XCTAssertEqual(Zeit.plainDate(profile.birthDate), "07.03.1984")
        let org = try JSONDecoder().decode(Profile.self, from: Data(#"{"kind":"organization","display_name":"Musterbau GmbH","last_name":"Musterbau"}"#.utf8))
        XCTAssertEqual(org.name, "Musterbau GmbH")
        XCTAssertNil(org.contact)
    }

    func testRechnungen() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"invoices":[{"id":1,"number":"R-2026-0007","status":"paid","status_label":"Bezahlt","date":"2026-01-15","total":"60.00","outstanding":"0.00","issuer_name":"Schützenverein Musterstadt"},{"id":2,"number":"R-2026-0031","status":"open","status_label":"Offen","date":"2026-11-01","due_date":"2026-11-30","total":"1260.5","outstanding":"1260.5","overdue":false,"issuer_name":"Schützenverein Musterstadt","department_name":"Zug 1"},{"id":3,"status":"open","outstanding":"12.00"}],"collective":[]}"#)])
        let list = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).myInvoices(accessId: 3)
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/portal/3/invoices/")
        XCTAssertEqual(list.sorted.map(\.id), [2, 3, 1])
        XCTAssertEqual(list.openSum, "1.272,50\u{00A0}€")
        XCTAssertEqual(list.sorted[0].headline, "R-2026-0031 · 01.11.2026 · Zug 1")
        XCTAssertEqual(list.sorted[0].stateText, "Offen: 1.260,50\u{00A0}€, fällig am 30.11.2026")
        XCTAssertEqual(list.sorted[2].headline, "R-2026-0007 · 15.01.2026 · Schützenverein Musterstadt")
        XCTAssertEqual(list.sorted[2].stateText, "Bezahlt")
        Texte.language = "en"
        XCTAssertEqual(list.sorted[0].stateText, "Open: 1.260,50\u{00A0}€, due on 30.11.2026")
        let none = try JSONDecoder().decode(MyInvoices.self, from: Data("{}".utf8))
        XCTAssertNil(none.openSum)
    }

    func testGeld() {
        XCTAssertEqual(Geld.format("60.00"), "60,00\u{00A0}€")
        XCTAssertEqual(Geld.format("1234567.8"), "1.234.567,80\u{00A0}€")
        XCTAssertEqual(Geld.format("-5"), "-5,00\u{00A0}€")
        XCTAssertEqual(Geld.format("0.07"), "0,07\u{00A0}€")
        XCTAssertEqual(Geld.format("-0.50"), "-0,50\u{00A0}€")
        XCTAssertEqual(Geld.cents("19.99"), 1999)
        // 0.1 + 0.2 ohne Rundungsfehler
        XCTAssertEqual(Geld.format(cents: Geld.cents("0.1")! + Geld.cents("0.2")!), "0,30\u{00A0}€")
        for wrong in ["", "abc", "1.234", "1,50", "1.2.3", ".5", "1e3", "١٢"] {
            XCTAssertNil(Geld.cents(wrong), wrong)
            XCTAssertEqual(Geld.format(wrong), "")
        }
        XCTAssertEqual(Geld.format(nil), "")
    }

    func testDatum() {
        XCTAssertEqual(Zeit.plainDate("2026-11-20"), "20.11.2026")
        XCTAssertEqual(Zeit.plainDate("2026-11-20T19:00:00+01:00"), "20.11.2026")
        XCTAssertEqual(Zeit.plainDate(nil), "")
        XCTAssertEqual(Zeit.plainDate("20.11.2026"), "")
        XCTAssertEqual(Zeit.plainDate("morgen"), "")
    }
}
