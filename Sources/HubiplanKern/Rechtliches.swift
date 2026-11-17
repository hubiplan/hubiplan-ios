import Foundation

/// Verweise unter „Über die App“ in „Mein Konto“ (UX-Audit 16.11., IOS-27), wie in der
/// Android-App (`AccountPane.kt`): Konto im Browser, Hilfe, Datenschutzhinweise und Impressum der
/// Einheit, Datenschutzerklärung der App, Quellcode und Lizenzen.
public enum Rechtliches {
    /// Öffentliches Repository der iOS-App
    public static let sourceRepo = "https://github.com/hubiplan/hubiplan-ios"
    /// Datenschutzerklärung des Herausgebers zur App (dieselbe Seite wie für die Android-App)
    public static let appPrivacy = "https://hubiplan.de/datenschutz/"

    /// Quellcode genau dieser Version der App (Tag `v<Version>`, wie bei Android).
    public static func sourceUrl(version: String) -> String {
        let clean = version.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean.allSatisfy({ $0.isNumber || $0 == "." }) else { return sourceRepo }
        return sourceRepo + "/tree/v" + clean
    }

    /// Seite der Instanz; `key` hängt den Schlüssel der Einheit an (`/datenschutz/<Schlüssel>`).
    public static func page(server: String, _ path: String, key: String? = nil) -> URL? {
        var full = path
        if let key, !key.isEmpty,
           let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) {
            full += "/" + safe
        }
        return serverLink(server: server, path: full).flatMap(URL.init(string:))
    }

    public static func myAccount(server: String) -> URL? { page(server: server, "/mein-konto") }
    public static func help(server: String) -> URL? { page(server: server, "/hilfe") }
    public static func privacy(server: String, key: String?) -> URL? { page(server: server, "/datenschutz", key: key) }
    public static func imprint(server: String, key: String?) -> URL? { page(server: server, "/impressum", key: key) }

    /// Erklärung zu „Konto und Daten löschen“ (Text wie in der Android-App, für das iPhone).
    public static func deleteInfo(server: String) -> String {
        let name = server.replacingOccurrences(of: "https://", with: "")
        return [
            tr("Deine Mitgliedsdaten verwaltet dein Verein in seiner HUBIplan-Instanz ({server}), nicht die App.", ["server": name]),
            "• " + tr("Abmelden löscht den Geräteschlüssel dieses Geräts beim Verein und alle Daten dieses Kontos in der App, auch den Kalender „HUBIplan“ und noch nicht gesendete Buchungen und Quittungen der Verwaltung."),
            "• " + tr("Dein Foto kannst du im Browser unter „Mein Konto“ selbst löschen."),
            "• " + tr("Die Löschung deines Zugangs und deiner Mitgliedsdaten beantragst du beim Verein. Wen du ansprichst, steht in seinen Datenschutzhinweisen."),
        ].joined(separator: "\n\n")
    }

    /// Lizenzhinweis der App
    public static func licenseLine(version: String) -> String {
        tr("HUBIplan-App {version} · freie Software unter der GNU AGPL 3.0 oder neuer", ["version": version])
    }
}
