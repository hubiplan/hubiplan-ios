import XCTest
@testable import HubiplanKern

final class NotenTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let folders = #"{"folders":[{"id":1,"key":"folder-1","kind":"marchbook","name":"Marschbuch","items":[{"arrangement":11,"title":"Gruß an Musterstadt","composer":"E. Beispiel","number":"27","position":2,"scores":[{"id":5,"position":2,"content_type":"application/pdf","url":"/api/portal/3/music/files/5/"},{"id":4,"position":1,"content_type":"image/png","url":"/api/portal/3/music/files/4/"},{"id":6,"notation":"midi","content_type":"audio/midi","url":"/api/portal/3/music/files/6/"}]},{"arrangement":12,"title":"Musterstädter Schützenmarsch","number":"27a","scores":[{"id":7,"notation":"musicxml","content_type":"application/vnd.recordare.musicxml+xml","formats":["pdf","midi"],"url":"/api/portal/3/music/files/7/"}]},{"arrangement":13,"title":"Élan","number":"3","scores":[]},{"kind":"pause","title":"Pause"}]}],"events":[{"key":"rehearsal-9","type":"rehearsal","title":"Probe","starts_at":"2026-12-01T19:30:00+01:00","location":"Vereinsheim","focus":"Weihnachtskonzert","items":[{"arrangement":11,"title":"Gruß an Musterstadt","scores":[{"id":5,"content_type":"application/pdf","url":"/api/portal/3/music/files/5/"}]}]}]}"#

    private func mappen() throws -> [Mappe] {
        try JSONDecoder().decode(ScoreFolders.self, from: Data(folders.utf8)).mappen
    }

    func testMappen() async throws {
        let net = FakeTransport([FakeTransport.json(200, folders)])
        let all = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).scoreFolders(accessId: 3)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/music/folders/")
        XCTAssertEqual(all.fixed.map(\.key), ["folder-1"])
        XCTAssertEqual(all.events.map(\.key), ["rehearsal-9"])
        let book = all.mappen[0]
        XCTAssertEqual(book.kindText, "Marschbuch")
        XCTAssertEqual(book.pieces.count, 3)
        // Ohne Noten für die eigene Stimme spielt das Pult das Stück nicht
        XCTAssertEqual(book.playable.map(\.number), ["27", "27a"])
        // Notenbilder in Spielreihenfolge, das Hörbeispiel gehört nicht dazu
        XCTAssertEqual(book.pieces[0].sheets.map(\.id), [4, 5])
        XCTAssertEqual(book.pieces[0].credit, "E. Beispiel")
        XCTAssertEqual(book.pieces[1].sheets.first?.sheetFormat, "pdf")
        XCTAssertEqual(book.pieces[0].sheets.first?.sheetFormat, "")
        XCTAssertEqual(all.mappen[1].kindText, "Probe")
        XCTAssertEqual(all.mappen[1].note, "Weihnachtskonzert")
        XCTAssertTrue(all.mappen[1].isEvent)
    }

    func testSuche() throws {
        let all = try mappen()
        XCTAssertEqual(NotenSuche.normalize("Grüße, Élan"), "gruesse, elan")
        XCTAssertEqual(NotenSuche.words("Gruß an Musterstadt (27a)"), ["gruss", "an", "musterstadt", "27a"])
        // Nummer genau vor Nummernanfang
        XCTAssertEqual(NotenSuche.suche("27", in: all).map(\.arrangement), [11, 12])
        XCTAssertEqual(NotenSuche.suche("27", in: all).map(\.rang), [0, 1])
        // Titelanfang, Umlaute tolerant, Wortanfänge in beliebiger Reihenfolge
        XCTAssertEqual(NotenSuche.suche("gruss an", in: all).map(\.arrangement), [11])
        XCTAssertEqual(NotenSuche.suche("gruss an", in: all).first?.rang, 2)
        XCTAssertEqual(NotenSuche.suche("schuetz must", in: all).map(\.arrangement), [12])
        XCTAssertEqual(NotenSuche.suche("elan", in: all).map(\.arrangement), [13])
        XCTAssertEqual(NotenSuche.suche("beispiel", in: all).map(\.arrangement), [11])
        // Gleiches Stück in zwei Mappen: ein Treffer mit beiden Stellen
        XCTAssertEqual(NotenSuche.suche("Gruß", in: all).first?.stellen.map(\.mappe.key), ["folder-1", "rehearsal-9"])
        XCTAssertTrue(NotenSuche.suche("pause", in: all).isEmpty)
        XCTAssertTrue(NotenSuche.suche("  ", in: all).isEmpty)
        XCTAssertTrue(NotenSuche.suche("xyz", in: all).isEmpty)
    }

    func testBlaettern() {
        let start = PultStelle(piece: 0, page: 0)
        XCTAssertEqual(Blaettern.vor(start, pages: 2, pieces: 2), PultStelle(piece: 0, page: 1))
        XCTAssertEqual(Blaettern.vor(PultStelle(piece: 0, page: 1), pages: 2, pieces: 2), PultStelle(piece: 1, page: 0))
        XCTAssertNil(Blaettern.vor(PultStelle(piece: 1, page: 0), pages: 1, pieces: 2))
        // Unbekannte Seitenzahl zählt als eine Seite
        XCTAssertEqual(Blaettern.vor(start, pages: 0, pieces: 2), PultStelle(piece: 1, page: 0))
        XCTAssertNil(Blaettern.zurueck(start, previousPages: 0))
        XCTAssertEqual(Blaettern.zurueck(PultStelle(piece: 0, page: 1), previousPages: 0), start)
        XCTAssertEqual(Blaettern.zurueck(PultStelle(piece: 1, page: 0), previousPages: 3), PultStelle(piece: 0, page: 2))
        XCTAssertEqual(Blaettern.zurueck(PultStelle(piece: 1, page: 0), previousPages: 0), start)

        XCTAssertEqual(Blaettern.tippen(x: 10, y: 300, width: 300, height: 600), Blaettern.rueck)
        XCTAssertEqual(Blaettern.tippen(x: 150, y: 300, width: 300, height: 600), Blaettern.mitte)
        XCTAssertEqual(Blaettern.tippen(x: 150, y: 50, width: 300, height: 600), Blaettern.weiter)
        XCTAssertEqual(Blaettern.tippen(x: 250, y: 300, width: 300, height: 600), Blaettern.weiter)
        XCTAssertEqual(Blaettern.tippen(x: 10, y: 10, width: 0, height: 0), 0)
    }

    func testNotendatei() async throws {
        let all = try mappen()
        let net = FakeTransport([FakeTransport.json(200, "%PDF-1.7"), FakeTransport.json(200, "%PDF-1.7")])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        _ = try await api.scoreFile(accessId: 3, file: all[0].pieces[0].sheets[1])
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/music/files/5/")
        // MusicXML kommt als gesetztes PDF
        _ = try await api.scoreFile(accessId: 3, file: all[0].pieces[1].sheets[0])
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/3/music/files/7/?format=pdf")
        XCTAssertNil(net.seen[1].headers["Accept"])

        XCTAssertEqual(Api.scorePath(accessId: 3, path: "/api/portal/3/music/files/5/?x=1", format: ""), "/api/portal/3/music/files/5/")
        for path in ["/api/portal/4/music/files/5/", "/api/portal/3/music/files/", "/api/portal/3/music/files/5/../6/", "https://example.org/api/portal/3/music/files/5/", "/api/portal/3/music/files/abc/"] {
            XCTAssertNil(Api.scorePath(accessId: 3, path: path, format: ""), path)
        }
    }

    func testBereichNoten() throws {
        func access(_ json: String) throws -> PortalAccess { try JSONDecoder().decode(PortalAccess.self, from: Data(json.utf8)) }
        XCTAssertTrue(try access(#"{"id":1,"club_name":"Kapelle","musician":true,"modules":["music","scores"]}"#).hasScores)
        XCTAssertFalse(try access(#"{"id":1,"club_name":"Kapelle","musician":false,"modules":["music","scores"]}"#).hasScores)
        XCTAssertFalse(try access(#"{"id":1,"club_name":"Kapelle","musician":true,"modules":["music"]}"#).hasScores)
        XCTAssertFalse(try access(#"{"id":1,"club_name":"Kapelle","musician":true}"#).hasScores)
    }
}
