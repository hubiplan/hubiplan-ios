import XCTest
@testable import HubiplanKern

/// Notenpult live: Vorgabe der Leitung lesen, senden und das Stück finden (wie Android). Erfundene Daten.
final class NotenLiveTests: XCTestCase {
    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let mappen = #"{"folders":[{"id":3,"key":"folder-3","can_lead":true,"kind":"marchbook","name":"Marschbuch","items":[{"arrangement":11,"title":"Alte Kameraden","number":"27","scores":[{"id":1,"kind":"sheet","content_type":"application/pdf","url":"/api/portal/1/music/files/1/"}]},{"arrangement":12,"title":"Ohne Noten","number":"28"}]}],"events":[{"key":"rehearsal-9","live_key":"rehearsal-9","type":"rehearsal","title":"Probe","items":[{"arrangement":13,"title":"Gruß an Musterstadt","scores":[{"id":2,"kind":"sheet","content_type":"application/pdf","url":"/api/portal/1/music/files/2/"}]}]},{"key":"performance-4","type":"performance","title":"Schützenfest"}]}"#

    func testMappenKennenLiveZiel() throws {
        let list = try JSONDecoder().decode(ScoreFolders.self, from: Data(mappen.utf8))
        XCTAssertEqual(list.mappen.map(\.liveKey), ["folder-3", "rehearsal-9", "performance-4"])
        XCTAssertEqual(list.mappen.map(\.canLead), [true, false, false])
    }

    func testZieleUndNeueVorgaben() throws {
        XCTAssertTrue(NotenLive.targetOk("folder-3"))
        XCTAssertTrue(NotenLive.targetOk("rehearsal-123456789012"))
        XCTAssertFalse(NotenLive.targetOk("rehearsal-1234567890123"))
        XCTAssertFalse(NotenLive.targetOk("member-3"))
        XCTAssertFalse(NotenLive.targetOk("folder-"))
        XCTAssertFalse(NotenLive.targetOk("folder-3/../x"))
        let cue = try JSONDecoder().decode(LiveCue.self, from: Data(#"{"seq":1763200000123,"arrangement":11,"number":"27","title":"Alte Kameraden","sender":"Dirigent"}"#.utf8))
        XCTAssertEqual(cue.headline, "Dirigent: Nr. 27 · Alte Kameraden")
        XCTAssertFalse(NotenLive.isNew(cue, lastSeq: nil, ownSeq: 0), "beim Öffnen nur merken")
        XCTAssertTrue(NotenLive.isNew(cue, lastSeq: 0, ownSeq: 0))
        XCTAssertFalse(NotenLive.isNew(cue, lastSeq: 1763200000123, ownSeq: 0))
        XCTAssertFalse(NotenLive.isNew(cue, lastSeq: 0, ownSeq: 1763200000123), "eigene Vorgabe")
        XCTAssertFalse(NotenLive.isNew(nil, lastSeq: 0, ownSeq: 0))
    }

    func testStueckFinden() throws {
        let list = try JSONDecoder().decode(ScoreFolders.self, from: Data(mappen.utf8))
        let book = list.mappen[0], probe = list.mappen[1]
        XCTAssertEqual(NotenLive.place(of: 11, current: book, all: list.mappen)?.piece, 0)
        let other = try XCTUnwrap(NotenLive.place(of: 13, current: book, all: list.mappen))
        XCTAssertEqual(other.mappe.key, "rehearsal-9")
        XCTAssertEqual(other.piece, 0)
        XCTAssertNil(NotenLive.place(of: 12, current: book, all: list.mappen), "ohne Noten nicht spielbar")
        XCTAssertNil(NotenLive.place(of: 99, current: probe, all: list.mappen))
    }

    func testAbfragenUndSenden() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"cue":null,"can_send":true,"poll_seconds":1}"#),
            FakeTransport.json(201, #"{"cue":{"seq":5,"arrangement":11,"number":"27","title":"Alte Kameraden","sender":"Erika M."}}"#),
        ])
        let api = Api(server: "https://verein.example.de", transport: net, tokens: FakeTokens("hpd_a"))
        let state = try await api.live(accessId: 1, target: "folder-3")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/1/music/live/folder-3/")
        XCTAssertTrue(state.canSend)
        XCTAssertEqual(state.pause, 2)
        let cue = try await api.sendLive(accessId: 1, target: "folder-3", arrangement: 11, number: "27")
        XCTAssertEqual(cue?.seq, 5)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[1].body ?? Data()) as? [String: Any])
        XCTAssertEqual(sent["arrangement"] as? Int, 11)
        XCTAssertEqual(sent["number"] as? String, "27")
        do {
            _ = try await api.live(accessId: 1, target: "../admin")
            XCTFail("unbekanntes Ziel")
        } catch let error as ApiError {
            XCTAssertEqual(error.code, "format")
        }
        XCTAssertEqual(net.seen.count, 2)
    }
}
