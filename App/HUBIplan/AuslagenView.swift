import HubiplanKern
import SwiftUI

// „Ich“ › Auslagen (HUBIplan Auslagen erstatten), wie in der Android-App: selbst bezahlte
// Ausgaben mit Foto des Belegs melden, Rückfragen der Kasse beantworten, Stand sehen.
// Fotos werden verkleinert und ohne Aufnahmedaten gesendet (BelegBild), nichts bleibt auf dem Gerät.

/// „2099-01-02“ als Tag (Mitternacht in der Zeitzone des Geräts).
private func kalendertag(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: text)
}

struct AuslagenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var creating = false
    @State private var notice: String?

    var body: some View {
        let overview = model.expenses ?? ExpenseOverview()
        List {
            if let message = model.error {
                Section { MeldungText(message, .fehler) }
            }
            if let notice {
                Section { MeldungText(notice, .gut) }
            }
            if !overview.options.maySubmit {
                Section { Text(tr("Auslagen melden hier nur Personen mit Amt oder Rolle im Verein.")) }
            } else {
                Section {
                    Button(tr("Auslage melden")) {
                        notice = nil
                        creating = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if overview.claims.isEmpty {
                Text(tr("Hast du etwas für den Verein selbst bezahlt? Melde es hier mit einem Foto des Belegs, die Kasse erstattet dir den Betrag."))
                    .foregroundStyle(.secondary)
            }
            ForEach(overview.claims) { claim in
                NavigationLink {
                    AuslageView(id: claim.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text([claim.number.isEmpty ? tr("Entwurf") : claim.number, claim.purpose.isEmpty ? tr("ohne Zweck") : claim.purpose].joined(separator: " · "))
                            .font(.hubi(.headline))
                        Text(claim.line).font(.hubi(.footnote)).foregroundStyle(.secondary)
                        if claim.asksMe {
                            ZustandText(tr("Die Kasse hat eine Rückfrage."), .warnung).font(.hubi(.footnote))
                        }
                    }
                }
            }
        }
        .navigationTitle(tr("Auslagen"))
        .task { await model.reloadExpenses() }
        .refreshable { await model.reloadExpenses() }
        .sheet(isPresented: $creating) {
            NavigationStack {
                AuslageFormular(options: overview.options) { claim in
                    creating = false
                    notice = claim.status == "draft"
                        ? tr("Entwurf gespeichert.")
                        : tr("Auslage {number} ist eingereicht. Du bekommst Bescheid, sobald sie geprüft ist.", ["number": claim.number])
                    Task { await model.reloadExpenses() }
                }
            }
        }
    }
}

/// Neue Auslage: Zweck, Datum, Beträge oder Fahrt, Fotos, Auszahlung.
private struct AuslageFormular: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let options: ExpenseOptions
    let done: (ExpenseClaim) -> Void
    @State private var draft: ExpenseDraft
    /// Ausgangsstand, um Änderungen zu erkennen (IOS-09)
    private let start: ExpenseDraft
    @State private var photos: [Data] = []
    @State private var busy = false
    @State private var failure: String?
    /// Ein Schlüssel je Formular: erneutes Senden nach einem Abbruch legt nichts doppelt an
    @State private var key = UUID().uuidString

    init(options: ExpenseOptions, done: @escaping (ExpenseClaim) -> Void) {
        self.options = options
        self.done = done
        let start = ExpenseDraft(date: Zeit.day(Date()), payee: options.payee)
        self.start = start
        _draft = State(initialValue: start)
    }

    var body: some View {
        Form {
            if options.mileageEnabled {
                Picker(tr("Art"), selection: $draft.kind) {
                    Text(tr("Auslage mit Beleg")).tag("expense")
                    Text(tr("Fahrtkosten")).tag("mileage")
                }
                .pickerStyle(.segmented)
            }
            Section {
                BeschriftetesFeld(label: tr("Wofür, für wen?"), text: $draft.purpose, axis: .vertical)
                // Datum zum Auswählen statt Tippen, höchstens heute (UX-Audit 16.11., IOS-20)
                DatePicker(
                    draft.kind == "mileage" ? tr("Datum der Fahrt") : tr("Datum des Kaufs"),
                    selection: Binding(
                        get: { kalendertag(draft.date) ?? Date() },
                        set: { draft.date = Zeit.day($0) }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
            }
            if draft.kind == "mileage" {
                Section {
                    BeschriftetesFeld(label: tr("Start, Ziel und Anlass"), text: $draft.route)
                    BeschriftetesFeld(label: tr("Gefahrene Kilometer (hin und zurück)"), text: $draft.km)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text(tr("{rate} je km", ["rate": Geld.format(options.kmRate)]))
                }
            } else {
                Section {
                    ForEach(draft.amounts.indices, id: \.self) { i in
                        BeschriftetesFeld(
                            label: draft.amounts.count > 1 ? tr("Betrag {n} in €", ["n": i + 1]) : tr("Betrag in €"),
                            text: $draft.amounts[i]
                        )
                        .keyboardType(.decimalPad)
                    }
                    if draft.amounts.count < 20 {
                        Button(tr("Weitere Position")) { draft.amounts.append("") }
                    }
                }
                Section {
                    ForEach(photos.indices, id: \.self) { i in
                        HStack {
                            if let image = UIImage(data: photos[i]) {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 72, height: 72)
                                    .accessibilityLabel(tr("Beleg {n}", ["n": i + 1]))
                            }
                            Spacer()
                            Button(tr("Entfernen"), role: .destructive) { photos.remove(at: i) }
                        }
                    }
                    if photos.count < 10 {
                        BelegWahl(again: false) { jpeg in
                            photos.append(jpeg)
                        } failed: { message in
                            failure = message
                        }
                    }
                } header: {
                    Text(tr("Belege"))
                }
            }
            Section {
                Picker(tr("Auszahlung"), selection: $draft.payout) {
                    Text(tr("Überweisung")).tag("bank")
                    Text(tr("Bar")).tag("cash")
                }
                .pickerStyle(.segmented)
                if draft.payout == "bank" {
                    BeschriftetesFeld(label: tr("Kontoinhaber"), text: $draft.holder)
                        .textInputAutocapitalization(.words)
                    BeschriftetesFeld(label: tr("IBAN"), text: $draft.iban)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            } header: {
                Text(tr("Auszahlung"))
            }
            if let failure {
                Section { MeldungText(failure, .fehler) }
            }
            Section {
                Button(tr("Als Entwurf speichern")) { Task { await send(submit: false) } }
                    .disabled(busy)
            } footer: {
                // Was zum Einreichen fehlt, steht hier, bevor etwas gesendet wird (IOS-20)
                if let missing { Text(missing) }
            }
        }
        .tastaturFuehrung()
        .navigationTitle(tr("Neue Auslage"))
        .toolbar {
            // Bestätigen oben rechts wie in jedem Blatt; erst aktiv, wenn alles da ist (IOS-20)
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Einreichen")) { Task { await send(submit: true) } }
                    .disabled(busy || missing != nil)
            }
        }
        .eingabeschutz(draft != start || !photos.isEmpty, disabled: busy)
    }

    private var missing: String? { draft.missing(photos: photos.count, today: Zeit.day(Date())) }

    private func send(submit: Bool) async {
        if submit, missing != nil { return }
        busy = true
        failure = nil
        defer { busy = false }
        let draft = draft
        let photos = photos
        let key = key
        switch await model.portalCall({ api, access in
            try await api.createExpense(accessId: access, draft: draft, submit: submit, photos: photos, key: key)
        }) {
        case .success(let claim):
            done(claim)
        case .failure(let error):
            failure = error.status == 0
                ? tr("Ohne Verbindung: Die Angaben bleiben hier stehen. Bitte später erneut senden.")
                : error.text
        case nil:
            break
        }
    }
}

/// Eine Auslage: Stand, Rückfrage beantworten, Beleg ergänzen, einreichen, zurückziehen.
private struct AuslageView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let id: Int
    @State private var claim: ExpenseClaim?
    @State private var failure: String?
    @State private var notice: String?
    @State private var busy = false
    @State private var answer = ""
    @State private var confirmWithdraw = false

    var body: some View {
        List {
            if let failure {
                Section { MeldungText(failure, .fehler) }
            }
            if let notice {
                Section { MeldungText(notice, .gut) }
            }
            if let c = claim {
                Section {
                    Text([c.number.isEmpty ? tr("Entwurf") : c.number, c.statusLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.hubi(.headline))
                        .accessibilityAddTraits(.isHeader)
                    if !c.purpose.isEmpty { Text(c.purpose) }
                    Text(tr("Summe: {amount}", ["amount": Geld.format(c.total)]))
                    if let approved = c.approvedAmount, approved != c.total {
                        Text(tr("Freigegeben: {amount} ({reason})", ["amount": Geld.format(approved), "reason": c.reduceReason]))
                    }
                    if !c.rejectReason.isEmpty {
                        Text(tr("Grund der Ablehnung: {reason}", ["reason": c.rejectReason]))
                    }
                    if let day = c.purchaseDate.flatMap(kalendertag) {
                        Text(tr("Datum: {day}", ["day": day.formatted(.dateTime.day().month().year().locale(Texte.locale))]))
                    }
                    Text(trn("1 Beleg", "{n} Belege", c.files.count)).font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                if c.asksMe {
                    Section {
                        if let question = c.question {
                            ZustandText(tr("Rückfrage der Kasse: {text}", ["text": question]), .warnung)
                        }
                        TextField(tr("Deine Antwort"), text: $answer, axis: .vertical)
                        Button(tr("Antwort senden")) {
                            let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                if await act(tr("Antwort gesendet. Die Kasse prüft erneut."), { api, access in
                                    try await api.expenseAction(accessId: access, id: id, action: "answer", text: text)
                                }) { answer = "" }
                            }
                        }
                        .disabled(busy || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if c.status == "draft", !c.problems.isEmpty {
                    Section {
                        Text(tr("Zum Einreichen fehlt noch: {list}", ["list": c.problems.values.sorted().joined(separator: " ")]))
                            .font(.hubi(.footnote))
                    }
                }
                if c.canAddFile {
                    Section {
                        BelegWahl(again: false) { jpeg in
                            Task {
                                _ = await act(tr("Beleg hinzugefügt.")) { api, access in
                                    _ = try await api.addExpensePhoto(accessId: access, id: id, jpeg: jpeg)
                                }
                            }
                        } failed: { message in
                            failure = message
                        }
                        .disabled(busy)
                    }
                }
                Section {
                    if c.status == "draft" {
                        Button(tr("Einreichen")) {
                            Task {
                                _ = await act(tr("Auslage eingereicht.")) { api, access in
                                    try await api.expenseAction(accessId: access, id: id, action: "submit")
                                }
                            }
                        }
                    }
                    if c.canWithdraw {
                        Button(c.isLooseDraft ? tr("Löschen") : tr("Zurückziehen"), role: .destructive) { confirmWithdraw = true }
                    }
                }
                .disabled(busy)
                if !c.events.isEmpty {
                    Section {
                        ForEach(Array(c.events.enumerated()), id: \.offset) { _, e in
                            let day = Zeit.parse(e.at).map { $0.formatted(.dateTime.day().month().year().locale(Texte.locale)) } ?? ""
                            Text([day, e.label, e.who, e.text].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.hubi(.footnote))
                        }
                    } header: {
                        Text(tr("Verlauf"))
                    }
                }
            } else if failure == nil {
                Laedt()
            }
        }
        .navigationTitle(claim.map { $0.number.isEmpty ? tr("Entwurf") : $0.number } ?? tr("Auslage"))
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            claim?.isLooseDraft == true ? tr("Entwurf löschen?") : tr("Auslage zurückziehen?"),
            isPresented: $confirmWithdraw,
            titleVisibility: .visible
        ) {
            if claim?.isLooseDraft == true {
                Button(tr("Löschen"), role: .destructive) {
                    Task {
                        if await act(tr("Entwurf gelöscht."), { api, access in
                            try await api.deleteExpense(accessId: access, id: id)
                        }, reload: false) {
                            await model.reloadExpenses()
                            dismiss()
                        }
                    }
                }
            } else {
                Button(tr("Zurückziehen"), role: .destructive) {
                    Task {
                        _ = await act(tr("Auslage zurückgezogen.")) { api, access in
                            try await api.expenseAction(accessId: access, id: id, action: "withdraw")
                        }
                    }
                }
            }
            Button(tr("Abbrechen"), role: .cancel) {}
        } message: {
            Text(claim?.purpose ?? "")
        }
    }

    private func load() async {
        switch await model.portalCall({ api, access in try await api.memberExpense(accessId: access, id: id) }) {
        case .success(let fresh):
            claim = fresh
            failure = nil
        case .failure(let error):
            failure = error.text
        case nil:
            break
        }
    }

    /// Eine Aktion; danach neu laden. `true`, wenn sie geklappt hat.
    private func act(_ done: String, _ work: @escaping (Api, Int) async throws -> Void, reload: Bool = true) async -> Bool {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        switch await model.portalCall({ api, access in try await work(api, access) }) {
        case .success:
            notice = done
            if reload {
                await load()
                await model.reloadExpenses()
            }
            return true
        case .failure(let error):
            failure = error.text
            return false
        case nil:
            return false
        }
    }
}
