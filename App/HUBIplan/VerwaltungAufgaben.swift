import HubiplanKern
import SwiftUI

/// „Aufgaben verteilen“: Aufgaben der Einheit, offen oder erledigt; neue Aufgabe anlegen.
/// Inhalte bleiben nur in der entsperrten Ansicht, die App legt nichts davon ab.
struct AufgabenVerwaltungView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var rows: [AdminTodo]?
    @State private var done = false
    @State private var creating = false
    @State private var demoShown = false
    /// Vorführmodus: für das Bildschirmfoto gleich in eine Aufgabe; sonst die gerade angelegte
    @State private var shown: Int? = Demo.active && Demo.section == "vaufgabe" ? 1 : nil

    var body: some View {
        VerwaltungSchutz {
            List {
                Picker(tr("Stand"), selection: $done) {
                    Text(tr("Offen")).tag(false)
                    Text(tr("Erledigt")).tag(true)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                VerwaltungMeldung { await load() }
                if let rows {
                    let visible = AdminTodo.visible(rows, done: done)
                    Section {
                        if visible.isEmpty {
                            Text(tr("Keine Aufgaben in dieser Ansicht.")).foregroundStyle(.secondary)
                        }
                        ForEach(visible) { todo in
                            NavigationLink {
                                AufgabeVerwaltungView(unit: unit, id: todo.id) { await load() }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(todo.sharedText).font(.caption).foregroundStyle(Color.secondary)
                                    Text(todo.title)
                                    Text(todo.dueText).font(.footnote).foregroundStyle(todo.urgent ? Color.fehlerText : Color.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text(tr("Teilen, Anhänge und Serien verwaltest du im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .navigationDestination(item: $shown) { id in
                AufgabeVerwaltungView(unit: unit, id: id) { await load() }
            }
        }
        .navigationTitle(tr("Aufgaben verteilen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true
                } label: {
                    Label(tr("Neue Aufgabe"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $creating) {
            NeueAufgabeBlatt(unit: unit) { id in
                Task {
                    await load()
                    shown = id
                }
            }
        }
    }

    private func load() async {
        guard let result = await model.verwaltung(unit, { try await $0.todos() }) else { return }
        rows = result
        if Demo.active, Demo.section == "neueaufgabe", !demoShown {
            demoShown = true
            creating = true
        }
    }
}

/// Eine Aufgabe: Stand, Frist, Beschreibung; erledigen oder wieder öffnen.
struct AufgabeVerwaltungView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let id: Int
    /// Liste davor neu laden, wenn sich der Stand geändert hat
    let changed: () async -> Void
    @State private var todo: AdminTodo?
    @State private var busy = false

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung {
                    await load()
                    await changed()
                }
                if let todo {
                    Section {
                        Text(todo.title).font(.title3.weight(.semibold))
                        Text("\(todo.statusText) · \(todo.sharedText)")
                        Text(todo.dueText).foregroundStyle(todo.urgent && !todo.done ? Color.fehlerText : Color.primary)
                        if todo.dueTime != nil {
                            Text(tr("Zeitzone: {zone}", ["zone": todo.timezone])).font(.footnote).foregroundStyle(Color.secondary)
                        }
                    }
                    if !todo.description.isEmpty {
                        Section(tr("Beschreibung")) { Text(todo.description) }
                    }
                    if !todo.localNote.isEmpty {
                        Section(tr("Lokale Notizen")) { Text(todo.localNote) }
                    }
                    Section {
                        if todo.mayComplete {
                            Button(todo.done ? tr("Wieder öffnen") : tr("Erledigen")) { Task { await toggle(todo) } }
                                .disabled(busy)
                        }
                    } footer: {
                        Text(tr("Teilen, Anhänge und Serien verwaltest du im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Aufgabe"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let id = self.id
        guard let result = await model.verwaltung(unit, { try await $0.todo(id) }) else {
            // Nach Entzug keine alten Daten weiter zeigen
            todo = nil
            return
        }
        todo = result
    }

    private func toggle(_ current: AdminTodo) async {
        busy = true
        defer { busy = false }
        guard let result = await model.verwaltung(unit, { try await $0.completeTodo(current.id, version: current.version, done: !current.done) }) else {
            // Versionskonflikt oder Entzug: frisch laden statt alte Daten anzubieten
            let message = model.adminError
            await load()
            if model.adminError == nil { model.adminError = message }
            return
        }
        todo = result.todo
        model.adminChanged(unit, text: result.todo.done ? tr("Aufgabe erledigt") : tr("Aufgabe wieder geöffnet"), change: result.change)
        await changed()
    }
}

/// Neue Aufgabe: zunächst privat, mit Frist und Uhrzeit nach Wahl.
private struct NeueAufgabeBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let done: (Int) -> Void
    @State private var draft = TodoDraft()
    @State private var hasDate = false
    @State private var hasTime = false
    @State private var day = Date()
    @State private var error: String?
    @State private var saving = false

    private var values: TodoDraft {
        var copy = draft
        copy.date = hasDate ? Zeit.day(day, timeZone: Self.zone) : ""
        if hasDate, hasTime {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Self.zone
            let parts = calendar.dateComponents([.hour, .minute], from: day)
            copy.time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        } else {
            copy.time = ""
        }
        return copy
    }

    private static let zone = TimeZone(identifier: TodoDraft.timezone) ?? .current

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { MeldungText(error, .fehler) } }
                Section {
                    BeschriftetesFeld(label: tr("Titel"), text: $draft.title)
                    BeschriftetesFeld(label: tr("Beschreibung"), text: $draft.description, axis: .vertical)
                } footer: {
                    Text(tr("Die neue Aufgabe ist zunächst privat. Teilen, Anhänge und Serien verwaltest du im Browser."))
                }
                Section {
                    Toggle(tr("Mit Frist"), isOn: $hasDate)
                    if hasDate {
                        DatePicker(tr("Frist"), selection: $day, displayedComponents: .date)
                        Toggle(tr("Mit Uhrzeit"), isOn: $hasTime)
                        if hasTime {
                            DatePicker(tr("Uhrzeit"), selection: $day, displayedComponents: .hourAndMinute)
                        }
                    }
                } footer: {
                    if hasDate, hasTime { Text(tr("Zeitzone: {zone}", ["zone": TodoDraft.timezone])) }
                }
            }
            .environment(\.locale, Texte.locale)
            .environment(\.timeZone, Self.zone)
            .disabled(saving)
            .navigationTitle(tr("Neue Aufgabe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Anlegen")) { Task { await save() } }.disabled(saving || values.body == nil)
                }
            }
            .onAppear {
                // Vorführmodus: ausgefülltes Blatt für das Bildschirmfoto
                guard Demo.active, draft.title.isEmpty else { return }
                draft.title = Texte.language == "en" ? "Book the band" : "Kapelle buchen"
                draft.description = Texte.language == "en" ? "Ask for the same line-up as last year." : "Nach der Besetzung vom letzten Jahr fragen."
                hasDate = true
            }
        }
    }

    private func save() async {
        error = nil
        guard let body = values.body else { return }
        saving = true
        defer { saving = false }
        guard let created = await model.verwaltung(unit, { try await $0.createTodo(body) }) else {
            error = model.adminError
            return
        }
        model.adminChanged(unit, text: tr("Aufgabe angelegt"), change: created.change)
        done(created.todo.id)
        dismiss()
    }
}
