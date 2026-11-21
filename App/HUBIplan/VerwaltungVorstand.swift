import HubiplanKern
import SwiftUI

// Vorstandsaufgaben in der Verwaltung, wie in der Android-App: Beitrittsanträge entscheiden,
// Belegungsanfragen freigeben, Versammlung leiten. Vorbereiten, Korrigieren und neue Buchungen
// bleiben im Browser.

// MARK: Beitrittsanträge

struct AntraegeView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var list: ApplicationList?

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let list {
                    Section {
                        if list.results.isEmpty {
                            Text(tr("Keine offenen Beitrittsanträge.")).foregroundStyle(.secondary)
                        }
                        ForEach(list.results) { row in
                            NavigationLink {
                                AntragView(unit: unit, id: row.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name.isEmpty ? row.number : row.name)
                                    Text(row.line).font(.footnote).foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    } header: {
                        if !list.ruleText.isEmpty { Text(list.ruleText) }
                    } footer: {
                        Text(tr("Angaben korrigieren und mehrere Anträge auf einmal aufnehmen geht im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Beitrittsanträge"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        if let result = await model.verwaltung(unit, { try await $0.applications() }) { list = result }
    }
}

struct AntragView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let id: Int
    @State private var data: ApplicationDetail?
    @State private var note = ""
    @State private var busy = false
    @State private var accepting = false
    @State private var rejecting = false
    @State private var asking = false
    @State private var entryDate = Date()
    @State private var acceptNote = ""
    @State private var welcome = true
    @State private var rejectNote = ""
    @State private var rejectMail = true
    @State private var question = ""

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let d = data {
                    Section {
                        Text([d.number, d.statusLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(d.summary.enumerated()), id: \.offset) { _, line in Text(line) }
                    }
                    if !d.matches.isEmpty {
                        Section(tr("Mögliche Treffer")) {
                            ForEach(Array(d.matches.enumerated()), id: \.offset) { _, m in
                                Text(treffer(m)).font(.footnote).foregroundStyle(Color.fehlerText)
                            }
                        }
                    }
                    Section {
                        ForEach(Array(d.approvals.enumerated()), id: \.offset) { _, a in
                            Text([a.userName, a.roles, a.decision == "approve" ? tr("stimmt zu") : tr("lehnt ab"), a.note]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote)
                        }
                        if d.isOpen, !d.missing.isEmpty {
                            Text(tr("Es fehlen noch Zustimmungen: {missing}", ["missing": d.missing.joined(separator: ", ")]))
                                .font(.footnote).foregroundStyle(Color.secondary)
                        }
                        if d.disputed {
                            MeldungText(tr("Es gibt eine Ablehnung. Bitte klärt das, bevor ihr aufnehmt."), .warnung)
                        }
                        if !d.isOpen, !d.decisionNote.isEmpty {
                            Text(tr("Vermerk: {note}", ["note": d.decisionNote])).font(.footnote)
                        }
                    } header: {
                        Text(tr("Zustimmungen"))
                    } footer: {
                        if !d.ruleText.isEmpty { Text(d.ruleText) }
                    }
                    if d.canApprove {
                        Section {
                            BeschriftetesFeld(label: tr("Vermerk (freiwillig)"), text: $note, axis: .vertical)
                            Button(tr("Zustimmen")) { approve(true) }.disabled(busy)
                            Button(tr("Nicht zustimmen"), role: .destructive) { approve(false) }.disabled(busy)
                        }
                    } else if let own = d.ownDecision, d.isOpen {
                        Section {
                            Text(own == "approve" ? tr("Du hast zugestimmt.") : tr("Du hast nicht zugestimmt."))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if d.mayDecide, d.isOpen {
                        Section {
                            if d.status == "open" {
                                Button(tr("Aufnehmen")) {
                                    entryDate = d.entryDate.flatMap { Zeit.parse($0 + "T12:00:00Z") } ?? Date()
                                    accepting = true
                                }
                                .disabled(busy || !d.canAccept)
                            }
                            Button(tr("Rückfrage")) { asking = true }.disabled(busy)
                            Button(tr("Ablehnen"), role: .destructive) { rejecting = true }.disabled(busy)
                        }
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(data?.name ?? tr("Beitrittsantrag"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $accepting) { aufnehmen }
        .sheet(isPresented: $rejecting) { ablehnen }
        .sheet(isPresented: $asking) { nachfragen }
    }

    private var aufnehmen: some View {
        NavigationStack {
            Form {
                if let type = data?.memberType, !type.isEmpty {
                    Text(tr("Mitgliedsart: {type}", ["type": type]))
                }
                DatePicker(tr("Eintritt"), selection: $entryDate, displayedComponents: .date)
                BeschriftetesFeld(label: tr("Vermerk (z. B. Beschluss)"), text: $acceptNote, axis: .vertical)
                Toggle(tr("Begrüßung per E-Mail schicken"), isOn: $welcome)
            }
            .navigationTitle(tr("{name} aufnehmen", ["name": data?.name ?? ""]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { accepting = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Aufnehmen")) {
                        let day = Zeit.day(entryDate)
                        run(tr("{name} ist aufgenommen", ["name": data?.name ?? ""])) {
                            try await $0.acceptApplication(id, entryDate: day, note: acceptNote, welcome: welcome)
                        }
                        accepting = false
                    }
                    .disabled(busy)
                }
            }
        }
        .verwaltungsBlatt()
    }

    private var ablehnen: some View {
        NavigationStack {
            Form {
                BeschriftetesFeld(label: tr("Vermerk (nur intern)"), text: $rejectNote, axis: .vertical)
                Toggle(tr("Absage per E-Mail schicken"), isOn: $rejectMail)
            }
            .navigationTitle(tr("Antrag ablehnen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { rejecting = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Ablehnen"), role: .destructive) {
                        run(tr("Antrag abgelehnt")) { try await $0.rejectApplication(id, note: rejectNote, sendMail: rejectMail) }
                        rejecting = false
                    }
                    .disabled(busy)
                }
            }
        }
        .verwaltungsBlatt()
    }

    private var nachfragen: some View {
        NavigationStack {
            Form {
                BeschriftetesFeld(label: tr("Frage an die antragstellende Person"), text: $question, axis: .vertical)
            }
            .navigationTitle(tr("Rückfrage stellen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { asking = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Verschicken")) {
                        run(tr("Rückfrage verschickt")) { try await $0.askApplication(id, text: question) }
                        asking = false
                    }
                    .disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .verwaltungsBlatt()
    }

    private func treffer(_ m: ApplicationMatch) -> String {
        var parts = [m.name]
        if let birth = m.birthDate { parts.append(Zeit.plainDate(birth)) }
        if m.here { parts.append(m.former ? tr("früher Mitglied") : tr("schon Mitglied")) }
        if !m.activeElsewhere.isEmpty { parts.append(tr("aktiv in {org}", ["org": m.activeElsewhere])) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        if let result = await model.verwaltung(unit, { try await $0.application(id) }) { data = result }
    }

    private func approve(_ yes: Bool) {
        run(yes ? tr("Zustimmung eingetragen") : tr("Ablehnung eingetragen")) {
            try await $0.approveApplication(id, approve: yes, note: note)
        }
    }

    private func run(_ done: String, _ work: @escaping @MainActor (AdminClient) async throws -> ApplicationDetail) {
        Task {
            busy = true
            defer { busy = false }
            if let result = await model.verwaltung(unit, work) {
                data = result
                model.adminDone(done)
            }
        }
    }
}

// MARK: Belegung freigeben

struct BelegungFreigebenView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var rows: [BookingRequest]?
    @State private var busy: Int?

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let rows {
                    if rows.isEmpty {
                        Text(tr("Keine offenen Anfragen.")).foregroundStyle(.secondary)
                    }
                    ForEach(rows) { b in
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.itemTitle).font(.headline)
                                Text(b.allDay
                                    ? terminZeit(b.startsAt, b.endsAt, allDay: true)
                                    : zeitraum(b.startsAt, b.endsAt))
                                Text([b.title, b.requester].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(Color.secondary)
                                if b.repeats { Text(tr("wiederholt sich")).font(.footnote).foregroundStyle(Color.secondary) }
                                if !b.note.isEmpty { Text(b.note).font(.footnote) }
                            }
                            Button(tr("Freigeben")) { decide(b, confirm: true) }.disabled(busy != nil)
                            Button(tr("Ablehnen"), role: .destructive) { decide(b, confirm: false) }.disabled(busy != nil)
                        }
                    }
                    Section {} footer: { Text(tr("Den Kalender ansehen und selbst buchen geht im Browser.")) }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Belegung freigeben"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let today = Zeit.day(Date())
        if let result = await model.verwaltung(unit, { try await $0.bookingRequests(today: today) }) { rows = result }
    }

    private func decide(_ b: BookingRequest, confirm: Bool) {
        Task {
            busy = b.id
            defer { busy = nil }
            if await model.verwaltung(unit, { try await $0.decideBooking(b.id, version: b.version, confirm: confirm) }) != nil {
                rows?.removeAll { $0.id == b.id }
                model.adminDone(confirm ? tr("Anfrage freigegeben") : tr("Anfrage abgelehnt"))
            } else {
                // Inzwischen geändert (409) oder anderer Fehler: Liste neu laden
                await load()
            }
        }
    }
}

// MARK: Versammlung leiten

struct VersammlungenLeitenView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var rows: [LeadMeeting]?

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let rows {
                    let shown = rows.filter(\.isLive).sorted { $0.startsAt < $1.startsAt }
                    Section {
                        if shown.isEmpty {
                            Text(tr("Keine Versammlung, die sich jetzt leiten lässt.")).foregroundStyle(.secondary)
                        }
                        ForEach(shown) { m in
                            NavigationLink {
                                VersammlungLeitenView(unit: unit, id: m.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title)
                                    Text([zeitraum(m.startsAt, m.startsAt), m.location, LeadMeeting.statusLabel(m.status)]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.footnote).foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text(tr("Vorbereiten, Einladen und das Protokoll gehen im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Versammlung leiten"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        if let result = await model.verwaltung(unit, { try await $0.meetings() }) { rows = result }
    }
}

struct VersammlungLeitenView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let id: Int
    @State private var meeting: LeadMeeting?
    @State private var live: LeadLive?
    @State private var attendance: AttendanceList?
    @State private var busy = false
    @State private var query = ""
    @State private var guest = ""
    @State private var bigQr = false
    @State private var newPoll = false
    @State private var scanning = false

    private var server: String { model.account?.server ?? "" }

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let m = meeting, let l = live {
                    Section {
                        Text([zeitraum(m.startsAt, m.startsAt), m.location, LeadMeeting.statusLabel(m.status)]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote)
                    }
                    anmeldung(l)
                    if l.onlineVoting { abstimmungen(m, l) }
                    if unit.canMeetingAttendance, let a = attendance { anwesenheit(a) }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task {
                // Neu laden: bei offener Anmeldung zum Codewechsel, sonst alle 5 bis 15 Sekunden
                while !Task.isCancelled {
                    await load()
                    let wait: Int
                    if let l = live, l.checkinOpen {
                        wait = min(5, max(1, l.refreshIn))
                    } else if live?.polls.contains(where: { $0.status == "open" }) == true {
                        wait = 5
                    } else {
                        wait = 15
                    }
                    try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                }
            }
        }
        .navigationTitle(meeting?.title ?? tr("Versammlung leiten"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: live?.checkinOpen ?? false) { open in
            // Bildschirm bleibt an, solange der QR-Code zum Anmelden zu sehen ist
            UIApplication.shared.isIdleTimerDisabled = open
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .fullScreenCover(isPresented: $bigQr) {
            VStack(spacing: 16) {
                if let link = live?.checkinLink(server: server), let image = qrImage(link) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().padding()
                        .accessibilityLabel(tr("QR-Code zum Anmelden"))
                }
                Text(tr("Mit der HUBIplan-App scannen, um dich anzumelden.")).foregroundStyle(.black)
                Button(tr("Schließen")) { bigQr = false }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .sheet(isPresented: $newPoll) {
            if let m = meeting {
                AbstimmungAnlegen(meeting: m) { item, question, secret, office, candidates in
                    newPoll = false
                    act(tr("Abstimmung angelegt")) {
                        live = try await $0.createPoll(meeting: id, agendaItem: item, question: question, secret: secret, office: office, candidates: candidates)
                    }
                } onCancel: { newPoll = false }
                .verwaltungsBlatt()
            }
        }
        .sheet(isPresented: $scanning) {
            EinlassScan { code in
                scanning = false
                einlass(code)
            } onCancel: { scanning = false }
            .verwaltungsBlatt()
        }
    }

    @ViewBuilder private func anmeldung(_ l: LeadLive) -> some View {
        Section {
            Toggle(tr("Anmeldung offen"), isOn: Binding(get: { l.checkinOpen }, set: { open in
                act { live = try await $0.setCheckin(meeting: id, open: open) }
            }))
            .disabled(busy || !l.live)
            if l.remoteAllowed {
                Toggle(tr("Teilnahme aus der Ferne erlauben"), isOn: Binding(get: { l.remote }, set: { remote in
                    act { live = try await $0.setCheckin(meeting: id, open: l.checkinOpen, remote: remote) }
                }))
                .disabled(busy || !l.live)
            }
            if let link = l.checkinLink(server: server), let image = qrImage(link) {
                HStack {
                    Spacer()
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 220, height: 220)
                        .accessibilityLabel(tr("QR-Code zum Anmelden"))
                    Spacer()
                }
                Text(tr("Mitglieder scannen den Code mit der HUBIplan-App. Er wechselt alle 30 Sekunden."))
                    .font(.footnote).foregroundStyle(Color.secondary)
                Button(tr("Groß zeigen")) { bigQr = true }
            }
        } header: {
            Text(tr("Anmeldung per App"))
        } footer: {
            Text(tr("{app} per App angemeldet, {online} online · {entitled} Stimmen", [
                "app": l.presentApp, "online": l.presentOnline, "entitled": l.entitled,
            ]))
        }
    }

    @ViewBuilder private func abstimmungen(_ m: LeadMeeting, _ l: LeadLive) -> some View {
        Section {
            if l.polls.isEmpty {
                Text(tr("Noch keine Abstimmung angelegt.")).foregroundStyle(.secondary)
            }
            ForEach(l.polls) { p in
                VStack(alignment: .leading, spacing: 4) {
                    Text([p.agendaNumber, p.agendaTitle].filter { !$0.isEmpty }.joined(separator: " ")).font(.subheadline.weight(.semibold))
                    let headline = [p.question, p.office.isEmpty ? "" : tr("Wahl: {office}", ["office": p.office]), p.candidate].filter { !$0.isEmpty }
                    if !headline.isEmpty { Text(headline.joined(separator: " · ")) }
                    Text(pollLine(p)).font(.footnote).foregroundStyle(Color.secondary)
                    if let result = p.result {
                        ForEach(result) { r in Text("\(r.label): \(r.votes)").font(.footnote) }
                    }
                    HStack {
                        switch p.status {
                        case "draft":
                            Button(tr("Starten")) { pollAction(p, "open") }.buttonStyle(.borderedProminent)
                            Button(tr("Löschen"), role: .destructive) {
                                act(tr("Abstimmung gelöscht")) { live = try await $0.deletePoll(meeting: id, poll: p.id) }
                            }.buttonStyle(.bordered)
                        case "open":
                            Button(tr("Beenden")) { pollAction(p, "close") }.buttonStyle(.borderedProminent)
                        case "closed":
                            if p.resolution == nil {
                                Button(tr("Als Beschluss übernehmen")) { pollAction(p, "apply") }.buttonStyle(.bordered)
                            } else {
                                Text(tr("als Beschluss übernommen")).font(.footnote).foregroundStyle(Color.secondary)
                            }
                        default:
                            EmptyView()
                        }
                    }
                    .disabled(busy)
                }
            }
            Button(tr("Neue Abstimmung")) { newPoll = true }
                .disabled(busy || !l.live || !m.agenda.contains(where: \.votable))
        } header: {
            Text(tr("Abstimmungen"))
        }
    }

    @ViewBuilder private func anwesenheit(_ a: AttendanceList) -> some View {
        Section {
            Text(tr("{present} von {voters} Stimmberechtigten anwesend, {represented} vertreten, {guests} Gäste", [
                "present": a.present, "voters": a.voters, "represented": a.represented, "guests": a.guests,
            ]))
            if a.editable {
                if unit.canCheckCards {
                    Button {
                        scanning = true
                    } label: {
                        Label(tr("Ausweis scannen"), systemImage: "qrcode.viewfinder")
                    }
                    .disabled(busy)
                }
                HStack {
                    BeschriftetesFeld(label: tr("Gast eintragen"), text: $guest)
                    Button(tr("Eintragen")) {
                        let name = guest.trimmingCharacters(in: .whitespacesAndNewlines)
                        act(tr("{name} ist eingetragen.", ["name": name])) {
                            attendance = try await $0.setAttendance(meeting: id, membership: nil, name: name, status: "present")
                            guest = ""
                        }
                    }
                    .disabled(busy || guest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text(tr("Die Anwesenheit lässt sich jetzt nicht mehr ändern.")).font(.footnote).foregroundStyle(Color.secondary)
            }
            BeschriftetesFeld(label: tr("Name suchen"), text: $query)
        } header: {
            Text(tr("Anwesenheit"))
        } footer: {
            Text(tr("Vollmachten und Vertreter von Organisationen trägst du im Browser ein."))
        }
        Section {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ForEach(a.rows.filter { q.isEmpty || $0.name.lowercased().contains(q) }, id: \.key) { r in
                Toggle(isOn: Binding(get: { r.present }, set: { present in toggle(r, present: present, list: a) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name)
                        if !r.label.isEmpty { Text(r.label).font(.footnote).foregroundStyle(Color.secondary) }
                    }
                }
                .disabled(busy || !a.editable || r.status == "represented")
            }
        }
    }

    private func pollLine(_ p: LeadPoll) -> String {
        var parts = [LeadPoll.statusLabel(p.status)]
        if p.secret { parts.append(tr("geheim")) }
        if p.status != "draft" { parts.append(tr("{cast} von {entitled} abgestimmt", ["cast": p.cast, "entitled": p.entitled])) }
        return parts.joined(separator: " · ")
    }

    private func pollAction(_ p: LeadPoll, _ action: String) {
        let done: String
        switch action {
        case "open": done = tr("Abstimmung gestartet")
        case "close": done = tr("Abstimmung beendet")
        default: done = tr("Ergebnis als Beschluss übernommen")
        }
        act(done) { live = try await $0.pollAction(meeting: id, poll: p.id, action: action) }
    }

    private func toggle(_ r: AttendanceRow, present: Bool, list: AttendanceList) {
        act {
            if present {
                attendance = try await $0.setAttendance(meeting: id, membership: r.membership, name: r.membership == nil ? r.name : nil, status: "present")
            } else if let entry = r.id {
                attendance = try await $0.removeAttendance(meeting: id, entry: entry)
            }
        }
    }

    private func einlass(_ code: String) {
        Task {
            busy = true
            defer { busy = false }
            guard let card = await model.verwaltung(unit, { try await $0.checkCard(code: code) }) else { return }
            guard let membership = card.membership, card.status != "unknown" else {
                model.adminError = card.status == "unknown" ? card.statusLabel : tr("Der Ausweis gehört nicht zu diesem Verein.")
                return
            }
            if let list = await model.verwaltung(unit, { try await $0.setAttendance(meeting: id, membership: membership, name: nil, status: "present") }) {
                attendance = list
                let name = [card.firstName, card.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                model.adminDone(tr("{name} ist als anwesend eingetragen.", ["name": name]))
            }
        }
    }

    private func load() async {
        let wantsAttendance = unit.canMeetingAttendance
        let loaded: (LeadMeeting, LeadLive, AttendanceList?)? = await model.verwaltung(unit) { client in
            let m = try await client.meeting(id)
            let l = try await client.meetingLive(id)
            let a = wantsAttendance ? try await client.attendance(meeting: id) : nil
            return (m, l, a)
        }
        guard let loaded else { return }
        meeting = loaded.0
        live = loaded.1
        if let a = loaded.2 { attendance = a }
    }

    private func act(_ done: String? = nil, _ work: @escaping @MainActor (AdminClient) async throws -> Void) {
        Task {
            busy = true
            defer { busy = false }
            if await model.verwaltung(unit, work) != nil, let done {
                model.adminDone(done)
            }
        }
    }
}

/// Mitgliedsausweis am Eingang scannen.
private struct EinlassScan: View {
    let found: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if QrScanner.available {
                    QrScanner { text in found(text) }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(tr("Halte die Kamera auf den QR-Code des Mitgliedsausweises."))
                        .font(.footnote).foregroundStyle(Color.secondary)
                } else {
                    KameraHinweis()
                    Text(tr("Ohne Kamera suchst du die Person in der Liste und trägst sie dort ein."))
                        .font(.footnote).foregroundStyle(Color.secondary)
                    Spacer()
                }
            }
            .padding()
            .navigationTitle(tr("Ausweis scannen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen"), action: onCancel) }
            }
        }
    }
}

/// Neue Abstimmung zu einem Beschluss oder einer Wahl.
private struct AbstimmungAnlegen: View {
    let meeting: LeadMeeting
    let create: (Int, String, Bool, String, [String]) -> Void
    let onCancel: () -> Void
    @State private var item: Int?
    @State private var question = ""
    @State private var secret = false
    @State private var office = ""
    @State private var candidates = ""

    init(meeting: LeadMeeting, create: @escaping (Int, String, Bool, String, [String]) -> Void, onCancel: @escaping () -> Void) {
        self.meeting = meeting
        self.create = create
        self.onCancel = onCancel
        _item = State(initialValue: meeting.agenda.first(where: \.votable)?.id)
    }

    private var election: Bool { meeting.agenda.first { $0.id == item }?.type == "election" }

    var body: some View {
        NavigationStack {
            Form {
                Picker(tr("Tagesordnungspunkt"), selection: $item) {
                    ForEach(meeting.agenda.filter(\.votable)) { a in Text(a.label).tag(Optional(a.id)) }
                }
                BeschriftetesFeld(label: election ? tr("Frage (freiwillig)") : tr("Frage, über die abgestimmt wird"), text: $question, axis: .vertical)
                if election {
                    BeschriftetesFeld(label: tr("Amt"), text: $office)
                    BeschriftetesFeld(label: tr("Kandidaten (je Zeile ein Name)"), text: $candidates, axis: .vertical)
                }
                Toggle(tr("Geheime Abstimmung"), isOn: $secret)
            }
            .navigationTitle(tr("Neue Abstimmung"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen"), action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Anlegen")) {
                        guard let item else { return }
                        let names = election ? candidates.components(separatedBy: .newlines) : []
                        create(item, question, secret, election ? office : "", names)
                    }
                    .disabled(item == nil)
                }
            }
        }
    }
}
