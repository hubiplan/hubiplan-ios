import XCTest
@testable import HubiplanKern

/// Kacheln der Übersicht (hubiplan backend/hometiles), gleiche Fälle wie `KachelnTest` in Android.
/// Alle Daten erfunden.
final class KachelnTests: XCTestCase {
    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let text = #"""
    {"scope":"p9","tiles":[
      {"key":"umfragen","title":"Offene Umfragen","description":"Umfragen, die noch auf deine Antwort warten",
       "state":"auto","urgent":true,"shown":true,
       "content":{"figures":[],"rows":[{"title":"Sommerfest: Wer hilft mit?","detail":"bis Sa. 27.06. 18:00",
         "link":"/mein-bereich/umfragen","tone":"warn"}],"text":"","link":"/mein-bereich/umfragen",
         "link_label":"Zu den Umfragen","reason":"Eine Umfrage wartet auf deine Antwort."}},
      {"key":"pinnwand","title":"Pinnwand","description":"Neue Beiträge auf der Pinnwand",
       "state":"auto","urgent":false,"shown":false,
       "content":{"figures":[{"label":"Neue Beiträge","value":"0","tone":null}],"rows":[],"text":"",
         "link":"/mein-bereich/pinnwand","link_label":"Zur Pinnwand","reason":""}},
      {"key":"meine-anmeldungen","title":"Meine Anmeldungen","state":"off","urgent":false,"shown":false,
       "content":null, "neu_in_spaeterer_fassung": 1}
    ]}
    """#

    func testAntwortLesen() throws {
        let data = try JSONDecoder().decode(HomeTiles.self, from: Data(text.utf8))
        XCTAssertEqual(data.tiles.count, 3)
        // Nur Kacheln mit Anlass oder „immer“ erscheinen
        XCTAssertEqual(data.visible.map(\.key), ["umfragen"])
        let umfragen = try XCTUnwrap(data.tiles[0].content)
        XCTAssertEqual(umfragen.reason, "Eine Umfrage wartet auf deine Antwort.")
        XCTAssertEqual(umfragen.rows.first?.tone, "warn")
        XCTAssertEqual(umfragen.linkLabel, "Zu den Umfragen")
        XCTAssertEqual(data.tiles[1].content?.figures.first?.value, "0")
        XCTAssertEqual(data.tiles[2].state, .off)
        XCTAssertNil(data.tiles[2].content)
    }

    func testAuswahlBeschriftet() {
        XCTAssertEqual(TileState.allCases.map(\.label), ["bei Anlass", "immer", "nie"])
        Texte.language = "en"
        XCTAssertEqual(TileState.allCases.map(\.label), ["when relevant", "always", "never"])
    }

    func testUnbekannterZustandIstBeiAnlass() throws {
        let tile = try JSONDecoder().decode(HomeTile.self, from: Data(#"{"key":"x","state":"vielleicht"}"#.utf8))
        XCTAssertEqual(tile.state, .auto)
        XCTAssertFalse(tile.shown)
    }
}
