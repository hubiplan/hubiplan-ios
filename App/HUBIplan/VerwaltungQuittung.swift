import HubiplanKern
import SwiftUI

// Verwaltung: Quittung mit Unterschrift (Bargeld gegen zwei Unterschriften).

/// Unterschrift als Linien, eingepasst in die Fläche.
struct UnterschriftBild: View {
    let lines: [[(x: Double, y: Double)]]
    let width: Double
    let height: Double

    var body: some View {
        Canvas { context, size in
            guard width > 0, height > 0 else { return }
            let factor = min(size.width / width, size.height / height)
            let dx = (size.width - width * factor) / 2
            let dy = (size.height - height * factor) / 2
            for line in lines where line.count > 1 {
                var path = Path()
                path.move(to: CGPoint(x: dx + line[0].x * factor, y: dy + line[0].y * factor))
                for point in line.dropFirst() {
                    path.addLine(to: CGPoint(x: dx + point.x * factor, y: dy + point.y * factor))
                }
                context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Vollbild zum Unterschreiben: oben steht, was bestätigt wird.
private struct UnterschriftFeld: View {
    let title: String
    let text: String
    let done: (SignatureStrokes) -> Void
    let cancel: () -> Void
    @State private var lines: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var area = CGSize.zero
    @State private var confirmDiscard = false

    private var all: [[CGPoint]] { lines + [current] }
    private var empty: Bool { !all.contains { $0.count > 1 } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
                        Canvas { context, _ in
                            for line in all where line.count > 1 {
                                var path = Path()
                                path.addLines(line)
                                context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            }
                        }
                        Rectangle().fill(Color.secondary).frame(height: 1)
                            .padding(.horizontal, 24).padding(.bottom, 44)
                        Text(title).font(.footnote).foregroundStyle(Color.secondary)
                            .padding(.horizontal, 24).padding(.bottom, 20)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in current.append(value.location) }
                            .onEnded { _ in
                                if current.count > 1 { lines.append(current) }
                                current = []
                            }
                    )
                    .onAppear { area = proxy.size }
                    .onChange(of: proxy.size) { old, new in
                        // Drehen: vorhandene Linien mitziehen
                        if old.width > 0, old.height > 0 {
                            lines = lines.map { line in line.map { CGPoint(x: $0.x * new.width / old.width, y: $0.y * new.height / old.height) } }
                        }
                        area = new
                    }
                    .accessibilityLabel(tr("Unterschriftsfeld: {name}", ["name": title]))
                }
                Text(tr("Tipp: Gerät quer halten, dann ist mehr Platz.")).font(.footnote).foregroundStyle(Color.secondary)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Abbrechen")) { if empty { cancel() } else { confirmDiscard = true } }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(tr("Löschen")) {
                        lines = []
                        current = []
                    }
                    .disabled(empty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Übernehmen")) {
                        let drawn = all.map { line in line.map { (x: Double($0.x), y: Double($0.y)) } }
                        if let strokes = SignatureStrokes(width: Double(area.width), height: Double(area.height), lines: drawn) { done(strokes) }
                    }
                    .disabled(empty)
                }
            }
            .confirmationDialog(tr("Unterschrift verwerfen?"), isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(tr("Verwerfen"), role: .destructive) { cancel() }
                Button(tr("Weiter unterschreiben"), role: .cancel) {}
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Quittung ausstellen: Angaben, zwei Unterschriften, Bestätigung, Abschluss.
struct QuittungBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let done: () -> Void
    @State private var draft = ReceiptDraft()
    @State private var accounts: [FinanceAccount]?
    @State private var categories: [FinanceCategory] = []
    @State private var stored: SignatureShape?
    /// Ohne Verbindung: Auswahl vom letzten Mal, die Quittung wird später abgeschlossen
    @State private var offline = false
    @State private var noChoices = false
    @State private var signing: String?
    @State private var askDecline = false
    @State private var declineText = ""
    @State private var confirmed = false
    @State private var error: String?
    @State private var saving = false
    @State private var finished: CashReceiptItem?

    private var fitting: [FinanceCategory] { FinanceCategory.matching(categories, kind: draft.kind) }
    private var ready: Bool {
        draft.formReady && draft.treasurerReady(stored: stored != nil) && draft.counterpartyReady && confirmed
    }
    /// Unterschriebene Angaben: ändern sie sich, müssen beide neu unterschreiben
    private var signedValues: String { "\(draft.receives)|\(draft.name)|\(draft.amount)|\(draft.purpose)" }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { MeldungText(error, .fehler) } }
                if let finished {
                    fertig(finished)
                } else if let accounts {
                    if accounts.isEmpty {
                        Section {
                            Text(tr("Es gibt keine Barkasse. Bitte im Browser unter Finanzen › Einrichtung › Konten eine anlegen."))
                        }
                    } else {
                        angaben(accounts)
                        unterschriften
                        abschluss
                    }
                } else if noChoices {
                    Section {
                        Text(tr("Ohne Netz und ohne gespeicherte Auswahl. Bitte einmal mit Netz öffnen."))
                        Button(tr("Erneut laden")) { Task { await load() } }
                    }
                } else if error == nil {
                    Laedt()
                }
            }
            .disabled(saving)
            .navigationTitle(tr("Quittung"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished == nil ? tr("Abbrechen") : tr("Fertig")) { dismiss() }
                }
            }
            .onChange(of: signedValues) { _, _ in
                draft.signedChanged()
                confirmed = false
                // Ein schon angelegter Entwurf auf dem Server trägt die alten Angaben: neu anlegen
                if draft.serverId != nil {
                    let fresh = ReceiptDraft()
                    draft.serverId = nil
                    draft.key = fresh.key
                    draft.finalizeKey = fresh.finalizeKey
                }
            }
            .onChange(of: draft.receives) { _, _ in draft.category = nil }
            .task { await load() }
            .fullScreenCover(item: Binding(get: { signing.map(Rolle.init) }, set: { signing = $0?.id })) { rolle in
                Group {
                    UnterschriftFeld(
                        title: rolle.id == "treasurer" ? tr("Kassierer") : draft.name.trimmingCharacters(in: .whitespaces),
                        text: rolle.id == "treasurer" ? draft.treasurerText : draft.counterpartyText(unitName: unit.name)
                    ) { strokes in
                        let now = Zeit.stamp(Date())
                        if rolle.id == "treasurer" {
                            draft.treasurer = strokes
                            draft.treasurerAt = now
                            draft.useStored = false
                        } else {
                            draft.counterparty = strokes
                            draft.counterpartyAt = now
                            draft.declined = ""
                        }
                        signing = nil
                    } cancel: {
                        signing = nil
                    }
                }
                .verwaltungsBlatt()
            }
            .alert(tr("Zahler unterschreibt nicht"), isPresented: $askDecline) {
                TextField(tr("Grund"), text: $declineText)
                Button(tr("Übernehmen")) {
                    let reason = declineText.trimmingCharacters(in: .whitespaces)
                    if !reason.isEmpty {
                        draft.counterparty = nil
                        draft.declined = reason
                    }
                }
                Button(tr("Abbrechen"), role: .cancel) {}
            } message: {
                Text(tr("Dann gilt nur deine Unterschrift als Kassierer, wie bei einer Papierquittung."))
            }
        }
    }

    private struct Rolle: Identifiable {
        let id: String
    }

    @ViewBuilder
    private func angaben(_ accounts: [FinanceAccount]) -> some View {
        Section {
            Picker(tr("Richtung"), selection: $draft.receives) {
                Text(tr("Verein zahlt aus")).tag(false)
                Text(tr("Verein erhält Geld")).tag(true)
            }
            .pickerStyle(.segmented)
            BeschriftetesFeld(label: draft.receives ? tr("Zahler (Name)") : tr("Empfänger (Name)"), text: $draft.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            BeschriftetesFeld(label: tr("Betrag in €"), text: $draft.amount)
                .keyboardType(.decimalPad)
            BeschriftetesFeld(label: tr("Zweck"), text: $draft.purpose)
            BeschriftetesFeld(label: tr("E-Mail für das PDF (optional)"), text: $draft.email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker(tr("Konto"), selection: $draft.account) {
                ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker(tr("Kategorie"), selection: $draft.category) {
                Text(tr("Bitte wählen")).tag(Int?.none)
                ForEach(fitting) { Text($0.name).tag(Optional($0.id)) }
            }
        } footer: {
            Text(tr("Ändern sich Betrag, Name, Zweck oder Richtung, müssen beide neu unterschreiben. Abgeschlossene Quittungen lassen sich nur im Browser stornieren."))
        }
    }

    @ViewBuilder
    private var unterschriften: some View {
        Section {
            Button {
                signing = "treasurer"
            } label: {
                feld(lines: kassierer, hint: kassiererHinweis)
            }
            .disabled(!draft.formReady)
        } header: {
            Text(draft.receives ? tr("Betrag erhalten (Kassierer)") : tr("Betrag ausgezahlt (Kassierer)"))
        }
        Section {
            if draft.declined.isEmpty {
                Button {
                    signing = "counterparty"
                } label: {
                    feld(lines: gegenseite, hint: tr("Antippen: im Vollbild unterschreiben lassen"))
                }
                .disabled(!draft.formReady)
                if draft.receives, draft.counterparty == nil {
                    Button(tr("Zahler unterschreibt nicht")) {
                        declineText = ""
                        askDecline = true
                    }
                    .disabled(!draft.formReady)
                }
            } else {
                Text(tr("ohne Unterschrift: {grund}", ["grund": draft.declined]))
                Button(tr("Doch unterschreiben lassen")) { draft.declined = "" }
            }
        } header: {
            Text(draft.receives ? tr("Betrag gezahlt (Zahler)") : tr("Betrag erhalten (Empfänger)"))
        } footer: {
            if !draft.formReady { Text(tr("Erst Name, Betrag, Zweck und Kategorie angeben")) }
        }
    }

    private typealias Linien = ([[(x: Double, y: Double)]], Double, Double)

    private var kassierer: Linien? {
        if let own = draft.treasurer { return (own.lines, Double(own.width), Double(own.height)) }
        if draft.useStored, let stored { return (stored.lines, Double(stored.w), Double(stored.h > 0 ? stored.h : max(stored.w / 3, 1))) }
        return nil
    }

    private var kassiererHinweis: String {
        if draft.treasurer == nil, draft.useStored, stored != nil {
            return tr("Deine hinterlegte Unterschrift. Antippen, um neu zu unterschreiben.")
        }
        return tr("Antippen zum Unterschreiben")
    }

    private var gegenseite: Linien? {
        guard let other = draft.counterparty else { return nil }
        return (other.lines, Double(other.width), Double(other.height))
    }

    private func feld(lines: Linien?, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lines {
                UnterschriftBild(lines: lines.0, width: lines.1, height: lines.2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
            }
            Text(hint).font(.footnote).foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var abschluss: some View {
        Section {
            Toggle(isOn: $confirmed) {
                Text(draft.receives
                    ? tr("Ich bestätige, {betrag} erhalten zu haben.", ["betrag": Geld.format(draft.parsedAmount)])
                    : tr("Ich bestätige, {betrag} ausgezahlt zu haben.", ["betrag": Geld.format(draft.parsedAmount)]))
            }
            .disabled(!draft.formReady)
            if !draft.email.trimmingCharacters(in: .whitespaces).isEmpty {
                Toggle(tr("PDF an {adresse} senden", ["adresse": draft.email.trimmingCharacters(in: .whitespaces)]), isOn: $draft.sendMail)
            }
            Button(tr("Quittung abschließen")) { Task { await finish() } }
                .disabled(!ready)
        } footer: {
            if offline { Text(tr("Ohne Netz: Die Quittung wird gespeichert und später abgeschlossen.")) }
        }
    }

    @ViewBuilder
    private func fertig(_ item: CashReceiptItem) -> some View {
        Section {
            Text(tr("Quittung {nummer} abgeschlossen", ["nummer": item.number])).font(.headline)
            Text(tr("Gebucht in der {konto}. Das PDF hängt als Beleg an der Buchung.", ["konto": item.accountName]))
        }
    }

    private func load() async {
        let box = model.draftBox
        let result = await model.verwaltung(unit) { try await $0.receiptChoices(box: box) }
        guard let result else {
            error = model.adminError
            return
        }
        error = nil
        offline = result.offline
        noChoices = result.choices == nil
        guard let choices = result.choices else { return }
        accounts = choices.accounts
        categories = choices.categories
        stored = choices.signature
        if draft.account == nil, choices.accounts.count == 1 { draft.account = choices.accounts[0].id }
        // Vorführmodus: ausgefülltes Blatt für das Bildschirmfoto
        if Demo.active, draft.name.isEmpty {
            draft.name = "Max Mustermann"
            draft.amount = Texte.language == "en" ? "25.00" : "25,00"
            draft.purpose = Texte.language == "en" ? "Expenses for flowers" : "Auslagen Blumen"
            draft.category = fitting.last?.id
            // Erst nach dem Zurücksetzen durch die geänderten Angaben
            try? await Task.sleep(for: .milliseconds(400))
            draft.counterparty = SignatureStrokes(width: 300, height: 100, strokes: [[[20, 70], [50, 30], [70, 75], [95, 35], [120, 70], [160, 55], [210, 60], [270, 45]]])
            confirmed = true
        }
    }

    private func finish() async {
        error = nil
        let choices = ReceiptChoices(accounts: accounts ?? [], categories: categories, signature: stored)
        guard let receipt = StoredReceipt(draft, unit: unit, choices: choices) else {
            error = tr("Bitte Angaben und Unterschriften prüfen.")
            return
        }
        saving = true
        defer { saving = false }
        // Erst verschlüsselt sichern, dann senden: ohne Verbindung bleibt die Quittung auf dem Gerät.
        let box = model.draftBox
        let outcome = await model.verwaltung(unit) { client -> ReceiptOutcome in
            if let box { return try await client.submit(receipt, box: box) { id in draft.serverId = id } }
            return .finished(try await client.submitReceipt(receipt.draft) { id in draft.serverId = id })
        }
        switch outcome {
        case let .finished(item):
            finished = item
            model.adminDone(tr("Quittung {nummer} abgeschlossen", ["nummer": item.number]))
            done()
        case .kept:
            model.adminDone(tr("Ohne Verbindung: Quittung gespeichert, wird später abgeschlossen"))
            done()
            dismiss()
        case nil:
            error = model.adminError
        }
    }
}
