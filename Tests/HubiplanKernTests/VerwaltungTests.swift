import XCTest
@testable import HubiplanKern

final class VerwaltungTests: XCTestCase {
    private let server = "https://verein.example.de"

    private func decode<T: Decodable>(_ text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    func testUebersichtMitEinheitenUndUntereinheiten() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"units":[{"id":1,"name":"Schützenverein Musterstadt","type":"club","permissions":["members.view","events.manage"],"modules":["events"],"neu":1}],"departments":[{"id":9,"name":"1. Zug","club_name":"Schützenverein Musterstadt","permissions":["dept.members.view"]}],"two_factor":true,"unlocked":false}"#)])
        let overview = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).adminOverview()
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/app/v1/admin/")
        XCTAssertEqual(net.seen.first?.headers["Authorization"], "Bearer hpd_a")
        XCTAssertTrue(overview.twoFactor)
        XCTAssertFalse(overview.unlocked)
        XCTAssertEqual(overview.allUnits.map(\.key), ["u:1", "d:9"])
        XCTAssertEqual(overview.allUnits[0].sections, [.tasks, .members])
        XCTAssertEqual(overview.allUnits[1].sections, [.members])
        XCTAssertTrue(overview.allUnits[1].isDepartment)
    }

    func testAeltereUebersichtOhneFelder() throws {
        let overview: AdminOverview = try decode("{}")
        XCTAssertTrue(overview.allUnits.isEmpty)
        XCTAssertFalse(overview.twoFactor)
        XCTAssertNil(overview.until)
    }

    func testMitgliederRechteMitUndOhneStufen() {
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["finance.view"]).showsMembers)
        XCTAssertTrue(AdminUnit(id: 1, name: "A", permissions: ["members.edit"]).showsMembers)
        XCTAssertFalse(AdminUnit(id: 2, name: "Zug", permissions: ["members.view"], scope: "d").showsMembers)
        XCTAssertTrue(AdminUnit(id: 2, name: "Zug", permissions: ["dept.members.view"], scope: "d").showsMembers)
        XCTAssertTrue(AdminUnit(id: 2, name: "Zug", permissions: ["members.view"], scope: "d", stufen: true).showsMembers)
        XCTAssertFalse(AdminUnit(id: 2, name: "Zug", permissions: ["dept.members.view"], scope: "d", stufen: true).showsMembers)
        XCTAssertEqual(AdminUnit(id: 3, name: "B", permissions: ["finance.view"]).sections, [.tasks])
    }

    func testFreischaltenSchicktSchluesselpaar() async throws {
        let net = FakeTransport([FakeTransport.json(201, #"{"token":"hpa_erfunden","until":"2026-12-14T10:00:00+01:00","signed":true}"#)])
        let unlock = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
            .unlockAdmin(password: "erfunden", code: "123456", adminKey: "BEcc")
        XCTAssertEqual(unlock.token, "hpa_erfunden")
        XCTAssertTrue(unlock.signed)
        let request = try XCTUnwrap(net.seen.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://verein.example.de/api/app/v1/admin/unlock/")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: String])
        XCTAssertEqual(body, ["password": "erfunden", "code": "123456", "admin_key": "BEcc"])
        // Freischalten selbst läuft mit dem Geräteschlüssel, ohne Unterschrift
        XCTAssertEqual(request.headers["Authorization"], "Bearer hpd_a")
        XCTAssertNil(request.headers[SignedFormat.signatureHeader])
    }

    func testSperren() async throws {
        let net = FakeTransport([.success(HttpResponse(status: 204, body: Data()))])
        try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).lockAdmin()
        XCTAssertEqual(net.seen.first?.method, "DELETE")
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/app/v1/admin/unlock/")
    }

    func testVerwaltungsanfrageTraegtBeideSchluesselUndUnterschrift() async throws {
        let key = P256.Signing.PrivateKey()
        let access = AdminAccess(token: "hpa_erfunden", key: key, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let other = "https://alt.example.de"
        let net = FakeTransport([FakeTransport.json(200, #"{"items":[{"kind":"change_request","kind_label":"Datenänderung","title":"Erika Musterfrau","detail":"Neue Anschrift"}]}"#)])
        let api = Api(server: other, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(access)
        let tasks = try await AdminClient(api: api, unit: AdminUnit(id: 4, name: "Verein")).tasks()
        XCTAssertEqual(tasks.map(\.kindLabel), ["Datenänderung"])
        let request = try XCTUnwrap(net.seen.first)
        XCTAssertEqual(request.url, "https://alt.example.de/api/app/v1/admin/u/4/tasks/")
        XCTAssertEqual(request.headers["Authorization"], "Bearer hpa_erfunden")
        XCTAssertEqual(request.headers[Api.deviceHeader], "hpd_a")
        XCTAssertEqual(request.headers[SignedFormat.timeHeader], "1800000000")
        // Instanz ohne Ankündigung: Format 1, ohne Zufallskennung
        XCTAssertNil(request.headers[SignedFormat.nonceHeader])
        let message = SignedFormat.adminMessage(method: "GET", path: "/api/app/v1/admin/u/4/tasks/", timestamp: "1800000000", body: Data())
        let der = try XCTUnwrap(Base64Url.decode(try XCTUnwrap(request.headers[SignedFormat.signatureHeader])))
        XCTAssertTrue(key.publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: der), for: message))
    }

    func testFormat2NachAnkuendigungDerInstanz() async throws {
        let key = P256.Signing.PrivateKey()
        let access = AdminAccess(token: "hpa_erfunden", key: key, now: { Date(timeIntervalSince1970: 1_800_000_000) }, nonce: { "kennung" })
        let neu = "https://neu.example.de"
        let net = FakeTransport([
            .success(HttpResponse(status: 200, body: Data(#"{"items":[]}"#.utf8), headers: ["x-hubiplan-signature-format": "2"])),
            FakeTransport.json(200, #"{"count":0,"results":[]}"#),
        ])
        let client = AdminClient(api: Api(server: neu, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(access), unit: AdminUnit(id: 4, name: "Verein"))
        _ = try await client.tasks()
        _ = try await client.members(search: " Müller & Söhne ")
        let request = net.seen[1]
        let path = "/api/app/v1/admin/u/4/members/?suche=M%C3%BCller%20%26%20S%C3%B6hne&status=aktiv&page=1&page_size=50"
        XCTAssertEqual(request.url, neu + path)
        XCTAssertEqual(request.headers[SignedFormat.nonceHeader], "kennung")
        let message = SignedFormat.adminMessage(method: "GET", path: path, timestamp: "1800000000", body: Data(), nonce: "kennung")
        let der = try XCTUnwrap(Base64Url.decode(try XCTUnwrap(request.headers[SignedFormat.signatureHeader])))
        XCTAssertTrue(key.publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: der), for: message))
    }

    func testOhneGeraeteschluesselKeineVerwaltungsanfrage() async throws {
        let net = FakeTransport([])
        let api = Api(server: server, transport: net, tokens: FakeTokens(nil)).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil))
        do {
            _ = try await AdminClient(api: api, unit: AdminUnit(id: 4, name: "Verein")).tasks()
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 401)
        }
        XCTAssertTrue(net.seen.isEmpty)
    }

    func testUntereinheitNutztEigenenPfadUndHatKeineOffenenPunkte() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"id":5,"kind":"person","first_name":"Erika","last_name":"Musterfrau","title":"Dr.","status":"active","club_number":"17","current_type":{"member_type":1,"member_type_name":"Aktiv"},"contact":{"email":"erika@example.org","phone":"01234 56789","city":"Musterstadt"},"periods":[{"id":2,"entry_date":"2015-03-01"},{"id":1,"entry_date":"2001-01-01","exit_date":"2010-12-31"}],"departments":[{"id":1,"department":9,"department_name":"1. Zug","valid_from":"2015-03-01"},{"id":2,"department":8,"department_name":"2. Zug","valid_from":"2001-01-01","valid_until":"2010-12-31"}]}"#)])
        let unit = AdminUnit(id: 9, name: "1. Zug", scope: "d")
        let client = AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: unit)
        let tasks = try await client.tasks()
        XCTAssertTrue(tasks.isEmpty)
        XCTAssertTrue(net.seen.isEmpty)
        let member = try await client.member(5)
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/app/v1/admin/d/9/members/5/")
        // Ohne Schlüsselpaar keine Unterschrift
        XCTAssertNil(net.seen.first?.headers[SignedFormat.signatureHeader])
        XCTAssertEqual(member.name, "Dr. Erika Musterfrau")
        XCTAssertEqual(member.typeName, "Aktiv")
        XCTAssertEqual(member.entryDate, "2001-01-01")
        XCTAssertEqual(member.contact?.phone, "01234 56789")
        XCTAssertEqual(member.currentDepartments(today: "2026-11-14").map(\.name), ["1. Zug"])
        XCTAssertFalse(member.isFormer)
    }

    func testMitgliederlisteMitOrganisation() throws {
        let page: MemberPage = try decode(#"{"count":2,"next":"x","results":[{"id":1,"last_name":"Musterfrau","first_name":"Erika","member_type":"Aktiv","departments":["1. Zug"],"city":"Musterstadt"},{"id":2,"kind":"organization","last_name":"Musterbau GmbH","name_suffix":"Niederlassung","status":"active"}]}"#)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.results[0].listName, "Musterfrau, Erika")
        XCTAssertEqual(page.results[0].listDetail, "Aktiv · 1. Zug · Musterstadt")
        XCTAssertEqual(page.results[1].listName, "Musterbau GmbH – Niederlassung")
        XCTAssertEqual(page.results[1].listDetail, "")
        let detail: MemberDetail = try decode(#"{"id":2,"kind":"organization","last_name":"Musterbau GmbH","organization":{"name_suffix":""},"status":"former"}"#)
        XCTAssertEqual(detail.name, "Musterbau GmbH")
        XCTAssertTrue(detail.isFormer)
    }

    override func setUp() {
        Texte.language = "de"
    }

    private func verwaltung(_ net: FakeTransport, unit: AdminUnit = AdminUnit(id: 4, name: "Verein")) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: unit)
    }

    func testOffenePunkteFuehrenInDieApp() throws {
        let tasks: [AdminTask] = try decode(#"[{"kind":"change_request","ref":3},{"kind":"photo","membership":5},{"kind":"photo"},{"kind":"event","ref":"x"}]"#)
        XCTAssertEqual(tasks.map(\.target), [.changeRequests, .member(5), nil, nil])
    }

    func testAenderungsmeldungenInFesterReihenfolge() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"[{"id":3,"member_id":5,"member_name":"Erika Musterfrau","data":{"phone":"01234 99999","zusatz":7,"birth_date":"1984-03-08","gender":"weiblich","city":null},"previous":{"phone":"01234 56789","birth_date":"1984-03-07","city":"Musterstadt"},"message":"Neue Nummer","created_at":"2026-11-10T09:00:00+01:00"}]"#)])
        let list = try await verwaltung(net).changeRequests()
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/app/v1/admin/u/4/change-requests/")
        XCTAssertEqual(list.first?.memberName, "Erika Musterfrau")
        XCTAssertEqual(list.first?.lines.map(\.key), ["birth_date", "gender", "phone", "city", "zusatz"])
        XCTAssertEqual(list.first?.lines.map(\.text), [
            "Geburtsdatum: 07.03.1984 → 08.03.1984", "Geschlecht: – → weiblich", "Telefon: 01234 56789 → 01234 99999",
            "Ort: Musterstadt → –", "zusatz: – → 7",
        ])
        let ohne: AdminChangeRequest = try decode(#"{"id":1,"member_id":2}"#)
        XCTAssertTrue(ohne.lines.isEmpty)
    }

    func testEntscheidenMitRueckgaengigUndKonflikt() async throws {
        let net = FakeTransport([
            .success(HttpResponse(status: 200, body: Data("{}".utf8), headers: ["X-Change-Set": "ab12-cd", "X-Change-Undoable": "1", "X-Change-Label": "Stammdaten%20ge%C3%A4ndert"])),
            FakeTransport.json(409, #"{"detail":"Die Anschrift wurde inzwischen geändert."}"#),
            .success(HttpResponse(status: 200, body: Data("{}".utf8), headers: ["X-Change-Set": "ef34"])),
            .success(HttpResponse(status: 204, body: Data())),
        ])
        let client = verwaltung(net)
        let change = try await client.decide(3, accept: true)
        XCTAssertEqual(change.changeSet, "ab12-cd")
        XCTAssertEqual(change.label, "Stammdaten geändert")
        let first = net.seen[0]
        XCTAssertEqual(first.method, "POST")
        XCTAssertEqual(first.url, "https://verein.example.de/api/app/v1/admin/u/4/change-requests/3/decide/")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(first.body)) as? [String: Any])
        XCTAssertEqual(body["accept"] as? Bool, true)
        XCTAssertEqual(body["overwrite"] as? Bool, false)
        XCTAssertEqual(body["response"] as? String, "")
        do {
            _ = try await client.decide(3, accept: true)
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 409)
            XCTAssertEqual(error.message, "Die Anschrift wurde inzwischen geändert.")
        }
        // Ohne Ankündigung „rückgängig möglich“ kein Paket
        let photo = try await client.decidePhoto(member: 5, approve: false)
        XCTAssertNil(photo.changeSet)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/4/members/5/photo/approve/")
        XCTAssertEqual(try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[2].body)) as? [String: String]), ["decision": "reject"])
        try await client.undo("ab12-cd")
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/app/v1/admin/u/4/changes/ab12-cd/undo/")
        do {
            try await client.undo("../x")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.code, "format")
        }
        XCTAssertEqual(net.seen.count, 4)
    }

    func testAusweisPruefen() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"status":"active","status_label":"Gültig","first_name":"Erika","last_name":"Musterfrau","member_type":"Vollmitglied","club":"Schützenverein Musterstadt","departments":["1. Zug"],"photo_url":"/api/public/cards/abc/photo/","membership":5}"#)])
        let check = try await verwaltung(net).checkCard(code: "https://verein.example.de/ausweis/pruefen/abc")
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/app/v1/admin/u/4/cards/check/")
        XCTAssertEqual(try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen.first?.body)) as? [String: String]), ["code": "https://verein.example.de/ausweis/pruefen/abc"])
        XCTAssertTrue(check.valid)
        XCTAssertEqual(check.name, "Erika Musterfrau")
        XCTAssertEqual(check.detail, "Vollmitglied · Schützenverein Musterstadt")
        XCTAssertEqual(check.membership, 5)
        let gesperrt: CardCheck = try decode(#"{"status":"revoked","status_label":"Gesperrt","kind":"organization"}"#)
        XCTAssertFalse(gesperrt.valid)
        XCTAssertTrue(gesperrt.isOrganization)
        XCTAssertEqual(gesperrt.name, "")
    }

    func testFotosUndBildpfade() async throws {
        let detail: MemberDetail = try decode(#"{"id":5,"photo":{"approved":{"url":"/api/orgs/4/members/5/photo/"},"pending":{"url":"/api/orgs/4/members/5/photo/pending/"}}}"#)
        XCTAssertEqual(detail.photo, "/api/orgs/4/members/5/photo/")
        XCTAssertEqual(detail.pendingPhoto, "/api/orgs/4/members/5/photo/pending/")
        let ohne: MemberDetail = try decode(#"{"id":5,"photo":{"approved":null}}"#)
        XCTAssertNil(ohne.photo)
        let net = FakeTransport([.success(HttpResponse(status: 200, body: Data([1, 2])))])
        let client = verwaltung(net)
        XCTAssertEqual(client.imagePath("/api/orgs/4/members/5/photo/"), "/api/app/v1/admin/u/4/members/5/photo/")
        XCTAssertNil(client.imagePath("/api/orgs/9/members/5/photo/"))
        XCTAssertNil(client.imagePath("https://fremd.example.org/bild"))
        let data = await client.image("/api/orgs/4/members/5/photo/")
        XCTAssertEqual(data, Data([1, 2]))
        XCTAssertEqual(net.seen.first?.headers["Authorization"], "Bearer hpa_erfunden")
        let fremd = await client.image("/api/orgs/9/members/5/photo/")
        XCTAssertNil(fremd)
        XCTAssertEqual(net.seen.count, 1)
    }

    func testRechteFuerFotosUndAusweise() {
        XCTAssertTrue(AdminUnit(id: 1, name: "A", permissions: ["photos.manage"]).canEditPhotos)
        XCTAssertTrue(AdminUnit(id: 1, name: "A", permissions: ["photos.edit"]).canEditPhotos)
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["members.view"]).canEditPhotos)
        XCTAssertTrue(AdminUnit(id: 1, name: "A", permissions: ["members.view"]).canCheckCards)
        XCTAssertFalse(AdminUnit(id: 1, name: "Zug", permissions: ["members.view"], scope: "d", stufen: true).canCheckCards)
    }

    func testSchluesselAblage() throws {
        let key = P256.Signing.PrivateKey()
        let stored = AdminAccess(token: "hpa_erfunden", key: key).stored
        let back = try XCTUnwrap(AdminAccess(stored: stored))
        XCTAssertEqual(back.token, "hpa_erfunden")
        XCTAssertEqual(back.key?.rawRepresentation, key.rawRepresentation)
        XCTAssertNil(AdminAccess(stored: "hpa_erfunden")?.key)
        XCTAssertNil(AdminAccess(stored: "hpd_falsch"))
        XCTAssertNil(AdminAccess(stored: "hpa_erfunden kaputt"))
        XCTAssertNil(AdminAccess(stored: ""))
    }

    func testPausen() {
        XCTAssertFalse(AdminPause.locked(sinceUse: 300))
        XCTAssertTrue(AdminPause.locked(sinceUse: 301))
        XCTAssertFalse(AdminPause.lockedAfterBackground(60))
        XCTAssertTrue(AdminPause.lockedAfterBackground(61))
    }
}
