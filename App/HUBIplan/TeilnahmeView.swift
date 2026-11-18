import HubiplanKern
import SwiftUI

/// Verbindliche Anmeldung mit Teilnahmegebühr am Termin, wie in der Android-App
/// (`AnmeldungSection.kt`): Tarife mit Preisstufe, eigene Anmeldungen mit Rechnung und
/// Abmelden, Formular für sich, die Familie und Gäste.
struct TeilnahmeSection: View {
    @EnvironmentObject private var model: AppModel
    let eventId: Int

    @State private var data: MemberRegistration?
    @State private var failure: String?
    @State private var notice: String?
    @State private var busy = false
    @State private var chosen: [Int: Int] = [:]
    @State private var births: [Int: Date] = [:]
    @State private var guests: [Guest] = []
    @State private var note = ""
    @State private var terms = false
    @State private var gap: RegistrationGap?
    @State private var cancelling: MyRegistration?

    struct Guest: Identifiable {
        let id = UUID()
        var name = ""
        var priceId: Int?
        var birth = Date()
    }

    var body: some View {
        Section {
            if let failure { MeldungText(failure, .fehler) }
            if let notice { MeldungText(notice, .gut) }
            if let data {
                inhalt(data)
            } else if failure == nil {
                Laedt()
            }
            if busy { Laedt(text: tr("Wird gesendet …")) }
        } header: {
            Text(tr("Anmeldung"))
        }
        .task(id: eventId) { await load() }
        .confirmationDialog(
            cancelling.map { tr("Anmeldung {number} abmelden?", ["number": $0.number]) } ?? "",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible
        ) {
            if let reg = cancelling {
                Button(tr("Anmeldung abmelden"), role: .destructive) { abmelden(reg) }
            }
        } message: {
            if let reg = cancelling {
                if let inv = reg.invoice, (Geld.cents(inv.paid) ?? 0) > 0 {
                    Text(tr("Die Rechnung wird storniert; den gezahlten Betrag erstattet der Verein."))
                } else if reg.invoice != nil {
                    Text(tr("Die Rechnung wird storniert."))
                } else {
                    Text(tr("Du bist dann nicht mehr angemeldet."))
                }
            }
        }
    }

    @ViewBuilder
    private func inhalt(_ d: MemberRegistration) -> some View {
        let offer = d.offer
        if !offer.stateText.isEmpty { Text(offer.stateText) }
        if let closes = offer.closesAt, let date = Zeit.parse(closes) {
            Text(tr("Anmeldeschluss: {date}", ["date": date.formatted(.dateTime.day().month().year().hour().minute().locale(Texte.locale))]))
                .font(.footnote)
        }
        if let free = offer.free { Text(tr("Noch {n} Plätze frei.", ["n": free])).font(.footnote) }
        ForEach(offer.prices.filter(\.isActive)) { p in
            VStack(alignment: .leading, spacing: 2) {
                Text(Teilnahme.priceLine(p))
                let extra = Teilnahme.priceExtra(p)
                if !extra.isEmpty { Text(extra).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        ForEach(d.mine) { reg in
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Deine Anmeldung {number}", ["number": reg.number])).font(.headline)
                Text(reg.paidText).font(.footnote).foregroundStyle(.secondary)
                ForEach(reg.participants) { Text($0.line) }
                if let inv = reg.invoice {
                    Text(tr("Rechnung {number} über {total}, zahlbar bis {due}", [
                        "number": inv.number, "total": Geld.format(inv.total), "due": Zeit.plainDate(inv.dueDate),
                    ])).font(.footnote)
                }
                if d.canCancel && reg.active {
                    Button(tr("Anmeldung abmelden"), role: .destructive) { cancelling = reg }
                        .buttonStyle(.borderless)
                        .disabled(busy)
                }
            }
        }
        let free = d.persons.filter { !$0.registered }
        if offer.state == "open" && (!free.isEmpty || offer.guestsAllowed) {
            formular(d, free)
        }
    }

    @ViewBuilder
    private func formular(_ d: MemberRegistration, _ free: [RegistrationPerson]) -> some View {
        let offer = d.offer
        let memberPrices = offer.prices(member: true)
        let guestPrices = offer.prices(member: false)
        Text(tr("Personen anmelden")).font(.headline).accessibilityAddTraits(.isHeader)
        ForEach(free) { person in
            Toggle(person.name, isOn: Binding(
                get: { chosen[person.membershipId] != nil },
                set: { on in
                    if on { chosen[person.membershipId] = memberPrices.count == 1 ? memberPrices[0].id : -1 } else { chosen[person.membershipId] = nil }
                }
            ))
            .disabled(busy || memberPrices.isEmpty)
            if let price = chosen[person.membershipId] {
                tarifWahl(memberPrices, selected: price) { chosen[person.membershipId] = $0 }
                if memberPrices.first(where: { $0.id == price })?.hasAge == true && !person.hasBirthDate {
                    DatePicker(tr("Geburtsdatum"), selection: Binding(
                        get: { births[person.membershipId] ?? Date() },
                        set: { births[person.membershipId] = $0 }
                    ), displayedComponents: .date)
                }
            }
        }
        if offer.guestsAllowed && !guestPrices.isEmpty {
            ForEach($guests) { $g in
                TextField(tr("Name des Gasts"), text: $g.name)
                    .textContentType(.name)
                    .weiterFeld()
                tarifWahl(guestPrices, selected: g.priceId ?? -1) { g.priceId = $0 }
                if guestPrices.first(where: { $0.id == g.priceId })?.hasAge == true {
                    DatePicker(tr("Geburtsdatum"), selection: $g.birth, displayedComponents: .date)
                }
                Button(tr("Gast entfernen"), role: .destructive) { guests.removeAll { $0.id == g.id } }
                    .buttonStyle(.borderless)
            }
            Button(tr("Gast hinzufügen")) {
                guests.append(Guest(priceId: guestPrices.count == 1 ? guestPrices[0].id : nil))
            }
            .disabled(busy || chosen.count + guests.count >= offer.maxPersons)
        }
        TextField(tr("Bemerkung (optional)"), text: $note, axis: .vertical)
            .onChange(of: note) { _, now in if now.count > 500 { note = String(now.prefix(500)) } }
        if !offer.terms.isEmpty {
            Text(tr("Teilnahmebedingungen")).font(.subheadline.bold())
            Text(offer.terms).font(.footnote)
            Toggle(tr("Ich habe die Teilnahmebedingungen gelesen und akzeptiere sie."), isOn: $terms)
        }
        let persons = auswahl(d)
        let sum = Teilnahme.sumCents(offer, persons)
        if !persons.isEmpty { Text(tr("Summe: {sum}", ["sum": Geld.format(cents: sum)])).font(.headline) }
        if let closes = offer.closesAt, let date = Zeit.parse(closes) {
            Text(tr("Abmelden ist bis {when} möglich.", ["when": date.formatted(.dateTime.day().month().year().locale(Texte.locale))]))
                .font(.footnote).foregroundStyle(.secondary)
        }
        if let gap { MeldungText(gap.text(max: offer.maxPersons), .fehler) }
        if ohneTarif { Text(tr("Bitte für jede Person einen Tarif wählen.")).font(.footnote) }
        Button(sum > 0 ? tr("Zahlungspflichtig anmelden") : tr("Verbindlich anmelden")) { anmelden(d) }
            .buttonStyle(.borderedProminent)
            .disabled(busy || persons.isEmpty)
    }

    @ViewBuilder
    private func tarifWahl(_ prices: [RegistrationPrice], selected: Int, pick: @escaping (Int) -> Void) -> some View {
        Picker(tr("Tarif"), selection: Binding(get: { selected }, set: pick)) {
            if !prices.contains(where: { $0.id == selected }) { Text(tr("Bitte wählen")).tag(-1) }
            ForEach(prices) { p in
                Text(p.label + " · " + Geld.format(p.current?.amount)).tag(p.id)
            }
        }
    }

    private var ohneTarif: Bool { chosen.values.contains(-1) || guests.contains { $0.priceId == nil } }

    private func auswahl(_ d: MemberRegistration) -> [RegistrationChoice] {
        let ages = Set(d.offer.prices.filter(\.hasAge).map(\.id))
        let members = chosen.filter { $0.value >= 0 }.sorted { $0.key < $1.key }.map { id, price in
            let known = d.persons.first { $0.membershipId == id }?.hasBirthDate ?? false
            let birth = ages.contains(price) && !known ? Zeit.day(births[id] ?? Date()) : nil
            return RegistrationChoice(membershipId: id, priceId: price, birthDate: birth)
        }
        let others = guests.compactMap { g -> RegistrationChoice? in
            guard let price = g.priceId else { return nil }
            return RegistrationChoice(membershipId: nil, name: g.name, priceId: price, birthDate: ages.contains(price) ? Zeit.day(g.birth) : nil)
        }
        return members + others
    }

    private func load() async {
        let id = eventId
        switch await model.portalCall({ api, access in try await api.memberRegistration(accessId: access, eventId: id) }) {
        case .success(let fresh):
            data = fresh
            failure = nil
        case .failure(let error):
            failure = error.text
        case nil:
            break
        }
    }

    private func anmelden(_ d: MemberRegistration) {
        let persons = auswahl(d)
        // Geburtsdatum kommt hier immer aus dem Datumsfeld; offen bleibt nur, was fehlt
        gap = Teilnahme.missing(d.offer, persons, needsBirthDate: { _ in false }, termsAccepted: terms)
        guard gap == nil, !ohneTarif else { return }
        let text = note
        let accepted = terms
        let id = eventId
        senden(tr("Angemeldet. Die Bestätigung kommt per E-Mail.")) { api, access in
            try await api.register(accessId: access, eventId: id, payload: Teilnahme.payload(persons, note: text, termsAccepted: accepted))
        } done: {
            chosen = [:]
            births = [:]
            guests = []
            note = ""
            terms = false
        }
    }

    private func abmelden(_ reg: MyRegistration) {
        cancelling = nil
        let id = eventId
        let regId = reg.id
        senden(tr("Du bist abgemeldet. Die Bestätigung kommt per E-Mail.")) { api, access in
            try await api.cancelRegistration(accessId: access, eventId: id, registrationId: regId)
        } done: {}
    }

    private func senden(
        _ text: String,
        _ work: @escaping @Sendable (Api, Int) async throws -> MemberRegistration,
        done: @escaping () -> Void
    ) {
        guard !busy else { return }
        busy = true
        failure = nil
        notice = nil
        Task {
            defer { busy = false }
            switch await model.portalCall(work) {
            case .success(let fresh):
                data = fresh
                notice = text
                done()
            case .failure(let error):
                failure = error.text
            case nil:
                break
            }
        }
    }
}
