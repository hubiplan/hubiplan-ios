import SwiftUI
import UIKit
import HubiplanKern

// Gestaltung „Frisch mobil“: Schrift, Strichsymbole und die Bausteine, aus denen die Seiten
// bestehen (Karte, Abschnittstitel, Zeile, Zähler, Leerzustand, Platzhalter). Werte und Formen
// stehen im Kern (`Design`, `Symbolsatz`) und sind dieselben wie in der Android-App.

// MARK: Schrift

enum Schrift {
    /// PostScript-Name der beiliegenden Schrift (`Schrift/Inter.ttf`, in `UIAppFonts` angemeldet).
    static let name = "InterVariable"
    /// Fehlt die Schrift (etwa in einer Erweiterung), bleibt es bei der Systemschrift.
    static let vorhanden = UIFont(name: name, size: 17) != nil

    /// Grundgröße je Stufe wie die Systemschrift bei Standardgröße; „Dynamischer Text“ vergrößert.
    static func groesse(_ stil: Font.TextStyle) -> CGFloat {
        switch stil {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    /// Titel der Kopfleiste und Beschriftung der Reiter in derselben Schrift.
    static func anwenden() {
        guard vorhanden else { return }
        func uiFont(_ stil: UIFont.TextStyle, _ groesse: CGFloat, _ gewicht: UIFont.Weight) -> UIFont {
            let beschreibung = UIFontDescriptor(fontAttributes: [
                .name: name,
                .traits: [UIFontDescriptor.TraitKey.weight: gewicht],
            ])
            return UIFontMetrics(forTextStyle: stil).scaledFont(for: UIFont(descriptor: beschreibung, size: groesse))
        }
        let kopf = UINavigationBar.appearance()
        kopf.titleTextAttributes = [.font: uiFont(.headline, 17, .semibold)]
        kopf.largeTitleTextAttributes = [.font: uiFont(.largeTitle, 34, .bold)]
    }
}

extension Font {
    /// Schrift der App in der Stufe des Systems; wächst mit „Dynamischer Text“.
    static func hubi(_ stil: Font.TextStyle) -> Font {
        guard Schrift.vorhanden else { return .system(stil) }
        let schrift = Font.custom(Schrift.name, size: Schrift.groesse(stil), relativeTo: stil)
        return stil == .headline ? schrift.weight(.semibold) : schrift
    }
}

// MARK: Farben

extension Color {
    private static func neutral(_ wert: @escaping (Design.Neutral) -> String) -> Color {
        Color(UIColor { traits in
            guard let rgb = Farbe.rgb(wert(Design.neutral(dunkel: traits.userInterfaceStyle == .dark))) else { return .label }
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }

    /// Grund der Seite
    static let hubiGrund = neutral { $0.grund }
    /// Karten und Felder
    static let hubiKarte = neutral { $0.karte }
    /// Kartenrand und Trennlinien
    static let hubiLinie = neutral { $0.linie }
    /// Gedämpfte Schrift
    static let hubiGedaempft = neutral { $0.gedaempft }
    /// Platzhalter beim Laden
    static let hubiPlatzhalter = neutral { $0.platzhalter }
}

// MARK: Strichsymbole

/// Zeichnet ein Symbol des gemeinsamen Satzes in ein Quadrat.
private struct SymbolUmriss: Shape {
    let pfade: [[Symbolpfad.Befehl]]

    func path(in rect: CGRect) -> Path {
        let faktor = min(rect.width, rect.height) / Symbolsatz.raster
        func punkt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * faktor, y: rect.minY + y * faktor)
        }
        var path = Path()
        for befehle in pfade {
            for befehl in befehle {
                switch befehl {
                case let .start(x, y): path.move(to: punkt(x, y))
                case let .linie(x, y): path.addLine(to: punkt(x, y))
                case let .kurve(x1, y1, x2, y2, x, y):
                    path.addCurve(to: punkt(x, y), control1: punkt(x1, y1), control2: punkt(x2, y2))
                case .schliessen: path.closeSubpath()
                }
            }
        }
        return path
    }
}

/// Strichsymbol in der Farbe des umgebenden Textes. Nur Blickfang: Die Bedeutung steht daneben,
/// VoiceOver liest das Symbol nicht eigens vor.
struct SymbolBild: View {
    let symbol: Strichsymbol
    @ScaledMetric private var groesse: CGFloat

    init(_ symbol: Strichsymbol, groesse: CGFloat = 24) {
        self.symbol = symbol
        _groesse = ScaledMetric(wrappedValue: groesse, relativeTo: .body)
    }

    var body: some View {
        let form = Symbolsatz.form(symbol)
        ZStack {
            SymbolUmriss(pfade: form?.strich ?? [])
                .stroke(style: StrokeStyle(lineWidth: Symbolsatz.strich * groesse / Symbolsatz.raster, lineCap: .round, lineJoin: .round))
            SymbolUmriss(pfade: form?.flaeche ?? []).fill()
        }
        .frame(width: groesse, height: groesse)
        .accessibilityHidden(true)
    }
}

/// Symbol auf getönter Fläche vor einer Zeile.
struct SymbolKopf: View {
    let symbol: Strichsymbol
    @ScaledMetric(relativeTo: .body) private var seite: CGFloat = Design.symbolKopf

    init(_ symbol: Strichsymbol) { self.symbol = symbol }

    var body: some View {
        SymbolBild(symbol, groesse: 20)
            .foregroundStyle(Color.accentColor)
            .frame(width: seite, height: seite)
            .background(RoundedRectangle(cornerRadius: Design.radiusGross).fill(Color.accentColor.opacity(Design.getoent)))
    }
}

// MARK: Bausteine

/// Karte: helle Fläche mit feinem Rand, ohne Schatten.
struct Karte<Inhalt: View>: View {
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { inhalt() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.radiusGross).fill(Color.hubiKarte))
            .overlay(RoundedRectangle(cornerRadius: Design.radiusGross).stroke(Color.hubiLinie, lineWidth: 1))
    }
}

/// Überschrift eines Abschnitts, wahlweise mit einer Aktion rechts („Alle“).
struct Abschnittstitel: View {
    let text: String
    var aktion: String?
    var onAktion: (() -> Void)?

    init(_ text: String, aktion: String? = nil, onAktion: (() -> Void)? = nil) {
        self.text = text
        self.aktion = aktion
        self.onAktion = onAktion
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.hubi(.footnote).weight(.semibold))
                .foregroundStyle(Color.hubiGedaempft)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Design.Abstand.klein)
            if let aktion, let onAktion {
                Button(aktion, action: onAktion)
                    .font(.hubi(.footnote).weight(.semibold))
                    .frame(minHeight: Design.ziel)
            }
        }
    }
}

/// Zähler: ab 100 „99+“, bei 0 nichts.
struct Zaehler: View {
    let anzahl: Int

    init(_ anzahl: Int) { self.anzahl = anzahl }

    var body: some View {
        if anzahl > 0 {
            Text(Design.zaehlerText(anzahl))
                .font(.hubi(.caption).weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.zustand(.warnung))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.flaeche(.warnung)))
        }
    }
}

/// Zeile einer Liste: Symbolkopf, Titel, Detail darunter, am Ende Zähler oder Pfeil. Mindestens
/// 56 Punkte hoch. Mit `aktion` ist die ganze Zeile ein Knopf.
struct Zeile: View {
    let titel: String
    var detail: String?
    var symbol: Strichsymbol?
    var anzahl = 0
    var pfeil = true
    var aktion: (() -> Void)?

    var body: some View {
        if let aktion {
            Button(action: aktion) { inhalt }
                .buttonStyle(.plain)
        } else {
            inhalt
        }
    }

    private var inhalt: some View {
        HStack(spacing: Design.Abstand.mittel) {
            if let symbol { SymbolKopf(symbol) }
            VStack(alignment: .leading, spacing: Design.Abstand.zeile) {
                Text(titel).font(.hubi(.body))
                if let detail, !detail.isEmpty {
                    Text(detail).font(.hubi(.footnote)).foregroundStyle(Color.hubiGedaempft)
                }
            }
            Spacer(minLength: Design.Abstand.klein)
            Zaehler(anzahl)
            if pfeil, aktion != nil {
                SymbolBild(.weiter, groesse: 18).foregroundStyle(Color.hubiGedaempft)
            }
        }
        .padding(.horizontal, Design.Abstand.rand)
        .padding(.vertical, Design.Abstand.klein)
        .frame(minHeight: Design.zeileHoehe)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Trennlinie zwischen Zeilen einer Karte, hinter dem Symbolkopf eingerückt.
struct ZeilenTrenner: View {
    var body: some View {
        Rectangle().fill(Color.hubiLinie).frame(height: 1)
            .padding(.leading, Design.Abstand.rand + Design.symbolKopf + Design.Abstand.mittel)
    }
}

/// Leerer Zustand: Symbol, ein Satz, wahlweise ein Knopf für den nächsten Schritt.
struct Leerzustand: View {
    let symbol: Strichsymbol
    let text: String
    var aktion: String?
    var onAktion: (() -> Void)?

    var body: some View {
        VStack(spacing: Design.Abstand.mittel) {
            SymbolBild(symbol, groesse: 40).foregroundStyle(Color.hubiGedaempft)
            Text(text)
                .font(.hubi(.subheadline))
                .foregroundStyle(Color.hubiGedaempft)
                .multilineTextAlignment(.center)
            if let aktion, let onAktion {
                Button(aktion, action: onAktion).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Design.Abstand.gross)
    }
}

/// Platzhalter beim Laden: ruhige Balken statt eines Kreisels; VoiceOver liest „Wird geladen …“.
struct Platzhalter: View {
    var zeilen = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Abstand.mittel) {
            ForEach(0..<zeilen, id: \.self) { nummer in
                HStack(spacing: Design.Abstand.mittel) {
                    RoundedRectangle(cornerRadius: Design.radiusGross).fill(Color.hubiPlatzhalter)
                        .frame(width: Design.symbolKopf, height: Design.symbolKopf)
                    VStack(alignment: .leading, spacing: Design.Abstand.klein) {
                        RoundedRectangle(cornerRadius: Design.radiusKlein).fill(Color.hubiPlatzhalter)
                            .frame(height: 12).frame(maxWidth: nummer % 2 == 0 ? 220 : 160)
                        RoundedRectangle(cornerRadius: Design.radiusKlein).fill(Color.hubiPlatzhalter)
                            .frame(height: 10).frame(maxWidth: 110)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Design.Abstand.rand)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Wird geladen …"))
    }
}

/// Lizenztext der beiliegenden Schrift.
struct SchriftLizenzView: View {
    private var text: String {
        guard let url = Bundle.main.url(forResource: "Inter-OFL-1.1", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "https://openfontlicense.org" }
        return text
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.hubi(.footnote))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(tr("Lizenz der Schrift"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Symbol des gemeinsamen Satzes als Bild, für Stellen, die nur Bilder nehmen (Reiterleiste).
/// Als Vorlage gezeichnet: die Leiste färbt es selbst (gewählt, nicht gewählt).
enum SymbolZeichner {
    static func bild(_ symbol: Strichsymbol, groesse: CGFloat = 25) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: groesse, height: groesse)
        let form = Symbolsatz.form(symbol)
        let bild = UIGraphicsImageRenderer(size: rect.size).image { kontext in
            let cg = kontext.cgContext
            cg.setLineWidth(Symbolsatz.strich * groesse / Symbolsatz.raster)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setFillColor(UIColor.black.cgColor)
            cg.addPath(SymbolUmriss(pfade: form?.strich ?? []).path(in: rect).cgPath)
            cg.strokePath()
            cg.addPath(SymbolUmriss(pfade: form?.flaeche ?? []).path(in: rect).cgPath)
            cg.fillPath()
        }
        return bild.withRenderingMode(.alwaysTemplate)
    }
}

/// Liste und Detail: auf dem iPhone nacheinander, auf dem iPad nebeneinander (wie `ListDetail`
/// der Android-App). `liste` bekommt auf dem iPad die Bindung für `List(selection:)`; die Zeilen
/// bleiben `NavigationLink(value:)` und wählen dort aus, statt zu stapeln.
struct ListeDetail<Wert: Hashable, Liste: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var breite
    @Binding var path: [Wert]
    /// Hinweis rechts, solange nichts gewählt ist
    let leer: String
    @ViewBuilder var liste: (Binding<Wert?>?) -> Liste
    @ViewBuilder var detail: (Wert) -> Detail

    var body: some View {
        if Zweispaltig.gilt(breit: breite == .regular) {
            NavigationSplitView {
                liste(Binding(get: { Zweispaltig.auswahl(path) }, set: { path = Zweispaltig.pfad($0) }))
            } detail: {
                NavigationStack {
                    Group {
                        if let wert = Zweispaltig.auswahl(path) {
                            detail(wert).id(wert)
                        } else {
                            Leerzustand(symbol: .info, text: leer)
                        }
                    }
                    .navigationDestination(for: Wert.self) { detail($0) }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack(path: $path) {
                liste(nil).navigationDestination(for: Wert.self) { detail($0) }
            }
        }
    }
}
