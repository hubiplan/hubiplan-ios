import XCTest

/// Tastaturführung (UX-Audit 16.11., IOS-21, wie AND-09 in der Android-App): Jedes Formular
/// hat die Leiste „Weiter“/„Fertig“ über der Tastatur, einzeilige Felder sagen, was die
/// Eingabetaste tut, und Mitglieder wenden sich an ihren Verein statt an „den Vorstand“.
final class TastaturTests: XCTestCase {
    private func quellen() throws -> [(String, String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("App/HUBIplan")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".swift") }
            .map { ($0, try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8)) }
    }

    func testJedesFormularHatTastaturfuehrung() throws {
        for (name, text) in try quellen() {
            let formulare = text.components(separatedBy: "Form {").count - 1
            let gefuehrt = text.components(separatedBy: ".tastaturFuehrung()").count - 1
            XCTAssertEqual(formulare, gefuehrt, "\(name): \(formulare) Formulare, \(gefuehrt) mit Tastaturführung")
        }
    }

    func testEinzeiligeFelderSagenWasDieEingabetasteTut() throws {
        let feld = try NSRegularExpression(pattern: #"^\s*(TextField|SecureField)\((?!.*axis:)[^\n]*\n(\s*\.[^\n]*\n){0,6}"#, options: [.anchorsMatchLines])
        var ohne: [String] = []
        for (name, text) in try quellen() where name != "Tastatur.swift" {
            let ns = text as NSString
            for treffer in feld.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let stelle = ns.substring(with: treffer.range)
                // Felder in Rückfragen (alert) haben eine eigene Bestätigung
                if stelle.contains("declineText") { continue }
                // Aufruf über mehrere Zeilen (Umfrage-Antwort, mehrzeilig mit axis weiter unten)
                if stelle.split(separator: "\n").first?.hasSuffix("Binding(") == true { continue }
                if !(stelle.contains("submitLabel") || stelle.contains("weiterFeld()") || stelle.contains("suchFeld()")) {
                    ohne.append("\(name): \(stelle.split(separator: "\n").first ?? "")")
                }
            }
        }
        XCTAssertEqual(ohne, [])
    }

    func testVereinStattVorstand() throws {
        let alles = try quellen().map(\.1).joined(separator: "\n")
        XCTAssertFalse(alles.contains("wende dich an den Vorstand"))
        XCTAssertFalse(alles.contains("Nachricht an den Vorstand ("))
    }
}
