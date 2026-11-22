import XCTest
@testable import HubiplanKern

/// Gestaltung „Frisch mobil“, Etappe U6: Formulare schützen angefangene Eingaben, überall
/// (wie `FormulareTest` der Android-App). Die Oberfläche läuft nur auf macOS; hier wird geprüft,
/// dass kein Formular des Mitgliederbereichs ohne Schutz ist.
final class FormulareTests: XCTestCase {
    private func quelle(_ name: String) throws -> String {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/HUBIplan")
        return try String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)
    }

    func testJedesFormularDerMitgliederFragtVorDemVerwerfen() throws {
        // Eingabeblätter: „Abbrechen“ fragt nach, Herunterwischen ruht
        for blatt in ["AuslagenView.swift", "PinnwandView.swift", "VersammlungenView.swift", "TrainingView.swift"] {
            XCTAssertTrue(try quelle(blatt).contains(".eingabeschutz("), "\(blatt) ohne Eingabeschutz")
        }
        XCTAssertTrue(try quelle("SendenView.swift").contains("interactiveDismissDisabled"))
        // Formulare auf einer Seite: melden angefangene Eingaben, die Seite fragt bei „Zurück“ nach
        let seiten = [
            "BestellungenView.swift", "UmfragenView.swift", "IchAnfragenView.swift", "BeitragsnachweiseView.swift",
        ]
        for seite in seiten {
            let text = try quelle(seite)
            XCTAssertTrue(text.contains(".entwurf("), "\(seite) meldet keine angefangenen Eingaben")
            XCTAssertTrue(text.contains(".zurueckSchutz()"), "\(seite) fragt bei „Zurück“ nicht nach")
        }
        // Die Anmeldung steht im Termin: das Formular meldet, die Terminseite schützt
        XCTAssertTrue(try quelle("TeilnahmeView.swift").contains(".entwurf("))
        XCTAssertTrue(try quelle("TerminDetailView.swift").contains(".zurueckSchutz()"))
    }

    func testDatumUeberDieAuswahlDesSystems() throws {
        // Datum und Uhrzeit kommen aus der Auswahl des Systems, nie als Freitext
        for datei in ["IchAnfragenView.swift", "TrainingView.swift", "VerwaltungTermine.swift"] {
            XCTAssertTrue(try quelle(datei).contains("DatePicker("), "\(datei) ohne Datumsauswahl")
        }
    }
}
