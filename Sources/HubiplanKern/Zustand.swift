import Foundation

/// Zustand, der ein Beenden der App durch das System übersteht (UX-Audit 16.11., IOS-25):
/// zuletzt gewählter Reiter und zuletzt gewählter Zugang je Konto, wie in der Android-App
/// (`selectedAccess` am Konto).
public enum Zustand {
    /// Die vier festen Reiter, in beiden Apps gleich (Gestaltung „Frisch mobil“): Start, Termine,
    /// Neues, Ich. Dazu kommt ein fünfter je Rolle ([fuenfterReiter]).
    public static let festeReiter = ["start", "termine", "mitteilungen", "ausweis"]

    /// Wer den fünften Platz der Leiste bekommen kann, in der Reihenfolge der Vorgabe: Verwaltung
    /// vor Noten vor Aufgaben. Nur was dieses Konto überhaupt hat.
    public static func fuenfteReiter(verwaltung: Bool, noten: Bool, aufgaben: Bool) -> [String] {
        var reiter: [String] = []
        if verwaltung { reiter.append("verwaltung") }
        if noten { reiter.append("noten") }
        if aufgaben { reiter.append("aufgaben") }
        return reiter
    }

    /// Der fünfte Reiter: die eigene Wahl aus „Mein Konto“, wenn es sie (noch) gibt, sonst die Vorgabe.
    public static func fuenfterReiter(_ moeglich: [String], wahl: String?) -> String? {
        if let wahl, moeglich.contains(wahl) { return wahl }
        return moeglich.first
    }

    /// Reiter der Leiste: nie mehr als fünf.
    public static func leiste(_ moeglich: [String], wahl: String?) -> [String] {
        festeReiter + (fuenfterReiter(moeglich, wahl: wahl).map { [$0] } ?? [])
    }

    /// Bereiche dieses Kontos, die nicht in der Leiste stehen: „Start“ führt dorthin.
    public static func weitereReiter(_ moeglich: [String], wahl: String?) -> [String] {
        let fuenfter = fuenfterReiter(moeglich, wahl: wahl)
        return moeglich.filter { $0 != fuenfter }
    }

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
