import HubiplanKern
import SwiftUI

// Mein Bereich wie in der Android-App: Belegung anfragen, Meldungen zu Wettbewerben,
// Abwesenheiten in der Musik und Kündigung (unter „Meine Daten“).

/// Zeitraum einer Buchung; ganztägig nur die Tage (bis zum letzten Tag).
func belegungZeit(_ startsAt: String, _ endsAt: String, allDay: Bool) -> String {
    guard allDay else { return zeitraum(startsAt, endsAt) }
    guard let start = Zeit.parse(startsAt) else { return startsAt }
    var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(Texte.locale)
    style.timeZone = Belegung.berlin
    let first = start.formatted(style)
    guard let last = Zeit.parse(Belegung.shownEnd(endsAt, allDay: true)) else { return first }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Belegung.berlin
    return calendar.isDate(start, inSameDayAs: last) ? first : first + " – " + last.formatted(style)
}

// MARK: Belegung

struct BelegungView: View {
    @EnvironmentObject private var model: AppModel
    @State private var monday = Belegung.monday(Date())
    @State private var data: BookingWeek?
    @State private var error: String?
    @State private var problem: String?
    @State private var notice: String?
    @State private var busy = false
    @State private var cancelling: OwnBooking?

    var body: some View {
        List {
            if let error {
                Section {
                    MeldungText(error, .fehler)
                    Button(tr("Erneut versuchen")) { Task { await load() } }
                }
            }
            if let data {
                if data.items.isEmpty {
                    Text(tr("Zurzeit lassen sich hier keine Objekte anfragen.")).foregroundStyle(.secondary)
                } else {
                    woche(data)
                    Section(tr("Anfrage stellen")) {
                        BelegungAnfrage(items: data.items) { await load() }
                    }
                    Section(tr("Meine Anfragen und Buchungen")) {
                        if let notice { MeldungText(notice, .gut) }
                        if let problem { MeldungText(problem, .fehler) }
                        if data.own.isEmpty { Text(tr("Noch keine.")).foregroundStyle(.secondary) }
                        ForEach(data.own) { booking in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(booking.title).font(.hubi(.subheadline).weight(.semibold))
                                Text([booking.itemTitle, belegungZeit(booking.startsAt, booking.endsAt, allDay: booking.allDay)]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.hubi(.footnote)).foregroundStyle(.secondary)
                                Text(booking.statusLabel).font(.hubi(.footnote))
                                if booking.cancellable {
                                    Button(tr("Buchung stornieren"), role: .destructive) { cancelling = booking }
                                        .buttonStyle(.bordered)
                                        .disabled(busy)
                                }
                            }
                        }
                    }
                }
            } else if error == nil {
                Laedt()
            }
        }
        .navigationTitle(tr("Belegung"))
        .zurueckSchutz()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: "\(model.accessId ?? 0)-\(monday.timeIntervalSince1970)") { await load() }
        .confirmationDialog(
            tr("Buchung stornieren?"),
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible,
            presenting: cancelling
        ) { booking in
            Button(tr("Stornieren"), role: .destructive) { Task { await cancel(booking) } }
            Button(tr("Abbrechen"), role: .cancel) {}
        } message: { booking in
            Text(booking.title + " · " + belegungZeit(booking.startsAt, booking.endsAt, allDay: booking.allDay))
        }
    }

    @ViewBuilder
    private func woche(_ data: BookingWeek) -> some View {
        let until = Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? monday
        Section {
            Text(tr("Woche vom {from} bis {until}", ["from": Zeit.plainDate(Zeit.day(monday)), "until": Zeit.plainDate(Zeit.day(until))]))
                .font(.hubi(.footnote)).foregroundStyle(.secondary)
            KnopfReihe {
                Button(tr("Vorige Woche")) { monday = Calendar.current.date(byAdding: .day, value: -7, to: monday) ?? monday }
                Spacer()
                Button(tr("Nächste Woche")) { monday = Calendar.current.date(byAdding: .day, value: 7, to: monday) ?? monday }
            }
            .buttonStyle(.borderless)
            ForEach(data.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.hubi(.subheadline).weight(.semibold)).accessibilityAddTraits(.isHeader)
                    let rows = data.busy(item.id)
                    if rows.isEmpty {
                        Text(tr("In dieser Woche frei.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                    }
                    ForEach(rows.indices, id: \.self) { index in
                        Text(belegungZeit(rows[index].startsAt, rows[index].endsAt, allDay: rows[index].allDay) + " · " + rows[index].title)
                            .font(.hubi(.footnote))
                    }
                }
            }
        } header: {
            Text(tr("Belegte Zeiten"))
        }
    }

    private func load() async {
        let start = Zeit.day(monday)
        switch await model.portalCall({ api, access in try await api.bookings(accessId: access, monday: start) }) {
        case .success(let fresh):
            data = fresh
            error = nil
        case .failure(let failure): error = failure.text
        case nil: break
        }
    }

    private func cancel(_ booking: OwnBooking) async {
        busy = true
        problem = nil
        notice = nil
        defer { busy = false }
        switch await model.portalCall({ api, access in try await api.cancelBooking(accessId: access, booking: booking) }) {
        case .success:
            notice = tr("Storniert.")
            await load()
        case .failure(let failure): problem = failure.text
        case nil: break
        }
    }
}

private struct BelegungAnfrage: View {
    @EnvironmentObject private var model: AppModel
    let items: [BookableItem]
    let onSent: () async -> Void
    @State private var itemId: Int?
    @State private var title = ""
    @State private var allDay = false
    @State private var start = BelegungAnfrage.nextHour()
    @State private var end = BelegungAnfrage.nextHour().addingTimeInterval(2 * 3600)
    @State private var note = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var notice: String?

    static func nextHour() -> Date {
        let now = Date()
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        return hour.addingTimeInterval(3600)
    }

    private var item: BookableItem? { items.first { $0.id == itemId } ?? items.first }
    private var times: (from: String, to: String)? { Belegung.requestTimes(start: start, end: end, allDay: allDay) }

    var body: some View {
        Text(tr("Die Verwaltung bestätigt deine Anfrage oder lehnt sie ab; du bekommst eine E-Mail."))
            .font(.hubi(.footnote)).foregroundStyle(.secondary)
        Picker(tr("Objekt"), selection: Binding(get: { item?.id ?? 0 }, set: { itemId = $0 })) {
            ForEach(items) { Text($0.title).tag($0.id) }
        }
        TextField(tr("Zweck"), text: $title)
            .weiterFeld()
        Toggle(tr("Ganztägig"), isOn: $allDay)
        DatePicker(tr("Beginn"), selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            .environment(\.locale, Texte.locale)
        DatePicker(tr("Ende"), selection: $end, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            .environment(\.locale, Texte.locale)
        if let item, item.horizonDays > 0 {
            Text(tr("Bis zu {n} Tage im Voraus buchbar.", ["n": item.horizonDays])).font(.hubi(.footnote)).foregroundStyle(.secondary)
        }
        TextField(tr("Notiz (optional)"), text: $note, axis: .vertical).lineLimit(2...5)
        if times == nil {
            ZustandText(tr("Das Ende liegt vor dem Beginn."), .fehler).font(.hubi(.footnote))
        }
        if let problem { MeldungText(problem, .fehler) }
        if let notice { MeldungText(notice, .gut) }
        Button(busy ? tr("Wird gesendet …") : tr("Anfrage senden")) { Task { await send() } }
            .buttonStyle(.borderedProminent)
            .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty || times == nil || item == nil)
            .onChange(of: start) { if end <= start { end = start.addingTimeInterval(allDay ? 0 : 2 * 3600) } }
            .entwurf(!title.isEmpty || !note.isEmpty)
    }

    private func send() async {
        guard let item, let times else { return }
        busy = true
        problem = nil
        notice = nil
        defer { busy = false }
        let text = String(title.trimmingCharacters(in: .whitespaces).prefix(200))
        let memo = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        let whole = allDay
        switch await model.portalCall({ api, access in
            try await api.requestBooking(accessId: access, item: item.id, title: text, note: memo,
                                         startsAt: times.from, endsAt: times.to, allDay: whole)
        }) {
        case .success:
            notice = tr("Deine Anfrage ist eingegangen.")
            title = ""
            note = ""
            await onSent()
        case .failure(let failure): problem = failure.text
        case nil: break
        }
    }
}

// MARK: Meldungen

/// „Gemeldet“ oben unter „Wettbewerbe“.
struct GemeldetAbschnitt: View {
    let entries: [MyEntry]?

    var body: some View {
        Section(tr("Gemeldet")) {
            if let entries {
                if entries.isEmpty {
                    Text(tr("Zurzeit bist du für nichts gemeldet. Sobald der Verein dich zu einem Wettbewerb oder Anlass meldet, steht das hier."))
                        .font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                let today = Zeit.day(Date())
                let coming = entries.filter { !$0.past(today: today) }
                let past = entries.filter { $0.past(today: today) }
                if !coming.isEmpty { gruppe(tr("Demnächst"), coming) }
                if !past.isEmpty { gruppe(tr("Vergangen"), past) }
            } else {
                Laedt()
            }
        }
    }

    @ViewBuilder
    private func gruppe(_ title: String, _ rows: [MyEntry]) -> some View {
        Text(title).font(.hubi(.subheadline).weight(.semibold)).accessibilityAddTraits(.isHeader)
        ForEach(rows) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.hubi(.subheadline).weight(.semibold))
                if !entry.meta.isEmpty { Text(entry.meta).font(.hubi(.footnote)).foregroundStyle(.secondary) }
                Text(entry.line).font(.hubi(.footnote))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: Abwesenheiten

struct AbwesenheitenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var data: OwnAbsences?
    @State private var error: String?
    @State private var problem: String?
    @State private var notice: String?
    /// Offene Eingabe: neue (id 0) oder bestehende Abwesenheit
    @State private var editing: AbwesenheitEntwurf?
    @State private var removing: MusicAbsence?
    /// Ein Schlüssel je Löschauftrag: Wiederholen löscht nicht doppelt
    @State private var deleteKeys: [Int: String] = [:]

    var body: some View {
        List {
            if let error {
                Section {
                    MeldungText(error, .fehler)
                    Button(tr("Erneut versuchen")) { Task { await load() } }
                }
            }
            if let data {
                if !data.enabled {
                    Text(tr("Du hast in diesem Verein kein aktives Musikerprofil.")).foregroundStyle(.secondary)
                } else {
                    Section {
                        Text(tr("Trage Zeiträume ein, in denen du nicht mitspielen kannst. Eine Begründung wird nicht erfasst. Bestehende Einteilungen bleiben erhalten; bitte dort zusätzlich absagen."))
                            .font(.hubi(.footnote)).foregroundStyle(.secondary)
                        if let notice { MeldungText(notice, .gut) }
                        if let problem { MeldungText(problem, .fehler) }
                        Button(tr("Abwesenheit eintragen")) { notice = nil; editing = AbwesenheitEntwurf(row: nil) }
                    }
                    Section {
                        if data.items.isEmpty {
                            Text(tr("Keine Abwesenheiten eingetragen.")).foregroundStyle(.secondary)
                        }
                        ForEach(data.items) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(zeitraum(row.startsAt, row.endsAt))
                                KnopfReihe {
                                    Button(tr("Bearbeiten")) { notice = nil; editing = AbwesenheitEntwurf(row: row) }
                                    Spacer()
                                    Button(tr("Entfernen"), role: .destructive) { removing = row }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            } else if error == nil {
                Laedt()
            }
        }
        .navigationTitle(tr("Abwesenheiten"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: model.accessId) { await load() }
        .sheet(item: $editing) { draft in
            AbwesenheitFormular(draft: draft) { saved in
                editing = nil
                if saved {
                    notice = tr("Gespeichert.")
                    Task { await load() }
                }
            }
        }
        .confirmationDialog(
            tr("Abwesenheit entfernen?"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { row in
            Button(tr("Entfernen"), role: .destructive) { Task { await remove(row) } }
            Button(tr("Abbrechen"), role: .cancel) {}
        } message: { row in
            Text(zeitraum(row.startsAt, row.endsAt))
        }
    }

    private func load() async {
        switch await model.portalCall({ api, access in try await api.myAbsences(accessId: access) }) {
        case .success(let fresh):
            data = fresh
            error = nil
        case .failure(let failure): error = failure.text
        case nil: break
        }
    }

    private func remove(_ row: MusicAbsence) async {
        problem = nil
        notice = nil
        let key = deleteKeys[row.id] ?? UUID().uuidString
        deleteKeys[row.id] = key
        switch await model.portalCall({ api, access in try await api.deleteAbsence(accessId: access, id: row.id, key: key) }) {
        case .success:
            notice = tr("Entfernt.")
            await load()
        case .failure(let failure): problem = failure.text
        case nil: break
        }
    }
}

struct AbwesenheitEntwurf: Identifiable {
    let id = UUID()
    let row: MusicAbsence?
}

private struct AbwesenheitFormular: View {
    @EnvironmentObject private var model: AppModel
    let draft: AbwesenheitEntwurf
    let onDone: (Bool) -> Void
    @State private var start: Date
    @State private var end: Date
    @State private var busy = false
    @State private var problem: String?
    /// Gleicher Schlüssel beim Wiederholen derselben Eingabe; neue Eingabe, neuer Schlüssel
    @State private var key = UUID().uuidString

    init(draft: AbwesenheitEntwurf, onDone: @escaping (Bool) -> Void) {
        self.draft = draft
        self.onDone = onDone
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _start = State(initialValue: draft.row.flatMap { Zeit.parse($0.startsAt) } ?? today)
        _end = State(initialValue: draft.row.flatMap { Zeit.parse($0.endsAt) }
            ?? (calendar.date(byAdding: .minute, value: 24 * 60 - 1, to: today) ?? today))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(tr("Von"), selection: $start).environment(\.locale, Texte.locale)
                DatePicker(tr("Bis"), selection: $end).environment(\.locale, Texte.locale)
                if end <= start {
                    ZustandText(tr("Das Ende der Abwesenheit muss nach dem Beginn liegen."), .fehler).font(.hubi(.footnote))
                }
                if let problem { MeldungText(problem, .fehler) }
            }
            .tastaturFuehrung()
            .navigationTitle(draft.row == nil ? tr("Abwesenheit eintragen") : tr("Abwesenheit ändern"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: start) { key = UUID().uuidString }
            .onChange(of: end) { key = UUID().uuidString }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Abbrechen")) { onDone(false) }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? tr("Wird gespeichert …") : tr("Speichern")) { Task { await save() } }
                        .disabled(busy || end <= start)
                }
            }
        }
    }

    private func save() async {
        guard let times = Belegung.requestTimes(start: start, end: end, allDay: false) else { return }
        busy = true
        problem = nil
        defer { busy = false }
        let id = draft.row?.id
        let key = self.key
        switch await model.portalCall({ api, access in
            try await api.saveAbsence(accessId: access, id: id, startsAt: times.from, endsAt: times.to, key: key)
        }) {
        case .success: onDone(true)
        case .failure(let failure): problem = failure.text
        case nil: break
        }
    }
}

// MARK: Kündigung

/// „Mitgliedschaft kündigen“ unter „Meine Daten“, wie im Browser und in der Android-App.
struct KuendigungAbschnitt: View {
    @EnvironmentObject private var model: AppModel
    let info: CancellationInfo
    @State private var open = false
    @State private var exitDate = Date()
    @State private var message = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var notice: String?
    @State private var confirm = false
    @State private var withdraw: CancellationItem?

    /// `JJJJ-MM-TT` → Datum (Mittag, damit Zeitzonen den Tag nicht verschieben).
    private static func date(_ day: String?) -> Date? {
        guard let day else { return nil }
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    private var chosen: String { Zeit.day(exitDate) }

    var body: some View {
        IchAbschnitt(title: tr("Mitgliedschaft kündigen")) {
            if let planned = info.plannedExit, info.pending == nil {
                Text(tr("Dein Austritt ist zum {date} eingetragen.", ["date": Zeit.plainDate(planned)]))
            }
            if info.possible, !open, let earliest = info.earliestDate {
                Text(tr("Kündigen ist {rule} möglich, heute also frühestens zum {date}.", ["rule": info.rule, "date": Zeit.plainDate(earliest)]))
                    .font(.hubi(.footnote)).foregroundStyle(.secondary)
                Button(tr("Kündigen")) {
                    notice = nil
                    exitDate = Self.date(earliest) ?? Date()
                    open = true
                }
                .buttonStyle(.bordered)
            }
            if let pending = info.pending {
                Text(tr("Deine Kündigung zum {date} vom {sent} wartet auf Bearbeitung durch deinen Verein.", [
                    "date": Zeit.plainDate(pending.exitDate),
                    "sent": Zeit.plainDate(pending.createdAt),
                ]))
                Button(tr("Zurücknehmen")) { withdraw = pending }
                    .buttonStyle(.bordered)
                    .disabled(busy)
            }
            if open, let earliest = info.earliestDate {
                Text(tr("Kündigen ist {rule} möglich. Ein späteres Datum kannst du wählen.", ["rule": info.rule]))
                    .font(.hubi(.footnote)).foregroundStyle(.secondary)
                DatePicker(tr("Austritt zum"), selection: $exitDate, in: (Self.date(earliest) ?? Date())..., displayedComponents: [.date])
                    .environment(\.locale, Texte.locale)
                TextField(tr("Nachricht an den Verein (optional)"), text: $message, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                if info.tooEarly(chosen) {
                    ZustandText(tr("Frühestens zum {date}.", ["date": Zeit.plainDate(earliest)]), .fehler).font(.hubi(.footnote))
                }
                KnopfReihe {
                    // Gewöhnlicher Knopf; rot ist erst die Bestätigung in der Rückfrage (IOS-23)
                    Button(tr("Weiter")) { confirm = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || info.tooEarly(chosen))
                    Button(tr("Abbrechen")) { open = false }.disabled(busy)
                }
            }
            if let notice { MeldungText(notice, .gut) }
            if let problem { MeldungText(problem, .fehler) }
            ForEach(info.requests.filter { !$0.pending }) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.statusLabel).font(.hubi(.subheadline))
                    Text(tr("Kündigung zum {date}, gesendet {sent}", [
                        "date": Zeit.plainDate(item.exitDate),
                        "sent": Zeit.plainDate(item.createdAt),
                    ]))
                    .font(.hubi(.footnote)).foregroundStyle(.secondary)
                    if !item.response.isEmpty {
                        Text(tr("Antwort deines Vereins: {text}", ["text": item.response])).font(.hubi(.footnote))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .alert(tr("Mitgliedschaft wirklich kündigen?"), isPresented: $confirm) {
            Button(tr("Kündigung absenden"), role: .destructive) { Task { await send() } }
            Button(tr("Abbrechen"), role: .cancel) {}
        } message: {
            Text(tr("Du trittst zum {date} aus. Dein Verein bestätigt die Kündigung per Mail.", ["date": Zeit.plainDate(chosen)]))
        }
        .alert(
            tr("Kündigung zurücknehmen?"),
            isPresented: Binding(get: { withdraw != nil }, set: { if !$0 { withdraw = nil } }),
            presenting: withdraw
        ) { item in
            Button(tr("Zurücknehmen")) { Task { await takeBack(item) } }
            Button(tr("Abbrechen"), role: .cancel) {}
        } message: { _ in
            Text(tr("Deine Mitgliedschaft läuft dann weiter."))
        }
    }

    private func send() async {
        busy = true
        problem = nil
        defer { busy = false }
        let day = chosen
        let text = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        switch await model.portalCall({ api, access in try await api.cancelMembership(accessId: access, exitDate: day, message: text) }) {
        case .success:
            open = false
            message = ""
            notice = tr("Kündigung gesendet. Du bekommst eine Eingangsbestätigung per Mail.")
            await model.reloadProfile()
        case .failure(let failure): problem = failure.text
        case nil: break
        }
    }

    private func takeBack(_ item: CancellationItem) async {
        busy = true
        problem = nil
        defer { busy = false }
        switch await model.portalCall({ api, access in try await api.withdrawCancellation(accessId: access, id: item.id) }) {
        case .success:
            notice = tr("Kündigung zurückgenommen.")
            await model.reloadProfile()
        case .failure(let failure): problem = failure.text
        case nil: break
        }
    }
}
