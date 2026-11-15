import XCTest
@testable import HubiplanKern

final class VerwaltungNachschlagenTests: XCTestCase {
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

    func testRechteModuleUndBereiche() {
        let alles = AdminUnit(
            id: 1, name: "A", permissions: ["members.view", "partners.view", "obligations.edit"], stufen: true,
            modules: ["qualifications", "obligations"]
        )
        XCTAssertEqual(alles.sections, [.tasks, .obligations, .members, .occasions, .qualifications, .partners])
        // Ohne Modul keine Qualifikationen und Fristen
        let ohneModule = AdminUnit(id: 1, name: "A", permissions: ["members.view", "partners.edit", "obligations.view"], stufen: true)
        XCTAssertEqual(ohneModule.sections, [.tasks, .members, .occasions, .partners])
        // Fristen brauchen das eigene Recht, Qualifikationen das Lesen der Mitglieder
        let nurModule = AdminUnit(id: 1, name: "A", permissions: ["finance.view"], stufen: true, modules: ["qualifications", "obligations"])
        XCTAssertFalse(nurModule.showsQualifications)
        XCTAssertFalse(nurModule.showsObligations)
        XCTAssertFalse(nurModule.showsPartners)
        // Nur in der Einheit selbst
        let zug = AdminUnit(
            id: 9, name: "Zug", permissions: ["members.view", "partners.view", "obligations.view"], scope: "d", stufen: true,
            modules: ["qualifications", "obligations"]
        )
        XCTAssertFalse(zug.showsPartners)
        XCTAssertFalse(zug.showsQualifications)
        XCTAssertFalse(zug.showsObligations)
    }

    func testGeschaeftspartner() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":1,"name":"Getränkemarkt Beispiel","kind":"organization","roles":["supplier","sponsor","eigene"],"number":"GP-0007","details":{"street":"Musterstraße 12","postcode":"12345","city":"Musterstadt","email":"info@getraenke.example","phone":"+49 30 1234567"},"notes":"Liefert freitags.","contacts":[{"id":1,"last_name":"Beispiel","first_name":"Lena","function":"Einkauf","is_primary":true},{"id":2,"last_name":"Probe"}]},{"id":2,"name":"Zeltverleih Muster"}]"#),
            FakeTransport.json(200, #"{"count":0,"results":[]}"#),
        ])
        let client = verwaltung(net)
        let list = try await client.partners(search: " Müller & Co ")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/billing/partners/?suche=M%C3%BCller%20%26%20Co")
        XCTAssertEqual(list.count, 2)
        let first = list[0]
        XCTAssertEqual(first.roleText, "Lieferant, Sponsor, eigene")
        XCTAssertEqual(first.listDetail, "Lieferant, Sponsor, eigene · Musterstadt · Lena Beispiel")
        XCTAssertEqual(first.headline, "GP-0007 · Lieferant, Sponsor, eigene")
        XCTAssertEqual(first.details.address, "Musterstraße 12, 12345 Musterstadt")
        XCTAssertEqual(first.contacts[0].info, "Einkauf · Hauptansprechpartner")
        XCTAssertEqual(first.contacts[1].fullName, "Probe")
        XCTAssertEqual(first.contacts[1].info, "")
        XCTAssertEqual(list[1].listDetail, "")
        XCTAssertEqual(list[1].headline, "")
        XCTAssertEqual(list[1].details.address, "")
        let empty = try await client.partners(search: "")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/4/billing/partners/?suche=")
        XCTAssertTrue(empty.isEmpty)
    }

    func testQualifikationen() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":1,"member":2,"first_name":"Max","last_name":"Mustermann","kind_name":"Erste Hilfe","valid_until":"2026-11-02","status":"expired"},{"id":2,"member":1,"first_name":"Erika","last_name":"Musterfrau","kind_name":"Schießleiter","valid_until":"2026-12-24","status":"expiring"},{"id":3,"member":4,"last_name":"Beispiel","kind_name":"Jugendleiter-Card","status":"valid"}]"#),
            FakeTransport.json(200, "[]"),
        ])
        let client = verwaltung(net)
        let soon = try await client.qualifications(soonOnly: true)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/qualifications/?stand=bald")
        XCTAssertEqual(soon.map(\.member), [2, 1, 4])
        XCTAssertEqual(soon[0].name, "Max Mustermann")
        XCTAssertEqual(soon[0].detail, "Erste Hilfe · abgelaufen · bis 02.11.2026")
        XCTAssertTrue(soon[0].urgent)
        XCTAssertEqual(soon[1].detail, "Schießleiter · läuft bald ab · bis 24.12.2026")
        XCTAssertEqual(soon[2].name, "Beispiel")
        XCTAssertEqual(soon[2].detail, "Jugendleiter-Card · gültig · unbefristet")
        XCTAssertFalse(soon[2].urgent)
        _ = try await client.qualifications(soonOnly: false)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/4/qualifications/")
    }

    func testFristenSortiertMitVerlauf() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"items":[{"id":4,"title":"Transparenzregister","status":"election","role_name":"Vorstand"},{"id":2,"title":"Feuerlöscher","due_date":"2026-12-29","status":"planned","role_name":"Hauswart","interval_months":24},{"id":5,"title":"Archiv","due_date":"2026-12-01","status":"planned","interval_months":1},{"id":1,"title":"Steuererklärung","note":"Notartermin","due_date":"2026-11-09","status":"overdue","role_name":"Kassierer","history":[{"id":1,"done_on":"2023-11-02","note":"Fristgerecht","done_by":"Max Mustermann"},{"id":2,"done_on":"2020-10-30"}]},{"id":3,"title":"Vereinsregister","due_date":"2026-12-04","status":"soon"},{"id":6,"title":"Neu","status":"unbekannt"}]}"#),
        ])
        let client = verwaltung(net)
        let list = try await client.obligations()
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/obligations/")
        XCTAssertEqual(list.map(\.id), [1, 3, 5, 2, 4, 6])
        XCTAssertEqual(list[0].line, "überfällig · Frist 09.11.2026 · Kassierer")
        XCTAssertTrue(list[0].urgent)
        XCTAssertNil(list[0].repeatText)
        XCTAssertEqual(list[0].history.map(\.line), ["erledigt am 02.11.2023 · Max Mustermann · Fristgerecht", "erledigt am 30.10.2020"])
        XCTAssertEqual(list[1].line, "bald fällig · Frist 04.12.2026")
        XCTAssertEqual(list[2].repeatText, "wiederholt sich jeden Monat")
        XCTAssertEqual(list[3].repeatText, "wiederholt sich alle 24 Monate")
        XCTAssertEqual(list[4].line, "nach jeder Vorstandswahl · Vorstand")
        XCTAssertFalse(list[4].urgent)
        XCTAssertEqual(list[5].line, "unbekannt")
    }
}
