import HubiplanKern
import SwiftUI

/// Blatt „Neues Mitglied“: Person oder Organisation. Vor der Aufnahme sucht die App nach
/// möglichen Dubletten und fragt, ob es die Person schon gibt.
struct AufnahmeBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let done: (MemberDetail) -> Void
    @State private var draft = AdmitDraft(entry: Zeit.day(Date()))
    @State private var entry = Date()
    @State private var types: [MemberTypeItem] = []
    @State private var units: [DepartmentItem] = []
    @State private var found: [DuplicateItem]?
    @State private var error: String?
    @State private var busy = false
    /// Ein Schlüssel je Formular: erneutes Senden nimmt nicht doppelt auf
    @State private var key = UUID().uuidString
    @State private var leave = false

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { MeldungText(error, .fehler) } }
                if let found {
                    dubletten(found)
                } else {
                    formular
                }
            }
            .tastaturFuehrung()
            .disabled(busy)
            .environment(\.locale, Texte.locale)
            .navigationTitle(found == nil ? tr("Neues Mitglied") : draft.organization ? tr("Gibt es die Organisation schon?") : tr("Gibt es die Person schon?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if found == nil {
                        Button(tr("Abbrechen")) { if draft.hasInput { leave = true } else { dismiss() } }
                    } else {
                        Button(tr("Zurück")) { found = nil }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if found == nil { Button(tr("Aufnehmen")) { Task { await check() } }.disabled(busy) }
                }
            }
            .task { await load() }
            .interactiveDismissDisabled()
            .confirmationDialog(tr("Eingaben verwerfen?"), isPresented: $leave, titleVisibility: .visible) {
                Button(tr("Verwerfen"), role: .destructive) { dismiss() }
                Button(tr("Weiter bearbeiten"), role: .cancel) {}
            } message: {
                Text(tr("Was du in diesem Blatt eingegeben hast, geht verloren."))
            }
        }
    }

    @ViewBuilder
    private var formular: some View {
        Section {
            Picker(tr("Mitglied ist"), selection: $draft.organization) {
                Text(tr("Person")).tag(false)
                Text(tr("Organisation")).tag(true)
            }
            .pickerStyle(.segmented)
        } footer: {
            if draft.organization {
                Text(tr("Firma, Verein, Behörde oder Stiftung. Rechtsform, Register und Ansprechpartner trägst du danach im Browser ein."))
            }
        }
        Section {
            if draft.organization {
                BeschriftetesFeld(label: tr("Name der Organisation"), text: $draft.lastName)
                BeschriftetesFeld(label: tr("Namenszusatz (optional)"), text: $draft.nameSuffix)
            } else {
                BeschriftetesFeld(label: tr("Vorname"), text: $draft.firstName)
                BeschriftetesFeld(label: tr("Nachname"), text: $draft.lastName)
                BeschriftetesFeld(label: tr("Geburtsdatum (freiwillig, TT.MM.JJJJ)"), text: $draft.birthDate)
                    .keyboardType(.numbersAndPunctuation)
                Picker(tr("Geschlecht"), selection: $draft.gender) {
                    Text(tr("keine Angabe")).tag("")
                    Text(tr("männlich")).tag("männlich")
                    Text(tr("weiblich")).tag("weiblich")
                    Text(tr("divers")).tag("divers")
                }
                BeschriftetesFeld(label: tr("Titel (optional)"), text: $draft.title)
            }
        }
        .autocorrectionDisabled()
        Section(tr("Kontakt")) {
            BeschriftetesFeld(label: tr("Straße"), text: $draft.street)
            BeschriftetesFeld(label: tr("PLZ"), text: $draft.postalCode)
                .keyboardType(.numbersAndPunctuation)
            BeschriftetesFeld(label: tr("Ort"), text: $draft.city)
            BeschriftetesFeld(label: tr("E-Mail"), text: $draft.email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            BeschriftetesFeld(label: tr("Telefon"), text: $draft.phone)
                .keyboardType(.phonePad)
        }
        .autocorrectionDisabled()
        Section(tr("Mitgliedschaft")) {
            Picker(tr("Mitgliedsart"), selection: $draft.type) {
                Text(tr("Bitte wählen")).tag(Int?.none)
                ForEach(types) { Text($0.name).tag(Int?.some($0.id)) }
            }
            if !units.isEmpty {
                Picker(tr("Untereinheit (optional)"), selection: $draft.department) {
                    Text(tr("keine")).tag(Int?.none)
                    ForEach(units) { Text($0.label).tag(Int?.some($0.id)) }
                }
            }
            DatePicker(tr("Eintritt am"), selection: $entry, displayedComponents: .date)
        }
    }

    @ViewBuilder
    private func dubletten(_ list: [DuplicateItem]) -> some View {
        Section {
            ForEach(list) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text(item.detail).font(.footnote).foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    if !item.alreadyMemberHere {
                        Button(draft.organization ? tr("Diese") : tr("Diese Person")) { Task { await admit(item.id) } }
                            .buttonStyle(.borderless)
                    }
                }
            }
        } footer: {
            Text(tr("Mit diesem Namen gibt es schon jemanden in HUBIplan. Wähle den Eintrag, wenn er gemeint ist."))
        }
        Section {
            Button(draft.organization ? tr("Neue Organisation anlegen") : tr("Neue Person anlegen")) { Task { await admit(nil) } }
        }
    }

    private func load() async {
        guard types.isEmpty else { return }
        // Vorführmodus: ausgefülltes Blatt für das Bildschirmfoto
        if Demo.active, draft.lastName.isEmpty {
            draft.firstName = "Lena"
            draft.lastName = "Beispiel"
            draft.birthDate = Zeit.plainDate("2008-03-07")
            draft.street = "Musterweg 2"
            draft.postalCode = "41468"
            draft.city = "Musterstadt"
        }
        let lists = await model.verwaltung(unit) { client -> ([MemberTypeItem], [DepartmentItem]) in
            let types = try await client.memberTypes()
            // Untereinheiten sind freiwillig: ohne sie geht die Aufnahme trotzdem
            let units = (try? await client.departments()) ?? []
            return (types, units)
        }
        guard let lists else {
            error = model.adminError
            return
        }
        types = lists.0
        units = lists.1
        if Demo.active, Demo.section == "dubletten" {
            draft.type = types.first?.id
            await check()
        }
    }

    /// Eingaben prüfen und nach möglichen Dubletten suchen; ohne Treffer gleich aufnehmen.
    private func check() async {
        guard !busy else { return }
        draft.entry = Zeit.day(entry)
        error = draft.error
        guard error == nil else { return }
        busy = true
        let wanted = draft
        let list = await model.verwaltung(unit) { try await $0.duplicates(wanted) }
        busy = false
        guard let list else {
            error = model.adminError
            return
        }
        if list.isEmpty {
            await admit(nil)
        } else {
            found = list
        }
    }

    private func admit(_ person: Int?) async {
        guard !busy, let body = draft.body(person: person) else { return }
        busy = true
        defer { busy = false }
        let values = SendableValues(body)
        let sent = key
        guard let member = await model.verwaltung(unit, { try await $0.admit(body: values.values, key: sent) }) else {
            error = model.adminError
            // Fehler steht über dem Formular; die Eingaben bleiben
            found = nil
            return
        }
        model.adminDone(tr("{name} aufgenommen", ["name": member.name]))
        done(member)
        dismiss()
    }
}
