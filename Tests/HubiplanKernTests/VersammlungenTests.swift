import XCTest
@testable import HubiplanKern

final class VersammlungenTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    func testVersammlungen() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"upcoming":[{"id":4,"title":"Jahreshauptversammlung 2027","kind_name":"Jahreshauptversammlung","unit":"Schützenverein Musterstadt","starts_at":"2027-01-15T19:30:00+01:00","location":"Vereinsheim","address":"Musterweg 1","motion_until":"2027-01-01T23:59:00+01:00","motions":[{"id":9,"title":"Neue Fahne","text":"Die alte ist verschlissen.","status":"submitted"},{"id":8,"title":"Beitrag","status":"rejected","reply":"Schon beschlossen."}],"agenda":[{"position":2,"title":"Bericht des Vorstands","number":"2"},{"position":1,"title":"Begrüßung"},{"position":3,"title":"Kasse","level":1,"number":"2.1","description":"mit Aussprache"}]}],"minutes":[{"id":2,"title":"Jahreshauptversammlung 2026","kind_name":"Jahreshauptversammlung","starts_at":"2026-01-16T19:30:00+01:00"}]}"#),
            FakeTransport.json(201, #"[{"id":10,"title":"Mehr Licht","status":"submitted"}]"#),
            FakeTransport.json(200, "{}"),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let list = try await api.myMeetings(accessId: 3)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/meetings/")
        let meeting = try XCTUnwrap(list.upcoming.first)
        XCTAssertEqual(meeting.kindLine, "Jahreshauptversammlung · Schützenverein Musterstadt")
        XCTAssertEqual(meeting.sortedAgenda.map(\.line), ["1. Begrüßung", "2. Bericht des Vorstands", "2.1. Kasse"])
        XCTAssertEqual(meeting.sortedAgenda[2].level, 1)
        XCTAssertTrue(meeting.motionsOpen(now: Zeit.parse("2026-12-31T12:00:00+01:00")!))
        XCTAssertFalse(meeting.motionsOpen(now: Zeit.parse("2027-01-02T00:00:00+01:00")!))
        XCTAssertTrue(meeting.motions[0].withdrawable)
        XCTAssertEqual(meeting.motions[0].statusText, "eingereicht")
        XCTAssertFalse(meeting.motions[1].withdrawable)
        XCTAssertEqual(meeting.motions[1].statusText, "nicht aufgenommen")
        XCTAssertEqual(list.minutes.first?.id, 2)
        XCTAssertFalse(list.isEmpty)

        let motions = try await api.submitMotion(accessId: 3, meetingId: 4, title: "Mehr Licht", text: "Am Schießstand ist es zu dunkel.")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/3/meetings/4/motions/")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[1].body ?? Data()) as? [String: Any])
        XCTAssertEqual(sent["title"] as? String, "Mehr Licht")
        XCTAssertEqual(sent["text"] as? String, "Am Schießstand ist es zu dunkel.")
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(motions.map(\.id), [10])

        try await api.withdrawMotion(accessId: 3, motionId: 10)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/portal/3/meetings/motions/10/withdraw/")

        let none = try JSONDecoder().decode(MyMeetings.self, from: Data("{}".utf8))
        XCTAssertTrue(none.isEmpty)
        let plain = try JSONDecoder().decode(UpcomingMeeting.self, from: Data(#"{"id":1,"title":"Zugversammlung","kind_name":"Zugversammlung"}"#.utf8))
        XCTAssertEqual(plain.kindLine, "")
        XCTAssertFalse(plain.motionsOpen())
    }

    func testDokumente() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"folders":[{"id":1,"name":"Satzung und Ordnungen","documents":[{"id":1,"title":"Satzung","date":"2024-03-01","note":"Fassung 2024","current":{"id":7,"name":"Satzung 2024.pdf","size":120000,"content_type":"application/pdf","url":"/api/portal/3/documents/versions/7/"}},{"id":2,"title":"Entwurf"}]},{"id":2,"name":"Leer","documents":[{"id":3,"title":"Ohne Datei"}]},{"id":3,"name":"Protokolle","department":"Zug 1","documents":[{"id":4,"current":{"id":8,"name":"Protokoll.pdf","url":"/api/portal/3/documents/versions/8/"}}]}]}"#),
            FakeTransport.json(200, "%PDF-1.7"),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let docs = try await api.myDocuments(accessId: 3)
        XCTAssertEqual(docs.count, 2)
        XCTAssertEqual(docs.shown.map(\.heading), ["Satzung und Ordnungen", "Protokolle · Zug 1"])
        XCTAssertEqual(docs.shown[0].shown.map(\.shownTitle), ["Satzung"])
        XCTAssertEqual(docs.shown[0].shown[0].line, "01.03.2024 · Fassung 2024")
        XCTAssertEqual(docs.shown[1].shown[0].shownTitle, "Protokoll.pdf")

        let data = try await api.documentFile(accessId: 3, path: "/api/portal/3/documents/versions/7/")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "%PDF-1.7")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/3/documents/versions/7/")
        XCTAssertNil(net.seen[1].headers["Accept"])
        // Fremde Pfade werden gar nicht erst angefragt
        for path in ["/api/portal/4/documents/versions/7/", "/api/portal/3/documents/versions/7/../../", "https://example.org/x", "/api/portal/3/documents/versions//", "/api/portal/3/documents/versions/7"] {
            do {
                _ = try await api.documentFile(accessId: 3, path: path)
                XCTFail(path)
            } catch {}
        }
        XCTAssertEqual(net.seen.count, 2)
    }

    func testProtokollUndGroesse() async throws {
        let big = String(repeating: "x", count: Api.maxJsonBytes + 10)
        let net = FakeTransport([FakeTransport.json(200, big), FakeTransport.json(404, #"{"detail":"Nicht gefunden."}"#), FakeTransport.json(200, big)])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        // Dateien dürfen größer sein als JSON-Antworten
        let data = try await api.minutesPdf(accessId: 3, meetingId: 2)
        XCTAssertEqual(data.count, Api.maxJsonBytes + 10)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/meetings/2/minutes/")
        do {
            _ = try await api.minutesPdf(accessId: 3, meetingId: 5)
            XCTFail("404 erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 404)
        }
        do {
            _ = try await api.myMeetings(accessId: 3)
            XCTFail("zu groß erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.code, "too_large")
        }
    }

    func testDateiname() {
        XCTAssertEqual(Ansicht.safeName("Satzung 2024.pdf"), "Satzung-2024.pdf")
        XCTAssertEqual(Ansicht.safeName("../../etc/passwd"), "passwd")
        XCTAssertEqual(Ansicht.safeName("C:\\Ordner\\Größe.pdf"), "Gr--e.pdf")
        XCTAssertEqual(Ansicht.safeName("...."), "datei.pdf")
        XCTAssertEqual(Ansicht.safeName(""), "datei.pdf")
        XCTAssertEqual(Ansicht.safeName(String(repeating: "a", count: 200)).count, 80)
    }

    func testModule() throws {
        func access(_ json: String) throws -> PortalAccess { try JSONDecoder().decode(PortalAccess.self, from: Data(json.utf8)) }
        let new = try access(#"{"id":1,"club_name":"Verein","modules":["meetings"],"docs_enabled":true}"#)
        XCTAssertTrue(new.hasMeetings)
        XCTAssertFalse(new.hasDocs)
        let old = try access(#"{"id":1,"club_name":"Verein","docs_enabled":true}"#)
        XCTAssertFalse(old.hasMeetings)
        XCTAssertTrue(old.hasDocs)
    }
}
