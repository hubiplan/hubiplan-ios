import SwiftUI
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
    var gedaempft = false

    var body: some View {
        if let teile = Design.datumKaestchen(iso) {
            VStack(spacing: 0) {
                Text(teile.tag).font(.headline.monospacedDigit())
                Text(teile.monat).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(gedaempft ? Color.secondary : Color.accentColor)
            .frame(width: 48)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Design.radius)
                    .fill(gedaempft ? Color(.secondarySystemFill) : Color.accentColor.opacity(0.14))
            )
            .accessibilityHidden(true)
        }
    }
}
