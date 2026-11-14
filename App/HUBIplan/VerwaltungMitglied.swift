import HubiplanKern
import SwiftUI

/// Vorgang an einem Mitglied, den das Blatt `VorgangBlatt` abfragt.
enum MitgliedVorgang: String, Identifiable {
    case art, untereinheit, austritt, wiedereintritt, beitragSelbst, beitragFremd

    var id: String { rawValue }
}

/// Blatt für einen Vorgang: erst die Angaben, dann „Das passiert:“ mit den Folgen vom Server,
/// ausgeführt wird erst nach „Bestätigen“.
struct VorgangBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let member: MemberDetail
    let vorgang: MitgliedVorgang
    let saved: (MemberDetail) -> Void
    @State private var types: [MemberTypeItem] = []
    @State private var units: [DepartmentItem] = []
    @State private var type: Int?
    @State private var department: Int?
    @State private var reason = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var error: String?
    @State private var busy = false
    @State private var process: MemberProcess?
    @State private var preview: MemberPreview?

    private var today: String { Zeit.day(Date()) }

    private var title: String {
        switch vorgang {
        case .art: return tr("Mitgliedsart wechseln")
        case .untereinheit: return tr("Untereinheit wechseln")
        case .austritt: return tr("Austritt eintragen")
        case .wiedereintritt: return tr("Wiedereintritt eintragen")
        case .beitragSelbst, .beitragFremd: return tr("Zahlt Beitrag selbst")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let preview {
                    FolgenAbschnitt(preview: preview)
                } else if vorgang == .beitragSelbst || vorgang == .beitragFremd {
                    if error == nil { ProgressView() }
                } else {
                    angaben
                }
            }
            .disabled(busy)
            .environment(\.locale, Texte.locale)
            .navigationTitle(preview?.heading ?? title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if preview != nil {
                        Button(tr("Bestätigen")) { Task { await apply() } }.disabled(busy)
                    } else if vorgang != .beitragSelbst, vorgang != .beitragFremd {
                        Button(tr("Weiter")) { Task { await next() } }.disabled(busy)
                    }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var angaben: some View {
        switch vorgang {
        case .art:
            Section {
                Picker(tr("Neue Mitgliedsart"), selection: $type) {
                    Text(tr("Bitte wählen")).tag(Int?.none)
                    ForEach(types) { Text($0.name).tag(Int?.some($0.id)) }
                }
                DatePicker(tr("Ab"), selection: $date, displayedComponents: .date)
            } header: {
                Text(tr("Bisher: {name}", ["name": member.typeName.isEmpty ? tr("keine") : member.typeName]))
            }
        case .untereinheit:
            Section {
                Picker(tr("Neue Untereinheit"), selection: $department) {
                    Text(tr("Bitte wählen")).tag(Int?.none)
                    ForEach(units) { Text($0.label).tag(Int?.some($0.id)) }
                }
                DatePicker(tr("Ab"), selection: $date, displayedComponents: .date)
            } header: {
                let names = member.currentDepartments(today: today).map(\.name).filter { !$0.isEmpty }
                Text(tr("Bisher: {name}", ["name": names.isEmpty ? tr("keine") : names.joined(separator: ", ")]))
            }
        case .austritt:
            Section {
                DatePicker(tr("Austritt zum"), selection: $date, displayedComponents: .date)
                Picker(tr("Grund"), selection: $reason) {
                    Text(tr("Bitte wählen")).tag("")
                    ForEach(member.exitReasons) { Text($0.label).tag($0.value) }
                }
                BeschriftetesFeld(label: tr("Notiz (optional)"), text: $note, axis: .vertical)
            } header: {
                Text(member.name)
            }
        case .wiedereintritt:
            Section {
                Picker(tr("Mitgliedsart"), selection: $type) {
                    Text(tr("Bitte wählen")).tag(Int?.none)
                    ForEach(types) { Text($0.name).tag(Int?.some($0.id)) }
                }
                DatePicker(tr("Eintritt am"), selection: $date, displayedComponents: .date)
            } header: {
                Text(member.name)
            } footer: {
                Text(tr("Neuer Zeitraum; frühere Zeiten und Nummern bleiben erhalten."))
            }
        case .beitragSelbst, .beitragFremd:
            EmptyView()
        }
    }

    private func load() async {
        switch vorgang {
        case .art, .wiedereintritt:
            guard types.isEmpty else { return }
            guard let list = await model.verwaltung(unit, { try await $0.memberTypes() }) else {
                error = model.adminError
                return
            }
            types = vorgang == .art ? member.otherTypes(list) : list
        case .untereinheit:
            guard units.isEmpty else { return }
            guard let list = await model.verwaltung(unit, { try await $0.departments() }) else {
                error = model.adminError
                return
            }
            units = member.otherDepartments(list, today: today)
        case .austritt:
            break
        case .beitragSelbst, .beitragFremd:
            if preview == nil { await show(.feeSelf(vorgang == .beitragSelbst)) }
        }
        // Vorführmodus: für das Bildschirmfoto gleich die Folgen des Austritts
        if Demo.active, Demo.section == "folgen", vorgang == .austritt, preview == nil {
            await show(.exit(date: Zeit.day(date), reason: member.exitReasons.first?.value ?? "", note: ""))
        }
    }

    private func next() async {
        error = nil
        let day = Zeit.day(date)
        switch vorgang {
        case .art:
            guard let type else { return error = tr("Bitte eine Mitgliedsart wählen.") }
            await show(.changeType(type: type, from: day))
        case .untereinheit:
            guard let department else { return error = tr("Bitte eine Untereinheit wählen.") }
            await show(.move(department: department, from: day))
        case .austritt:
            guard !reason.isEmpty else { return error = tr("Bitte einen Grund wählen.") }
            await show(.exit(date: day, reason: reason, note: note))
        case .wiedereintritt:
            guard let type else { return error = tr("Bitte eine Mitgliedsart wählen.") }
            await show(.reentry(type: type, typeName: types.first { $0.id == type }?.name ?? "", from: day))
        case .beitragSelbst, .beitragFremd:
            break
        }
    }

    /// Folgen holen und zur Bestätigung zeigen.
    private func show(_ wanted: MemberProcess) async {
        busy = true
        defer { busy = false }
        let id = member.id
        guard let result = await model.verwaltung(unit, { try await $0.preview(member: id, wanted) }) else {
            error = model.adminError
            return
        }
        process = wanted
        preview = result
    }

    private func apply() async {
        guard let process, let preview, !busy else { return }
        error = nil
        busy = true
        defer { busy = false }
        let id = member.id
        guard let result = await model.verwaltung(unit, { try await $0.apply(member: id, process) }) else {
            error = model.adminError
            return
        }
        model.adminChanged(unit, text: preview.doneText, change: result.change)
        saved(result.member)
        dismiss()
    }
}

/// Aufzählungspunkt mit kleinem Punkt, Text über mehrere Zeilen.
private struct FolgenZeile: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(Color.secondary)
            configuration.title
        }
    }
}

/// „Das passiert:“ mit den Folgen einer Änderung, vor dem Bestätigen.
struct FolgenAbschnitt: View {
    let preview: MemberPreview

    var body: some View {
        Section {
            ForEach(Array(preview.consequences.enumerated()), id: \.offset) { _, line in
                Label(line, systemImage: "circle.fill")
                    .labelStyle(FolgenZeile())
            }
        } header: {
            Text(tr("Das passiert:"))
        } footer: {
            Text(tr("Danach lässt sich die Änderung rückgängig machen."))
        }
    }
}
