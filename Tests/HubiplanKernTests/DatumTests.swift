import XCTest
@testable import HubiplanKern

/// Ein Datum sieht überall gleich aus: „20.11.2026“, Englisch „20/11/2026“ (wie in der
/// Android-App), Uhrzeiten immer mit 24 Stunden.
final class DatumTests: XCTestCase {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    func testDatumWiePlainDate() throws {
        let abend = try XCTUnwrap(Zeit.parse("2026-11-20T18:30:00+01:00"))
        XCTAssertEqual(Zeit.datum(abend, timeZone: berlin), "20.11.2026")
        XCTAssertEqual(Zeit.datum(abend, timeZone: berlin), Zeit.plainDate("2026-11-20"))
        XCTAssertEqual(Zeit.datumUhrzeit(abend, timeZone: berlin), "20.11.2026, 18:30")
    }

    func testEnglischBritischUndVierundzwanzigStunden() throws {
        Texte.language = "en"
        let abend = try XCTUnwrap(Zeit.parse("2026-11-20T18:05:00+01:00"))
        XCTAssertEqual(Zeit.datum(abend, timeZone: berlin), "20/11/2026")
        XCTAssertEqual(Zeit.datumUhrzeit(abend, timeZone: berlin), "20/11/2026, 18:05")
    }

    func testTagNachZeitzone() throws {
        // Kurz nach Mitternacht in Berlin ist in UTC noch der Vortag
        let nacht = try XCTUnwrap(Zeit.parse("2026-11-21T00:10:00+01:00"))
        XCTAssertEqual(Zeit.datum(nacht, timeZone: berlin), "21.11.2026")
        XCTAssertEqual(Zeit.datum(nacht, timeZone: TimeZone(identifier: "UTC")!), "20.11.2026")
    }
}
