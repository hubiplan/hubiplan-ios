import HubiplanKern
import PhotosUI
import SwiftUI

// Verwaltung: Kassenbuch mit Kontoständen, Buchungen, Belegen und „Neue Buchung“ mit Belegfoto.

/// Belegfoto für den Versand: verkleinert, als JPEG und ohne Aufnahmedaten (wie in der Android-App).
enum BelegBild {
    static let maxSide: CGFloat = 1600

    static func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let factor = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * factor).rounded(), height: (image.size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Neu zeichnen: richtet das Bild auf und lässt Ort, Gerät und Zeit der Aufnahme weg
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return drawn.jpegData(compressionQuality: 0.88)
    }
}

/// Kamera für ein Belegfoto.
struct KameraBild: UIViewControllerRepresentable {
    let taken: (UIImage?) -> Void

    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(taken: taken) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let taken: (UIImage?) -> Void

        init(taken: @escaping (UIImage?) -> Void) { self.taken = taken }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            taken(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            taken(nil)
        }
    }
}

/// Knöpfe „Beleg fotografieren“ und „Aus der Mediathek“; liefert das fertige JPEG.
struct BelegWahl: View {
    let again: Bool
    let picked: (Data) -> Void
    let failed: (String) -> Void
    @State private var camera = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        Group {
            if KameraBild.available {
                Button {
                    camera = true
                } label: {
                    Label(again ? tr("Neu fotografieren") : tr("Beleg fotografieren"), systemImage: "camera")
                }
            }
            PhotosPicker(selection: $item, matching: .images) {
                Label(tr("Aus der Mediathek"), systemImage: "photo.on.rectangle")
            }
        }
        .fullScreenCover(isPresented: $camera) {
            KameraBild { image in
                camera = false
                if let image { use(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            item = nil
            Task {
                guard let data = try? await chosen.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    failed(tr("Das Bild ließ sich nicht öffnen."))
                    return
                }
                use(image)
            }
        }
    }

    private func use(_ image: UIImage) {
        if let jpeg = BelegBild.jpeg(image) { picked(jpeg) } else { failed(tr("Das Bild ließ sich nicht öffnen.")) }
    }
}

/// Kontostände und letzte Buchungen der Einheit.
struct KassenbuchView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var accounts: [FinanceAccount]?
    /// Buchungen dieser Einheit, die noch nicht gesendet sind
    @State private var drafts: [StoredBooking] = []
    /// Unterschriebene Quittungen dieser Einheit, die noch nicht abgeschlossen sind
    @State private var receipts: [StoredReceipt] = []
    @State private var unreadable = 0
    @State private var fix: StoredBooking?
    @State private var discard: StoredBooking?
    @State private var fixReceipt: StoredReceipt?
    @State private var discardReceipt: StoredReceipt?
    @State private var confirmUnreadable = false
    @State private var bookings: [BookingItem] = []
    @State private var count = 0
    @State private var page = 1
    @State private var more = false
    @State private var withoutReceipt = false
    @State private var creating = false
    @State private var receipt = false
    @State private var finishedDemo = false
    /// Vorführmodus: für das Bildschirmfoto gleich in eine Buchung
    @State private var showDemo = Demo.active && Demo.section == "buchung"

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                entwuerfe
                if let accounts {
                    Section(tr("Konten")) {
                        if accounts.isEmpty { Text(tr("Keine.")).foregroundStyle(.secondary) }
                        ForEach(accounts) { account in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                    if !account.kindLabel.isEmpty {
                                        Text(account.kindLabel).font(.footnote).foregroundStyle(Color.secondary)
                                    }
                                }
                                Spacer()
                                Text(Geld.format(account.balance)).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Section {
                        Picker(tr("Buchungen"), selection: $withoutReceipt) {
                            Text(tr("Letzte Buchungen")).tag(false)
                            Text(tr("Ohne Beleg")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                        if bookings.isEmpty {
                            Text(withoutReceipt ? tr("Alle Buchungen haben einen Beleg.") : tr("Noch keine Buchungen."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(bookings) { booking in
                            NavigationLink {
                                BuchungView(unit: unit, id: booking.id)
                            } label: {
                                BuchungZeile(booking: booking)
                            }
                        }
                        if more {
                            Button(tr("Weitere laden ({n} von {gesamt})", ["n": bookings.count, "gesamt": count])) {
                                Task { await loadMore() }
                            }
                        }
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task(id: withoutReceipt) { await load() }
            .navigationDestination(isPresented: $showDemo) { BuchungView(unit: unit, id: 9) }
        }
        .navigationTitle(tr("Kassenbuch"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if unit.canEditFinance {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            creating = true
                        } label: {
                            Label(tr("Neue Buchung"), systemImage: "camera")
                        }
                        Button {
                            receipt = true
                        } label: {
                            Label(tr("Quittung mit Unterschrift"), systemImage: "signature")
                        }
                    } label: {
                        Label(tr("Neu"), systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $creating) {
            Group {
                NeueBuchungBlatt(unit: unit) {
                    Task { await load() }
                }
            }
            .verwaltungsBlatt()
        }
        .sheet(item: $fix) { draft in
            Group {
                EntwurfKorrigierenBlatt(unit: unit, line: draft.line, problem: draft.error, kind: draft.kind, account: draft.account, category: draft.category, cashOnly: false) { account, category in
                    model.draftBox?.save(draft.fixed(account: account, category: category)) == true
                } saved: {
                    Task { await load() }
                }
            }
            .verwaltungsBlatt()
        }
        .sheet(item: $fixReceipt) { receipt in
            Group {
                EntwurfKorrigierenBlatt(unit: unit, line: receipt.line, problem: receipt.error, kind: receipt.draft.kind, account: receipt.draft.account, category: receipt.draft.category, cashOnly: true) { account, category in
                    guard let category else { return false }
                    return model.draftBox?.save(receipt.fixed(account: account, category: category)) == true
                } saved: {
                    Task { await load() }
                }
            }
            .verwaltungsBlatt()
        }
        .confirmationDialog(
            tr("Quittung verwerfen?"),
            isPresented: Binding(get: { discardReceipt != nil }, set: { if !$0 { discardReceipt = nil } }),
            titleVisibility: .visible,
            presenting: discardReceipt
        ) { receipt in
            Button(tr("Verwerfen"), role: .destructive) {
                model.draftBox?.deleteReceipt(receipt.id)
                showDrafts()
            }
        } message: { _ in
            Text(tr("Die Quittung und beide Unterschriften werden von diesem Gerät gelöscht. Das lässt sich nicht rückgängig machen."))
        }
        .confirmationDialog(
            tr("Entwurf verwerfen?"),
            isPresented: Binding(get: { discard != nil }, set: { if !$0 { discard = nil } }),
            titleVisibility: .visible,
            presenting: discard
        ) { draft in
            Button(tr("Verwerfen"), role: .destructive) {
                model.draftBox?.delete(draft.key)
                showDrafts()
            }
        } message: { _ in
            Text(tr("Die Buchung und das Belegfoto werden von diesem Gerät gelöscht. Das lässt sich nicht rückgängig machen."))
        }
        .confirmationDialog(tr("Unlesbare Entwürfe löschen?"), isPresented: $confirmUnreadable, titleVisibility: .visible) {
            Button(tr("Löschen"), role: .destructive) {
                _ = model.draftBox?.discardUnreadable()
                showDrafts()
            }
        } message: {
            Text(tr("Diese Entwürfe lassen sich nicht mehr öffnen und nicht senden. Das Löschen lässt sich nicht rückgängig machen."))
        }
        .sheet(isPresented: $receipt) {
            Group {
                QuittungBlatt(unit: unit) {
                    Task { await load() }
                }
            }
            .verwaltungsBlatt()
        }
    }

    /// Abschnitt „Noch nicht gesendet“: auch ohne Verbindung sichtbar.
    @ViewBuilder
    private var entwuerfe: some View {
        if !drafts.isEmpty || !receipts.isEmpty {
            Section {
                ForEach(receipts) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.line)
                        Text([receipt.accountName, receipt.categoryName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Color.secondary)
                        if let problem = receipt.error {
                            MeldungText(problem, .fehler).font(.footnote)
                        }
                        if unit.canEditFinance {
                            HStack(spacing: 16) {
                                if receipt.error != nil { Button(tr("Korrigieren")) { fixReceipt = receipt } }
                                Button(tr("Verwerfen …"), role: .destructive) { discardReceipt = receipt }
                            }
                            .buttonStyle(.borderless)
                            .font(.footnote)
                        }
                    }
                }
                ForEach(drafts) { draft in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.line)
                        Text([draft.accountName, draft.categoryName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Color.secondary)
                        if let problem = draft.error {
                            MeldungText(problem, .fehler).font(.footnote)
                        }
                        if unit.canEditFinance {
                            HStack(spacing: 16) {
                                if draft.error != nil { Button(tr("Korrigieren")) { fix = draft } }
                                Button(tr("Verwerfen …"), role: .destructive) { discard = draft }
                            }
                            .buttonStyle(.borderless)
                            .font(.footnote)
                        }
                    }
                }
            } header: {
                Text(tr("Noch nicht gesendet ({n})", ["n": drafts.count + receipts.count]))
            } footer: {
                Text(tr("Diese Buchungen und Quittungen liegen verschlüsselt auf diesem Gerät. Die App sendet sie, sobald wieder eine Verbindung besteht."))
            }
        }
        if unreadable > 0 {
            Section {
                Text(trn("1 Entwurf lässt sich nicht mehr öffnen.", "{n} Entwürfe lassen sich nicht mehr öffnen.", unreadable))
                Button(tr("Unlesbare Entwürfe löschen …"), role: .destructive) { confirmUnreadable = true }
            }
        }
    }

    private func showDrafts() {
        guard let box = model.draftBox else { return }
        drafts = box.list(unit: unit.id)
        receipts = box.receipts(unit: unit.id)
        unreadable = box.unreadable
    }

    /// Liegengebliebene Buchungen senden; ohne Verbindung bleiben sie liegen.
    private func sendDrafts() async {
        guard let box = model.draftBox else { return }
        if Demo.active, Demo.section == "entwuerfe", box.count == 0 { Demo.fillDrafts(box, unit: unit) }
        showDrafts()
        guard unit.canEditFinance, !drafts.isEmpty || !receipts.isEmpty, !Demo.active else { return }
        let sent = await model.verwaltung(unit) { client -> Int in
            let bookings = try await client.send(drafts: box)
            return bookings + (try await client.send(receipts: box))
        }
        if let sent, sent > 0 {
            model.adminDone(trn("1 Entwurf gesendet", "{n} Entwürfe gesendet", sent))
        }
        showDrafts()
    }

    private func load() async {
        await sendDrafts()
        let filter = withoutReceipt
        let result = await model.verwaltung(unit) { client -> ([FinanceAccount], BookingPage) in
            (try await client.accounts(), try await client.bookings(page: 1, withoutReceipt: filter))
        }
        guard let result, filter == withoutReceipt else { return }
        accounts = result.0
        bookings = result.1.results
        count = result.1.count
        more = result.1.hasMore
        page = 1
        if Demo.active, Demo.section == "neuebuchung" { creating = true }
        if Demo.active, Demo.section == "quittung", finishedDemo == false {
            finishedDemo = true
            receipt = true
        }
    }

    private func loadMore() async {
        let filter = withoutReceipt
        let wanted = page + 1
        guard let next = await model.verwaltung(unit, { try await $0.bookings(page: wanted, withoutReceipt: filter) }),
              filter == withoutReceipt
        else { return }
        bookings += next.results
        more = next.hasMore
        page = wanted
    }
}

private struct BuchungZeile: View {
    let booking: BookingItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.head).font(.footnote).foregroundStyle(Color.secondary)
                Text(booking.title)
                if !booking.detail.isEmpty {
                    Text(booking.detail).font(.footnote).foregroundStyle(Color.secondary)
                }
            }
            Spacer()
            Text(booking.signedAmount).monospacedDigit()
        }
    }
}

/// Eine Buchung mit ihren Belegen; Beleg nachreichen.
struct BuchungView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let id: Int
    @State private var booking: BookingItem?
    @State private var images: [Int: UIImage] = [:]
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let error { Section { MeldungText(error, .fehler) } }
                if let booking {
                    Section {
                        Text(booking.title).font(.title3.weight(.semibold))
                        Text("\(booking.kindLabel) · \(booking.signedAmount)")
                        Text(booking.facts).font(.footnote).foregroundStyle(Color.secondary)
                    } footer: {
                        Text(tr("Ändern oder stornieren bitte im Browser."))
                    }
                    Section(tr("Belege")) {
                        if booking.receipts.isEmpty { Text(tr("Noch kein Beleg.")).foregroundStyle(.secondary) }
                        ForEach(booking.receipts) { receipt in
                            if receipt.isImage {
                                if let image = images[receipt.id] {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity, maxHeight: 480)
                                        .accessibilityLabel(receipt.name)
                                } else {
                                    Laedt()
                                }
                            } else {
                                Text(tr("{name} (im Browser ansehen)", ["name": receipt.name]))
                            }
                        }
                        if unit.canEditFinance {
                            BelegWahl(again: false) { jpeg in
                                Task { await add(jpeg) }
                            } failed: { message in
                                error = message
                            }
                            .disabled(busy)
                        }
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Buchung"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let id = self.id
        guard let result = await model.verwaltung(unit, { try await $0.booking(id) }) else { return }
        booking = result
        for receipt in result.receipts where receipt.isImage && images[receipt.id] == nil {
            let wanted = receipt.id
            if let data = await model.verwaltung(unit, { await $0.receipt(wanted) }) ?? nil, let image = UIImage(data: data) {
                images[wanted] = image
            }
        }
    }

    private func add(_ jpeg: Data) async {
        error = nil
        busy = true
        defer { busy = false }
        let id = self.id
        let done: Bool? = await model.verwaltung(unit) { client in
            try await client.addReceipt(booking: id, jpeg: jpeg)
            return true
        }
        guard done == true else { return }
        model.adminDone(tr("Beleg hinzugefügt"))
        await load()
    }
}

/// Neue Buchung mit Belegfoto; wird sofort gebucht.
private struct NeueBuchungBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    let done: () -> Void
    @State private var draft = BookingDraft()
    @State private var day = Date()
    @State private var jpeg: Data?
    @State private var accounts: [FinanceAccount] = []
    @State private var categories: [FinanceCategory] = []
    @State private var error: String?
    @State private var saving = false

    private var fitting: [FinanceCategory] { FinanceCategory.matching(categories, kind: draft.kind) }

    private var values: BookingDraft {
        var copy = draft
        copy.date = Zeit.day(day)
        return copy
    }

    private var ready: Bool { jpeg != nil && values.fields(categories: categories) != nil }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { MeldungText(error, .fehler) } }
                Section {
                    if let jpeg, let image = UIImage(data: jpeg) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .accessibilityLabel(tr("Beleg"))
                    }
                    BelegWahl(again: jpeg != nil) { data in
                        jpeg = data
                        error = nil
                    } failed: { message in
                        error = message
                    }
                } footer: {
                    Text(tr("Wird sofort gebucht, nur mit Belegfoto. Ändern und Storno im Browser."))
                }
                Section {
                    Picker(tr("Art"), selection: $draft.kind) {
                        Text(tr("Ausgabe")).tag("expense")
                        Text(tr("Einnahme")).tag("income")
                    }
                    .pickerStyle(.segmented)
                    BeschriftetesFeld(label: tr("Betrag in €"), text: $draft.amount)
                        .keyboardType(.decimalPad)
                    DatePicker(tr("Datum"), selection: $day, displayedComponents: .date)
                    BeschriftetesFeld(label: tr("Buchungstext"), text: $draft.text)
                    BeschriftetesFeld(
                        label: draft.kind == "expense" ? tr("Empfänger (optional)") : tr("Zahler (optional)"),
                        text: $draft.counterparty
                    )
                    Picker(tr("Konto"), selection: $draft.account) {
                        ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if !fitting.isEmpty {
                        Picker(tr("Kategorie"), selection: $draft.category) {
                            Text(tr("Bitte wählen")).tag(Int?.none)
                            ForEach(fitting) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
            }
            .tastaturFuehrung()
            .environment(\.locale, Texte.locale)
            .disabled(saving)
            .navigationTitle(tr("Neue Buchung"))
            .navigationBarTitleDisplayMode(.inline)
            // Konto und Kategorie setzt das Laden vor; zählt nur, was die Person eingibt (IOS-09)
            .eingabeschutz(jpeg != nil || !draft.amount.isEmpty || !draft.text.isEmpty || !draft.counterparty.isEmpty, disabled: saving)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Buchen")) { Task { await save() } }.disabled(saving || !ready)
                }
            }
            .onChange(of: draft.kind) { _, _ in draft.category = nil }
            .task { await load() }
        }
    }

    private func load() async {
        let result = await model.verwaltung(unit) { client -> ([FinanceAccount], [FinanceCategory]) in
            (try await client.accounts(), try await client.categories())
        }
        guard let result else {
            error = model.adminError
            return
        }
        accounts = result.0
        categories = result.1
        if draft.account == nil { draft.account = FinanceAccount.preferred(result.0)?.id }
        // Vorführmodus: ausgefülltes Blatt für das Bildschirmfoto
        if Demo.active, jpeg == nil {
            jpeg = BelegBild.jpeg(DemoBild.beleg())
            draft.amount = "23,40"
            draft.text = Texte.language == "en" ? "Drinks for the platoon meeting" : "Getränke Zugversammlung"
            draft.category = fitting.first?.id
        }
    }

    private func save() async {
        error = nil
        guard let jpeg, let stored = StoredBooking(values, unit: unit, accounts: accounts, categories: categories, jpeg: jpeg) else {
            error = tr("Bitte Beleg, Betrag, Buchungstext, Konto und Kategorie prüfen.")
            return
        }
        saving = true
        defer { saving = false }
        // Derselbe Schlüssel bei jedem Versuch: ein zweites Senden bucht nicht doppelt.
        // Erst als Entwurf sichern, dann senden: ohne Verbindung bleibt die Buchung auf dem Gerät.
        let box = model.draftBox
        let outcome = await model.verwaltung(unit) { client -> BookingOutcome in
            if let box { return try await client.book(stored, box: box) }
            let booked = try await client.book(fields: stored.fields, jpeg: stored.photo, key: stored.key)
            return .booked(booked.displayNumber)
        }
        switch outcome {
        case let .booked(number):
            model.adminDone(tr("Gebucht als Nr. {nummer}", ["nummer": number]))
        case .kept:
            model.adminDone(tr("Ohne Verbindung: als Entwurf gespeichert, wird später gesendet"))
        case nil:
            error = model.adminError
            return
        }
        done()
        dismiss()
    }
}

/// Entwurf, den der Server abgelehnt hat: Konto und Kategorie neu wählen, dann erneut senden.
private struct EntwurfKorrigierenBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: AdminUnit
    /// Zeile und Fehler des Entwurfs, Art ("expense"/"income"), bisherige Wahl
    let line: String
    let problem: String?
    let kind: String
    let account: Int?
    let category: Int?
    /// Quittung: nur Barkassen, Kategorie ist Pflicht
    let cashOnly: Bool
    /// Speichert die neue Wahl; false, wenn es nicht geklappt hat
    let store: (FinanceAccount, FinanceCategory?) -> Bool
    let saved: () -> Void
    @State private var accounts: [FinanceAccount] = []
    @State private var categories: [FinanceCategory] = []
    @State private var chosenAccount: Int?
    @State private var chosenCategory: Int?
    @State private var error: String?

    private var fitting: [FinanceCategory] { FinanceCategory.matching(categories, kind: kind) }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { MeldungText(error, .fehler) } }
                Section {
                    Text(line)
                    if let problem { MeldungText(problem, .fehler).font(.footnote) }
                }
                Section {
                    Picker(tr("Konto"), selection: $chosenAccount) {
                        Text(tr("Bitte wählen")).tag(Int?.none)
                        ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if !fitting.isEmpty {
                        Picker(tr("Kategorie"), selection: $chosenCategory) {
                            Text(tr("Bitte wählen")).tag(Int?.none)
                            ForEach(fitting) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                } footer: {
                    Text(cashOnly
                        ? tr("Betrag, Name, Zweck und Unterschriften bleiben, wie sie sind. Stimmt davon etwas nicht, verwirf die Quittung und stelle sie neu aus.")
                        : tr("Betrag, Datum, Text und Beleg bleiben, wie sie sind. Stimmt davon etwas nicht, verwirf den Entwurf und buche neu."))
                }
            }
            .tastaturFuehrung()
            .navigationTitle(tr("Entwurf korrigieren"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(tr("Speichern")) { save() } }
            }
            .task { await load() }
        }
    }

    private func load() async {
        let result = await model.verwaltung(unit) { client -> ([FinanceAccount], [FinanceCategory]) in
            (try await client.accounts(), try await client.categories())
        }
        guard let result else {
            error = model.adminError
            return
        }
        accounts = cashOnly ? result.0.filter { $0.kind == "cash" } : result.0
        categories = result.1
        chosenAccount = accounts.contains { $0.id == account } ? account : nil
        chosenCategory = fitting.contains { $0.id == category } ? category : nil
    }

    private func save() {
        guard let chosen = accounts.first(where: { $0.id == chosenAccount }) else {
            error = tr("Bitte ein Konto wählen.")
            return
        }
        let wanted = fitting.first { $0.id == chosenCategory }
        if wanted == nil, cashOnly || !fitting.isEmpty {
            error = tr("Bitte eine Kategorie wählen.")
            return
        }
        guard store(chosen, wanted) else {
            error = tr("Der Entwurf ließ sich nicht speichern.")
            return
        }
        saved()
        dismiss()
    }
}
