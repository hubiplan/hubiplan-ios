import XCTest
@testable import HubiplanKern

/// Meldungs- und Zustandsfarben (UX-Audit 16.11., IOS-11): Text erreicht 4,5 : 1 auf allen
/// Flächen, auf denen die App ihn zeigt, und die Systemfarben Rot, Grün, Orange kommen für
/// Text nicht mehr vor.
final class MeldungsfarbenTests: XCTestCase {
    /// Zellgrund, gruppierter Grund, Abzeichenfläche (hell) und dasselbe dunkel (Apple-Standardwerte)
    private let hell = ["#FFFFFF", "#F2F2F7"]
    private let dunkel = ["#000000", "#1C1C1E", "#2C2C2E"]

    func testMeldungstextAufAllenFlaechen() throws {
        for zustand in Design.Zustand.allCases {
            let h = Design.farben(zustand, dunkel: false)
            let d = Design.farben(zustand, dunkel: true)
            for grund in hell + [h.flaeche] {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(Design.kontrast(h.schrift, grund)), 4.5, "\(zustand) hell auf \(grund)")
            }
            for grund in dunkel + [d.flaeche] {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(Design.kontrast(d.schrift, grund)), 4.5, "\(zustand) dunkel auf \(grund)")
            }
        }
    }

    func testKeineSystemfarbenFuerText() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("App/HUBIplan")
        let verboten = try NSRegularExpression(pattern: #"(foregroundStyle|foregroundColor|tint)\(\s*(Color)?\.(red|green|orange)\b|Color\.(red|green|orange)\b"#)
        var funde: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            for (nummer, zeile) in text.components(separatedBy: "\n").enumerated() where !zeile.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                if verboten.firstMatch(in: zeile, range: NSRange(zeile.startIndex..., in: zeile)) != nil {
                    funde.append("\(name):\(nummer + 1)")
                }
            }
        }
        XCTAssertEqual(funde, [], "Statt .red/.green/.orange: MeldungText oder Color.fehlerText/.gutText/.warnText")
    }
}
