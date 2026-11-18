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
        let szenen: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window: UIWindow = szenen.compactMap({ $0.keyWindow }).first else { return }
        let sichtbar: [UIView] = eingabefelder(in: window).filter { (feld: UIView) -> Bool in
            feld.window != nil && !feld.isHidden && feld.alpha > 0.01 && feld.isUserInteractionEnabled
        }
        let felder: [UIView] = sichtbar.sorted { (a: UIView, b: UIView) -> Bool in
            let ra: CGRect = a.convert(a.bounds, to: window)
            let rb: CGRect = b.convert(b.bounds, to: window)
            if abs(ra.minY - rb.minY) > 4 { return ra.minY < rb.minY }
            return ra.minX < rb.minX
        }
        if let i = felder.firstIndex(where: { (feld: UIView) -> Bool in feld.isFirstResponder }), i + 1 < felder.count {
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
