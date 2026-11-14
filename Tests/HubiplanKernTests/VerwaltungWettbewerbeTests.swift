import XCTest
@testable import HubiplanKern

final class VerwaltungWettbewerbeTests: XCTestCase {
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

    func testRechteModulUndBereich() {
        let mit = AdminUnit(id: 1, name: "A", permissions: ["results.edit"], stufen: true, modules: ["competitions"])
        XCTAssertEqual(mit.sections, [.tasks, .competitions])
        XCTAssertTrue(AdminUnit(id: 1, name: "A", permissions: ["competitions.manage"], modules: ["competitions"]).showsCompetitions)
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["results.edit"], stufen: true).showsCompetitions)
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["competitions.view"], stufen: true, modules: ["competitions"]).showsCompetitions)
        XCTAssertFalse(AdminUnit(id: 9, name: "Zug", permissions: ["results.edit"], scope: "d", stufen: true, modules: ["competitions"]).showsCompetitions)
    }

    func testOffeneWettbewerbeHeuteZuerst() throws {
        let all: [AdminCompetition] = try decode(#"[{"id":1,"title":"Alt","date":"2026-10-01","status":"offen"},{"id":2,"title":"Fertig","date":"2026-11-14","status":"endgueltig"},{"id":3,"title":"Später","date":"2026-12-06","status":"offen","form":"vogel","location":"Schießstand","starter_count":23},{"id":4,"title":"Heute","date":"2026-11-14","status":"laufend","location":" ","starter_count":1},{"id":5,"title":"Fremd","date":"2026-11-14","own":false},{"id":6,"title":"Älter","date":"2026-09-01"}]"#)
        let open = AdminCompetition.open(all, today: "2026-11-14")
        XCTAssertEqual(open.map(\.id), [4, 3, 1, 6])
        XCTAssertEqual(open[0].line, "14.11.2026 · 1 Starter")
        XCTAssertEqual(open[1].line, "06.12.2026 · Schießstand · Vogelschießen · 23 Starter")
        XCTAssertEqual(open[2].line, "01.10.2026")
    }

    func testStandLink() {
        XCTAssertEqual(StandLink.url(server: "https://verein.example.de/", token: "abc"), "https://verein.example.de/stand/zugang/abc")
        let link = StandLink.parse(" https://Verein.Example.de/stand/zugang/abcDEF0123456789_-/ ")
        XCTAssertEqual(link, StandLink(server: "https://verein.example.de", token: "abcDEF0123456789_-"))
        XCTAssertEqual(link?.url, "https://verein.example.de/stand/zugang/abcDEF0123456789_-")
        XCTAssertEqual(StandLink.parse("https://verein.example.de:8443/stand/zugang/abcdefghijklmnop")?.server, "https://verein.example.de:8443")
        XCTAssertNil(StandLink.parse("http://verein.example.de/stand/zugang/abcdefghijklmnop"))
        XCTAssertNil(StandLink.parse("https://verein.example.de/stand/zugang/kurz"))
        XCTAssertNil(StandLink.parse("https://verein.example.de/stand/zugang/abcdefghijklmnop?x=1"))
        XCTAssertNil(StandLink.parse("https://verein.example.de/stand/zugang/abcdefgh/ijklmnop"))
        XCTAssertNil(StandLink.parse("https://verein.example.de/andere/abcdefghijklmnop"))
        XCTAssertNil(StandLink.parse("https://nutzer@verein.example.de/stand/zugang/abcdefghijklmnop"))
        XCTAssertNil(StandLink.parse("https://verein.example.de/stand/zugang/abcdefghijkl%2Fmnop"))
        XCTAssertNil(StandLink.parse("kein link"))
    }

    func testNurDieEigeneInstanz() {
        XCTAssertTrue(StandLink.sameInstance(server: server, url: "https://verein.example.de/stand/x"))
        XCTAssertTrue(StandLink.sameInstance(server: server, url: "https://VEREIN.example.de:443/api/"))
        XCTAssertFalse(StandLink.sameInstance(server: server, url: "http://verein.example.de/stand/x"))
        XCTAssertFalse(StandLink.sameInstance(server: server, url: "https://verein.example.de:8443/stand/x"))
        XCTAssertFalse(StandLink.sameInstance(server: server, url: "https://verein.example.de.boese.example/stand/x"))
        XCTAssertFalse(StandLink.sameInstance(server: server, url: "https://boese.example/?u=https://verein.example.de/"))
        XCTAssertFalse(StandLink.sameInstance(server: server, url: "about:blank"))
        XCTAssertFalse(StandLink.sameInstance(server: server, url: ""))
    }

    func testStandzugaengeMerkenBisZumAblauf() throws {
        let store = MemoryStore()
        let stand = StandStore(store: store)
        let unit = AdminUnit(id: 4, name: "Verein")
        let zug = AdminUnit(id: 4, name: "Zug", scope: "d")
        let now = try XCTUnwrap(Zeit.parse("2026-11-14T12:00:00+01:00"))
        let heute: StandAccess = try decode(#"{"id":1,"label":"App","expires_at":"2026-11-14T23:59:59+01:00","token":"abcdefghijklmnop"}"#)
        let morgen: StandAccess = try decode(#"{"id":2,"expires_at":"2026-11-15T23:59:59+01:00","token":"qrstuvwxyz012345"}"#)
        let ohne: StandAccess = try decode(#"{"id":3,"expires_at":"2026-11-15T23:59:59+01:00"}"#)
        XCTAssertTrue(heute.valid(now: now))
        XCTAssertFalse(heute.valid(now: now.addingTimeInterval(13 * 3600)))
        XCTAssertFalse(try (decode(#"{"id":4,"expires_at":"irgendwann"}"#) as StandAccess).valid(now: now))

        XCTAssertNil(stand.get(unit: unit, competition: 7, now: now))
        stand.put(unit: unit, competition: 7, access: heute, now: now)
        stand.put(unit: unit, competition: 8, access: morgen, now: now)
        stand.put(unit: unit, competition: 9, access: ohne, now: now)
        XCTAssertEqual(stand.get(unit: unit, competition: 7, now: now), heute)
        XCTAssertEqual(stand.get(unit: unit, competition: 8, now: now)?.token, "qrstuvwxyz012345")
        // Ohne Schlüssel nichts merken; Untereinheit mit derselben Nummer ist ein anderer Platz
        XCTAssertNil(stand.get(unit: unit, competition: 9, now: now))
        XCTAssertNil(stand.get(unit: zug, competition: 7, now: now))
        // Abgelaufene verschwinden auch aus der Ablage
        let spaeter = now.addingTimeInterval(13 * 3600)
        XCTAssertNil(stand.get(unit: unit, competition: 7, now: spaeter))
        XCTAssertFalse(store.read(StandStore.key)?.contains("abcdefghijklmnop") ?? false)
        XCTAssertNotNil(stand.get(unit: unit, competition: 8, now: spaeter))
        stand.remove(unit: unit, competition: 8, now: spaeter)
        XCTAssertNil(store.read(StandStore.key))
        stand.put(unit: unit, competition: 8, access: morgen, now: now)
        stand.clear()
        XCTAssertNil(stand.get(unit: unit, competition: 8, now: now))
        // Unlesbare Ablage gilt als leer
        store.write(StandStore.key, "kaputt")
        XCTAssertNil(stand.get(unit: unit, competition: 8, now: now))
    }

    func testWettbewerbeUndStandzugangAnlegenUndBeenden() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":1,"title":"Königsschießen","date":"2026-11-14","status":"laufend"}]"#),
            FakeTransport.json(200, #"[{"id":1,"label":"App","active":true},{"id":2,"label":"Alt","active":false}]"#),
            FakeTransport.json(201, #"{"id":3,"label":"App (iPhone)","expires_at":"2026-11-14T23:59:59+01:00","active":true,"token":"abcdefghijklmnop"}"#),
            .success(HttpResponse(status: 204, body: Data())),
            FakeTransport.json(403, #"{"detail":"Dafür fehlt dir das Recht."}"#),
        ])
        let client = verwaltung(net)
        let list = try await client.competitions()
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/competitions/")
        XCTAssertEqual(list.map(\.title), ["Königsschießen"])
        let active = try await client.standAccesses(competition: 1)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/4/competitions/1/stand-access/")
        XCTAssertEqual(active.map(\.id), [1])
        let created = try await client.createStandAccess(competition: 1, label: String(repeating: "a", count: 150))
        XCTAssertEqual(net.seen[2].method, "POST")
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/4/competitions/1/stand-access/")
        XCTAssertEqual(String(decoding: try XCTUnwrap(net.seen[2].body), as: UTF8.self), #"{"label":"\#(String(repeating: "a", count: 100))"}"#)
        XCTAssertEqual(created.token, "abcdefghijklmnop")
        try await client.endStandAccess(competition: 1, access: 3)
        XCTAssertEqual(net.seen[3].method, "DELETE")
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/app/v1/admin/u/4/competitions/1/stand-access/3/")
        do {
            try await client.endStandAccess(competition: 1, access: 1)
            XCTFail("403 erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.status, 403)
        }
    }
}
