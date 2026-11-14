import HubiplanKern
import SwiftUI

struct HauptView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            TermineView()
                .tabItem { Label(tr("Termine"), systemImage: "calendar") }
            KontoView()
                .tabItem { Label(tr("Mein Konto"), systemImage: "person.crop.circle") }
        }
        .task { await model.refresh() }
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
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month().year().locale(Locale(identifier: Texte.language)))
        if event.allDay { return day + " · " + tr("Ganztägig") }
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

struct KontoView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Verbunden als")) {
                    Text(model.account?.display ?? "")
                    Text(model.account?.email ?? "").foregroundStyle(.secondary)
                }
                Section(tr("Instanz")) {
                    Text(model.account?.server ?? "")
                }
                Section {
                    Button(tr("Verbindung trennen"), role: .destructive) { Task { await model.disconnect() } }
                } footer: {
                    Text(tr("Die App vergisst dieses Konto. Im Browser bleibt alles, wie es ist."))
                }
                Section {
                    Text(tr("Version {version}", ["version": AppModel.version]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("Mein Konto"))
        }
    }
}
