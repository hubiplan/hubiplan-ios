import HubiplanKern
import SwiftUI

/// Zeitraum eines Dienstes: Tag und Uhrzeiten; über Mitternacht mit beiden Tagen.
func zeitraum(_ from: String, _ to: String) -> String {
    guard let start = Zeit.parse(from) else { return from }
    let locale = Locale(identifier: Texte.language)
    let day = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(locale)
    let time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
    let first = start.formatted(day) + ", " + start.formatted(time)
    guard let end = Zeit.parse(to), end > start else { return first }
    if Calendar.current.isDate(start, inSameDayAs: end) { return first + "–" + end.formatted(time) }
    return first + " – " + end.formatted(day) + ", " + end.formatted(time)
}

/// Reiter „Aufgaben“: freigegebene Aufgaben und Helferdienste des Mitgliederbereichs.
struct AufgabenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var helpers = Demo.section == "helfer"
    @State private var done = false

    private var both: Bool { model.access?.hasTodos == true && model.access?.hasHelpers == true }
    private var showHelpers: Bool {
        guard let access = model.access else { return false }
        return access.hasHelpers && (helpers || !access.hasTodos)
    }

    var body: some View {
        NavigationStack {
            List {
                if let message = model.error {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button(tr("Erneut versuchen")) { Task { await model.refreshTasks() } }
                    }
                }
                if let notice = model.taskNotice {
                    Section { Text(notice).foregroundStyle(.green) }
                }
                if both {
                    Picker(tr("Aufgaben"), selection: $helpers) {
                        Text(tr("Aufgaben")).tag(false)
                        Text(tr("Helferdienste")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                if let access = model.access, !access.hasTodos, !access.hasHelpers {
                    Text(tr("{club} nutzt keine Aufgaben.", ["club": access.clubDisplayName.isEmpty ? access.clubName : access.clubDisplayName]))
                        .foregroundStyle(.secondary)
                } else if showHelpers {
                    HelferListe()
                } else {
                    aufgaben
                }
            }
            .navigationTitle(showHelpers ? tr("Helferdienste") : tr("Aufgaben"))
            .navigationDestination(for: Int.self) { id in AufgabeView(id: id) }
            .refreshable { await model.refreshTasks() }
            .task { await model.refreshTasks() }
            .onDisappear { model.taskNotice = nil }
        }
    }

    @ViewBuilder private var aufgaben: some View {
        let shown = model.todos.filter { $0.done == done }
        Section {
            Picker(tr("Offen"), selection: $done) {
                Text(tr("Offen")).tag(false)
                Text(tr("Erledigt")).tag(true)
            }
            .pickerStyle(.segmented)
            if shown.isEmpty && !model.loading {
                Text(tr("Keine Aufgaben in dieser Ansicht.")).foregroundStyle(.secondary)
            }
            ForEach(shown) { todo in
                NavigationLink(value: todo.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(todo.title).font(.headline)
                        Text(todo.dueText).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        } footer: {
            Text(tr("Für dich freigegebene Aufgaben und offene Angebote deiner Einheit."))
        }
    }
}

/// Eine Aufgabe: übernehmen, freigeben, erledigen. Anhänge öffnet der Browser.
struct AufgabeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    let id: Int

    var body: some View {
        List {
            if let todo = model.todos.first(where: { $0.id == id }) {
                if let message = model.error {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if let notice = model.taskNotice {
                    Section { Text(notice).foregroundStyle(.green) }
                }
                Section {
                    Text(todo.title).font(.title3.bold())
                    Text((todo.done ? tr("Erledigt") : tr("Offen")) + " · " + todo.dueText).foregroundStyle(.secondary)
                    if !todo.description.isEmpty { Text(todo.description) }
                    if todo.claimed {
                        Text(todo.claimedByMe ? tr("Von dir übernommen") : tr("Bereits übernommen")).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if todo.canClaim {
                        Button(tr("Aufgabe übernehmen")) { Task { await model.change(todo, action: "claim") } }
                    }
                    if todo.claimedByMe && !todo.done {
                        Button(tr("Übernahme freigeben")) { Task { await model.change(todo, action: "release") } }
                    }
                    if todo.canComplete {
                        Button(todo.done ? tr("Wieder öffnen") : tr("Erledigen")) { Task { await model.change(todo, action: "status") } }
                    }
                }
                .disabled(model.loading)
                if !todo.attachments.isEmpty {
                    Section(tr("Anhänge")) {
                        ForEach(todo.attachments) { file in Text(file.name) }
                        if let access = model.access, let server = model.account?.server,
                           let url = URL(string: "\(server)/mein-bereich/aufgaben?zugang=\(access.id)&aufgabe=\(todo.id)") {
                            Button(tr("Mit Anhängen im Browser öffnen")) { openURL(url) }
                        }
                    }
                }
            } else {
                Text(tr("Die Aufgabe ist nicht mehr verfügbar oder nicht freigegeben.")).foregroundStyle(.secondary)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Helferdienste: eigene Dienste mit Absage bis zur Frist, Pläne mit freien Schichten zum Eintragen.
struct HelferListe: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var cancel: MyShift?

    var body: some View {
        let data = model.helpers
        Section(tr("Meine Dienste")) {
            if data?.mine.isEmpty ?? true {
                Text(tr("Du hast noch keine Dienste.")).foregroundStyle(.secondary)
            }
            ForEach(data?.mine ?? []) { shift in
                VStack(alignment: .leading, spacing: 4) {
                    Text(shift.title).font(.headline)
                    Text(zeitraum(shift.startsAt, shift.endsAt)).font(.subheadline)
                    if !shift.location.isEmpty { Text(shift.location).font(.subheadline).foregroundStyle(.secondary) }
                    if data?.canCancel(shift.id) == true {
                        Button(tr("Dienst absagen"), role: .destructive) { cancel = shift }
                            .buttonStyle(.bordered)
                            .disabled(model.loading)
                    } else {
                        Text(tr("Absage nur über die Verwaltung")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .confirmationDialog(
            tr("Dienst absagen"),
            isPresented: Binding(get: { cancel != nil }, set: { if !$0 { cancel = nil } }),
            titleVisibility: .visible
        ) {
            Button(tr("Dienst absagen"), role: .destructive) {
                if let shift = cancel { Task { await model.cancelShift(shift) } }
                cancel = nil
            }
            Button(tr("Abbrechen"), role: .cancel) { cancel = nil }
        } message: {
            Text(cancel.map { $0.title + "\n" + zeitraum($0.startsAt, $0.endsAt) } ?? "")
        }
        if data?.openPlans.isEmpty ?? true {
            Section(tr("Dienstpläne")) {
                Text(tr("Zurzeit gibt es keine offenen Dienstpläne.")).foregroundStyle(.secondary)
            }
        }
        ForEach(data?.openPlans ?? []) { plan in
            Section {
                if !plan.info.isEmpty { Text(plan.info).font(.footnote).foregroundStyle(.secondary) }
                if !plan.note.isEmpty { Text(plan.note) }
                if plan.signup != "self" {
                    Text(tr("In diesen Plan trägt nur die Verwaltung ein.")).font(.footnote).foregroundStyle(.secondary)
                }
                if let most = plan.maxShifts, most > 0 {
                    Text(tr("Höchstens {n} Schichten je Person.", ["n": most])).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(plan.duties.filter { !$0.open.isEmpty }) { duty in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(duty.line).font(.headline)
                        if !duty.description.isEmpty { Text(duty.description).font(.footnote).foregroundStyle(.secondary) }
                        ForEach(duty.open) { shift in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zeitraum(shift.startsAt, shift.endsAt)).font(.subheadline)
                                Text(shift.freeLabel).font(.footnote).foregroundStyle(.secondary)
                                if !shift.note.isEmpty { Text(shift.note).font(.footnote).foregroundStyle(.secondary) }
                                if !shift.names.isEmpty {
                                    Text(shift.names.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                                }
                                if shift.mine != nil {
                                    Text(tr("Du bist eingetragen.")).font(.footnote.weight(.semibold)).foregroundStyle(Color.accentColor)
                                } else if plan.canSignup(shift) {
                                    Button(tr("Mich eintragen")) { Task { await model.signup(shift) } }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(model.loading)
                                        .padding(.top, 2)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(plan.title)
            }
        }
        if let access = model.access, let server = model.account?.server,
           let url = URL(string: "\(server)/mein-bereich/helferdienste?zugang=\(access.id)") {
            Section {
                Button(tr("Im Browser öffnen")) { openURL(url) }
            }
        }
    }
}
