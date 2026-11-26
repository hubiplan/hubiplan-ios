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
        /// Ein weiteres Konto nutzt dieselbe Instanz: Dort kann noch Ungesendetes liegen. Nur
        /// die Sitzung (Cookies) dieser Instanz löschen, damit die des abgemeldeten Kontos nicht
        /// bleibt (Sicherheitsprüfung 26.11.2026, SEC-04); das andere Konto öffnet den
        /// Standmodus mit seinem Zugang neu.
        case sitzung(String)
        /// Adresse unlesbar: nichts gezielt löschbar.
        case nichts
    }

    /// `server`: Instanz des abgemeldeten Kontos; `uebrige`: Instanzen der verbleibenden Konten.
    public static func webDaten(server: String, uebrige: [String]) -> WebDaten {
        if uebrige.isEmpty { return .alles }
        guard let host = URL(string: server)?.host?.lowercased() else { return .nichts }
        if uebrige.contains(where: { URL(string: $0)?.host?.lowercased() == host }) { return .sitzung(host) }
        return .instanz(host)
    }
}

/// Adresse aus einer Serverantwort, die die App an Safari oder eine andere App gibt
/// (Sicherheitsprüfung 26.11.2026, SEC-06): nur `https` ohne Benutzerangabe, und wenn `hosts`
/// gesetzt ist, nur zu diesen Hosts.
public func safeExternalUrl(_ text: String?, hosts: Set<String>? = nil) -> URL? {
    guard let text, let parts = URLComponents(string: text), parts.scheme == "https",
          parts.user == nil, parts.password == nil, let host = parts.host?.lowercased(), !host.isEmpty,
          !host.contains(where: { $0.isWhitespace || $0 == "\\" || $0 == "@" })
    else { return nil }
    if let hosts, !hosts.contains(host) { return nil }
    return URL(string: text)
}

/// Kartendienste, zu denen der Server Routenlinks liefert.
public enum Kartenlinks {
    public static let osm: Set<String> = ["www.openstreetmap.org", "openstreetmap.org"]
    public static let google: Set<String> = ["www.google.com", "maps.google.com", "google.com"]
}
