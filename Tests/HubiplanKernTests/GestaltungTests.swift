import XCTest
@testable import HubiplanKern

/// Gestaltung „Frisch mobil“: Werte-Datei und Symbolsatz sind dieselben wie in der Android-App
/// (Prüfsummen), und die Werte im Code stimmen mit der Datei überein.
final class GestaltungTests: XCTestCase {
    /// Dieselben Prüfsummen stehen in `DesignWerteTest` der Android-App. Wer eine Datei ändert,
    /// ändert sie in beiden Apps.
    private let werteSumme = "bd5ec229a52c6d716c822c52dc7d5cfcadee166524abfdfd37c504f42a41735c"
    private let symboleSumme = "856e26da5760d165a35744ec1671dbb137f9f74aee396c97f1b803c039299f51"

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func datei(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("Sources/HubiplanKern/Gestaltung/\(name)"))
    }

    private func summe(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func werte() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: datei("werte.json")) as? [String: Any])
    }

    private func zahl(_ werte: [String: Any], _ gruppe: String, _ name: String) throws -> Double {
        let eintrag = try XCTUnwrap(werte[gruppe] as? [String: Any], gruppe)
        return try XCTUnwrap((eintrag[name] as? NSNumber)?.doubleValue, "\(gruppe).\(name)")
    }

    func testDateienWieInDerAndroidApp() throws {
        XCTAssertEqual(summe(try datei("werte.json")), werteSumme)
        XCTAssertEqual(summe(try datei("symbole.json")), symboleSumme)
        // Das Paket liefert dieselbe Datei aus
        XCTAssertEqual(try XCTUnwrap(Symbolsatz.datei), try datei("symbole.json"))
    }

    func testJedesSymbolHatEineForm() throws {
        let namen = Set(Strichsymbol.allCases.map(\.rawValue))
        XCTAssertEqual(namen.count, Strichsymbol.allCases.count)
        XCTAssertEqual(Set(Symbolsatz.alle.keys), namen)
        let roh = try XCTUnwrap(JSONSerialization.jsonObject(with: datei("symbole.json")) as? [String: Any])
        XCTAssertEqual((roh["raster"] as? NSNumber)?.doubleValue, Symbolsatz.raster)
        XCTAssertEqual((roh["strich"] as? NSNumber)?.doubleValue, Symbolsatz.strich)
        let symbole = try XCTUnwrap(roh["symbole"] as? [String: [String: [String]]])
        for (name, eintrag) in symbole {
            let form = try XCTUnwrap(Symbolsatz.alle[name], name)
            // Kein Teilpfad fällt beim Lesen weg
            XCTAssertEqual(form.strich.count, eintrag["strich"]?.count ?? 0, name)
            XCTAssertEqual(form.flaeche.count, eintrag["flaeche"]?.count ?? 0, name)
            XCTAssertFalse(form.strich.isEmpty && form.flaeche.isEmpty, name)
            for befehl in (form.strich + form.flaeche).flatMap({ $0 }) {
                let punkte: [Double]
                switch befehl {
                case let .start(x, y), let .linie(x, y): punkte = [x, y]
                case let .kurve(x1, y1, x2, y2, x, y): punkte = [x1, y1, x2, y2, x, y]
                case .schliessen: punkte = []
                }
                for wert in punkte {
                    XCTAssertTrue((0...Symbolsatz.raster).contains(wert), "\(name): \(wert) außerhalb des Rasters")
                }
            }
        }
    }

    func testPfadeLesen() {
        XCTAssertEqual(Symbolpfad.lesen("M 3 10.5 L 12 3 Z"), [.start(x: 3, y: 10.5), .linie(x: 12, y: 3), .schliessen])
        XCTAssertEqual(
            Symbolpfad.lesen("M 1 2 C 3 4 5 6 7 8"),
            [.start(x: 1, y: 2), .kurve(x1: 3, y1: 4, x2: 5, y2: 6, x: 7, y: 8)]
        )
        XCTAssertNil(Symbolpfad.lesen("L 1 2"))
        XCTAssertNil(Symbolpfad.lesen("M 1"))
        XCTAssertNil(Symbolpfad.lesen("M 1 2 A 3 4"))
        XCTAssertNil(Symbolpfad.lesen("M 1 2 L x 4"))
        XCTAssertNil(Symbolpfad.lesen(""))
    }

    func testWerteImCodeWieInDerDatei() throws {
        let werte = try werte()
        XCTAssertEqual(try zahl(werte, "radius", "klein"), Design.radiusKlein)
        XCTAssertEqual(try zahl(werte, "radius", "normal"), Design.radius)
        XCTAssertEqual(try zahl(werte, "radius", "gross"), Design.radiusGross)
        XCTAssertEqual(try zahl(werte, "radius", "blatt"), Design.radiusBlatt)
        XCTAssertEqual(try zahl(werte, "abstand", "zeile"), Design.Abstand.zeile)
        XCTAssertEqual(try zahl(werte, "abstand", "eng"), Design.Abstand.eng)
        XCTAssertEqual(try zahl(werte, "abstand", "klein"), Design.Abstand.klein)
        XCTAssertEqual(try zahl(werte, "abstand", "mittel"), Design.Abstand.mittel)
        XCTAssertEqual(try zahl(werte, "abstand", "rand"), Design.Abstand.rand)
        XCTAssertEqual(try zahl(werte, "abstand", "gross"), Design.Abstand.gross)
        XCTAssertEqual(try zahl(werte, "ziel", "ios"), Design.ziel)
        XCTAssertEqual(try zahl(werte, "ziel", "zeile"), Design.zeileHoehe)
        XCTAssertEqual(try zahl(werte, "symbol", "kopf"), Design.symbolKopf)
        XCTAssertEqual(try zahl(werte, "symbol", "raster"), Symbolsatz.raster)
        XCTAssertEqual(try zahl(werte, "symbol", "strich"), Symbolsatz.strich)
        XCTAssertEqual(try zahl(werte, "marke", "getoent"), Design.getoent)
        let schrift = try XCTUnwrap(werte["schrift"] as? [String: Any])
        XCTAssertEqual(schrift["familie"] as? String, Design.schriftFamilie)
    }

    func testFarbenWieInDerDatei() throws {
        let werte = try werte()
        let neutral = try XCTUnwrap(werte["neutral"] as? [String: [String: String]])
        for (name, dunkel) in [("hell", false), ("dunkel", true)] {
            let datei = try XCTUnwrap(neutral[name])
            let code = Design.neutral(dunkel: dunkel)
            XCTAssertEqual(code.grund, datei["surface"], name)
            XCTAssertEqual(code.karte, datei[dunkel ? "container" : "containerLowest"], name)
            XCTAssertEqual(code.schrift, datei["onSurface"], name)
            XCTAssertEqual(code.gedaempft, datei["onSurfaceVariant"], name)
            XCTAssertEqual(code.linie, datei["outlineVariant"], name)
            XCTAssertEqual(code.rand, datei["outline"], name)
            XCTAssertEqual(code.platzhalter, datei["containerHigh"], name)
            // Schrift und gedämpfte Schrift bleiben auf Grund und Karte lesbar
            for flaeche in [code.grund, code.karte] {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(Design.kontrast(code.schrift, flaeche)), 7, name)
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(Design.kontrast(code.gedaempft, flaeche)), 4.5, name)
            }
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(Design.kontrast(code.rand, code.grund)), 3, name)
        }
        let zustaende = try XCTUnwrap(werte["zustand"] as? [String: [String: [String: String]]])
        let namen: [(String, Design.Zustand)] = [
            ("gut", .gut), ("hinweis", .hinweis), ("warnung", .warnung), ("fehler", .fehler), ("neutral", .neutral),
        ]
        XCTAssertEqual(Set(zustaende.keys), Set(namen.map(\.0)))
        for (name, zustand) in namen {
            for (stufe, dunkel) in [("hell", false), ("dunkel", true)] {
                let datei = try XCTUnwrap(zustaende[name]?[stufe], "\(name).\(stufe)")
                let code = Design.farben(zustand, dunkel: dunkel)
                XCTAssertEqual(code.schrift, datei["schrift"], "\(name).\(stufe)")
                XCTAssertEqual(code.flaeche, datei["flaeche"], "\(name).\(stufe)")
            }
        }
    }

    func testSchriftLiegtBei() throws {
        let ordner = root.appendingPathComponent("App/HUBIplan/Schrift")
        let schrift = try Data(contentsOf: ordner.appendingPathComponent("Inter.ttf"))
        XCTAssertGreaterThan(schrift.count, 50_000)
        // Die Schrift bleibt klein (verkleinerter Zeichensatz), damit die App nicht wächst
        XCTAssertLessThan(schrift.count, 400_000)
        let lizenz = try String(contentsOf: ordner.appendingPathComponent("Inter-OFL-1.1.txt"), encoding: .utf8)
        XCTAssertTrue(lizenz.contains("SIL Open Font License"))
        let projekt = try String(contentsOf: root.appendingPathComponent("App/project.yml"), encoding: .utf8)
        XCTAssertTrue(projekt.contains("UIAppFonts: [Inter.ttf]"))
    }

    func testZaehler() {
        XCTAssertEqual(Design.zaehlerText(1), "1")
        XCTAssertEqual(Design.zaehlerText(99), "99")
        XCTAssertEqual(Design.zaehlerText(100), "99+")
    }
}
