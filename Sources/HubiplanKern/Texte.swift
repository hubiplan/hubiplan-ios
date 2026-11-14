import Foundation

/// Texte der App: Deutsch steht im Code, Englisch in `Texte/en.json` (wie in der Android-App).
/// Jeder neue Text braucht gleich seinen englischen Eintrag; `TexteTests` prüft das.
public enum Texte {
    public static let languages = ["de", "en"]

    private static let lock = NSLock()
    private static var current = "de"

    static let english: [String: String] = {
        guard let url = Bundle.module.url(forResource: "en", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }()

    /// Sprache der App: "de" oder "en"; alles andere wird Deutsch.
    public static var language: String {
        get { lock.withLock { current } }
        set { lock.withLock { current = languages.contains(newValue) ? newValue : "de" } }
    }

    /// Sprache aus den bevorzugten Sprachen des Geräts (z. B. "en-GB" → "en").
    public static func pick(preferred: [String]) -> String {
        for entry in preferred {
            let code = String(entry.prefix(2)).lowercased()
            if languages.contains(code) { return code }
        }
        return "de"
    }

    static func text(_ de: String) -> String {
        language == "en" ? (english[de] ?? de) : de
    }
}

/// Text in der Sprache der App; Platzhalter `{name}` werden ersetzt.
public func tr(_ de: String, _ args: [String: Any] = [:]) -> String {
    var s = Texte.text(de)
    for (key, value) in args {
        s = s.replacingOccurrences(of: "{\(key)}", with: "\(value)")
    }
    return s
}

/// Mehrzahl: erst der Text für genau eins, dann der für alle anderen Zahlen; `{n}` ist die Zahl.
public func trn(_ one: String, _ other: String, _ n: Int, _ args: [String: Any] = [:]) -> String {
    var all = args
    all["n"] = n
    return tr(n == 1 ? one : other, all)
}
