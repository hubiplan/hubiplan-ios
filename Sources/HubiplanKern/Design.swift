import Foundation

/// Design „Frisch“ (wie die Weboberfläche von HUBIplan und die Android-App): Zustände als
/// Abzeichen in den Zustandsfarben der Weboberfläche, ruhige Rundungen und ein Datumskästchen
/// vor Terminen. Die Werte folgen `frontend/src/theme/theme.css` in HUBIplan.
public enum Design {
    /// Rundungen in Punkten wie in der Weboberfläche (`--radius` 6, `--radius-lg` 8).
    public static let radiusKlein = 4.0
    public static let radius = 6.0
    public static let radiusGross = 8.0
    /// Blätter und Dialoge
    public static let radiusBlatt = 12.0

    /// Abstände wie in der Android-App (`Abstand`) und der Werte-Datei `Gestaltung/werte.json`.
    public enum Abstand {
        public static let zeile = 2.0
        public static let eng = 4.0
        public static let klein = 8.0
        public static let mittel = 12.0
        public static let rand = 16.0
        public static let gross = 24.0
    }

    /// Anteil der Vereinsfarbe in getönten Flächen.
    public static let getoent = 0.11
    /// Mindesthöhe einer antippbaren Zeile und Seitenlänge des Symbolkopfs.
    public static let zeileHoehe = 56.0
    public static let symbolKopf = 36.0
    /// Kleinstes Ziel zum Antippen auf iOS (Punkte).
    public static let ziel = 44.0

    /// Neutrale Flächen, Schrift und Linien wie in der Weboberfläche und der Android-App
    /// (`NEUTRAL_HELL`, `NEUTRAL_DUNKEL`), als `#rrggbb`.
    public struct Neutral: Equatable, Sendable {
        /// Grund der Seite
        public let grund: String
        /// Karten und Felder
        public let karte: String
        public let schrift: String
        public let gedaempft: String
        /// Kartenrand und Trennlinien
        public let linie: String
        /// Feldrand und Symbole (3 : 1 gegen den Grund)
        public let rand: String
        /// Platzhalter beim Laden
        public let platzhalter: String
    }

    public static func neutral(dunkel: Bool) -> Neutral {
        dunkel
            ? Neutral(grund: "#111614", karte: "#1a201d", schrift: "#dfe5e2", gedaempft: "#a3ada8", linie: "#2f3833", rand: "#838d88", platzhalter: "#242b27")
            : Neutral(grund: "#fbfcfb", karte: "#ffffff", schrift: "#121614", gedaempft: "#545e5a", linie: "#dde1de", rand: "#737d79", platzhalter: "#e7eae7")
    }

    /// Schriftfamilie der Werte-Datei.
    public static let schriftFamilie = "Inter"

    /// Beschriftung eines Zählers: ab 100 „99+“.
    public static func zaehlerText(_ anzahl: Int) -> String { anzahl > 99 ? "99+" : String(anzahl) }

    /// Bedeutung eines Abzeichens. Der Text trägt die Bedeutung, die Farbe hilft nur.
    public enum Zustand: CaseIterable, Sendable {
        case gut, hinweis, warnung, fehler, neutral
    }

    /// Schrift- und Flächenfarbe eines Abzeichens als `#RRGGBB`.
    public struct Farben: Equatable, Sendable {
        public let schrift: String
        public let flaeche: String
    }

    /// Zustandsfarben wie in der Weboberfläche (`--color-success`, `-info`, `-warning`, `-error` samt `-bg`).
    public static func farben(_ zustand: Zustand, dunkel: Bool) -> Farben {
        switch zustand {
        case .gut: return dunkel ? Farben(schrift: "#8fd6b0", flaeche: "#15302a") : Farben(schrift: "#1d6b46", flaeche: "#e6f3ee")
        case .hinweis: return dunkel ? Farben(schrift: "#a9c7f2", flaeche: "#18263a") : Farben(schrift: "#1f4f8f", flaeche: "#eef3fb")
        case .warnung: return dunkel ? Farben(schrift: "#f4cf86", flaeche: "#3a2c10") : Farben(schrift: "#7a5200", flaeche: "#fdf1d8")
        case .fehler: return dunkel ? Farben(schrift: "#ffb4ab", flaeche: "#3b1714") : Farben(schrift: "#b3261e", flaeche: "#fbe9e7")
        case .neutral: return dunkel ? Farben(schrift: "#c9d1cd", flaeche: "#2a302d") : Farben(schrift: "#4a5551", flaeche: "#eef1f0")
        }
    }

    /// Zustand der eigenen Rückmeldung zu einem Termin (wie in der Android-App).
    public static func zustand(abgesagt: Bool, antwort: String?) -> Zustand {
        if abgesagt { return .fehler }
        switch antwort {
        case "yes": return .gut
        case "no": return .neutral
        case "maybe": return .hinweis
        default: return .warnung
        }
    }

    /// Kontrast nach WCAG 2.x zwischen zwei Farben (`#RRGGBB`); nil bei ungültiger Angabe.
    public static func kontrast(_ a: String, _ b: String) -> Double? {
        guard let la = helligkeit(a), let lb = helligkeit(b) else { return nil }
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func helligkeit(_ hex: String) -> Double? {
        guard let rgb = Farbe.rgb(hex) else { return nil }
        func kanal(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * kanal(rgb.red) + 0.7152 * kanal(rgb.green) + 0.0722 * kanal(rgb.blue)
    }

    private static let monateDe = ["JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ"]
    private static let monateEn = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// Tag und Monatskürzel für das Datumskästchen („14“, „NOV“); nil bei unlesbarem Zeitpunkt.
    /// Ganztägig zählt der Kalendertag der Verwaltung, unabhängig von der Zeitzone (AND-27).
    public static func datumKaestchen(
        _ iso: String, allDay: Bool = false, timeZone: TimeZone = .current, englisch: Bool = Texte.language == "en"
    ) -> (tag: String, monat: String)? {
        guard let date = Zeit.parse(iso) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = allDay ? Zeit.kalenderZone : timeZone
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let day = parts.day, let month = parts.month, (1...12).contains(month) else { return nil }
        return (String(day), (englisch ? monateEn : monateDe)[month - 1])
    }
}
