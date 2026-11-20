import XCTest
@testable import HubiplanKern

/// Pinnwand unter „Ich“, gleiche Fälle wie `PinnwandTest` in Android. Alle Daten erfunden.
final class PinnwandTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let list = #"""
    {"notices":[
      {"id":7,"text":"Sommerfest: Aufbau ab 9 Uhr","unit":"","department":null,"from":"Musterverein",
       "author":"Anna Muster","pinned":true,"visible_until":"2099-06-30","created_at":"2099-06-01T08:00:00Z",
       "edited_at":"2099-06-02T08:00:00Z","pushed":true,"version":2,"can_edit":true,"new":true,
       "photos":[{"id":3,"url":"/api/portal/9/pinboard/7/photos/3/","width":800,"height":600}],"unbekannt":1},
      {"id":8,"text":"Probe fällt aus","unit":"Jugend","department":4,"from":"Jugend","author":"",
       "pinned":false,"visible_until":null,"created_at":"2099-05-01T08:00:00Z","edited_at":null,"photos":[]}
    ],
    "targets":[{"department":null,"name":"Musterverein"},{"department":4,"name":"Jugend"}],
    "max_photos":6,"max_text":2000}
    """#

    func testLiestDieListe() throws {
        let l = try JSONDecoder().decode(PinboardList.self, from: Data(list.utf8))
        XCTAssertEqual(l.notices.count, 2)
        let n = l.notices[0]
        XCTAssertTrue(n.pinned)
        XCTAssertTrue(n.isNew)
        XCTAssertTrue(n.canEdit)
        XCTAssertEqual(n.photos.first?.url, "/api/portal/9/pinboard/7/photos/3/")
        XCTAssertEqual(n.line, "Anna Muster · geändert · sichtbar bis 30.06.2099")
        XCTAssertEqual(l.notices[1].line, "")
        XCTAssertNil(l.targets[0].department)
        XCTAssertEqual(l.targets[1].department, 4)
        XCTAssertTrue(l.canWrite)
        XCTAssertEqual(l.newCount, 1)
        XCTAssertEqual(l.summary, "1 neuer Beitrag")
    }

    func testKurzstand() {
        XCTAssertEqual(PinboardList().summary, "Noch keine Beiträge")
        XCTAssertFalse(PinboardList().canWrite)
        Texte.language = "en"
        XCTAssertEqual(PinboardList().summary, "No posts yet")
    }

    func testIchZeigtPinnwandNurMitModul() throws {
        let on = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV","pinboard_enabled":true,"pinboard_new":3}"#.utf8))
        XCTAssertTrue(on.hasPinboard)
        XCTAssertEqual(on.pinboardNew, 3)
        let off = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV"}"#.utf8))
        XCTAssertFalse(off.hasPinboard)
    }

    func testFormularfelder() {
        let f = pinNoticeFields(text: "  Hallo  ", department: 4, pinned: true, push: false)
        XCTAssertEqual(f.map(\.name), ["text", "department", "pinned", "push"])
        XCTAssertEqual(f.map(\.value), ["Hallo", "4", "1", "0"])
        XCTAssertEqual(pinNoticeFields(text: "x", department: nil, pinned: false, push: true).map(\.name), ["text", "pinned", "push"])
    }

    func testFotosUnterPhotos() {
        let form = Multipart(fields: [], files: [(name: "foto-1.jpg", data: Data([1]), type: "image/jpeg")], fileField: "photos", boundary: "grenze")
        var expected = Data("--grenze\r\nContent-Disposition: form-data; name=\"photos\"; filename=\"foto-1.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        expected.append(Data([1]))
        expected.append(Data("\r\n--grenze--\r\n".utf8))
        XCTAssertEqual(form.body, expected)
    }

    func testSchreibenMitSchluesselUndLesenOhneGelesen() async throws {
        let notice = #"{"id":9,"text":"Hallo","from":"Musterverein","version":1}"#
        let net = FakeTransport([
            FakeTransport.json(201, notice),
            FakeTransport.json(400, #"{"text":["Bitte einen Text angeben."]}"#),
            FakeTransport.json(200, #"{"notices":[],"targets":[]}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("t1"))
        let made = try await api.createPinNotice(accessId: 9, text: "Hallo", department: nil, pinned: false, push: true, photos: [Data([0xFF])], key: "k1")
        XCTAssertEqual(made.id, 9)
        XCTAssertEqual(net.seen[0].method, "POST")
        XCTAssertTrue(net.seen[0].url.hasSuffix("/api/portal/9/pinboard/"))
        XCTAssertEqual(net.seen[0].headers["Idempotency-Key"], "k1")
        do {
            _ = try await api.createPinNotice(accessId: 9, text: "", department: nil, pinned: false, push: false, photos: [], key: "k2")
            XCTFail("Feldfehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.message, "Bitte einen Text angeben.")
        }
        _ = try await api.memberPinboard(accessId: 9, seen: false)
        XCTAssertTrue(net.seen[2].url.hasSuffix("/api/portal/9/pinboard/?seen=0"))
    }
}
