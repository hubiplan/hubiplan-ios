import XCTest
@testable import HubiplanKern

/// UX-Audit 16.11.: Offline-Stand (IOS-24) und ungelesene Mitteilungen (IOS-22), wie Android.
final class OhneNetzTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let eventsJson = #"{"items":[{"key":"12:2026-11-20","event_id":12,"title":"Zugversammlung","starts_at":"2026-11-20T19:00:00+01:00","ends_at":"2026-11-20T21:00:00+01:00","rsvp_enabled":true}]}"#
    private let circularsJson = #"[{"id":17,"subject":"Antreten","sender":"Zug 1","attachments":[{"id":4,"name":"Plan.pdf","size":12}]}]"#

    func testStandWirdVerschluesseltAbgelegtUndGelesen() throws {
        let files = MemoryFiles()
        let secrets = MemoryStore()
        let box = OfflineBox(files: files, secrets: secrets)
        let saved = Date(timeIntervalSince1970: 1_795_000_000)
        box.save(accessId: 3, eventsJson: Data(eventsJson.utf8), circularsJson: Data(circularsJson.utf8), at: saved)

        let raw = try XCTUnwrap(files.read("stand-3.bin"))
        XCTAssertNil(String(data: raw, encoding: .utf8)?.range(of: "Zugversammlung"), "nur verschlüsselt ablegen")

        let snapshot = try XCTUnwrap(box.load(accessId: 3))
        XCTAssertEqual(snapshot.events.map(\.eventId), [12])
        XCTAssertEqual(snapshot.circulars.map(\.id), [17])
        XCTAssertEqual(snapshot.savedAt, saved)
        XCTAssertNil(box.load(accessId: 4))

        box.clear()
        XCTAssertNil(box.load(accessId: 3))
        XCTAssertTrue(files.names().isEmpty)
    }

    func testUnlesbareAntwortWirdNichtAbgelegt() {
        let files = MemoryFiles()
        let box = OfflineBox(files: files, secrets: MemoryStore())
        box.save(accessId: 3, eventsJson: Data("kaputt".utf8), circularsJson: Data(circularsJson.utf8))
        XCTAssertTrue(files.names().isEmpty)
    }

    func testBeimErstenMalIstAllesGelesen() {
        let box = OfflineBox(files: MemoryFiles(), secrets: MemoryStore())
        XCTAssertEqual(box.unread(accessId: 3, ids: [16, 17]), [])
        XCTAssertEqual(box.unread(accessId: 3, ids: [16, 17, 18]), [18])
        box.markRead(accessId: 3, id: 18)
        XCTAssertEqual(box.unread(accessId: 3, ids: [16, 17, 18]), [])
        // Anderer Zugang beginnt wieder „alles gelesen“
        XCTAssertEqual(box.unread(accessId: 9, ids: [1]), [])
    }

    func testGelesenBehaeltDieNeuesten() {
        let many = Set(1...(Gelesen.max + 20))
        let kept = Gelesen.trimmed(many)
        XCTAssertEqual(kept.count, Gelesen.max)
        XCTAssertEqual(kept.first, Gelesen.max + 20)
        XCTAssertFalse(kept.contains(1))
    }

    func testAbrufMitAntwortUndAnhang() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, eventsJson),
            FakeTransport.json(200, circularsJson),
            .success(HttpResponse(status: 200, body: Data("%PDF".utf8))),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let (events, eventsBody) = try await api.eventsWithJson(accessId: 3, from: "2026-11-18", to: "2027-05-18")
        XCTAssertEqual(events.map(\.eventId), [12])
        XCTAssertEqual(String(data: eventsBody, encoding: .utf8), eventsJson)
        let (items, _) = try await api.circularsWithJson(accessId: 3)
        XCTAssertEqual(items.first?.attachments.first?.id, 4)
        let file = try await api.circularAttachment(accessId: 3, circularId: 17, attachmentId: 4)
        XCTAssertEqual(file, Data("%PDF".utf8))
        XCTAssertEqual(net.seen.map(\.url), [
            "\(server)/api/portal/3/events/?from=2026-11-18&to=2027-05-18",
            "\(server)/api/portal/3/circulars/",
            "\(server)/api/portal/3/circulars/17/attachments/4/",
        ])
    }
}

extension OhneNetzTests {
    func testNeuesterStandBeimKaltstart() throws {
        let box = OfflineBox(files: MemoryFiles(), secrets: MemoryStore())
        XCTAssertNil(box.latest())
        box.save(accessId: 3, eventsJson: Data(eventsJson.utf8), circularsJson: Data("[]".utf8), at: Date(timeIntervalSince1970: 1_795_000_000))
        box.save(accessId: 5, eventsJson: Data(#"{"items":[]}"#.utf8), circularsJson: Data(circularsJson.utf8), at: Date(timeIntervalSince1970: 1_795_000_600))
        box.markRead(accessId: 5, id: 17)
        let latest = try XCTUnwrap(box.latest())
        XCTAssertEqual(latest.id, 5)
        XCTAssertEqual(latest.snapshot.circulars.map(\.id), [17])
    }
}
