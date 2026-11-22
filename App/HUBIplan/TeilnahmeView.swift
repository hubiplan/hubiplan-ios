import HubiplanKern
import SwiftUI

/// Verbindliche Anmeldung mit Teilnahmegebühr am Termin, wie in der Android-App
/// (`AnmeldungSection.kt`): Tarife mit Preisstufe, eigene Anmeldungen mit Rechnung,
/// Warteliste, Abmelden mit Vorschau der Stornogebühr (auch einzelner Personen) und
/// Ersatzperson, Formular für sich, die Familie und Gäste.
struct TeilnahmeSection: View {
    @EnvironmentObject private var model: AppModel
    let eventId: Int
    /// Erster Tag (ISO), für „unter 18“ bei „Minderjährige möglich“
    var start: String?

    @State private var data: MemberRegistration?
    @State private var failure: String?
    @State private var notice: String?
    @State private var busy = false
    @State private var chosen: [Int: Int] = [:]
    @State private var births: [Int: Date] = [:]
    @State private var extras: [Int: RegistrationExtras] = [:]
    @State private var regExtras = RegistrationExtras()
    @State private var consent = false
    @State private var guests: [Guest] = []
    @State private var note = ""
    @State private var terms = false
    @State private var gap: RegistrationGap?
    @State private var cancelling: MyRegistration?
    @State private var replacing: Replacing?

    struct Replacing: Identifiable {
        let reg: MyRegistration
        let participant: RegistrationParticipant
        var id: Int { participant.id }
    }

    struct Guest: Identifiable {
        let id = UUID()
        var name = ""
        var priceId: Int?
        var birth = Date()
        /// Geburtsdatum ausdrücklich gewählt (sonst zählt es als fehlend)
        var birthSet = false
        var extras = RegistrationExtras()
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
        .entwurf(!chosen.isEmpty || !guests.isEmpty || !note.isEmpty)
        .sheet(item: $cancelling) { reg in
            if let d = data {
                AbmeldenSheet(eventId: eventId, reg: reg, offer: d.offer) { ids in
                    cancelling = nil
                    abmelden(reg, ids)
                }
            }
        }
        .sheet(item: $replacing) { r in
            if let d = data {
                ErsatzSheet(participant: r.participant, offer: d.offer, family: d.persons.filter { !$0.registered }) { member, name, birth in
                    replacing = nil
                    ersetzen(r.reg, r.participant, member, name, birth)
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
                .font(.hubi(.footnote))
        }
        if let free = offer.free { Text(tr("Noch {n} Plätze frei.", ["n": free])).font(.hubi(.footnote)) }
        ForEach(offer.prices.filter(\.isActive)) { p in
            VStack(alignment: .leading, spacing: 2) {
                Text(Teilnahme.priceLine(p))
                let extra = Teilnahme.priceExtra(p)
                if !extra.isEmpty { Text(extra).font(.hubi(.footnote)).foregroundStyle(.secondary) }
            }
        }
        ForEach(d.mine) { reg in
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Deine Anmeldung {number}", ["number": reg.number])).font(.hubi(.headline))
                Text(reg.paidText).font(.hubi(.footnote)).foregroundStyle(.secondary)
                if let n = reg.waitlistPosition {
                    Text(tr("Du stehst auf Platz {n} der Warteliste. Wird ein Platz frei, rückst du automatisch verbindlich nach und bekommst die Rechnung per E-Mail.", ["n": n]))
                        .font(.hubi(.footnote))
                }
                if reg.status == "registered", reg.movedUpAt != nil, let until = reg.freeCancelUntil, let date = Zeit.parse(until) {
                    Text(tr("Nachgerückt: Bis {when} kannst du dich kostenfrei abmelden.", [
                        "when": date.formatted(.dateTime.day().month().year().hour().minute().locale(Texte.locale)),
                    ])).font(.hubi(.footnote))
                }
                ForEach(reg.participants) { p in
                    Text(p.line)
                    if !p.bookings.isEmpty { Text(Booking.line(p.bookings)).font(.hubi(.footnote)).foregroundStyle(.secondary) }
                    if p.status == "active" && reg.canSubstitute {
                        Button(tr("Ersatzperson für {name}", ["name": p.name])) { replacing = Replacing(reg: reg, participant: p) }
                            .buttonStyle(.borderless)
                            .disabled(busy)
                    }
                }
                if !reg.bookings.isEmpty { Text(Booking.line(reg.bookings)).font(.hubi(.footnote)).foregroundStyle(.secondary) }
                if (Geld.cents(reg.cancelFee) ?? 0) > 0 {
                    Text(tr("Stornogebühr {fee}", ["fee": Geld.format(reg.cancelFee)])).font(.hubi(.footnote))
                }
                if let inv = reg.feeInvoice {
                    Text(tr("Rechnung {number} über {total}, zahlbar bis {due}", [
                        "number": inv.number, "total": Geld.format(inv.total), "due": Zeit.plainDate(inv.dueDate),
                    ])).font(.hubi(.footnote))
                }
                if let inv = reg.invoice, reg.status == "registered" {
                    Text(tr("Rechnung {number} über {total}, zahlbar bis {due}", [
                        "number": inv.number, "total": Geld.format(inv.total), "due": Zeit.plainDate(inv.dueDate),
                    ])).font(.hubi(.footnote))
                }
                if reg.hasTickets {
                    Button(tr("Eintrittskarten (PDF)")) { Task { await model.openTickets(eventId: eventId, registration: reg) } }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                    Text(tr("Bitte beim Einlass zeigen, auf dem Handy oder ausgedruckt.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                if reg.active && (reg.canCancel ?? d.canCancel) {
                    Button(tr("Anmeldung abmelden"), role: .destructive) { cancelling = reg }
                        .buttonStyle(.borderless)
                        .disabled(busy)
                }
            }
        }
        let free = d.persons.filter { !$0.registered }
        if offer.canJoin && (!free.isEmpty || offer.guestsAllowed) {
            formular(d, free)
        }
    }

    @ViewBuilder
    private func formular(_ d: MemberRegistration, _ free: [RegistrationPerson]) -> some View {
        let offer = d.offer
        let memberPrices = offer.prices(member: true)
        let guestPrices = offer.prices(member: false)
        Text(tr("Personen anmelden")).font(.hubi(.headline)).accessibilityAddTraits(.isHeader)
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
                if (memberPrices.first(where: { $0.id == price })?.hasAge == true || offer.minors) && !person.hasBirthDate {
                    DatePicker(tr("Geburtsdatum"), selection: Binding(
                        get: { births[person.membershipId] ?? Date() },
                        set: { births[person.membershipId] = $0 }
                    ), displayedComponents: .date)
                }
                ZusatzFelder(
                    offer: offer, per: "person",
                    value: Binding(get: { extras[person.membershipId] ?? RegistrationExtras() }, set: { extras[person.membershipId] = $0 }),
                    enabled: !busy, minor: minderjaehrig(person)
                )
            }
        }
        if offer.guestsAllowed && !guestPrices.isEmpty {
            ForEach($guests) { $g in
                TextField(tr("Name des Gasts"), text: $g.name)
                    .textContentType(.name)
                    .weiterFeld()
                tarifWahl(guestPrices, selected: g.priceId ?? -1) { g.priceId = $0 }
                if guestPrices.first(where: { $0.id == g.priceId })?.hasAge == true || offer.minors {
                    DatePicker(tr("Geburtsdatum"), selection: Binding(
                        get: { g.birth },
                        set: { g.birth = $0; g.birthSet = true }
                    ), displayedComponents: .date)
                }
                ZusatzFelder(offer: offer, per: "person", value: $g.extras, enabled: !busy, minor: minderjaehrig(g))
                Button(tr("Gast entfernen"), role: .destructive) { guests.removeAll { $0.id == g.id } }
                    .buttonStyle(.borderless)
            }
            Button(tr("Gast hinzufügen")) {
                guests.append(Guest(priceId: guestPrices.count == 1 ? guestPrices[0].id : nil))
            }
            .disabled(busy || chosen.count + guests.count >= offer.maxPersons)
        }
        ZusatzFelder(offer: offer, per: "registration", value: $regExtras, enabled: !busy)
        TextField(tr("Bemerkung (optional)"), text: $note, axis: .vertical)
            .onChange(of: note) { _, now in if now.count > 500 { note = String(now.prefix(500)) } }
        if !offer.terms.isEmpty {
            Text(tr("Teilnahmebedingungen")).font(.hubi(.subheadline).bold())
            Text(offer.terms).font(.hubi(.footnote))
            Toggle(tr("Ich habe die Teilnahmebedingungen gelesen und akzeptiere sie."), isOn: $terms)
        }
        let persons = auswahl(d)
        let sum = Teilnahme.sumCents(offer, persons, extras: regExtras)
        if gesundheit(offer, persons) {
            Toggle(tr("Ich willige ein, dass der Verein die Angaben zu Allergien und Unverträglichkeiten für die Planung des Essens verarbeitet."), isOn: $consent)
                .disabled(busy)
        }
        if !persons.isEmpty { Text(tr("Summe: {sum}", ["sum": Geld.format(cents: sum)])).font(.hubi(.headline)) }
        if let closes = offer.closesAt, let date = Zeit.parse(closes) {
            Text(tr("Abmelden ist bis {when} möglich.", ["when": date.formatted(.dateTime.day().month().year().locale(Texte.locale))]))
                .font(.hubi(.footnote)).foregroundStyle(.secondary)
        }
        if let gap { MeldungText(gap.text(max: offer.maxPersons), .fehler) }
        if ohneTarif { Text(tr("Bitte für jede Person einen Tarif wählen.")).font(.hubi(.footnote)) }
        Button(offer.toWaitlist ? tr("Auf die Warteliste") : sum > 0 ? tr("Zahlungspflichtig anmelden") : tr("Verbindlich anmelden")) { anmelden(d) }
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

    /// Unter 18 am ersten Tag: Mitglied laut Server oder nach dem eingegebenen Geburtsdatum
    private func minderjaehrig(_ person: RegistrationPerson) -> Bool {
        guard data?.offer.minors == true else { return false }
        return person.minor || Teilnahme.isMinor(births[person.membershipId].map { Zeit.day($0) }, start: start)
    }

    private func minderjaehrig(_ g: Guest) -> Bool {
        data?.offer.minors == true && g.birthSet && Teilnahme.isMinor(Zeit.day(g.birth), start: start)
    }

    /// Wird nach Allergien gefragt und hat jemand etwas eingetragen?
    private func gesundheit(_ offer: RegistrationOffer, _ persons: [RegistrationChoice]) -> Bool {
        offer.asksHealth && persons.contains { !$0.extras.health.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Braucht dieser Tarif (oder „Minderjährige möglich“) ein Geburtsdatum, das der Verein nicht kennt?
    private func brauchtGeburtsdatum(_ d: MemberRegistration, _ c: RegistrationChoice) -> Bool {
        let age = d.offer.prices.first { $0.id == c.priceId }?.hasAge ?? false
        let known = c.membershipId.flatMap { id in d.persons.first { $0.membershipId == id }?.hasBirthDate } ?? false
        return (age || d.offer.minors) && !known
    }

    /// Geburtsdatum zählt erst, wenn es gewählt wurde; sonst meldet `missing` es als fehlend.
    private func auswahl(_ d: MemberRegistration) -> [RegistrationChoice] {
        let ages = Set(d.offer.prices.filter(\.hasAge).map(\.id))
        let minors = d.offer.minors
        let members = chosen.filter { $0.value >= 0 }.sorted { $0.key < $1.key }.map { id, price in
            let person = d.persons.first { $0.membershipId == id }
            let known = person?.hasBirthDate ?? false
            let birth = (ages.contains(price) || minors) && !known ? births[id].map { Zeit.day($0) } : nil
            return RegistrationChoice(
                membershipId: id, priceId: price, birthDate: birth,
                extras: extras[id] ?? RegistrationExtras(), minor: person.map { minderjaehrig($0) } ?? false
            )
        }
        let others = guests.compactMap { g -> RegistrationChoice? in
            guard let price = g.priceId else { return nil }
            let birth = (ages.contains(price) || minors) && g.birthSet ? Zeit.day(g.birth) : nil
            return RegistrationChoice(
                membershipId: nil, name: g.name, priceId: price, birthDate: birth,
                extras: g.extras, minor: minderjaehrig(g)
            )
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
        let health = gesundheit(d.offer, persons) && consent
        gap = Teilnahme.missing(
            d.offer, persons, needsBirthDate: { brauchtGeburtsdatum(d, $0) }, termsAccepted: terms,
            extras: regExtras, healthConsent: health
        )
        guard gap == nil, !ohneTarif else { return }
        let text = note
        let accepted = terms
        let common = regExtras
        let asks = d.offer.asksHealth
        let id = eventId
        let done = d.offer.toWaitlist
            ? tr("Du stehst auf der Warteliste. Die Bestätigung kommt per E-Mail.")
            : tr("Angemeldet. Die Bestätigung kommt per E-Mail.")
        senden(done) { api, access in
            try await api.register(accessId: access, eventId: id, payload: Teilnahme.payload(
                persons, note: text, termsAccepted: accepted, extras: common, healthConsent: health, asksHealth: asks
            ))
        } done: {
            chosen = [:]
            births = [:]
            extras = [:]
            regExtras = RegistrationExtras()
            consent = false
            guests = []
            note = ""
            terms = false
        }
    }

    private func abmelden(_ reg: MyRegistration, _ participants: [Int]) {
        let id = eventId
        let regId = reg.id
        senden(tr("Du bist abgemeldet. Die Bestätigung kommt per E-Mail.")) { api, access in
            try await api.cancelRegistration(accessId: access, eventId: id, registrationId: regId, participants: participants)
        } done: {}
    }

    private func ersetzen(_ reg: MyRegistration, _ p: RegistrationParticipant, _ member: Int?, _ name: String, _ birth: String?) {
        let id = eventId
        let regId = reg.id
        let pid = p.id
        senden(tr("Ersatzperson eingetragen.")) { api, access in
            try await api.substitute(
                accessId: access, eventId: id, registrationId: regId, participantId: pid,
                payload: Teilnahme.substitutePayload(membershipId: member, name: name, birthDate: birth)
            )
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

/// Abmelden ganz oder für einzelne Personen, mit Vorschau der Stornogebühr.
private struct AbmeldenSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let eventId: Int
    let reg: MyRegistration
    let offer: RegistrationOffer
    let confirm: ([Int]) -> Void

    @State private var chosen: Set<Int> = []
    @State private var quote: FeeQuote?
    @State private var started = false

    private var active: [RegistrationParticipant] { reg.activeParticipants }
    private var whole: Bool { chosen.count == active.count }
    private var selection: [Int] { whole ? [] : chosen.sorted() }

    var body: some View {
        NavigationStack {
            List {
                if active.count > 1 {
                    Section(tr("Wer wird abgemeldet?")) {
                        ForEach(active) { p in
                            Toggle(p.line, isOn: Binding(
                                get: { chosen.contains(p.id) },
                                set: { on in if on { chosen.insert(p.id) } else { chosen.remove(p.id) } }
                            ))
                        }
                    }
                }
                Section {
                    if let quote { Text(quote.text) } else if !chosen.isEmpty { Laedt() }
                    if quote?.hasFee == true && offer.waitlist && offer.waiting > 0 {
                        Text(tr("Rückt dafür jemand von der Warteliste nach, entfällt die Gebühr.")).font(.hubi(.footnote))
                    }
                    if let inv = reg.invoice, !reg.waiting {
                        if whole && quote?.hasFee != true {
                            Text((Geld.cents(inv.paid) ?? 0) > 0
                                ? tr("Die Rechnung wird storniert; den gezahlten Betrag erstattet der Verein.")
                                : tr("Die Rechnung wird storniert.")).font(.hubi(.footnote))
                        } else {
                            Text(tr("Die Rechnung wird storniert, und es kommt eine neue Rechnung über den Rest. Schon Gezahltes wird damit verrechnet."))
                                .font(.hubi(.footnote))
                        }
                    } else if reg.invoice == nil {
                        Text(tr("Du bist dann nicht mehr angemeldet.")).font(.hubi(.footnote))
                    }
                }
                Section {
                    Button(whole ? tr("Verbindlich abmelden") : tr("Ausgewählte abmelden"), role: .destructive) {
                        confirm(selection)
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .navigationTitle(tr("Anmeldung {number} abmelden", ["number": reg.number]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
            }
            .onAppear {
                if !started {
                    started = true
                    chosen = Set(active.map(\.id))
                }
            }
            .task(id: chosen) { await vorschau() }
        }
    }

    private func vorschau() async {
        quote = nil
        guard !chosen.isEmpty else { return }
        let id = eventId
        let regId = reg.id
        let ids = selection
        if case .success(let fresh) = await model.portalCall({ api, access in
            try await api.cancelQuote(accessId: access, eventId: id, registrationId: regId, participants: ids)
        }) {
            quote = fresh
        }
    }
}

/// Ersatzperson zum selben Tarif und Preis: jemand aus der Familie oder ein Gast.
private struct ErsatzSheet: View {
    @Environment(\.dismiss) private var dismiss
    let participant: RegistrationParticipant
    let offer: RegistrationOffer
    let family: [RegistrationPerson]
    let confirm: (Int?, String, String?) -> Void

    /// -1: ein Gast
    @State private var member = -1
    @State private var name = ""
    @State private var birth = Date()
    @State private var started = false

    private var person: RegistrationPerson? { family.first { $0.membershipId == member } }
    private var needsBirth: Bool {
        offer.prices.first { $0.id == participant.priceId }?.hasAge == true && !(person?.hasBirthDate ?? false)
    }
    private var ready: Bool { person != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tr("Tarif und Preis bleiben, die Rechnung auch: {price}, {amount}", [
                        "price": participant.priceName, "amount": Geld.format(participant.amount),
                    ])).font(.hubi(.footnote))
                    Picker(tr("Ersatzperson"), selection: $member) {
                        if offer.guestsAllowed { Text(tr("ein Gast (Name eingeben)")).tag(-1) }
                        ForEach(family) { f in Text(f.name).tag(f.membershipId) }
                    }
                    if person == nil && offer.guestsAllowed {
                        TextField(tr("Name"), text: $name)
                            .textContentType(.name)
                            .submitLabel(.done)
                    }
                    if needsBirth {
                        DatePicker(tr("Geburtsdatum"), selection: $birth, displayedComponents: .date)
                    }
                }
                Section {
                    Button(tr("Ersatzperson eintragen")) {
                        confirm(person?.membershipId, name, needsBirth ? Zeit.day(birth) : nil)
                    }
                    .disabled(!ready)
                }
            }
            .tastaturFuehrung()
            .navigationTitle(tr("Ersatzperson für {name}", ["name": participant.name]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
            }
            .onAppear {
                if !started {
                    started = true
                    if !offer.guestsAllowed, let first = family.first { member = first.membershipId }
                }
            }
        }
    }
}
