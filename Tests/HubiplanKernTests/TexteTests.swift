import XCTest
@testable import HubiplanKern

/// Jeder Text der App hat einen englischen Eintrag, und kein Eintrag ist übrig.
final class TexteTests: XCTestCase {
    override func tearDown() { Texte.language = "de" }

    /// Alle `tr("…")`- und `trn("…", "…")`-Texte aus Kern und App.
    private func usedTexts() throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var found = Set<String>()
        let literal = #""((?:[^"\\]|\\.)*)""#
        let call = try NSRegularExpression(pattern: #"\btrn?\(\s*"# + literal + #"(?:\s*,\s*"# + literal + ")?")
        for folder in ["Sources", "App"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let file = files?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                let whole = NSRange(text.startIndex..., in: text)
                for match in call.matches(in: text, range: whole) {
                    for group in 1...2 {
                        guard let range = Range(match.range(at: group), in: text) else { continue }
                        found.insert(String(text[range]).replacingOccurrences(of: "\\\"", with: "\""))
                    }
                }
            }
        }
        return found
    }

    func testJederTextHatEnglisch() throws {
        let used = try usedTexts()
        XCTAssertGreaterThan(used.count, 10)
        let missing = used.subtracting(Texte.english.keys).sorted()
        XCTAssertEqual(missing, [], "Englisch fehlt in Texte/en.json")
        let unused = Set(Texte.english.keys).subtracting(used).sorted()
        XCTAssertEqual(unused, [], "Einträge ohne Verwendung in Texte/en.json")
    }

    func testPlatzhalterBleibenErhalten() throws {
        let placeholder = try NSRegularExpression(pattern: #"\{[a-z]+\}"#)
        func names(_ s: String) -> [String] {
            placeholder.matches(in: s, range: NSRange(s.startIndex..., in: s))
                .compactMap { Range($0.range, in: s).map { String(s[$0]) } }.sorted()
        }
        for (de, en) in Texte.english {
            XCTAssertEqual(names(de), names(en), de)
            XCTAssertFalse(en.isEmpty, de)
        }
    }

    func testSpracheUndPlatzhalter() {
        XCTAssertEqual(tr("Mit {server} verbinden?", ["server": "https://verein.example.de"]), "Mit https://verein.example.de verbinden?")
        Texte.language = "en"
        XCTAssertEqual(tr("Mit {server} verbinden?", ["server": "https://verein.example.de"]), "Connect to https://verein.example.de?")
        XCTAssertEqual(tr("Termine"), "Events")
        Texte.language = "fr"
        XCTAssertEqual(Texte.language, "de")
        XCTAssertEqual(Texte.pick(preferred: ["fr-FR", "en-GB", "de-DE"]), "en")
        XCTAssertEqual(Texte.pick(preferred: ["de-AT"]), "de")
        XCTAssertEqual(Texte.pick(preferred: ["fr-FR"]), "de")
        XCTAssertEqual(Texte.pick(preferred: []), "de")
    }

    func testFehlertexte() {
        XCTAssertEqual(ApiError(status: 0, code: "offline").text, "Keine Verbindung. Bitte prüfe das Netz und versuche es erneut.")
        XCTAssertEqual(ApiError(status: 400, message: "Der Code ist abgelaufen.").text, "Der Code ist abgelaufen.")
        XCTAssertEqual(ApiError(status: 500).text, "Das hat nicht geklappt (500). Bitte später erneut versuchen.")
        XCTAssertEqual(ApiError(status: 401, code: "device_not_authenticated", message: "x").text, "Dieses Gerät ist abgemeldet. Bitte neu verbinden.")
        Texte.language = "en"
        XCTAssertEqual(ApiError(status: 200, code: "format").text, "The instance's answer could not be read. The app may be too old.")
    }
}
