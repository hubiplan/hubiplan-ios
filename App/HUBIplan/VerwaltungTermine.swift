import HubiplanKern
import SwiftUI

// Verwaltung: Termine der Einheit, Absagen, Rückmeldungen und „Neuer Termin“.

/// Wann ein Termin ist; ganztägige Termine zählen als Kalendertag in deutscher Zeit.
func terminZeit(_ from: String, _ to: String, allDay: Bool) -> String {
    guard allDay else { return zeitraum(from, to) }
    guard let start = Zeit.parse(from) else { return from }
    var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
        .locale(Locale(identifier: Texte.language))
    if let berlin = TimeZone(identifier: "Europe/Berlin") { style.timeZone = berlin }
    return start.formatted(style) + " · " + tr("Ganztägig")
}

/// Beschriftung über dem Feld, das Feld selbst ohne Platzhalter.
struct BeschriftetesFeld: View {
    let label: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(Color.secondary)
            TextField("", text: $text, axis: axis)
                .accessibilityLabel(label)
        }
    }
}

/// Kommende Termine der Einheit (ein halbes Jahr), mit „Neuer Termin“ für alle mit Terminrecht.
struct TermineVerwaltungView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var list: AdminEventList?
    @State private var creating = false
    /// Vorführmodus: für das Bildschirmfoto gleich in einen Termin
    @State private var showDemo = Demo.active && Demo.section == "vtermin"

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let list {
                    Section {
                        if list.items.isEmpty {
                            Text(tr("Keine Termine im nächsten halben Jahr.")).foregroundStyle(.secondary)
                        }
                        ForEach(list.items, id: \.rowKey) { row in
                            NavigationLink {
                                TerminVerwaltungView(unit: unit, id: row.eventId, occurrence: row.occurrenceStart)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(terminZeit(row.startsAt, row.endsAt, allDay: row.allDay))
                                        .font(.footnote).foregroundStyle(Color.secondary)
                                    Text(row.title).strikethrough(row.isCancelled)
                                    if row.isCancelled {
                                        Text(tr("Abgesagt")).font(.footnote).foregroundStyle(.red)
                                    }
                                    if !row.detail.isEmpty {
                                        Text(row.detail).font(.footnote).foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(tr("Kommende Termine"))
                    }
                } else if model.adminError == nil {
                    ProgressView()
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .navigationDestination(isPresented: $showDemo) { TerminVerwaltungView(unit: unit, id: 3, occurrence: nil) }
        }
        .navigationTitle(tr("Termine"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if list?.canManage == true {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Label(tr("Neuer Termin"), systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $creating) {
            NeuerTerminBlatt(unit: unit, rsvpAllowed: list?.rsvpAllowed == true) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        let range = MasterData.upcoming(today: Date(), days: 183)
        if let result = await model.verwaltung(unit, { try await $0.events(from: range.from, to: range.to) }) {
            list = result
            if Demo.active, Demo.section == "neuertermin" { creating = true }
        }
    }
}

/// Ein Termin: Angaben, Stand der Rückmeldungen mit Listen, Eintragen für ein Mitglied und
/// Absagen. `occurrence`: bei Serien der gewählte Einzeltermin.
struct TerminVerwaltungView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let id: Int
    let occurrence: String?
    @State private var event: AdminEvent?
    @State private var responses: AdminResponses?
    @State private var tab = AdminResponses.Tab.yes
    @State private var search = ""
    @State private var cancelling = false
    @State private var entry: Eintrag?
    @State private var busy = false

    struct Eintrag: Identifiable {
        let row: ResponseRow
        var id: Int { row.membershipId }
    }

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let event {
                    let shown = event.shown(occurrence: occurrence)
                    Section {
                        Text(event.title).font(.title3.weight(.semibold))
                        Text(terminZeit(shown.start, shown.end, allDay: event.allDay))
                        if !event.detail.isEmpty {
                            Text(event.detail).font(.footnote).foregroundStyle(Color.secondary)
                        }
                        if shown.cancelled {
                            Text(shown.note.isEmpty ? tr("Abgesagt") : tr("Abgesagt: {hinweis}", ["hinweis": shown.note]))
                                .foregroundStyle(.red)
                        }
                        if !event.description.isEmpty { Text(event.description) }
                    }
                    if event.canEdit {
                        Section {
                            if shown.cancelled {
                                Button(tr("Absage zurücknehmen")) { Task { await restore(shown) } }
                            } else {
                                Button(shown.single != nil ? tr("Diesen Termin absagen") : tr("Termin absagen"), role: .destructive) {
                                    cancelling = true
                                }
                            }
                        }
                        .disabled(busy)
                    }
                    if event.rsvp.enabled || responses != nil {
                        Section(tr("Zu- und Absagen")) {
                            if let counts = responses?.summary ?? event.rsvp.summary { Text(counts.text) }
                            if let capacity = event.rsvp.capacity {
                                Text(tr("Höchstens {n} Personen", ["n": capacity])
                                    + (event.rsvp.free.map { tr(", noch {n} frei", ["n": $0]) } ?? ""))
                            }
                            if let deadline = event.rsvp.deadline {
                                Text(tr("Anmeldeschluss {datum}", ["datum": Zeit.plainDate(deadline)]))
                                    .font(.footnote).foregroundStyle(Color.secondary)
                            }
                            if event.isSeries {
                                Text(tr("Bei Serien gelten Rückmeldungen für die ganze Serie."))
                                    .font(.footnote).foregroundStyle(Color.secondary)
                            }
                        }
                    }
                    if let responses {
                        liste(responses, canEnter: event.rsvp.canEnter && event.canEdit)
                    }
                } else if model.adminError == nil {
                    ProgressView()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Termin"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $cancelling) {
            if let event {
                AbsageBlatt(unit: unit, event: event, single: event.shown(occurrence: occurrence).single) {
                    Task { await load() }
                }
            }
        }
        .sheet(item: $entry) { picked in
            if let event {
                RueckmeldungBlatt(unit: unit, event: event, row: picked.row) {
                    Task { await load() }
                }
            }
        }
    }

    private func label(_ tab: AdminResponses.Tab, _ count: Int) -> String {
        switch tab {
        case .yes: return tr("Zusagen ({n})", ["n": count])
        case .no: return tr("Absagen ({n})", ["n": count])
        case .open: return tr("Offen ({n})", ["n": count])
        }
    }

    @ViewBuilder
    private func liste(_ r: AdminResponses, canEnter: Bool) -> some View {
        Section {
            Picker(tr("Rückmeldungen"), selection: $tab) {
                ForEach(AdminResponses.Tab.allCases, id: \.self) { t in
                    Text(label(t, r.count(t))).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            TextField(tr("Name suchen"), text: $search)
                .autocorrectionDisabled()
            let rows = r.rows(tab, search: search)
            if rows.isEmpty { Text(tr("Keine.")).foregroundStyle(.secondary) }
            ForEach(rows, id: \.membershipId) { row in
                if canEnter {
                    Button {
                        entry = Eintrag(row: row)
                    } label: {
                        zeile(row)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint(row.status == nil ? tr("Rückmeldung eintragen") : tr("Rückmeldung ändern"))
                } else {
                    zeile(row)
                }
            }
        } footer: {
            if canEnter { Text(tr("Antippen, um für ein Mitglied einzutragen (z. B. nach einem Anruf).")) }
        }
    }

    private func zeile(_ row: ResponseRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
            if !row.detail.isEmpty {
                Text(row.detail).font(.footnote).foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func load() async {
        let id = self.id
        let result = await model.verwaltung(unit) { client -> (AdminEvent, AdminResponses?) in
            let event = try await client.event(id)
            var list: AdminResponses?
            if event.rsvp.canViewList { list = try await client.responses(id) }
            return (event, list)
        }
        if let result {
            event = result.0
            responses = result.1
        }
    }

    private func restore(_ shown: AdminEvent.Shown) async {
        busy = true
        defer { busy = false }
        let id = self.id
        let change = await model.verwaltung(unit) { client -> AdminChange in
            if let single = shown.single {
                return try await client.cancelOccurrence(id, originalStart: single, cancelled: false)
            }
            return try await client.cancelEvent(id, cancelled: false)
        }
        guard let change else { return }
        model.adminChanged(unit, text: tr("Absage zurückgenommen"), change: change)
        await load()
    }
}

/// Termin absagen: ganz oder, bei Serien, nur den gewählten Einzeltermin.
private struct AbsageBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let event: AdminEvent
    /// Einzeltermin einer Serie; nil: der ganze Termin
    let single: String?
    let done: () -> Void
    @State private var note = ""
    @State private var notify = true
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    BeschriftetesFeld(label: tr("Hinweis (optional)"), text: $note, axis: .vertical)
                    if single == nil {
                        Toggle(tr("Eingeladene per E-Mail informieren"), isOn: $notify)
                    }
                } footer: {
                    Text(single != nil
                        ? tr("Nur dieser Termin der Serie wird abgesagt; die übrigen bleiben.")
                        : tr("Der Termin bleibt im Kalender, als abgesagt gekennzeichnet. Rückmeldungen bleiben erhalten."))
                }
            }
            .disabled(saving)
            .navigationTitle(single != nil ? tr("Diesen Termin absagen?") : tr("Termin absagen?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Termin absagen")) { Task { await save() } }.disabled(saving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        error = nil
        saving = true
        defer { saving = false }
        let id = event.id
        let single = self.single
        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        let mail = notify
        let change = await model.verwaltung(unit) { client -> AdminChange in
            if let single {
                return try await client.cancelOccurrence(id, originalStart: single, cancelled: true, note: text)
            }
            return try await client.cancelEvent(id, cancelled: true, note: text, notify: mail)
        }
        guard let change else {
            error = model.adminError
            return
        }
        model.adminChanged(unit, text: tr("„{titel}“ abgesagt", ["titel": event.title]), change: change)
        done()
        dismiss()
    }
}

/// Zu- oder Absage für ein Mitglied eintragen, ändern oder entfernen.
private struct RueckmeldungBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let event: AdminEvent
    let row: ResponseRow
    let done: () -> Void
    @State private var status = "yes"
    @State private var guests = 0
    @State private var note = ""
    @State private var error: String?
    @State private var saving = false

    private var withGuests: Bool { event.rsvp.guestsAllowed && event.rsvp.maxGuests > 0 && status == "yes" }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Picker(tr("Rückmeldung"), selection: $status) {
                        Text(tr("Zusage")).tag("yes")
                        Text(tr("Absage")).tag("no")
                    }
                    .pickerStyle(.segmented)
                    if withGuests {
                        Stepper(tr("Begleitung: {n}", ["n": guests]), value: $guests, in: 0...event.rsvp.maxGuests)
                    }
                    BeschriftetesFeld(label: tr("Notiz (optional)"), text: $note, axis: .vertical)
                }
                if row.status != nil {
                    Section {
                        Button(tr("Rückmeldung entfernen"), role: .destructive) { Task { await remove() } }
                    }
                }
            }
            .disabled(saving)
            .navigationTitle(row.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Eintragen")) { Task { await save() } }.disabled(saving)
                }
            }
            .onAppear {
                status = row.status == "no" ? "no" : "yes"
                guests = min(row.guests, event.rsvp.maxGuests)
                note = row.note
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        let id = event.id
        let membership = row.membershipId
        let answer = status
        let count = withGuests ? guests : 0
        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        await run(answer == "yes" ? tr("Zusage für {name} eingetragen", ["name": row.name]) : tr("Absage für {name} eingetragen", ["name": row.name])) {
            try await $0.setResponse(id, membership: membership, status: answer, guests: count, note: text)
        }
    }

    private func remove() async {
        let id = event.id
        let membership = row.membershipId
        await run(tr("Rückmeldung von {name} entfernt", ["name": row.name])) {
            try await $0.deleteResponse(id, membership: membership)
        }
    }

    private func run(_ text: String, _ work: @MainActor (AdminClient) async throws -> AdminChange) async {
        error = nil
        saving = true
        defer { saving = false }
        guard let change = await model.verwaltung(unit, work) else {
            error = model.adminError
            return
        }
        model.adminChanged(unit, text: text, change: change)
        done()
        dismiss()
    }
}

/// Einfachen Termin anlegen: einmalig, Titel, Tag, Zeit, Ort, Sichtbarkeit, Zu-/Absagen.
private struct NeuerTerminBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let rsvpAllowed: Bool
    let done: () -> Void
    @State private var draft = EventDraft()
    @State private var day = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var start = NeuerTerminBlatt.uhrzeit(19, 0)
    @State private var withEnd = false
    @State private var end = NeuerTerminBlatt.uhrzeit(21, 0)
    @State private var withDeadline = false
    @State private var deadline = Date()
    @State private var error: String?
    @State private var saving = false

    private static func uhrzeit(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private static func text(_ time: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    BeschriftetesFeld(label: tr("Titel"), text: $draft.title)
                    DatePicker(tr("Tag"), selection: $day, displayedComponents: .date)
                    Toggle(tr("Ganztägig"), isOn: $draft.allDay)
                    if !draft.allDay {
                        DatePicker(tr("Beginn"), selection: $start, displayedComponents: .hourAndMinute)
                        Toggle(tr("Ende angeben"), isOn: $withEnd)
                        if withEnd {
                            DatePicker(tr("Ende"), selection: $end, displayedComponents: .hourAndMinute)
                        }
                    }
                    BeschriftetesFeld(label: tr("Ort (optional)"), text: $draft.location)
                    BeschriftetesFeld(label: tr("Beschreibung (optional)"), text: $draft.description, axis: .vertical)
                } footer: {
                    Text(tr("Einmaliger Termin. Serien, Anhänge und Weitergabe an andere Einheiten im Browser."))
                }
                Section {
                    Picker(tr("Wer sieht den Termin?"), selection: $draft.visibility) {
                        ForEach(EventDraft.visibilities, id: \.key) { Text($0.label).tag($0.key) }
                    }
                }
                if draft.canRsvp(allowed: rsvpAllowed) {
                    Section {
                        Toggle(tr("Zu- und Absagen"), isOn: $draft.rsvp)
                        if draft.rsvp {
                            Toggle(tr("Begleitung erlaubt"), isOn: $draft.guests)
                            Toggle(tr("Anmeldeschluss"), isOn: $withDeadline)
                            if withDeadline {
                                DatePicker(tr("Anmelden bis"), selection: $deadline, displayedComponents: .date)
                            }
                            Toggle(tr("Eingeladene per E-Mail einladen"), isOn: $draft.notify)
                        }
                    }
                }
            }
            .environment(\.locale, Locale(identifier: Texte.language))
            .disabled(saving)
            .navigationTitle(tr("Neuer Termin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Anlegen")) { Task { await save() } }
                        .disabled(saving || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // Vorführmodus: ausgefülltes Blatt für das Bildschirmfoto
                guard Demo.active, draft.title.isEmpty else { return }
                draft.title = Texte.language == "en" ? "Platoon meeting" : "Zugversammlung"
                draft.location = Texte.language == "en" ? "Clubhouse" : "Vereinsheim"
                draft.rsvp = true
            }
        }
    }

    private func save() async {
        error = nil
        var values = draft
        values.title = String(values.title.prefix(200))
        values.location = String(values.location.prefix(200))
        values.day = Zeit.day(day)
        values.start = Self.text(start)
        values.end = withEnd ? Self.text(end) : ""
        values.deadline = withDeadline ? Zeit.day(deadline) : ""
        guard let body = values.body(rsvpAllowed: rsvpAllowed) else {
            error = tr("Bitte Titel, Tag und Zeit prüfen.")
            return
        }
        saving = true
        defer { saving = false }
        guard let result = await model.verwaltung(unit, { try await $0.createEvent(body) }) else {
            error = model.adminError
            return
        }
        model.adminChanged(unit, text: tr("„{titel}“ angelegt", ["titel": result.event.title]), change: result.change)
        done()
        dismiss()
    }
}
