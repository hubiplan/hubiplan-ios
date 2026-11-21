import HubiplanKern
import SwiftUI

/// „Ich“ › Bestellungen: Sammelbestellungen wie Vereinskleidung oder Festschrift, offene zuerst.
/// Bis zur Frist bestellen, ändern und zurückziehen, wie unter „Mein Bereich › Bestellungen“.
struct BestellungenView: View {
    @EnvironmentObject private var model: AppModel
    /// Geöffnete Einzelansicht mit Artikeln (Formular)
    @State private var open: OrderCampaign?
    @State private var withdraw: OrderCampaign?

    var body: some View {
        let all = model.orders?.campaigns ?? []
        List {
            if let message = model.error {
                Section { MeldungText(message, .fehler) }
            }
            if let notice = model.taskNotice {
                Section { MeldungText(notice, .gut) }
            }
            if all.isEmpty {
                Text(tr("Gerade läuft keine Sammelbestellung für dich.")).foregroundStyle(.secondary)
            }
            ForEach(all.filter(\.isOpen)) { campaign in
                Section { karte(campaign) }
            }
            let closed = all.filter { !$0.isOpen }
            if !closed.isEmpty {
                Section {
                    ForEach(closed) { campaign in karte(campaign) }
                } header: {
                    Text(tr("Beendete Sammelbestellungen"))
                }
            }
        }
        .navigationTitle(tr("Bestellungen"))
        .task { await model.reloadOrders() }
        .refreshable { await model.reloadOrders() }
        .confirmationDialog(
            tr("Bestellung zurückziehen?"),
            isPresented: Binding(get: { withdraw != nil }, set: { if !$0 { withdraw = nil } }),
            titleVisibility: .visible,
            presenting: withdraw
        ) { campaign in
            Button(tr("Bestellung zurückziehen"), role: .destructive) {
                Task { if await model.withdrawOrder(campaign) { open = nil } }
            }
            Button(tr("Abbrechen"), role: .cancel) {}
        } message: { campaign in
            Text(campaign.title)
        }
    }

    @ViewBuilder
    private func karte(_ c: OrderCampaign) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(c.line).font(.footnote).foregroundStyle(.secondary)
            if let detail = open, detail.id == c.id {
                if !detail.text.isEmpty { Text(detail.text) }
                if detail.canOrder {
                    BestellFormular(campaign: detail, cancel: { open = nil }, withdraw: detail.order == nil ? nil : { withdraw = detail }) { lines, note in
                        if await model.placeOrder(detail, lines: lines, note: note) { open = nil }
                    }
                } else {
                    Text(tr("Die Bestellung lässt sich nicht mehr ändern. Bitte wende dich an deinen Verein."))
                        .foregroundStyle(.secondary)
                    Button(tr("Zurück")) { open = nil }.buttonStyle(.bordered)
                }
            } else {
                if let order = c.order {
                    Text(tr("Deine Bestellung")).font(.subheadline.weight(.semibold))
                    Text(order.linesText)
                    if c.showPrices, let total = order.total {
                        Text(tr("Summe: {x}", ["x": Geld.format(total)]))
                    }
                    if let invoice = order.invoice {
                        Text(tr("Rechnung {number}", ["number": invoice.number]) + (invoice.paid ? " · " + tr("bezahlt") : ""))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if order.handedOut {
                        Text(tr("Ausgegeben")).font(.footnote).foregroundStyle(.secondary)
                    }
                } else if !c.isOpen {
                    Text(tr("Du hast nichts bestellt.")).foregroundStyle(.secondary)
                }
                if c.isOpen {
                    Button(c.order == nil ? tr("Jetzt bestellen") : tr("Bestellung ansehen oder ändern")) {
                        Task { open = await model.orderCampaign(c.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.loading)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Menge je Artikel und Größe, Bemerkung, Summe (nur mit Preisen).
private struct BestellFormular: View {
    @EnvironmentObject private var model: AppModel
    let campaign: OrderCampaign
    let cancel: () -> Void
    let withdraw: (() -> Void)?
    let send: @MainActor ([OrderInput], String) async -> Void
    @State private var values: [String: Int]
    @State private var note: String

    init(campaign: OrderCampaign, cancel: @escaping () -> Void, withdraw: (() -> Void)?,
         send: @escaping @MainActor ([OrderInput], String) async -> Void) {
        self.campaign = campaign
        self.cancel = cancel
        self.withdraw = withdraw
        self.send = send
        _values = State(initialValue: campaign.order?.values ?? [:])
        _note = State(initialValue: campaign.order?.note ?? "")
    }

    var body: some View {
        let inputs = orderInputs(campaign.articles, values)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(campaign.articles) { a in
                VStack(alignment: .leading, spacing: 4) {
                    let price = campaign.showPrices ? Geld.format(a.price) : ""
                    Text(price.isEmpty ? a.name : "\(a.name) · \(price)").font(.subheadline.weight(.semibold))
                    if !a.text.isEmpty { Text(a.text).font(.footnote).foregroundStyle(.secondary) }
                    if !a.limitText.isEmpty { Text(a.limitText).font(.footnote).foregroundStyle(.secondary) }
                    if !a.variants.isEmpty && !a.variantLabel.isEmpty {
                        Text(tr("Auswahl: {label}", ["label": a.variantLabel])).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(a.choices, id: \.self) { v in
                        let key = orderKey(a.id, v)
                        let n = values[key] ?? 0
                        Stepper(value: Binding(get: { values[key] ?? 0 }, set: { values[key] = max(0, $0) }),
                                in: 0...min(a.maxPerMember ?? 99, 99)) {
                            Text("\(v.isEmpty ? tr("Menge") : v): \(n)")
                        }
                        .accessibilityLabel(v.isEmpty
                            ? tr("{name}: Menge", ["name": a.name])
                            : tr("{name}, {label} {value}: Menge", [
                                "name": a.name, "label": a.variantLabel.isEmpty ? tr("Auswahl") : a.variantLabel, "value": v,
                            ]))
                    }
                }
            }
            TextField(tr("Bemerkung (optional)"), text: Binding(get: { note }, set: { note = String($0.prefix(500)) }), axis: .vertical)
                .lineLimit(2...4)
            Text(tr("z. B. Name zum Besticken")).font(.footnote).foregroundStyle(.secondary)
            if campaign.showPrices, let total = orderTotal(campaign.articles, inputs) {
                Text(tr("Summe: {x}", ["x": Geld.format(total)])).font(.subheadline.weight(.semibold))
            }
            KnopfReihe {
                Button(campaign.order == nil ? tr("Bestellen") : tr("Bestellung ändern")) {
                    Task { await send(inputs, note) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputs.isEmpty || model.loading)
                if let withdraw {
                    Button(tr("Bestellung zurückziehen"), role: .destructive) { withdraw() }
                        .buttonStyle(.bordered)
                        .disabled(model.loading)
                }
                Button(tr("Abbrechen")) { cancel() }.buttonStyle(.bordered)
            }
        }
    }
}
