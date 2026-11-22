/// Liste und Detail nebeneinander auf breiten Geräten (iPad), wie `ListDetail` der Android-App:
/// auf schmalen Bildschirmen nacheinander, auf breiten bleibt die Liste links stehen.
public enum Zweispaltig {
    /// Nebeneinander nur bei breiter Darstellung (iPad im Vollbild oder in breiter Teilung).
    public static func gilt(breit: Bool) -> Bool { breit }

    /// Was rechts steht: das zuerst geöffnete Element des Pfads; nil zeigt den Hinweis „… auswählen“.
    public static func auswahl<Wert>(_ pfad: [Wert]) -> Wert? { pfad.first }

    /// Eine Auswahl in der Liste ersetzt, was rechts steht; ohne Auswahl ist rechts leer.
    public static func pfad<Wert>(_ auswahl: Wert?) -> [Wert] { auswahl.map { [$0] } ?? [] }
}
