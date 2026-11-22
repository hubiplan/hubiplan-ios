import HubiplanKern
import SwiftUI

/// Eingabeblatt mit Schutz vor Verlust (UX-Audit 16.11., IOS-09): Sind Felder geändert, lässt
/// sich das Blatt nicht herunterwischen, und „Abbrechen“ fragt erst nach. Ersetzt den eigenen
/// „Abbrechen“-Knopf des Blatts; innerhalb des `NavigationStack` des Blatts anwenden.
private struct Eingabeschutz: ViewModifier {
    let changed: Bool
    let disabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var leave = false

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(changed || disabled)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Abbrechen")) { if changed { leave = true } else { dismiss() } }
                        .disabled(disabled)
                }
            }
            .confirmationDialog(tr("Eingaben verwerfen?"), isPresented: $leave, titleVisibility: .visible) {
                Button(tr("Verwerfen"), role: .destructive) { dismiss() }
                Button(tr("Weiter bearbeiten"), role: .cancel) {}
            } message: {
                Text(tr("Was du in diesem Blatt eingegeben hast, geht verloren."))
            }
    }
}

extension View {
    /// „Abbrechen“ mit Rückfrage, solange [changed] gilt; während [disabled] (z. B. beim Senden)
    /// lässt sich das Blatt gar nicht schließen.
    func eingabeschutz(_ changed: Bool, disabled: Bool = false) -> some View {
        modifier(Eingabeschutz(changed: changed, disabled: disabled))
    }
}

/// Ein Formular meldet der Seite, auf der es steht, ob Eingaben angefangen sind. Mehrere
/// Formulare auf einer Seite zählen zusammen.
private struct EntwurfKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Schutz für Formulare auf einer Seite, die man mit „Zurück“ verlässt (Gestaltung „Frisch
/// mobil“, U6; wie `rememberFormDraft` der Android-App): Meldet ein Formular angefangene
/// Eingaben (`entwurf`), ersetzt ein eigener Knopf „Zurück“ den des Systems und fragt erst nach;
/// die Wischgeste zurück ruht solange. Auf der ersten Seite eines Reiters gibt es kein Zurück,
/// dort ändert sich nichts.
private struct ZurueckSchutz: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @State private var changed = false
    @State private var leave = false

    func body(content: Content) -> some View {
        let aktiv = changed && isPresented
        content
            .onPreferenceChange(EntwurfKey.self) { changed = $0 }
            .navigationBarBackButtonHidden(aktiv)
            .toolbar {
                if aktiv {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            leave = true
                        } label: {
                            Label(tr("Zurück"), systemImage: "chevron.backward")
                        }
                    }
                }
            }
            .confirmationDialog(tr("Eingaben verwerfen?"), isPresented: $leave, titleVisibility: .visible) {
                Button(tr("Verwerfen"), role: .destructive) { dismiss() }
                Button(tr("Weiter bearbeiten"), role: .cancel) {}
            } message: {
                Text(tr("Was du in diesem Formular eingegeben hast, geht verloren."))
            }
    }
}

extension View {
    /// Formular: meldet der Seite angefangene Eingaben.
    func entwurf(_ changed: Bool) -> some View {
        preference(key: EntwurfKey.self, value: changed)
    }

    /// Seite: „Zurück“ mit Rückfrage, solange ein Formular darauf angefangene Eingaben meldet.
    func zurueckSchutz() -> some View {
        modifier(ZurueckSchutz())
    }
}
