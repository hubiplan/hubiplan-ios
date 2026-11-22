import Foundation

/// Gemeinsamer Symbolsatz der beiden Apps (Gestaltung „Frisch mobil“): Strichsymbole im Raster
/// 24, Strich 1,75, runde Enden. Die Formen stehen in `Gestaltung/symbole.json`; dieselbe Datei
/// liegt in der Android-App, damit Anleitungen für beide gelten. `GestaltungTests` hält Liste
/// und Datei zusammen.
public enum Strichsymbol: String, CaseIterable, Sendable {
    case start, termine, neues, ich, verwaltung, noten, aufgaben
    case ausweis, einchecken
    case kalenderAbo = "kalender-abo"
    case geld, rechnung, nachweis, bestellung, training, wettbewerb, helfer, abwesenheit, belegung
    case versammlung, dokument, ordner
    case meineDaten = "meine-daten"
    case pinnwand, umfrage, mitteilung, firma
    case mitglieder, antrag, jubilaeum, qualifikation, frist, partner, kassenbuch, einlass
    case zuErledigen = "zu-erledigen"
    case plus, suche, kamera, scannen, hilfe, wallet, helligkeit, ort, uhr, telefon, teilen
    case einstellungen, sperre, offline, weiter, zurueck, unten, haken, schliessen, info, warnung, konto
}

/// Ein Teilpfad eines Symbols. Die Datei kennt nur vier Befehle mit absoluten Koordinaten.
public enum Symbolpfad {
    public enum Befehl: Equatable, Sendable {
        case start(x: Double, y: Double)
        case linie(x: Double, y: Double)
        case kurve(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
        case schliessen
    }

    /// Liest „M 3 10.5 L 12 3 C … Z“; nil, wenn etwas anderes darin steht.
    public static func lesen(_ text: String) -> [Befehl]? {
        let teile = text.split(separator: " ").map(String.init)
        var befehle: [Befehl] = []
        var i = 0
        func zahlen(_ anzahl: Int) -> [Double]? {
            guard i + anzahl < teile.count else { return nil }
            var werte: [Double] = []
            for k in 1...anzahl {
                guard let wert = Double(teile[i + k]) else { return nil }
                werte.append(wert)
            }
            return werte
        }
        while i < teile.count {
            switch teile[i] {
            case "M":
                guard let z = zahlen(2) else { return nil }
                befehle.append(.start(x: z[0], y: z[1]))
                i += 3
            case "L":
                guard let z = zahlen(2) else { return nil }
                befehle.append(.linie(x: z[0], y: z[1]))
                i += 3
            case "C":
                guard let z = zahlen(6) else { return nil }
                befehle.append(.kurve(x1: z[0], y1: z[1], x2: z[2], y2: z[3], x: z[4], y: z[5]))
                i += 7
            case "Z":
                befehle.append(.schliessen)
                i += 1
            default:
                return nil
            }
        }
        guard case .start = befehle.first else { return nil }
        return befehle
    }
}

/// Form eines Symbols: Teilpfade, die mit Strich gezeichnet, und (selten) solche, die gefüllt werden.
public struct Symbolform: Equatable, Sendable {
    public let strich: [[Symbolpfad.Befehl]]
    public let flaeche: [[Symbolpfad.Befehl]]

    public init(strich: [[Symbolpfad.Befehl]], flaeche: [[Symbolpfad.Befehl]]) {
        self.strich = strich
        self.flaeche = flaeche
    }
}

public enum Symbolsatz {
    public static let raster = 24.0
    public static let strich = 1.75

    /// Liest `symbole.json`: Name → Form. Unlesbare Teilpfade fallen weg.
    public static func lesen(_ data: Data) -> [String: Symbolform] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let symbole = root["symbole"] as? [String: Any] else { return [:] }
        var formen: [String: Symbolform] = [:]
        for (name, wert) in symbole {
            guard let eintrag = wert as? [String: Any] else { continue }
            let strich = (eintrag["strich"] as? [String] ?? []).compactMap(Symbolpfad.lesen)
            let flaeche = (eintrag["flaeche"] as? [String] ?? []).compactMap(Symbolpfad.lesen)
            formen[name] = Symbolform(strich: strich, flaeche: flaeche)
        }
        return formen
    }

    /// Die Datei aus dem Paket, für Tests und zum Lesen.
    public static var datei: Data? {
        guard let url = Bundle.module.url(forResource: "symbole", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Alle Symbole, einmal gelesen.
    public static let alle: [String: Symbolform] = datei.map(lesen) ?? [:]

    public static func form(_ symbol: Strichsymbol) -> Symbolform? { alle[symbol.rawValue] }
}
