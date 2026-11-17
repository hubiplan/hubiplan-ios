import Foundation

/// Inhalt des QR-Codes „App verbinden“: `https://<Instanz>/app/verbinden#code=<Code>`.
/// Auf demselben Telefon öffnet der Knopf „In der HUBIplan-App öffnen“ stattdessen
/// `hubiplan://verbinden?server=<Origin, URL-kodiert>&code=<Code>`.
public struct PairingLink: Equatable, Sendable {
    public let server: String
    public let code: String

    public init(server: String, code: String) {
        self.server = server
        self.code = code
    }

    /// Eigenes Schema der App; die Adresse der Instanz steht im Link, nur HTTPS.
    public static let scheme = "hubiplan"

    public static func parse(_ text: String) -> PairingLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed) else { return nil }
        if parts.scheme == scheme { return parseAppLink(parts) }
        guard parts.scheme == "https", let origin = httpsOrigin(parts) else { return nil }
        guard trimSlashes(parts.percentEncodedPath) == "/app/verbinden" else { return nil }
        guard let fragment = parts.percentEncodedFragment else { return nil }
        guard let entry = fragment.split(separator: "&").first(where: { $0.hasPrefix("code=") }) else { return nil }
        let code = String(entry.dropFirst("code=".count))
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return PairingLink(server: origin, code: code)
    }

    private static func parseAppLink(_ parts: URLComponents) -> PairingLink? {
        guard parts.host == "verbinden", parts.path.isEmpty || parts.path == "/" else { return nil }
        var params: [String: String] = [:]
        for part in (parts.percentEncodedQuery ?? "").split(separator: "&") {
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = pieces.first, !key.isEmpty else { continue }
            let raw = pieces.count > 1 ? String(pieces[1]) : ""
            guard let value = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { return nil }
            params[String(key)] = value
        }
        // Auch hubiplan://verbinden?link=<QR-Adresse, URL-kodiert>: dieselbe Prüfung wie beim QR-Code
        if let inner = params["link"] {
            return inner.hasPrefix("https://") ? parse(inner) : nil
        }
        guard let code = params["code"], !code.isEmpty, !code.contains(where: { $0.isWhitespace }) else { return nil }
        guard let serverText = params["server"], let server = URLComponents(string: serverText) else { return nil }
        guard server.scheme == "https", server.path.isEmpty || server.path == "/" else { return nil }
        guard server.query == nil, server.fragment == nil, server.user == nil, server.password == nil else { return nil }
        guard let origin = httpsOrigin(server) else { return nil }
        return PairingLink(server: origin, code: code)
    }
}

private func trimSlashes(_ path: String) -> String {
    var p = path
    while p.count > 1, p.hasSuffix("/") { p.removeLast() }
    return p
}

/// `https://Host[:Port]`, nur mit Host und gültigem Port (1–65535).
func httpsOrigin(_ parts: URLComponents) -> String? {
    guard let host = parts.host, !host.isEmpty else { return nil }
    guard !host.contains(where: { $0.isWhitespace || $0 == "\\" || $0 == "@" }) else { return nil }
    if let port = parts.port {
        guard (1...65535).contains(port) else { return nil }
        return "https://\(host.lowercased()):\(port)"
    }
    return "https://\(host.lowercased())"
}

/// Anmelden mit Passkey im eingebetteten Browser (`ASWebAuthenticationSession`).
///
/// iOS gibt Passkeys an Apps nur für Adressen heraus, die beim Bauen fest eingetragen sind;
/// selbst betriebene Instanzen gehen so nicht. Die App öffnet deshalb die Seite
/// `/app/anmelden` der Instanz. Dort gilt der Passkey wie auf der Webseite; nach „Verbinden“
/// kommt `hubiplan://verbinden?server=…&code=…` zurück, und die App verbindet sich wie beim
/// QR-Code (docs/app.md in hubiplan).
///
/// Prüfwert (Gesamtaudit 15.11., APP-01): Das Schema `hubiplan` gehört keiner App allein; eine
/// fremde App könnte den Rückruf abfangen. Die App erzeugt deshalb ein Geheimnis
/// (`newVerifier`) und schickt nur dessen Prüfwert (`challenge`, SHA-256 wie PKCE, RFC 7636) mit;
/// den Code löst nur ein, wer das Geheimnis kennt.
public enum BrowserLogin {
    /// Seite zum Anmelden; nil bei ungültiger Adresse.
    public static func url(server input: String, challenge: String? = nil) -> URL? {
        guard let origin = normalizeServer(input) else { return nil }
        guard let challenge else { return URL(string: origin + "/app/anmelden") }
        return URL(string: origin + "/app/anmelden?challenge=" + challenge)
    }

    /// 32 Zufallsbytes, base64url ohne „=“: 43 Zeichen aus A–Z a–z 0–9 - _.
    public static func newVerifier() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return Base64Url.encode(Data(bytes))
    }

    public static func challenge(verifier: String) -> String {
        Base64Url.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Knopf „In der HUBIplan-App öffnen“ ohne Code: `hubiplan://anmelden?server=<Origin>`.
    /// Liefert die Adresse der Instanz (nur HTTPS, ohne Pfad); die App fragt vor dem Öffnen nach.
    public static func parseStart(_ text: String) -> String? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == PairingLink.scheme, parts.host == "anmelden",
              parts.path.isEmpty || parts.path == "/",
              let serverText = parts.queryItems?.first(where: { $0.name == "server" })?.value,
              let server = URLComponents(string: serverText), server.scheme == "https",
              server.path.isEmpty || server.path == "/",
              server.query == nil, server.fragment == nil, server.user == nil, server.password == nil
        else { return nil }
        return httpsOrigin(server)
    }

    /// Rückruf der Seite: nur ein Link zum Verbinden mit genau der aufgerufenen Instanz.
    public static func pairing(callback: URL, server input: String) -> PairingLink? {
        guard let origin = normalizeServer(input),
              let link = PairingLink.parse(callback.absoluteString),
              link.server == origin else { return nil }
        return link
    }
}

/// Eingegebene Serveradresse vereinheitlichen; nur HTTPS.
public func normalizeServer(_ input: String) -> String? {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return nil }
    if !text.contains("://") { text = "https://" + text }
    guard let parts = URLComponents(string: text), parts.scheme == "https" else { return nil }
    return httpsOrigin(parts)
}

/// Vorhandene Web-Wiederherstellung derselben Instanz; keine Anmeldedaten im Link.
public func passwordResetUrl(_ serverInput: String) -> String? {
    normalizeServer(serverInput).map { $0 + "/passwort-vergessen" }
}

/// Pfad aus einer Serverantwort als Adresse auf derselben Instanz.
/// Nur Pfade mit genau einem führenden „/“; ohne Schrägstrich würde aus `https://verein.example.de`
/// und `.boese.example` eine fremde Adresse, „//“ und „\“ wären ebenfalls ein fremder Host.
/// Das Ergebnis muss Schema, Host und Port der Instanz behalten.
public func serverLink(server: String, path: String) -> String? {
    guard path.hasPrefix("/"), !path.hasPrefix("//") else { return nil }
    for scalar in path.unicodeScalars {
        if scalar == "\\" || scalar.properties.isWhitespace || scalar.value < 0x20 || scalar.value == 0x7F {
            return nil
        }
    }
    guard let base = URLComponents(string: server), base.scheme == "https", let origin = httpsOrigin(base) else {
        return nil
    }
    var trimmed = server
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    guard let url = URLComponents(string: trimmed + path), url.scheme == "https" else { return nil }
    guard httpsOrigin(url) == origin, url.user == nil, url.password == nil else { return nil }
    return trimmed + path
}
