import HubiplanKern
import SwiftUI

/// Bezeichnung einer Antwort: Text oder bei Terminfindung Tag und Uhrzeit.
func umfrageOption(label: String, startsAt: String?, allDay: Bool) -> String {
    if !label.isEmpty { return label }
    guard let date = startsAt.flatMap(Zeit.parse) else { return "" }
    let locale = Texte.locale
    if allDay { return date.formatted(.dateTime.weekday(.abbreviated).day().month().year().locale(locale)) }
    return tagUndZeit(date)
}

/// Zweite Zeile einer Umfrage: Untereinheit, Termin, Ende, anonym.
func umfrageZeile(_ s: MemberSurvey) -> String {
    var parts: [String] = []
    if !s.unit.isEmpty { parts.append(s.unit) }
    if let event = s.event { parts.append(tr("zum Termin {title}", ["title": event.title])) }
    if s.isOpen, let end = s.closesAt.flatMap(Zeit.parse) { parts.append(tr("läuft bis {when}", ["when": tagUndZeit(end)])) }
    if !s.isOpen { parts.append(tr("beendet")) }
    if s.anonymous { parts.append(tr("anonym")) }
    return parts.joined(separator: " · ")
}

/// „Ich“ › Umfragen: offene zuerst, beantworten, ändern, zurückziehen, Ergebnis, „Zusage übernehmen“.
struct UmfragenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: Int?
    @State private var withdraw: MemberSurvey?

    var body: some View {
        let all = model.surveys?.surveys ?? []
        List {
            if let message = model.error {
                Section { MeldungText(message, .fehler) }
            }
            if let notice = model.taskNotice {
                Section { MeldungText(notice, .gut) }
            }
            if all.isEmpty {
                Text(tr("Gerade läuft keine Umfrage für dich.")).foregroundStyle(.secondary)
            }
            ForEach(all.filter(\.isOpen)) { survey in
                Section { karte(survey) }
            }
            let closed = all.filter { !$0.isOpen }
            if !closed.isEmpty {
                Section {
                    ForEach(closed) { survey in karte(survey) }
                } header: {
                    Text(tr("Beendete Umfragen"))
                }
            }
        }
        .navigationTitle(tr("Umfragen"))
        .zurueckSchutz()
        .task { await model.reloadSurveys() }
        .refreshable { await model.reloadSurveys() }
        .confirmationDialog(
            tr("Antwort zurückziehen?"),
            isPresented: Binding(get: { withdraw != nil }, set: { if !$0 { withdraw = nil } }),
            titleVisibility: .visible,
            presenting: withdraw
        ) { survey in
            Button(tr("Antwort zurückziehen"), role: .destructive) {
                Task { await model.withdraw(survey) }
            }
            Button(tr("Abbrechen"), role: .cancel) {}
        } message: { survey in
            Text(survey.title)
        }
    }

    @ViewBuilder
    private func karte(_ s: MemberSurvey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.title).font(.hubi(.headline)).accessibilityAddTraits(.isHeader)
            Text(umfrageZeile(s)).font(.hubi(.footnote)).foregroundStyle(.secondary)
            if !s.description.isEmpty { Text(s.description) }
            if let event = s.followEvent {
                Text(tr("Termin steht fest: {title} am {day}.", [
                    "title": event.title,
                    "day": event.start.map { Zeit.datum($0) } ?? "",
                ]))
                if event.response == "yes" {
                    Text(tr("Du hast zugesagt.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                if s.canFollow {
                    Button(tr("Zusage übernehmen")) { Task { await model.follow(s) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.loading)
                }
            }
            if s.answered && editing != s.id {
                Text(tr("Du hast geantwortet.")).font(.hubi(.subheadline))
                if s.anonymous {
                    Text(tr("Anonym, nicht mehr änderbar.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
            }
            if s.canAnswer && (!s.answered || editing == s.id) {
                UmfrageFormular(survey: s, cancel: editing == s.id ? { editing = nil } : nil) { draft in
                    if await model.answer(s, draft: draft) { editing = nil }
                }
            } else if s.canChange {
                KnopfReihe {
                    Button(tr("Antwort ändern")) { editing = s.id }
                        .buttonStyle(.bordered)
                    Button(tr("Antwort zurückziehen"), role: .destructive) { withdraw = s }
                        .buttonStyle(.bordered)
                }
                .disabled(model.loading)
            }
            if let result = s.results {
                Text(tr("Ergebnis")).font(.hubi(.subheadline).weight(.semibold)).accessibilityAddTraits(.isHeader)
                UmfrageErgebnis(result: result)
            } else if s.answered && s.isOpen && s.resultsMode == "after_close" {
                Text(tr("Das Ergebnis erscheint nach dem Ende der Umfrage.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Antwortformular für alle Fragearten.
private struct UmfrageFormular: View {
    @EnvironmentObject private var model: AppModel
    let survey: MemberSurvey
    let cancel: (() -> Void)?
    let send: @MainActor ([Int: SurveyAnswerRow]) async -> Void
    @State private var draft: [Int: SurveyAnswerRow] = [:]

    init(survey: MemberSurvey, cancel: (() -> Void)?, send: @escaping @MainActor ([Int: SurveyAnswerRow]) async -> Void) {
        self.survey = survey
        self.cancel = cancel
        self.send = send
        _draft = State(initialValue: survey.initialDraft())
    }

    private func row(_ q: SurveyQuestion) -> Binding<SurveyAnswerRow> {
        Binding(get: { draft[q.id] ?? SurveyAnswerRow(question: q.id) }, set: { draft[q.id] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(survey.questions) { q in
                UmfrageFrage(question: q, row: row(q))
            }
            if survey.anonymous {
                Text(tr("Anonym. Deine Antwort lässt sich danach nicht mehr ändern.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
            }
            KnopfReihe {
                if let cancel {
                    Button(tr("Abbrechen"), action: cancel).buttonStyle(.bordered)
                }
                Button(survey.answered ? tr("Änderung speichern") : tr("Absenden")) {
                    Task { await send(draft) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.loading || !survey.ready(draft))
            }
        }
        .entwurf(draft != survey.initialDraft())
    }
}

/// Eine Frage im Formular.
private struct UmfrageFrage: View {
    let question: SurveyQuestion
    @Binding var row: SurveyAnswerRow

    /// `kontext`: wozu die Auswahl gehört (Tag bei der Terminfindung), für VoiceOver (IOS-13)
    private func auswahl(_ label: String, selected: Bool, radio: Bool, kontext: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Ganze Zeile mit mindestens 44 pt antippbar (IOS-15, wie Android AND-14)
            HStack {
                Image(systemName: selected ? (radio ? "largecircle.fill.circle" : "checkmark.square.fill") : (radio ? "circle" : "square"))
                Text(label).foregroundStyle(Color.primary)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kontext.map { "\($0): \(label)" } ?? label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    var body: some View {
        let q = question
        VStack(alignment: .leading, spacing: 6) {
            Text(q.required ? q.text : tr("{text} (freiwillig)", ["text": q.text])).font(.hubi(.subheadline).weight(.semibold))
            switch q.kind {
            case "single", "multiple":
                let chosen = row.options ?? []
                let multi = q.kind == "multiple"
                if multi, let max = q.maxChoices {
                    Text(tr("Höchstens {n} Antworten", ["n": max])).font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                ForEach(q.options) { o in
                    let base = umfrageOption(label: o.label, startsAt: o.startsAt, allDay: o.allDay)
                    let label = o.capacity.map { "\(base) (\(tr("{n} Plätze", ["n": $0])))" } ?? base
                    auswahl(label, selected: chosen.contains(o.id), radio: !multi) {
                        if !multi { row.options = [o.id] }
                        else if chosen.contains(o.id) { row.options = chosen.filter { $0 != o.id } }
                        else { row.options = chosen + [o.id] }
                    }
                }
                if !multi && !q.required && !chosen.isEmpty {
                    Button(tr("Auswahl löschen")) { row.options = [] }.font(.hubi(.footnote))
                }
            case "yesno":
                KnopfReihe(spacing: 16) {
                    ForEach(["yes", "no", "abstain"], id: \.self) { v in
                        auswahl(surveyValueLabel(v), selected: row.value == v, radio: true) { row.value = v }
                    }
                }
            case "dates":
                let values = q.allowMaybe ? ["yes", "maybe", "no"] : ["yes", "no"]
                ForEach(q.options) { o in
                    let tag = umfrageOption(label: o.label, startsAt: o.startsAt, allDay: o.allDay)
                    Text(tag).accessibilityHidden(true)
                    KnopfReihe(spacing: 16) {
                        ForEach(values, id: \.self) { v in
                            let key = String(o.id)
                            auswahl(surveyValueLabel(v), selected: row.dates?[key] == v, radio: true, kontext: tag) {
                                var dates = row.dates ?? [:]
                                dates[key] = v
                                row.dates = dates
                            }
                        }
                    }
                }
            case "quantity":
                let amounts = row.quantities ?? [:]
                Text(trn("Zusammen höchstens {n} Stück", "Zusammen höchstens {n} Stück", q.quantityLimit))
                    .font(.hubi(.footnote)).foregroundStyle(.secondary)
                ForEach(q.options) { o in
                    let key = String(o.id)
                    Stepper(value: Binding(
                        get: { amounts[key] ?? 0 },
                        set: { var next = amounts; next[key] = max(0, $0); row.quantities = next }
                    ), in: 0...max(q.quantityLimit, 1)) {
                        Text("\(umfrageOption(label: o.label, startsAt: o.startsAt, allDay: o.allDay)): \(amounts[key] ?? 0)")
                    }
                }
                if amounts.values.reduce(0, +) > q.quantityLimit {
                    ZustandText(tr("Zusammen höchstens {n} Stück.", ["n": q.quantityLimit]), .fehler)
                }
            default:
                TextField(tr("Antwort"), text: Binding(
                    get: { row.text ?? "" },
                    set: { row.text = String($0.prefix(500)) }
                ), axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
            }
        }
        // Antworten als Gruppe mit der Frage als Beschriftung (IOS-13)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(q.text)
    }
}

/// Ergebnis wie im Browser: Zahl, Balken, Namen nur bei offenen Umfragen.
struct UmfrageErgebnis: View {
    let result: SurveyResult

    var body: some View {
        if result.hidden {
            Text(tr("Das Ergebnis erscheint ab fünf Antworten, damit niemand zurückrechnen kann.") + " "
                + trn("Bisher {n} Antwort.", "Bisher {n} Antworten.", result.participants))
                .font(.hubi(.footnote)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(trn("{n} Teilnahme", "{n} Teilnahmen", result.participants)).font(.hubi(.footnote)).foregroundStyle(.secondary)
                ForEach(result.questions) { q in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(q.text).font(.hubi(.subheadline).weight(.semibold))
                        if let values = q.values {
                            ForEach(["yes", "no", "abstain"], id: \.self) { v in
                                if let entry = values[v] {
                                    zeile(surveyValueLabel(v), count: entry.count, total: result.participants, names: entry.names)
                                }
                            }
                        }
                        if q.kind == "text" {
                            if (q.texts ?? []).isEmpty {
                                Text(tr("Noch keine Antworten.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                            }
                            ForEach(Array((q.texts ?? []).enumerated()), id: \.offset) { _, t in
                                Text(t.name.isEmpty ? "„\(t.text)“" : "„\(t.text)“ · \(t.name)")
                            }
                        }
                        if let options = q.options {
                            let base = q.kind == "quantity" ? max(1, options.map(\.count).max() ?? 1) : result.participants
                            ForEach(options) { o in
                                let label = umfrageOption(label: o.label, startsAt: o.startsAt, allDay: o.allDay)
                                let count = o.capacity.map { "\(o.count) / \($0)" } ?? "\(o.count)"
                                let extra = q.kind == "dates" && o.maybe > 0 ? " " + tr("+{n} vielleicht", ["n": o.maybe]) : ""
                                zeile(q.best.contains(o.id) ? tr("{label} · meiste Stimmen", ["label": label]) : label, count: o.count, total: base, names: o.names, text: count + extra)
                            }
                        }
                    }
                }
            }
        }
    }

    private func zeile(_ label: String, count: Int, total: Int, names: [String], text: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(text ?? "\(count)").monospacedDigit()
            }
            ProgressView(value: total > 0 ? Double(count) / Double(total) : 0)
            if !names.isEmpty {
                Text(names.joined(separator: ", ")).font(.hubi(.footnote)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
