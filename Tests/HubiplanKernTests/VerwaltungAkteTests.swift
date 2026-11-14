import XCTest
@testable import HubiplanKern

final class VerwaltungAkteTests: XCTestCase {
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

    private func path(_ request: HttpRequest) -> String {
        request.url.replacingOccurrences(of: server + "/api/app/v1/admin/u/4/", with: "")
    }

    private let felder = #"[{"definition":{"id":1,"label":"Schießbuch-Nr.","field_type":"text"},"value":"A-17"},{"definition":{"id":2,"label":"Uniform erhalten","field_type":"date","help_text":"Tag der Ausgabe"},"value":"2024-05-03"},{"definition":{"id":3,"label":"Ersthelfer","field_type":"bool"},"value":false},{"definition":{"id":4,"label":"Schuhgröße","field_type":"number"},"value":"42.5"},{"definition":{"id":5,"label":"Kragenweite","field_type":"number"},"value":41},{"definition":{"id":6,"label":"Instrument","field_type":"choice","choices":["Trommel","Flöte"]},"value":null},{"definition":{"id":7,"label":"Lehrgänge","field_type":"text","repeatable":true},"value":["A","B"]},{"definition":{"id":8,"label":"Fahrer","field_type":"bool"}}]"#

    func testEhrungen() throws {
        let list: [AwardItem] = try decode(#"[{"id":1,"title":3,"title_name":"Ehrenmitglied","valid_from":"2020-01-11"},{"id":2,"title":4,"title_name":"Zugkönig","valid_from":"2018-09-01","valid_until":"2019-08-31","note":"Zug 1"}]"#)
        XCTAssertTrue(list[0].running)
        XCTAssertEqual(list[0].period, "seit 11.01.2020")
        XCTAssertFalse(list[1].running)
        XCTAssertEqual(list[1].period, "seit 01.09.2018 bis 31.08.2019")
        XCTAssertEqual(list[1].note, "Zug 1")
    }

    func testZusatzfelderLesen() throws {
        let list: [FieldEntry] = try decode(felder)
        XCTAssertEqual(list.map(\.text), ["A-17", "03.05.2024", "nein", "42,5", "41", "", "", ""])
        XCTAssertEqual(list.map(\.shown), ["A-17", "03.05.2024", "nein", "42,5", "41", "–", "(mehrere Einträge, im Browser)", "–"])
        XCTAssertEqual(list[1].definition.helpText, "Tag der Ausgabe")
        XCTAssertEqual(list[5].definition.choices, ["Trommel", "Flöte"])
        XCTAssertEqual(MemberFields.input(list), [1: "A-17", 2: "03.05.2024", 3: "nein", 4: "42,5", 5: "41", 6: "", 8: ""])
    }

    func testZusatzfelderAendern() throws {
        let list: [FieldEntry] = try decode(felder)
        var input = MemberFields.input(list)
        XCTAssertTrue(MemberFields.changes(list, input: input).values.isEmpty)
        input[1] = " A-18 "
        input[2] = "4.6.2024"
        input[3] = "ja"
        input[4] = "43"
        input[5] = ""
        input[6] = "Flöte"
        input[7] = "wird nicht gesendet"
        let result = MemberFields.changes(list, input: input)
        XCTAssertNil(result.error)
        XCTAssertEqual(try json(result.values), #"{"1":"A-18","2":"2024-06-04","3":true,"4":"43","5":null,"6":"Flöte"}"#)
        input[2] = "31.02.2024"
        XCTAssertEqual(MemberFields.changes(list, input: input).error, "Uniform erhalten: bitte als TT.MM.JJJJ eingeben.")
        input[2] = "03.05.2024"
        input[3] = "vielleicht"
        XCTAssertEqual(MemberFields.changes(list, input: input).error, "Ersthelfer: bitte ja, nein oder – wählen.")
        // Ja/Nein zurück auf „nicht angegeben“
        input[3] = ""
        XCTAssertTrue(MemberFields.changes(list, input: input).values["3"] is NSNull)
    }

    func testBankverbindung() throws {
        let list: [MandateItem] = try decode(#"[{"id":1,"reference":"M-0042-1","holder":"Erika Musterfrau","iban_masked":"DE02 •••• 5678","signed_on":"2023-02-01","status":"active"},{"id":2,"reference":"M-0042-0","holder":"Erika Musterfrau","iban":"DE02120300000000202051","iban_masked":"DE02 •••• 2051","status":"revoked"}]"#)
        XCTAssertTrue(list[0].isActive)
        XCTAssertFalse(list[1].isActive)
        XCTAssertEqual(list[0].line, "Erika Musterfrau: DE02 •••• 5678")
        XCTAssertEqual(list[0].detail, "Mandat M-0042-1, unterschrieben 01.02.2023")
        XCTAssertEqual(list[1].line, "Erika Musterfrau: DE02 1203 0000 0000 2020 51")
        XCTAssertEqual(Iban.grouped("de02 12030000 0000202051"), "DE02 1203 0000 0000 2020 51")
        var draft = MandateDraft(holder: " ", signed: "2026-11-14")
        XCTAssertEqual(draft.error, "Bitte den Kontoinhaber angeben.")
        draft.holder = " Erika Musterfrau "
        draft.iban = "DE02 1203"
        XCTAssertEqual(draft.error, "Bitte eine vollständige IBAN angeben.")
        draft.iban = "de02 1203 0000 0000 2020 51"
        draft.bic = " byladem1001 "
        XCTAssertNil(draft.error)
        XCTAssertEqual(try json(draft.body(member: 7)), #"{"bic":"BYLADEM1001","holder":"Erika Musterfrau","iban":"DE02120300000000202051","membership":7,"signed_on":"2026-11-14"}"#)
        XCTAssertTrue(AdminUnit(id: 1, name: "A", permissions: ["billing.view"], stufen: true).showsBank)
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["billing.view"], stufen: true).canEditBank)
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["members.edit"], stufen: true).showsBank)
    }

    func testAnfragen() async throws {
        let change: (String) -> Result<HttpResponse, Error> = { set in
            .success(HttpResponse(status: 200, body: Data("{}".utf8), headers: ["X-Change-Set": set, "X-Change-Undoable": "1"]))
        }
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":1,"title":3,"title_name":"Ehrenmitglied","valid_from":"2020-01-11"}]"#),
            FakeTransport.json(200, #"[{"id":3,"name":"Ehrenmitglied"},{"id":9,"name":"Alt","is_archived":true}]"#),
            change("cs-1"), change("cs-2"),
            FakeTransport.json(404, #"{"detail":"Nicht gefunden."}"#),
            FakeTransport.json(200, felder),
            change("cs-3"),
            FakeTransport.json(404, "{}"),
            FakeTransport.json(200, #"[{"id":1,"holder":"Erika Musterfrau","iban":"DE02120300000000202051","status":"active"}]"#),
            FakeTransport.json(200, #"{"title":"Bankverbindung ändern","consequences":["Das bisherige Mandat endet."]}"#),
            change("cs-4"),
            FakeTransport.json(500, "{}"),
        ])
        let client = verwaltung(net)
        let awards = try await client.awards(member: 7)
        XCTAssertEqual(awards.count, 1)
        let titles = try await client.honoraryTitles()
        XCTAssertEqual(titles.map(\.id), [3])
        let added = try await client.addAward(member: 7, title: 3, from: "2026-11-14", note: " Jubiläum ")
        XCTAssertEqual(added.changeSet, "cs-1")
        _ = try await client.endAward(member: 7, award: 1, until: "2026-12-31")
        // Zusatzfelder gibt es nicht überall
        let none = try await client.fields(member: 7)
        XCTAssertEqual(none, [])
        let fields = try await client.fields(member: 7)
        XCTAssertEqual(fields.count, 8)
        _ = try await client.saveFields(member: 7, values: ["3": true, "5": NSNull()])
        // SEPA ausgeschaltet
        let off = try await client.mandates(member: 7)
        XCTAssertEqual(off, [])
        let full = try await client.mandates(member: 7, full: true)
        XCTAssertEqual(full.first?.iban, "DE02120300000000202051")
        let preview = try await client.previewBank(member: 7)
        XCTAssertEqual(preview.consequences, ["Das bisherige Mandat endet."])
        var draft = MandateDraft(holder: "Erika Musterfrau", signed: "2026-11-14")
        draft.iban = "DE02120300000000202051"
        let mandate = try await client.addMandate(member: 7, draft)
        XCTAssertEqual(mandate.changeSet, "cs-4")
        do {
            _ = try await client.fields(member: 7)
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 500)
        }
        let seen = net.seen
        XCTAssertEqual(seen.map(\.method), ["GET", "GET", "POST", "PATCH", "GET", "GET", "PUT", "GET", "GET", "POST", "POST", "GET"])
        XCTAssertEqual(seen.map(path), [
            "members/7/honorary-titles/", "honorary-titles/", "members/7/honorary-titles/", "members/7/honorary-titles/1/",
            "members/7/fields/", "members/7/fields/", "members/7/fields/",
            "billing/mandates/?mitglied=7", "billing/mandates/?mitglied=7&voll=1", "members/7/preview/", "billing/mandates/", "members/7/fields/",
        ])
        XCTAssertEqual(try sent(seen[2]), #"{"note":"Jubiläum","title":3,"valid_from":"2026-11-14"}"#)
        XCTAssertEqual(try sent(seen[3]), #"{"valid_until":"2026-12-31"}"#)
        XCTAssertEqual(try sent(seen[6]), #"{"values":{"3":true,"5":null}}"#)
        XCTAssertEqual(try sent(seen[9]), #"{"action":"bank"}"#)
    }
}
