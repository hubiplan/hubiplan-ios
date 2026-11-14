import HubiplanKern
import SwiftUI

struct HauptView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    /// „Mein Konto“ liegt im Reiter „Ich“ (das iPhone zeigt höchstens fünf Reiter)
    @State private var tab = Demo.tab == "konto" ? "ausweis" : Demo.tab

    var body: some View {
        TabView(selection: $tab) {
            TermineView()
                .tabItem { Label(tr("Termine"), systemImage: "calendar") }
                .tag("termine")
            MitteilungenView()
                .tabItem { Label(tr("Neues"), systemImage: "envelope") }
                .tag("mitteilungen")
            if model.accesses.contains(where: { $0.hasTodos || $0.hasHelpers }) {
                AufgabenView()
                    .tabItem { Label(tr("Aufgaben"), systemImage: "checklist") }
                    .tag("aufgaben")
            }
            if model.accesses.contains(where: { $0.hasScores }) {
                NotenView()
                    .tabItem { Label(tr("Noten"), systemImage: "music.note.list") }
                    .tag("noten")
            }
            AusweisView()
                .tabItem { Label(tr("Ich"), systemImage: "person.text.rectangle") }
                .tag("ausweis")
        }
        .task { await model.refresh() }
        .onChange(of: model.showEvents) { _, _ in tab = "termine" }
        // Verwaltung: nach mehr als einer Minute im Hintergrund neu entsperren
        .onChange(of: phase) { _, now in model.sceneChanged(active: now == .active) }
        // Link zum Verbinden kam von außen (hubiplan://…), während schon ein Konto verbunden ist
        .verbindenFrage(aktiv: !model.adding)
        .alert(
            model.linkError ?? "",
            isPresented: Binding(get: { !model.adding && model.linkError != nil }, set: { if !$0 { model.linkError = nil } })
        ) {
            Button(tr("Schließen"), role: .cancel) { model.linkError = nil }
        }
    }
}

struct TermineView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let message = model.error {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button(tr("Erneut versuchen")) { Task { await model.refresh() } }
                    }
                }
                if model.accesses.count > 1 {
                    Picker(tr("Verein"), selection: Binding(
                        get: { model.access?.id ?? 0 },
                        set: { id in Task { await model.choose(access: id) } }
                    )) {
                        ForEach(model.accesses) { access in
                            Text(access.clubDisplayName.isEmpty ? access.clubName : access.clubDisplayName).tag(access.id)
                        }
                    }
                }
                if model.accesses.isEmpty && !model.loading && model.error == nil {
                    Text(tr("Du hast noch keinen Zugang zum Mitgliederbereich. Bitte wende dich an deinen Verein."))
                        .foregroundStyle(.secondary)
                } else if model.events.isEmpty && !model.loading && model.error == nil {
                    Text(tr("Keine Termine in den nächsten Monaten.")).foregroundStyle(.secondary)
                }
                ForEach(model.events) { event in
                    TerminZeile(event: event)
                }
            }
            .navigationTitle(tr("Termine"))
            .refreshable { await model.refresh() }
            .overlay { if model.loading && model.events.isEmpty { ProgressView() } }
        }
    }
}

struct TerminZeile: View {
    @EnvironmentObject private var model: AppModel
    let event: Occurrence

    private var when: String {
        guard let start = event.start else { return event.startsAt }
        // Ganztägige Termine zählen als Kalendertag in deutscher Zeit
        if event.allDay { return terminZeit(event.startsAt, event.endsAt, allDay: true) }
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month().year().locale(Locale(identifier: Texte.language)))
        return day + " · " + start.formatted(.dateTime.hour().minute().locale(Locale(identifier: Texte.language)))
    }

    private var status: String? {
        if event.isCancelled { return tr("Abgesagt") }
        guard event.rsvpEnabled else { return nil }
        switch event.myResponse {
        case "yes": return tr("Zugesagt")
        case "no": return tr("Abgelehnt")
        case "maybe": return tr("Vielleicht")
        default: return tr("Rückmeldung fehlt")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
                .strikethrough(event.isCancelled)
            Text(when).font(.subheadline)
            if !event.location.isEmpty {
                Text(event.location).font(.subheadline).foregroundStyle(.secondary)
            }
            if !event.owner.isEmpty {
                Text(event.owner).font(.footnote).foregroundStyle(.secondary)
            }
            if let status {
                Text(status)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(event.responseMissing ? Color.orange : Color.secondary)
            }
            if event.rsvpEnabled && !event.isCancelled {
                HStack {
                    Button(tr("Zusagen")) { Task { await model.respond(event, status: "yes") } }
                        .buttonStyle(.borderedProminent)
                        .disabled(event.myResponse == "yes" || model.loading)
                    Button(tr("Absagen")) { Task { await model.respond(event, status: "no") } }
                        .buttonStyle(.bordered)
                        .disabled(event.myResponse == "no" || model.loading)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

/// „Mein Konto“: Konten, Trennen, Gerätekalender. Erreichbar über den Knopf im Reiter „Ich“.
struct KontoView: View {
    @EnvironmentObject private var model: AppModel
    @State private var unsent = 0
    @State private var confirmDisconnect = false

    var body: some View {
            ScrollViewReader { scroll in
            Form {
                Section(tr("Verbunden als")) {
                    Text(model.account?.display ?? "")
                    Text(model.account?.email ?? "").foregroundStyle(.secondary)
                }
                Section(tr("Instanz")) {
                    Text(model.account?.server ?? "")
                }
                Section {
                    ForEach(model.accounts.accounts) { entry in
                        Button {
                            Task { await model.switchAccount(entry.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.accounts.label(entry)).foregroundStyle(Color.primary)
                                    Text(entry.email).font(.footnote).foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                if entry.id == model.accounts.activeId {
                                    Image(systemName: "checkmark").accessibilityLabel(tr("Wird gezeigt"))
                                }
                            }
                        }
                    }
                    Button {
                        model.linkError = nil
                        model.adding = true
                    } label: {
                        Label(tr("Weiteres Konto verbinden"), systemImage: "plus")
                    }
                    .disabled(model.accounts.full)
                } header: {
                    Text(tr("Konten"))
                } footer: {
                    Text(tr("Für mehrere Vereine mit eigener HUBIplan-Instanz. Tippe ein Konto an, um es zu zeigen."))
                }
                Section {
                    Button(tr("Verbindung trennen"), role: .destructive) {
                        // Nicht gesendete Buchungen gingen verloren: vorher fragen
                        unsent = model.draftBox?.count ?? 0
                        if unsent > 0, !Demo.active { confirmDisconnect = true } else { Task { await model.disconnect() } }
                    }
                    .confirmationDialog(tr("Verbindung trennen?"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
                        Button(tr("Trennen und Entwürfe löschen"), role: .destructive) { Task { await model.disconnect() } }
                    } message: {
                        Text(trn(
                            "Auf diesem iPhone liegt noch 1 nicht gesendete Buchung. Beim Trennen geht sie verloren.",
                            "Auf diesem iPhone liegen noch {n} nicht gesendete Buchungen. Beim Trennen gehen sie verloren.",
                            unsent
                        ))
                    }
                } footer: {
                    Text(tr("Die App vergisst dieses Konto. Im Browser bleibt alles, wie es ist."))
                }
                Section {
                    Toggle(tr("Termine in den Kalender des Geräts übernehmen"), isOn: Binding(
                        get: { model.calendarOn },
                        set: { on in Task { await model.setCalendar(on: on) } }
                    ))
                    if model.calendarOn {
                        Picker(tr("Erinnerung"), selection: Binding(
                            get: { model.reminder ?? -1 },
                            set: { minutes in Task { await model.setReminder(minutes >= 0 ? minutes : nil) } }
                        )) {
                            ForEach(Erinnerung.choices, id: \.self) { minutes in
                                Text(Erinnerung.label(minutes)).tag(minutes ?? -1)
                            }
                        }
                    }
                    if model.calendarDenied {
                        Text(tr("Ohne Zugriff auf den Kalender bleiben die Termine nur in der App. Du kannst ihn in den Einstellungen des Geräts unter HUBIplan erlauben."))
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(tr("Gerätekalender")).id("kalender")
                } footer: {
                    Text(tr("Je Verein ein eigener Kalender „HUBIplan“. Er liegt dort, wo dein Kalender neue Termine ablegt (zum Beispiel in iCloud), und wird aktualisiert, wenn du die App öffnest, und nach jeder Rückmeldung."))
                }
                Section {
                    Text(tr("Version {version}", ["version": AppModel.version]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("Mein Konto"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Vorführmodus: für das Bildschirmfoto zum Gerätekalender springen
                if Demo.active, Demo.section == "kalender" {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    scroll.scrollTo("kalender", anchor: .top)
                }
            }
            }
            .sheet(isPresented: $model.adding, onDismiss: {
                model.pending = nil
                model.linkError = nil
            }) {
                VerbindenView()
            }
    }
}
