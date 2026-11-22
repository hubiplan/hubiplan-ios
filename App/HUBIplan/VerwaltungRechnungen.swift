import HubiplanKern
import QuickLook
import SwiftUI

/// Rechnungen der Einheit: suchen, offene oder alle, eine Rechnung öffnen.
struct RechnungenView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var search = ""
    @State private var openOnly = true
    @State private var rows: [InvoiceItem]?
    @State private var count = 0
    @State private var page = 1
    @State private var more = false
    /// Vorführmodus: für das Bildschirmfoto gleich in eine Rechnung
    @State private var shown: Int? = Demo.active && Demo.section == "vrechnung" ? 7 : nil

    var body: some View {
        VerwaltungSchutz {
            List {
                Picker(tr("Stand"), selection: $openOnly) {
                    Text(tr("Offen")).tag(true)
                    Text(tr("Alle")).tag(false)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                VerwaltungMeldung { await load(reset: true) }
                if let rows {
                    Section {
                        if rows.isEmpty {
                            Text(openOnly ? tr("Keine offenen Rechnungen gefunden.") : tr("Keine Rechnungen gefunden."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(rows) { row in
                            NavigationLink {
                                RechnungView(unit: unit, id: row.id)
                            } label: {
                                RechnungZeile(invoice: row)
                            }
                        }
                        if more {
                            Button(tr("Weitere laden")) { Task { await load(reset: false) } }
                        }
                    } header: {
                        Text(trn("1 Rechnung", "{n} Rechnungen", count))
                    } footer: {
                        Text(tr("Beitragsläufe, Mahnungen und SEPA im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: tr("Name, Betreff oder Rechnungsnummer"))
            .task(id: "\(search)|\(openOnly)") {
                // Beim Tippen kurz warten, damit nicht jeder Buchstabe eine Anfrage auslöst
                if rows != nil { try? await Task.sleep(for: .milliseconds(350)) }
                if !Task.isCancelled { await load(reset: true) }
            }
            .navigationDestination(item: $shown) { RechnungView(unit: unit, id: $0) }
        }
        .navigationTitle(tr("Rechnungen"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load(reset: Bool) async {
        let wanted = reset ? 1 : page + 1
        let text = search
        let filter = openOnly
        guard let result = await model.verwaltung(unit, { try await $0.invoices(search: text, page: wanted, openOnly: filter) }) else { return }
        guard text == search, filter == openOnly else { return }
        rows = reset ? result.results : (rows ?? []) + result.results
        count = result.count
        page = wanted
        more = result.hasMore
    }
}

private struct RechnungZeile: View {
    let invoice: InvoiceItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.payer)
                if !invoice.listDetail.isEmpty {
                    Text(invoice.listDetail).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(invoice.listAmount).monospacedDigit()
                Text(invoice.listStatus).font(.hubi(.footnote)).foregroundStyle(invoice.isOverdue ? Color.fehlerText : Color.secondary)
            }
        }
    }
}

/// Eine Rechnung mit Positionen und Zahlungen; „Bar kassiert“ bucht eine Barzahlung.
struct RechnungView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let id: Int
    @State private var invoice: InvoiceItem?
    @State private var accounts: [BillingAccount]?
    @State private var draft = CashDraft(outstanding: "")
    @State private var day = Date()
    @State private var lastPayment: Int?
    @State private var error: String?
    @State private var busy = false

    private var values: CashDraft {
        var copy = draft
        copy.date = Zeit.day(day)
        return copy
    }

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let error { Section { MeldungText(error, .fehler) } }
                if let invoice {
                    Section {
                        Text(invoice.payer).font(.hubi(.title3).weight(.semibold))
                        if !invoice.headline.isEmpty { Text(invoice.headline) }
                        Text(invoice.dates).font(.hubi(.footnote)).foregroundStyle(invoice.isOverdue ? Color.fehlerText : Color.secondary)
                    }
                    Section {
                        ForEach(Array(invoice.lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.text)
                                    if !line.detail.isEmpty {
                                        Text(line.detail).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                    }
                                }
                                Spacer()
                                Text(Geld.format(line.amount)).monospacedDigit()
                            }
                        }
                        Betrag(label: tr("Gesamt"), amount: invoice.total)
                        if invoice.hasPaid { Betrag(label: tr("bezahlt"), amount: invoice.paid) }
                        if invoice.isOpen { Betrag(label: tr("offen"), amount: invoice.outstanding, bold: true) }
                    }
                    if let lastPayment {
                        Section {
                            Text(tr("Bar kassiert und gebucht.")).font(.hubi(.headline))
                            Button(tr("Quittung ansehen oder teilen")) {
                                Task { await model.openCashReceipt(unit, payment: lastPayment, name: invoice.receiptName(payment: lastPayment)) }
                            }
                            .disabled(model.previewBusy)
                        }
                    }
                    if unit.canEditBilling, invoice.canPayCash {
                        Section {
                            if let accounts {
                                if accounts.isEmpty {
                                    Text(tr("Es gibt noch keine Barkasse. Bitte im Browser unter Kasse eine anlegen."))
                                        .foregroundStyle(.secondary)
                                } else {
                                    kassieren(invoice, accounts)
                                }
                            } else {
                                Laedt()
                            }
                        } header: {
                            Text(tr("Bar kassiert"))
                        }
                    }
                    if !invoice.payments.isEmpty {
                        Section {
                            ForEach(invoice.payments) { payment in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Geld.format(payment.amount)).monospacedDigit()
                                        Text(payment.detail).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                    }
                                    Spacer()
                                    if payment.isCash {
                                        Button(tr("Quittung")) {
                                            Task { await model.openCashReceipt(unit, payment: payment.id, name: invoice.receiptName(payment: payment.id)) }
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(model.previewBusy)
                                    }
                                }
                            }
                        } header: {
                            Text(tr("Zahlungen"))
                        }
                    }
                    Section {} footer: {
                        Text(tr("Storno, Mahnungen und Zahlungen entfernen im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .environment(\.locale, Texte.locale)
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Rechnung"))
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($model.preview)
    }

    @ViewBuilder
    private func kassieren(_ invoice: InvoiceItem, _ accounts: [BillingAccount]) -> some View {
        let problem = draft.amount.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : CashDraft.amountError(draft.amount, outstanding: invoice.outstanding)
        BeschriftetesFeld(label: tr("Betrag in €"), text: $draft.amount)
            .keyboardType(.decimalPad)
        if let problem { MeldungText(problem, .fehler).font(.hubi(.footnote)) }
        DatePicker(tr("Datum"), selection: $day, in: ...Date(), displayedComponents: .date)
        if accounts.count > 1 {
            Picker(tr("Barkasse"), selection: $draft.account) {
                ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
            }
        } else {
            Text(tr("in die {konto}", ["konto": accounts[0].name])).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
        }
        Button(tr("Bar kassiert buchen")) { Task { await pay() } }
            .disabled(busy || values.body(outstanding: invoice.outstanding) == nil)
    }

    private func load() async {
        let id = self.id
        guard let result = await model.verwaltung(unit, { try await $0.invoice(id) }) else { return }
        show(result)
        // Zurückgenommene Zahlung: keine Quittung mehr anbieten
        if let paid = lastPayment, !result.payments.contains(where: { $0.id == paid }) { lastPayment = nil }
        guard unit.canEditBilling, result.canPayCash, accounts == nil else { return }
        guard let info = await model.verwaltung(unit, { try await $0.billingInfo() }) else { return }
        accounts = info.cashAccounts
        if draft.account == nil { draft.account = info.cashAccounts.first?.id }
    }

    /// Rechnung zeigen; der Betrag im Feld folgt dem offenen Rest, solange niemand etwas anderes eingegeben hat.
    private func show(_ result: InvoiceItem) {
        let before = invoice.map { Geld.inputText($0.outstanding) } ?? ""
        if draft.amount.isEmpty || draft.amount == before { draft.amount = Geld.inputText(result.outstanding) }
        invoice = result
    }

    private func pay() async {
        guard let invoice, let body = values.body(outstanding: invoice.outstanding) else { return }
        error = nil
        busy = true
        defer { busy = false }
        // Derselbe Schlüssel bei jedem Versuch: ein zweites Senden bucht nicht doppelt
        let key = draft.key
        let id = invoice.id
        guard let done = await model.verwaltung(unit, { try await $0.payCash(invoice: id, body: body, key: key) }) else {
            if model.adminError == ApiError(status: 0, code: "offline").text {
                model.adminError = nil
                error = tr("Keine Verbindung. Bitte erneut versuchen; doppelt gebucht wird nicht.")
            }
            return
        }
        let account = draft.account
        draft = CashDraft(outstanding: done.result.invoice.outstanding)
        draft.account = account
        self.invoice = done.result.invoice
        lastPayment = done.result.payment
        model.adminChanged(
            unit, text: tr("Barzahlung zu {nummer} gebucht", ["nummer": invoice.number ?? tr("der Rechnung")]), change: done.change
        )
    }
}

private struct Betrag: View {
    let label: String
    let amount: String
    var bold = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(Geld.format(amount)).monospacedDigit()
        }
        .fontWeight(bold ? .semibold : .regular)
    }
}
