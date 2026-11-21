import HubiplanKern
import SwiftUI

// „Ich“ › Training, wie in der Android-App: Einchecken per QR-Code, eigene Anwesenheit und mit
// Schießsport das eigene Schießbuch mit Stand nach § 14 WaffG und „Schießtermin melden“. Wer
// Trainings leiten darf, kommt zu „Trainings leiten“. Nichts davon bleibt auf dem Gerät.

/// Tag als „2099-01-02“ (Zeitzone des Geräts) für die Schnittstelle.
private func isoTag(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

struct TrainingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var data: MemberTraining?
    @State private var error: String?
    @State private var notice: String?
    @State private var busy = false
    @State private var scanning = false
    @State private var reporting = false

    var body: some View {
        List {
            if let error { Section { MeldungText(error, .fehler) } }
            if let notice { Section { MeldungText(notice, .gut) } }
            if let d = data {
                Section {
                    Button(tr("QR-Code scannen und einchecken")) { scanning = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                    if !d.targets.isEmpty {
                        NavigationLink(tr("Trainings leiten")) { TrainingLeitenView() }
                    }
                    ForEach(d.checkin) { s in
                        Text([Zeit.plainDate(s.date), s.title, s.present ? tr("eingecheckt") : tr("Einchecken offen")]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                }
                Section(tr("Meine Anwesenheit")) {
                    Text(tr("Dieses Jahr {year}-mal da, in den letzten 12 Monaten {last}-mal.", ["year": d.countYear, "last": d.count12]))
                    if d.attendance.isEmpty {
                        Text(tr("Noch keine Anwesenheit eingetragen.")).foregroundStyle(.secondary)
                    }
                    ForEach(d.attendance.prefix(30)) { a in
                        Text([Zeit.plainDate(a.date), a.title, a.kindLabel, a.departmentName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                    }
                }
                if d.shootingEnabled, let log = d.shooting {
                    Section(tr("Schießnachweis nach § 14 WaffG")) {
                        Text(tr("Es zählen nur vom Verein bestätigte Termine mit erlaubnispflichtigen Waffen. Was der Verband anerkennt, entscheidet er selbst."))
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(log.evaluation?.lines ?? [], id: \.self) { Text($0).font(.subheadline) }
                        Button(tr("Schießtermin melden")) { reporting = true }
                    }
                    Section(tr("Mein Schießbuch")) {
                        if log.entries.isEmpty {
                            Text(tr("Noch keine Einträge.")).foregroundStyle(.secondary)
                        }
                        ForEach(log.entries) { e in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Zeit.plainDate(e.date)): \(e.discipline)").font(.headline)
                                if !e.details.isEmpty { Text(e.details).font(.footnote) }
                                Text(e.statusLabel).font(.caption).foregroundStyle(e.status == "rejected" ? Color.fehlerText : Color.accentColor)
                                if e.canWithdraw {
                                    Button(tr("Zurückziehen")) {
                                        act(done: tr("Meldung zurückgezogen.")) { api, id in
                                            try await api.withdrawShooting(accessId: id, entryId: e.id)
                                        }
                                    }
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
        .navigationTitle(tr("Training"))
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $scanning) {
            TrainingScan { text in
                scanning = false
                let found = TrainingLink.from(scan: text, server: model.account?.server ?? "", clubId: model.access?.clubId ?? 0)
                if let link = found.link {
                    act(done: tr("Du bist eingecheckt. Viel Spaß beim Training!")) { api, id in
                        try await api.trainingCheckin(accessId: id, sessionId: link.sessionId, code: link.code)
                    }
                } else {
                    error = found.problem
                }
            }
        }
        .sheet(isPresented: $reporting) {
            NavigationStack {
                SchiessterminMelden { draft, key in
                    reporting = false
                    act(done: tr("Gemeldet. Der Verein bestätigt den Termin.")) { api, id in
                        try await api.reportShooting(accessId: id, draft: draft, key: key)
                    }
                }
            }
        }
    }

    private func reload() async {
        switch await model.portalCall({ api, id in try await api.memberTraining(accessId: id) }) {
        case let .success(fresh)?:
            data = fresh
            error = nil
        case let .failure(failure)?:
            error = failure.text
        case nil:
            break
        }
    }

    private func act(done: String, _ work: @escaping (Api, Int) async throws -> MemberTraining) {
        guard !busy else { return }
        busy = true
        notice = nil
        error = nil
        Task {
            switch await model.portalCall(work) {
            case let .success(fresh)?:
                data = fresh
                notice = done
            case let .failure(failure)?:
                error = failure.text
            case nil:
                break
            }
            busy = false
        }
    }
}

/// QR-Code der Übungsleitung scannen.
private struct TrainingScan: View {
    @Environment(\.dismiss) private var dismiss
    let found: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if QrScanner.available {
                    QrScanner(found: found)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    KameraHinweis()
                    Spacer()
                }
            }
            .padding()
            .navigationTitle(tr("QR-Code der Übungsleitung scannen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
            }
        }
    }
}

/// Schießtermin außerhalb der Trainings melden.
private struct SchiessterminMelden: View {
    @Environment(\.dismiss) private var dismiss
    let send: (ShootingDraft, String) -> Void
    @State private var day = Date()
    @State private var discipline = ""
    @State private var long = false
    @State private var caliber = ""
    @State private var place = ""
    @State private var permit = true
    @State private var competition = false
    @State private var external = true
    @State private var key = UUID().uuidString

    var body: some View {
        Form {
            Section {
                Text(tr("Für Termine außerhalb der Trainings, etwa in einem anderen Verein oder bei einem Wettkampf. Der Verein prüft die Meldung und bestätigt sie; erst dann zählt sie."))
                    .font(.footnote)
                DatePicker(tr("Datum"), selection: $day, in: ...Date(), displayedComponents: .date)
                TextField(tr("Disziplin"), text: $discipline)
                    .weiterFeld()
                Picker(tr("Waffe"), selection: $long) {
                    Text(tr("Kurzwaffe")).tag(false)
                    Text(tr("Langwaffe")).tag(true)
                }
                TextField(tr("Kaliber (optional)"), text: $caliber)
                    .weiterFeld()
                TextField(tr("Schießstand (optional)"), text: $place)
                    .weiterFeld()
                Toggle(tr("erlaubnispflichtige Waffe"), isOn: $permit)
                Toggle(tr("Wettkampf"), isOn: $competition)
                Toggle(tr("in einem anderen Verein"), isOn: $external)
            }
        }
        .tastaturFuehrung()
        .navigationTitle(tr("Schießtermin melden"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Melden")) {
                    var draft = ShootingDraft(date: isoTag(day), discipline: String(discipline.prefix(100)))
                    draft.weaponClass = long ? "long" : "short"
                    draft.caliber = String(caliber.prefix(40))
                    draft.place = String(place.prefix(200))
                    draft.permitRequired = permit
                    draft.competition = competition
                    draft.external = external
                    send(draft, key)
                }
                .disabled(discipline.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// Trainings leiten: Trainings der letzten 60 und nächsten 30 Tage, Übungsabend für heute anlegen.
private struct TrainingLeitenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var list: ManageTrainings?
    @State private var error: String?
    @State private var busy = false
    @State private var opened: Int?

    var body: some View {
        List {
            if let error { Section { MeldungText(error, .fehler) } }
            if let l = list {
                Section {
                    ForEach(l.targets, id: \.self) { target in
                        Button(tr("Übungsabend heute: {name}", ["name": target.name])) { create(target) }
                            .disabled(busy)
                    }
                }
                Section {
                    if l.sessions.isEmpty {
                        Text(tr("Keine Trainings in den letzten 60 und nächsten 30 Tagen.")).foregroundStyle(.secondary)
                    }
                    ForEach(l.sessions) { s in
                        NavigationLink {
                            TrainingLeitungView(sessionId: s.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.title).font(.headline)
                                Text([Zeit.plainDate(s.date), trainingTime(s.startsAt, s.endsAt), s.departmentName, s.discipline]
                                    .filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote)
                                Text(trn("1 anwesend", "{n} anwesend", s.count)).font(.caption)
                            }
                        }
                    }
                }
            } else if error == nil {
                Laedt()
            }
        }
        .navigationTitle(tr("Trainings leiten"))
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened { TrainingLeitungView(sessionId: opened) }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        switch await model.portalCall({ api, id in try await api.manageTrainings(accessId: id) }) {
        case let .success(fresh)?:
            list = fresh
            error = nil
        case let .failure(failure)?:
            error = failure.text
        case nil:
            break
        }
    }

    private func create(_ target: TrainingTarget) {
        guard !busy else { return }
        busy = true
        let key = UUID().uuidString
        let title = tr("Übungsabend")
        Task {
            let result = await model.portalCall { api, id in
                try await api.createTraining(accessId: id, department: target.department, date: isoTag(Date()), title: title, kind: "practice", key: key)
            }
            switch result {
            case let .success(made)?:
                opened = made.id
                await reload()
            case let .failure(failure)?:
                error = failure.text
            case nil:
                break
            }
            busy = false
        }
    }
}

/// Ein Training leiten: Anwesende abhaken, Einchecken öffnen und den QR-Code zeigen.
private struct TrainingLeitungView: View {
    @EnvironmentObject private var model: AppModel
    let sessionId: Int
    @State private var detail: TrainingDetail?
    @State private var code: TrainingCode?
    @State private var error: String?
    @State private var busy = false
    @State private var big = false

    private var link: String? {
        guard let code, detail?.checkinOpen == true else { return nil }
        return TrainingLink.build(server: model.account?.server ?? "", code: code)
    }

    var body: some View {
        List {
            if let error { Section { MeldungText(error, .fehler) } }
            if let d = detail {
                Section {
                    Text([Zeit.plainDate(d.date), trainingTime(d.startsAt, d.endsAt), d.kindLabel, d.location, d.departmentName, d.discipline]
                        .filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote)
                }
                if d.checkinPossible || d.checkinOpen {
                    Section(tr("Einchecken per QR-Code")) {
                        if d.checkinOpen {
                            if let link, let qr = qrImage(link) {
                                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                                    .frame(maxWidth: 240)
                                    .accessibilityLabel(tr("QR-Code zum Einchecken"))
                                Button(tr("Code groß zeigen")) { big = true }
                            }
                            Button(tr("Einchecken schließen")) { change { api, id in try await api.openTrainingCheckin(accessId: id, sessionId: sessionId, open: false) } }
                                .disabled(busy)
                        } else {
                            Button(tr("Einchecken öffnen")) { change { api, id in try await api.openTrainingCheckin(accessId: id, sessionId: sessionId, open: true) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy)
                        }
                    }
                }
                Section(tr("Anwesenheit: {n} von {total}", ["n": d.presentCount, "total": d.attendance.count])) {
                    ForEach(d.attendance) { row in
                        Toggle(isOn: Binding(
                            get: { row.present },
                            set: { on in change { api, id in try await api.setTrainingPresent(accessId: id, sessionId: sessionId, membership: row.membership, present: on) } }
                        )) {
                            Text(row.name + (row.source == "code" ? " · " + tr("per QR-Code") : ""))
                        }
                        .disabled(busy)
                    }
                }
            } else if error == nil {
                Laedt()
            }
        }
        .navigationTitle(detail?.title ?? tr("Training"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        // Offenes Einchecken: Code laufend erneuern, neue Anwesende alle 5 Sekunden
        .task(id: detail?.checkinOpen == true) {
            guard detail?.checkinOpen == true else {
                code = nil
                return
            }
            while !Task.isCancelled {
                if case let .success(next)? = await model.portalCall({ api, id in try await api.trainingCode(accessId: id, sessionId: sessionId) }) {
                    if next.count != detail?.presentCount { await reload() }
                    code = next
                    try? await Task.sleep(for: .seconds(min(5, next.refreshIn)))
                } else {
                    try? await Task.sleep(for: .seconds(15))
                }
            }
        }
        .fullScreenCover(isPresented: $big) {
            if let link {
                GrosserQrCode(url: link, name: detail?.title ?? "", club: tr("Mit der HUBIplan-App oder der Handykamera scannen, um einzuchecken.")) { big = false }
            }
        }
    }

    private func reload() async {
        switch await model.portalCall({ api, id in try await api.manageTraining(accessId: id, sessionId: sessionId) }) {
        case let .success(fresh)?:
            detail = fresh
            error = nil
        case let .failure(failure)?:
            error = failure.text
        case nil:
            break
        }
    }

    private func change(_ work: @escaping (Api, Int) async throws -> TrainingDetail) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            switch await model.portalCall(work) {
            case let .success(fresh)?:
                detail = fresh
            case let .failure(failure)?:
                error = failure.text
            case nil:
                break
            }
            busy = false
        }
    }
}
