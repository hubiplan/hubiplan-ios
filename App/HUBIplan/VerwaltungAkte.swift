import HubiplanKern
import LocalAuthentication
import SwiftUI

/// Weitere Teile der Akte: Ehrungen, Zusatzfelder, Bankverbindung.
struct AkteDaten {
    var awards: [AwardItem]?
    var fields: [FieldEntry] = []
    var mandates: [MandateItem]?
    /// Ganze IBAN zeigen (nach der Gerätesperre)
    var full = false

    @MainActor
    static func load(_ model: AppModel, _ unit: AdminUnit, member id: Int, full: Bool) async -> AkteDaten? {
        guard !unit.isDepartment else { return nil }
        let bank = unit.showsBank
        return await model.verwaltung(unit) { client in
            var daten = AkteDaten()
            daten.awards = try await client.awards(member: id)
            daten.fields = try await client.fields(member: id)
            if bank { daten.mandates = try await client.mandates(member: id, full: full) }
            daten.full = full
            return daten
        }
    }
}

/// Blatt, das die Akte gerade zeigt.
enum AkteBlatt: Identifiable {
    case ehrung
    case ehrungEnde(AwardItem)
    case felder
    case bank

    var id: String {
        switch self {
        case .ehrung: return "ehrung"
        case let .ehrungEnde(award): return "ende-\(award.id)"
        case .felder: return "felder"
        case .bank: return "bank"
        }
    }
}

/// Abschnitte der Akte unter den Stammdaten; nur in der Einheit.
struct AkteMehr: View {
    let unit: AdminUnit
    let member: MemberDetail
    let daten: AkteDaten
    @Binding var blatt: AkteBlatt?
    /// Ganze IBAN laden (nach der Gerätesperre)
    let showFull: () async -> Void
    @State private var asking = false

    private var canEdit: Bool { unit.canManageMembers }

    var body: some View {
        if let awards = daten.awards {
            Section(tr("Ehrungen und Würden")) {
                if awards.isEmpty { Text(tr("Keine.")).foregroundStyle(.secondary) }
                ForEach(awards) { award in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(award.titleName)
                            Text(award.period).font(.footnote).foregroundStyle(Color.secondary)
                            if !award.note.isEmpty { Text(award.note).font(.footnote).foregroundStyle(Color.secondary) }
                        }
                        Spacer()
                        if canEdit, award.running {
                            Button(tr("Beenden")) { blatt = .ehrungEnde(award) }.buttonStyle(.borderless)
                        }
                    }
                }
                if canEdit { Button(tr("Ehrung hinzufügen")) { blatt = .ehrung } }
            }
        }
        if !daten.fields.isEmpty {
            Section(tr("Zusatzfelder")) {
                ForEach(daten.fields) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.definition.label).font(.caption).foregroundStyle(Color.secondary)
                        Text(entry.shown)
                    }
                }
                if canEdit, daten.fields.contains(where: { !$0.definition.repeatable }) {
                    Button(tr("Zusatzfelder bearbeiten")) { blatt = .felder }
                }
            }
        }
        if let mandates = daten.mandates {
            let active = mandates.filter(\.isActive)
            Section(tr("Bankverbindung")) {
                if active.isEmpty { Text(tr("Kein gültiges SEPA-Mandat.")).foregroundStyle(.secondary) }
                ForEach(active) { mandate in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mandate.line)
                        Text(mandate.detail).font(.footnote).foregroundStyle(Color.secondary)
                    }
                }
                if !active.isEmpty, !daten.full {
                    Button(tr("IBAN ganz anzeigen")) { Task { await unlock() } }.disabled(asking)
                }
                if unit.canEditBank, !member.isFormer { Button(tr("Bankverbindung ändern")) { blatt = .bank } }
            }
        }
    }

    /// Ganze IBAN nur nach erneuter Gerätesperre (Face ID, Touch ID oder Gerätecode).
    private func unlock() async {
        asking = true
        defer { asking = false }
        if !Demo.active {
            let context = LAContext()
            let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: tr("IBAN anzeigen"))) ?? false
            guard ok else { return }
        }
        await showFull()
    }
}

/// Blätter der Akte: Ehrung hinzufügen oder beenden, Zusatzfelder, neue Bankverbindung.
struct AkteBlattView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let member: MemberDetail
    let blatt: AkteBlatt
    let fields: [FieldEntry]
    /// Nach dem Speichern: Akte neu laden
    let saved: () async -> Void
    @State private var titles: [HonoraryTitle] = []
    @State private var title: Int?
    @State private var date = Date()
    @State private var note = ""
    @State private var input: [Int: String] = [:]
    @State private var draft = MandateDraft(holder: "", signed: "")
    @State private var preview: MemberPreview?
    @State private var error: String?
    @State private var busy = false
    @State private var ready = false

    private var heading: String {
        switch blatt {
        case .ehrung: return tr("Ehrung hinzufügen")
        case let .ehrungEnde(award): return tr("„{name}“ beenden", ["name": award.titleName])
        case .felder: return tr("Zusatzfelder")
        case .bank: return preview?.heading ?? tr("Neue Bankverbindung")
        }
    }

    private var action: String {
        switch blatt {
        case .ehrung, .felder: return tr("Speichern")
        case .ehrungEnde: return tr("Beenden")
        case .bank: return preview == nil ? tr("Weiter") : tr("Bestätigen")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }
                switch blatt {
                case .ehrung:
                    Section {
                        Picker(tr("Ehrung"), selection: $title) {
                            Text(tr("Bitte wählen")).tag(Int?.none)
                            ForEach(titles) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                        DatePicker(tr("Seit"), selection: $date, displayedComponents: .date)
                        BeschriftetesFeld(label: tr("Notiz (optional)"), text: $note, axis: .vertical)
                    } header: {
                        Text(member.name)
                    }
                case .ehrungEnde:
                    Section {
                        DatePicker(tr("Endet am"), selection: $date, displayedComponents: .date)
                    } header: {
                        Text(member.name)
                    }
                case .felder:
                    Section {
                        ForEach(fields.filter { !$0.definition.repeatable }) { entry in
                            feld(entry.definition)
                        }
                    } header: {
                        Text(member.name)
                    }
                case .bank:
                    if let preview {
                        FolgenAbschnitt(preview: preview)
                    } else {
                        Section {
                            BeschriftetesFeld(label: tr("Kontoinhaber"), text: $draft.holder)
                                .autocorrectionDisabled()
                            BeschriftetesFeld(label: "IBAN", text: $draft.iban)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            BeschriftetesFeld(label: tr("BIC (optional)"), text: $draft.bic)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            DatePicker(tr("Unterschrieben am"), selection: $date, displayedComponents: .date)
                        } footer: {
                            Text(tr("Neues SEPA-Mandat auf Papier (vom Mitglied unterschrieben)."))
                        }
                    }
                }
            }
            .disabled(busy)
            .environment(\.locale, Locale(identifier: Texte.language))
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action) { Task { await save() } }.disabled(busy)
                }
            }
            .task { await start() }
        }
    }

    private func binding(_ id: Int) -> Binding<String> {
        Binding(get: { input[id] ?? "" }, set: { input[id] = $0 })
    }

    @ViewBuilder
    private func feld(_ def: FieldDef) -> some View {
        switch def.fieldType {
        case "bool":
            Picker(def.label, selection: binding(def.id)) {
                Text("–").tag("")
                Text(tr("ja")).tag("ja")
                Text(tr("nein")).tag("nein")
            }
        case "choice":
            Picker(def.label, selection: binding(def.id)) {
                Text("–").tag("")
                ForEach(def.choices, id: \.self) { Text($0).tag($0) }
                // Alter Wert, den es in der Auswahl nicht mehr gibt, bleibt wählbar
                if let old = input[def.id], !old.isEmpty, !def.choices.contains(old) { Text(old).tag(old) }
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                BeschriftetesFeld(label: def.fieldType == "date" ? tr("{label} (TT.MM.JJJJ)", ["label": def.label]) : def.label, text: binding(def.id))
                    .keyboardType(def.fieldType == "number" || def.fieldType == "date" ? .numbersAndPunctuation : .default)
                    .autocorrectionDisabled()
                if !def.helpText.isEmpty { Text(def.helpText).font(.caption).foregroundStyle(Color.secondary) }
            }
        }
    }

    private func start() async {
        guard !ready else { return }
        ready = true
        switch blatt {
        case .ehrung:
            guard let list = await model.verwaltung(unit, { try await $0.honoraryTitles() }) else {
                error = model.adminError
                return
            }
            titles = list
        case .ehrungEnde:
            break
        case .felder:
            input = MemberFields.input(fields)
        case .bank:
            draft.holder = member.name
            // Vorführmodus: ausgefülltes Blatt für das Bildschirmfoto (Prüf-IBAN aus der Bankenliteratur)
            if Demo.active { draft.iban = "DE02 1203 0000 0000 2020 51" }
        }
    }

    private func save() async {
        guard !busy else { return }
        error = nil
        let id = member.id
        let day = Zeit.day(date)
        busy = true
        defer { busy = false }
        switch blatt {
        case .ehrung:
            guard let title else { return error = tr("Bitte eine Ehrung wählen.") }
            let text = note
            let name = titles.first { $0.id == title }?.name ?? ""
            await finish(tr("{name} eingetragen", ["name": name])) { try await $0.addAward(member: id, title: title, from: day, note: text) }
        case let .ehrungEnde(award):
            await finish(tr("„{name}“ beendet", ["name": award.titleName])) { try await $0.endAward(member: id, award: award.id, until: day) }
        case .felder:
            let result = MemberFields.changes(fields, input: input)
            if let problem = result.error { return error = problem }
            if result.values.isEmpty { return dismiss() }
            let values = SendableValues(result.values)
            await finish(tr("Zusatzfelder gespeichert")) { try await $0.saveFields(member: id, values: values.values) }
        case .bank:
            draft.signed = day
            if let problem = draft.error { return error = problem }
            if preview == nil {
                guard let result = await model.verwaltung(unit, { try await $0.previewBank(member: id) }) else {
                    error = model.adminError
                    return
                }
                preview = result
            } else {
                let mandate = draft
                await finish(tr("Bankverbindung geändert")) { try await $0.addMandate(member: id, mandate) }
                // Bei einem Fehler zurück zu den Eingaben, sie bleiben erhalten
                if error != nil { preview = nil }
            }
        }
    }

    /// Ausführen; das Blatt schließt erst nach Erfolg, Fehler stehen im Blatt.
    private func finish(_ text: String, _ work: @MainActor (AdminClient) async throws -> AdminChange) async {
        guard let change = await model.verwaltung(unit, work) else {
            error = model.adminError
            return
        }
        model.adminChanged(unit, text: text, change: change)
        await saved()
        dismiss()
    }
}

/// Werte für die Anfrage über die Aufgabengrenze tragen (nur JSON-Werte).
struct SendableValues: @unchecked Sendable {
    let values: [String: Any]

    init(_ values: [String: Any]) {
        self.values = values
    }
}
