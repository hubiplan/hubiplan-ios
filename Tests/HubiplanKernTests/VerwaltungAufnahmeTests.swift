import XCTest
@testable import HubiplanKern

final class VerwaltungAufnahmeTests: XCTestCase {
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

    private func json(_ body: [String: Any]?) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(body), options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private func person() -> AdmitDraft {
        var draft = AdmitDraft(entry: "2026-11-14")
        draft.firstName = " Lena "
        draft.lastName = "Beispiel"
        draft.street = "Musterweg 2"
        draft.postalCode = "41468"
        draft.city = "Musterstadt"
        draft.type = 3
        return draft
    }

    func testPflichtangaben() {
        var draft = AdmitDraft(entry: "2026-11-14")
        XCTAssertEqual(draft.error, "Bitte Vor- und Nachname angeben.")
        XCTAssertNil(draft.body(person: nil))
        draft.firstName = "Lena"
        draft.lastName = "Beispiel"
        draft.birthDate = "31.02.2008"
        XCTAssertEqual(draft.error, "Bitte das Geburtsdatum als TT.MM.JJJJ eingeben.")
        draft.birthDate = ""
        XCTAssertEqual(draft.error, "Bitte die vollständige Anschrift angeben.")
        draft.street = "Musterweg 2"
        draft.postalCode = "41468"
        draft.city = "Musterstadt"
        XCTAssertEqual(draft.error, "Bitte eine Mitgliedsart wählen.")
        draft.type = 3
        XCTAssertNil(draft.error)
        draft.entry = ""
        XCTAssertEqual(draft.error, "Bitte das Eintrittsdatum angeben.")
        draft.entry = "2026-11-14"
        draft.organization = true
        draft.lastName = " "
        XCTAssertEqual(draft.error, "Bitte den Namen der Organisation angeben.")
    }

    func testInhaltPerson() throws {
        var draft = person()
        XCTAssertEqual(
            try json(draft.body(person: nil)),
            #"{"birth_date":null,"city":"Musterstadt","email":"","entry_date":"2026-11-14","first_name":"Lena","gender":"","last_name":"Beispiel","member_type":3,"phone":"","postal_code":"41468","street":"Musterweg 2","title":""}"#
        )
        draft.birthDate = "7.3.2008"
        draft.gender = "weiblich"
        draft.title = "Dr."
        draft.email = "lena@example.org"
        draft.department = 11
        // Gefundene Person: Geschlecht bleibt, wie es dort steht
        XCTAssertEqual(
            try json(draft.body(person: 55)),
            #"{"birth_date":"2008-03-07","city":"Musterstadt","department_ids":[11],"email":"lena@example.org","entry_date":"2026-11-14","first_name":"Lena","last_name":"Beispiel","member_type":3,"person":55,"phone":"","postal_code":"41468","street":"Musterweg 2","title":"Dr."}"#
        )
    }

    func testInhaltOrganisation() throws {
        var draft = person()
        draft.organization = true
        draft.lastName = "Musterbau GmbH"
        draft.nameSuffix = "Niederlassung"
        draft.firstName = ""
        draft.birthDate = "kein Datum"
        XCTAssertNil(draft.error)
        XCTAssertEqual(
            try json(draft.body(person: nil)),
            #"{"city":"Musterstadt","email":"","entry_date":"2026-11-14","kind":"organization","last_name":"Musterbau GmbH","member_type":3,"name_suffix":"Niederlassung","phone":"","postal_code":"41468","street":"Musterweg 2"}"#
        )
    }

    func testDubletten() throws {
        let list: [DuplicateItem] = try decode(#"[{"id":55,"last_name":"Beispiel","first_name":"Lena","birth_date":"2008-03-07"},{"id":56,"last_name":"Beispiel","first_name":"Lena","already_member_here":true},{"id":57,"last_name":"Musterbau GmbH","kind":"organization"}]"#)
        XCTAssertEqual(list.map(\.name), ["Lena Beispiel", "Lena Beispiel", "Musterbau GmbH"])
        XCTAssertEqual(list.map(\.detail), ["07.03.2008", "ohne Geburtsdatum · schon Mitglied hier", "Organisation"])
    }

    func testSuchenUndAufnehmen() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":55,"last_name":"Beispiel","first_name":"Lena","birth_date":"2008-03-07"}]"#),
            FakeTransport.json(200, "[]"),
            FakeTransport.json(201, #"{"id":70,"first_name":"Lena","last_name":"Beispiel","status":"active"}"#),
            FakeTransport.json(400, #"{"detail":"Diese Person ist hier schon Mitglied."}"#),
        ])
        let client = verwaltung(net)
        var draft = person()
        draft.lastName = "Beispiel & Söhne"
        draft.birthDate = "07.03.2008"
        let found = try await client.duplicates(draft)
        XCTAssertEqual(found.map(\.id), [55])
        draft.organization = true
        let none = try await client.duplicates(draft)
        XCTAssertEqual(none, [])
        draft.organization = false
        let member = try await client.admit(body: try XCTUnwrap(draft.body(person: 55)), key: "schluessel-1")
        XCTAssertEqual(member.id, 70)
        XCTAssertEqual(member.name, "Lena Beispiel")
        do {
            _ = try await client.admit(body: try XCTUnwrap(draft.body(person: 55)), key: "schluessel-1")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.message, "Diese Person ist hier schon Mitglied.")
        }
        let seen = net.seen
        let prefix = server + "/api/app/v1/admin/u/4/"
        XCTAssertEqual(seen[0].url, prefix + "members/duplicates/?name=Beispiel%20%26%20S%C3%B6hne&vorname=Lena&geburtsdatum=2008-03-07")
        XCTAssertEqual(seen[1].url, prefix + "members/duplicates/?typ=organisation&name=Beispiel%20%26%20S%C3%B6hne")
        XCTAssertEqual(seen[2].method, "POST")
        XCTAssertEqual(seen[2].url, prefix + "members/admit/")
        XCTAssertEqual(seen[2].headers["Idempotency-Key"], "schluessel-1")
    }
}
