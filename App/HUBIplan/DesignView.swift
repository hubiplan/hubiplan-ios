import SwiftUI
import UIKit
import HubiplanKern

/// Farbe aus `#RRGGBB`; bei ungültiger Angabe die Ersatzfarbe.
private func designFarbe(_ hex: String, sonst: Color) -> Color {
    guard let rgb = Farbe.rgb(hex) else { return sonst }
    return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
}

/// Zustand als kleines Abzeichen (Design „Frisch“): Klartext, wahlweise mit Symbol davor.
struct Abzeichen: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let zustand: Design.Zustand
    var symbol: String?

    init(_ text: String, _ zustand: Design.Zustand, symbol: String? = nil) {
        self.text = text
        self.zustand = zustand
        self.symbol = symbol
    }

    var body: some View {
        let farben = Design.farben(zustand, dunkel: colorScheme == .dark)
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(designFarbe(farben.schrift, sonst: .primary))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Design.radiusKlein)
                .fill(designFarbe(farben.flaeche, sonst: Color(.secondarySystemBackground)))
        )
    }
}

/// Datumskästchen vor einem Termin. Nur Blickfang: Das Datum steht ausgeschrieben im Eintrag,
/// deshalb liest VoiceOver das Kästchen nicht eigens vor.
struct DatumKaestchen: View {
    let iso: String
    var allDay = false
    var gedaempft = false
    /// Wächst mit der Schrift, damit Tag und Monat nicht abgeschnitten werden (IOS-14)
    @ScaledMetric(relativeTo: .headline) private var breite: CGFloat = 48

    var body: some View {
        if let teile = Design.datumKaestchen(iso, allDay: allDay) {
            VStack(spacing: 0) {
                Text(teile.tag).font(.headline.monospacedDigit())
                Text(teile.monat).font(.caption2.weight(.semibold))
            }
            // Geprüftes Farbpaar statt Akzentblau auf 14 % Blau (3,3 : 1, UX-Audit 16.11., IOS-11)
            .foregroundStyle(gedaempft ? Color.secondary : Color.zustand(.hinweis))
            .frame(minWidth: breite)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Design.radius)
                    .fill(gedaempft ? Color(.secondarySystemFill) : Color.flaeche(.hinweis))
            )
            .accessibilityHidden(true)
        }
    }
}

// MARK: Meldungen (UX-Audit 16.11., IOS-02, IOS-03, IOS-11, IOS-12)

extension Color {
    /// Schriftfarbe eines Zustands, hell und dunkel aus `Design.farben` (Kontrast geprüft in
    /// `DesignTests`). Ersetzt `.red`, `.green` und `.orange` für Text: Die Systemfarben
    /// erreichen im Hellmodus nur 2 bis 3,5 : 1.
    static func zustand(_ zustand: Design.Zustand) -> Color {
        Color(UIColor { traits in
            let hex = Design.farben(zustand, dunkel: traits.userInterfaceStyle == .dark).schrift
            guard let rgb = Farbe.rgb(hex) else { return .label }
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }

    /// Flächenfarbe eines Zustands, hell und dunkel.
    static func flaeche(_ zustand: Design.Zustand) -> Color {
        Color(UIColor { traits in
            let hex = Design.farben(zustand, dunkel: traits.userInterfaceStyle == .dark).flaeche
            guard let rgb = Farbe.rgb(hex) else { return .secondarySystemBackground }
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }

    static var fehlerText: Color { zustand(.fehler) }
    static var gutText: Color { zustand(.gut) }
    static var warnText: Color { zustand(.warnung) }
}

/// Ansagen für VoiceOver. Derselbe Text wird innerhalb kurzer Zeit nur einmal gesprochen, auch
/// wenn die Meldung beim Scrollen neu erscheint.
@MainActor
enum Ansage {
    private static var last: (text: String, at: Date)?

    /// `dringend`: auch wiederholen, wenn derselbe Text eben schon gesagt wurde (Fehler, Abstimmung).
    static func sagen(_ text: String, dringend: Bool = false) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let pause: TimeInterval = dringend ? 3 : 30
        if let last, last.text == clean, Date().timeIntervalSince(last.at) < pause { return }
        last = (clean, Date())
        AccessibilityNotification.Announcement(clean).post()
    }
}

/// Erfolgs-, Hinweis- oder Fehlertext mit Symbol in geprüfter Farbe. VoiceOver sagt ihn an,
/// sobald er erscheint oder sich ändert; Erfolg und Fehler geben dazu eine kurze Rückmeldung
/// über die Haptik.
struct MeldungText: View {
    let text: String
    let zustand: Design.Zustand

    init(_ text: String, _ zustand: Design.Zustand = .fehler) {
        self.text = text
        self.zustand = zustand
    }

    private var symbol: String {
        switch zustand {
        case .gut: return "checkmark.circle.fill"
        case .fehler: return "exclamationmark.triangle.fill"
        case .warnung: return "exclamationmark.circle.fill"
        case .hinweis, .neutral: return "info.circle.fill"
        }
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .foregroundStyle(Color.zustand(zustand))
        .onChange(of: text, initial: true) { _, now in
            Ansage.sagen(now, dringend: zustand == .fehler)
        }
        .sensoryFeedback(trigger: text) { _, _ in
            switch zustand {
            case .gut: return .success
            case .fehler: return .error
            default: return nil
            }
        }
    }
}

/// Ladeanzeige mit Text, für VoiceOver beschriftet (IOS-28).
struct Laedt: View {
    var text = tr("Wird geladen …")

    var body: some View {
        ProgressView { Text(text) }
            .accessibilityLabel(text)
    }
}

/// Hinweis über Terminen und Mitteilungen, wenn sie aus dem gespeicherten Stand kommen, weil
/// HUBIplan gerade nicht erreichbar ist (UX-Audit 16.11., IOS-24, wie Android AND-07).
struct OfflineStand: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let since = model.offlineSince {
            Section {
                MeldungText(tr(
                    "Gespeicherter Stand von {time}. Zusagen und Antworten gehen erst wieder mit Verbindung.",
                    ["time": since.formatted(.dateTime.day().month().hour().minute().locale(Texte.locale))]
                ), .hinweis)
                Button(tr("Erneut versuchen")) { Task { await model.refresh() } }
            }
        }
    }
}

/// Knöpfe nebeneinander; bei großer Schrift oder schmalem Bildschirm untereinander, statt sie
/// abzuschneiden oder zu quetschen (UX-Audit 16.11., IOS-14, wie Android AND-13).
struct KnopfReihe<Content: View>: View {
    var spacing: CGFloat?
    private let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content() }
            VStack(alignment: .leading, spacing: 8) { content() }
        }
    }
}
