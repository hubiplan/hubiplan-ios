import Foundation

/// Sichtschutz (Gesamtaudit 19.11.2026, S-09): Liegt die App nicht vorn, verdeckt sie ihren
/// Inhalt, damit in der App-Übersicht nichts zu lesen ist. Das Mitglied kann das abschalten;
/// der Verwaltungsbereich verdeckt sich unabhängig davon immer selbst. Bildschirmfotos kann
/// eine iOS-App nicht verhindern; die Android-App sperrt zusätzlich diese.
public enum Sichtschutz {
    private static let schluessel = "vorschauErlaubt"

    /// Inhalt verdecken? `aktiv`: Die App liegt vorn und wird bedient.
    public static func verdecken(aktiv: Bool, erlaubt: Bool) -> Bool {
        !aktiv && !erlaubt
    }

    /// Vorschau in der App-Übersicht erlaubt (Einstellung auf diesem Gerät, Vorgabe: nein).
    public static func erlaubt(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: schluessel)
    }

    public static func setze(erlaubt: Bool, defaults: UserDefaults = .standard) {
        defaults.set(erlaubt, forKey: schluessel)
    }

    /// Was nach dem Abmelden aus dem Speicher der eingebetteten Webansicht (Standmodus) zu
    /// löschen ist.
    public enum WebDaten: Equatable {
        /// Kein Konto mehr: alles.
        case alles
        /// Nur die Daten dieser Instanz (Hostname); andere Konten nutzen andere Instanzen.
        case instanz(String)
        /// Ein weiteres Konto nutzt dieselbe Instanz: Dort kann noch Ungesendetes liegen.
        case nichts
    }

    /// `server`: Instanz des abgemeldeten Kontos; `uebrige`: Instanzen der verbleibenden Konten.
    public static func webDaten(server: String, uebrige: [String]) -> WebDaten {
        if uebrige.isEmpty { return .alles }
        guard let host = URL(string: server)?.host?.lowercased() else { return .nichts }
        if uebrige.contains(where: { URL(string: $0)?.host?.lowercased() == host }) { return .nichts }
        return .instanz(host)
    }
}
