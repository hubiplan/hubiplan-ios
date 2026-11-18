import HubiplanKern
import SwiftUI
import UIKit

/// Tastaturführung in Formularen (UX-Audit 16.11., IOS-21, wie AND-09 in der Android-App):
/// Die Eingabetaste springt zum nächsten Feld, über der Tastatur stehen „Weiter“ und „Fertig“
/// (auch bei Zahlentastaturen ohne Eingabetaste), und Wischen über das Formular schließt die
/// Tastatur.
@MainActor
enum Tastatur {
    /// Zum nächsten sichtbaren Eingabefeld springen (von oben nach unten, links vor rechts);
    /// nach dem letzten Feld schließt sich die Tastatur.
    static func weiter() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        let felder = eingabefelder(in: window)
            .filter { $0.window != nil && !$0.isHidden && $0.alpha > 0.01 && $0.isUserInteractionEnabled }
            .map { ($0, $0.convert($0.bounds, to: window)) }
            .sorted { a, b in abs(a.1.minY - b.1.minY) > 4 ? a.1.minY < b.1.minY : a.1.minX < b.1.minX }
            .map(\.0)
        if let i = felder.firstIndex(where: \.isFirstResponder), i + 1 < felder.count {
            felder[i + 1].becomeFirstResponder()
        } else {
            fertig()
        }
    }

    /// Tastatur schließen.
    static func fertig() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static func eingabefelder(in view: UIView) -> [UIView] {
        if let feld = view as? UITextField { return feld.isEnabled ? [feld] : [] }
        if let feld = view as? UITextView { return feld.isEditable ? [feld] : [] }
        return view.subviews.flatMap { eingabefelder(in: $0) }
    }
}

private struct TastaturFuehrung: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button(tr("Weiter")) { Tastatur.weiter() }
                    Spacer()
                    Button(tr("Fertig")) { Tastatur.fertig() }.bold()
                }
            }
    }
}

extension View {
    /// Einmal je Formular: Leiste „Weiter“/„Fertig“ über der Tastatur, Wischen schließt sie.
    func tastaturFuehrung() -> some View {
        modifier(TastaturFuehrung())
    }

    /// Einzeiliges Feld: Eingabetaste „Weiter“ springt zum nächsten Feld.
    func weiterFeld() -> some View {
        submitLabel(.next).onSubmit { Tastatur.weiter() }
    }

    /// Suchfeld: Eingabetaste „Suchen“ schließt die Tastatur, gefiltert wird schon beim Tippen.
    func suchFeld() -> some View {
        submitLabel(.search).onSubmit { Tastatur.fertig() }
    }
}
