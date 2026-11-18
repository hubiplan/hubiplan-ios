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
