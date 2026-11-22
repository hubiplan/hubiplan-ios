import HubiplanKern
import SwiftUI

/// Zusatzleistungen, Zusatzfragen, Allergien und Erziehungsberechtigte bei der Anmeldung
/// (HUBIplan A5, F11, F13), wie in der Android-App (`AnmeldungExtras.kt`).
struct ZusatzFelder: View {
    let offer: RegistrationOffer
    /// "person" oder "registration"
    let per: String
    @Binding var value: RegistrationExtras
    var enabled = true
    var minor = false

    var body: some View {
        ForEach(offer.addons(per: per)) { a in
            Picker(a.label, selection: Binding(
                get: { value.addons[a.id] ?? -1 },
                set: { pick in value.addons[a.id] = pick < 0 ? nil : pick }
            )) {
                if !a.required || value.addons[a.id] == nil {
                    Text(a.required ? tr("Bitte wählen") : tr("nicht gewünscht")).tag(-1)
                }
                ForEach(a.choices.filter { $0.isActive && (!$0.full || value.addons[a.id] == $0.id) }) { c in
                    Text(c.label).tag(c.id)
                }
            }
            .disabled(!enabled)
        }
        ForEach(offer.questions(per: per)) { q in
            frage(q)
        }
        if minor { erziehungsberechtigte }
    }

    private func titel(_ q: Question) -> String {
        q.label + (q.required && q.kind != "health" ? "" : " " + tr("(optional)"))
    }

    @ViewBuilder
    private func frage(_ q: Question) -> some View {
        switch q.kind {
        case "health":
            VStack(alignment: .leading, spacing: 4) {
                TextField(titel(q), text: Binding(
                    get: { value.health },
                    set: { value.health = String($0.prefix(500)) }
                ), axis: .vertical)
                .disabled(!enabled)
                Text(tr("Nur für die Planung des Essens; sieht nur die Verwaltung, wird 14 Tage nach der Veranstaltung gelöscht."))
                    .font(.hubi(.footnote)).foregroundStyle(.secondary)
            }
        case "yesno":
            Picker(titel(q), selection: Binding(
                get: { () -> Int in
                    if case .yes(let b) = value.answers[q.id] { return b ? 1 : 0 }
                    return -1
                },
                set: { pick in value.answers[q.id] = pick < 0 ? nil : .yes(pick == 1) }
            )) {
                if value.answers[q.id] == nil { Text(tr("Bitte wählen")).tag(-1) }
                Text(tr("ja")).tag(1)
                Text(tr("nein")).tag(0)
            }
            .disabled(!enabled)
        case "choice":
            Picker(titel(q), selection: Binding(
                get: { () -> String in
                    if case .text(let s) = value.answers[q.id] { return s }
                    return ""
                },
                set: { pick in value.answers[q.id] = pick.isEmpty ? nil : .text(pick) }
            )) {
                Text(tr("Bitte wählen")).tag("")
                ForEach(q.choices, id: \.self) { c in Text(c).tag(c) }
            }
            .disabled(!enabled)
        default:
            TextField(titel(q), text: Binding(
                get: { () -> String in
                    if case .text(let s) = value.answers[q.id] { return s }
                    return ""
                },
                set: { value.answers[q.id] = .text(String($0.prefix(500))) }
            ))
            .weiterFeld()
            .disabled(!enabled)
        }
    }

    private var guardian: Guardian { value.guardians.first ?? Guardian() }

    /// Nur eine erziehungsberechtigte Person in der App, wie in der Android-App
    private func setze(_ change: (inout Guardian) -> Void) {
        var g = guardian
        change(&g)
        value.guardians = [g]
    }

    @ViewBuilder
    private var erziehungsberechtigte: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Erziehungsberechtigte")).font(.hubi(.subheadline).bold())
            Text(tr("Unter 18: Bitte Name, Telefonnummer (während der Veranstaltung erreichbar) und E-Mail angeben; die Anschrift nur, wenn sie abweicht."))
                .font(.hubi(.footnote))
        }
        TextField(tr("Name"), text: Binding(
            get: { guardian.name },
            set: { text in setze { $0.name = String(text.prefix(200)) } }
        ))
        .textContentType(.name)
        .weiterFeld()
        .disabled(!enabled)
        TextField(tr("Telefon"), text: Binding(
            get: { guardian.phone },
            set: { text in setze { $0.phone = String(text.prefix(50)) } }
        ))
        .keyboardType(.phonePad)
        .textContentType(.telephoneNumber)
        .weiterFeld()
        .disabled(!enabled)
        TextField(tr("E-Mail"), text: Binding(
            get: { guardian.email },
            set: { text in setze { $0.email = String(text.prefix(254)) } }
        ))
        .keyboardType(.emailAddress)
        .textContentType(.emailAddress)
        .textInputAutocapitalization(.never)
        .weiterFeld()
        .disabled(!enabled)
        TextField(tr("Anschrift (optional)"), text: Binding(
            get: { guardian.address },
            set: { text in setze { $0.address = String(text.prefix(1000)) } }
        ), axis: .vertical)
        .disabled(!enabled)
    }
}
