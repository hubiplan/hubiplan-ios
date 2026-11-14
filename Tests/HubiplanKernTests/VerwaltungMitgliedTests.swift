import XCTest
@testable import HubiplanKern

final class VerwaltungMitgliedTests: XCTestCase {
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

    private func sent(_ request: HttpRequest) throws -> String {
        let object = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any]
        return try json(object)
    }

    private let akte = #"{"id":7,"first_name":"Erika","last_name":"Musterfrau","status":"active","pays_fee_self":false,"current_type":{"member_type":2,"member_type_name":"Vollmitglied"},"departments":[{"id":1,"department":11,"department_name":"Zug 1","valid_from":"2010-01-01"},{"id":2,"department":12,"department_name":"Zug 2","valid_from":"2010-01-01","valid_until":"2015-12-31"}],"exit_reasons":[{"value":"resignation","label":"Kündigung"},{"value":"death","label":"Verstorben"}]}"#

    func testAkteMitAngabenFuerVorgaenge() throws {
        let member: MemberDetail = try decode(akte)
        XCTAssertEqual(member.currentType, 2)
        XCTAssertFalse(member.paysFeeSelf)
        XCTAssertEqual(member.exitReasons, [MemberChoice(value: "resignation", label: "Kündigung"), MemberChoice(value: "death", label: "Verstorben")])
        XCTAssertEqual(member.currentDepartments(today: "2026-11-14").map(\.department), [11])
        // Ältere Stände und Untereinheiten: Angaben fehlen
        let alt: MemberDetail = try decode(#"{"id":8,"last_name":"Probe","member_type":"Vollmitglied","departments":["Zug 1"]}"#)
        XCTAssertNil(alt.currentType)
        XCTAssertTrue(alt.paysFeeSelf)
        XCTAssertEqual(alt.exitReasons, [])
    }

    func testAuswahlOhneLaufendes() throws {
        let member: MemberDetail = try decode(akte)
        let types: [MemberTypeItem] = try decode(#"[{"id":1,"name":"Jugend"},{"id":2,"name":"Vollmitglied"},{"id":3,"name":"Alt","is_archived":true}]"#)
        XCTAssertEqual(member.otherTypes(types).map(\.id), [1, 3])
        let units: [DepartmentItem] = try decode(#"[{"id":11,"name":"Zug 1"},{"id":12,"name":"Zug 2","display_name":"Zweiter Zug"},{"id":13,"name":"Zug 3","is_active":false}]"#)
        XCTAssertEqual(member.otherDepartments(units, today: "2026-11-14").map(\.label), ["Zweiter Zug", "Zug 3"])
        // Bis zum letzten Tag zählt die alte Untereinheit noch
        XCTAssertEqual(member.otherDepartments(units, today: "2015-12-31").map(\.id), [13])
    }

    func testVorgaengeAlsAnfrage() throws {
        let wechsel = MemberProcess.changeType(type: 3, from: "2027-01-01")
        XCTAssertEqual(try json(wechsel.previewBody), #"{"action":"change_type","member_type":3,"valid_from":"2027-01-01"}"#)
        XCTAssertEqual(wechsel.request.path, "change-type/")
        XCTAssertEqual(try json(wechsel.request.body), #"{"member_type":3,"valid_from":"2027-01-01"}"#)
        let umzug = MemberProcess.move(department: 12, from: "2026-12-01")
        XCTAssertEqual(try json(umzug.previewBody), #"{"action":"move","department":12,"valid_from":"2026-12-01"}"#)
        XCTAssertEqual(try json(umzug.request.body), #"{"department":12,"valid_from":"2026-12-01"}"#)
        let austritt = MemberProcess.exit(date: "2026-12-31", reason: "resignation", note: "  schriftlich " + String(repeating: "a", count: 300))
        XCTAssertEqual(try json(austritt.previewBody), #"{"action":"exit","exit_date":"2026-12-31","exit_reason":"resignation"}"#)
        XCTAssertEqual(austritt.request.path, "exit/")
        XCTAssertEqual((austritt.request.body["note"] as? String)?.count, 200)
        XCTAssertEqual((austritt.request.body["note"] as? String)?.hasPrefix("schriftlich a"), true)
        let beitrag = MemberProcess.feeSelf(true)
        XCTAssertEqual(try json(beitrag.previewBody), #"{"action":"fee_self","pays_fee_self":true}"#)
        XCTAssertEqual(beitrag.request.method, "PATCH")
        XCTAssertEqual(beitrag.request.path, "")
        let wieder = MemberProcess.reentry(type: 2, typeName: "Vollmitglied", from: "2027-01-01")
        XCTAssertNil(wieder.previewBody)
        XCTAssertEqual(try json(wieder.request.body), #"{"entry_date":"2027-01-01","member_type":2}"#)
        XCTAssertEqual(wieder.localPreview?.consequences, ["Ab 01.01.2027 wieder Mitglied als Vollmitglied.", "Frühere Zeiten und Nummern bleiben erhalten."])
        XCTAssertEqual(MemberPreview(title: "", consequences: []).heading, "Änderung bestätigen")
        XCTAssertEqual(MemberPreview(title: "", consequences: []).doneText, "Gespeichert")
    }

    func testVorschauUndAusfuehren() async throws {
        let ehemalig = akte.replacingOccurrences(of: #""status":"active""#, with: #""status":"former""#)
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":1,"name":"Jugend"},{"id":3,"name":"Alt","is_archived":true}]"#),
            FakeTransport.json(200, #"[{"id":11,"name":"Zug 1"},{"id":13,"name":"Zug 3","is_active":false}]"#),
            FakeTransport.json(200, #"{"title":"Austritt","consequences":["Mitgliedschaft endet am 31.12.2026.","Das SEPA-Mandat wird beendet."]}"#),
            .success(HttpResponse(status: 200, body: Data(ehemalig.utf8), headers: ["X-Change-Set": "cs-9", "X-Change-Undoable": "1"])),
            .success(HttpResponse(status: 200, body: Data(akte.utf8), headers: ["X-Change-Set": "cs-10", "X-Change-Undoable": "1"])),
            FakeTransport.json(400, #"{"detail":"Das Datum liegt vor dem Eintritt."}"#),
        ])
        let client = verwaltung(net)
        let types = try await client.memberTypes()
        XCTAssertEqual(types.map(\.name), ["Jugend"])
        let units = try await client.departments()
        XCTAssertEqual(units.map(\.id), [11])
        let austritt = MemberProcess.exit(date: "2026-12-31", reason: "resignation", note: "")
        let preview = try await client.preview(member: 7, austritt)
        XCTAssertEqual(preview.heading, "Austritt")
        XCTAssertEqual(preview.consequences.count, 2)
        let result = try await client.apply(member: 7, austritt)
        XCTAssertTrue(result.member.isFormer)
        XCTAssertEqual(result.change.changeSet, "cs-9")
        // Wiedereintritt: Folgen nennt die App selbst, ohne Anfrage
        let wieder = MemberProcess.reentry(type: 2, typeName: "Vollmitglied", from: "2027-01-01")
        let lokal = try await client.preview(member: 7, wieder)
        XCTAssertEqual(lokal.title, "Wiedereintritt")
        let zurueck = try await client.apply(member: 7, wieder)
        XCTAssertFalse(zurueck.member.isFormer)
        do {
            _ = try await client.apply(member: 7, .changeType(type: 1, from: "1900-01-01"))
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.message, "Das Datum liegt vor dem Eintritt.")
        }
        let seen = net.seen
        XCTAssertEqual(seen.map(\.method), ["GET", "GET", "POST", "POST", "POST", "POST"])
        let prefix = server + "/api/app/v1/admin/u/4/"
        XCTAssertEqual(seen.map { $0.url.replacingOccurrences(of: prefix, with: "") }, [
            "member-types/", "departments/", "members/7/preview/", "members/7/exit/", "members/7/reentry/", "members/7/change-type/",
        ])
        XCTAssertEqual(try sent(seen[2]), #"{"action":"exit","exit_date":"2026-12-31","exit_reason":"resignation"}"#)
        XCTAssertEqual(try sent(seen[3]), #"{"exit_date":"2026-12-31","exit_reason":"resignation","note":""}"#)
    }
}
