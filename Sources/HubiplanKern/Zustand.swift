import Foundation

/// Zustand, der ein Beenden der App durch das System übersteht (UX-Audit 16.11., IOS-25):
/// zuletzt gewählter Reiter und zuletzt gewählter Zugang je Konto, wie in der Android-App
/// (`selectedAccess` am Konto).
public enum Zustand {
    /// Reiter, die es immer gibt; die übrigen nur, wenn ein Zugang sie hat.
    public static let festeReiter = ["termine", "mitteilungen", "ausweis"]

    /// Gespeicherten Reiter nur übernehmen, wenn es ihn gerade gibt; sonst [fallback].
    public static func reiter(_ saved: String?, available: [String], fallback: String) -> String {
        guard let saved, available.contains(saved) else { return fallback }
        return saved
    }

    /// Gespeicherten Zugang nur übernehmen, wenn das Konto ihn noch hat; sonst den ersten.
    public static func zugang(saved: Int?, available: [Int]) -> Int? {
        if let saved, available.contains(saved) { return saved }
        return available.first
    }

    private static func key(account: String) -> String { "zugang-\(account)" }

    /// Zuletzt gewählter Zugang dieses Kontos (nur die Kennung, keine Inhalte).
    public static func gespeicherterZugang(account: String, defaults: UserDefaults = .standard) -> Int? {
        defaults.object(forKey: key(account: account)) as? Int
    }

    public static func merke(zugang id: Int?, account: String, defaults: UserDefaults = .standard) {
        if let id { defaults.set(id, forKey: key(account: account)) } else { defaults.removeObject(forKey: key(account: account)) }
    }
}
