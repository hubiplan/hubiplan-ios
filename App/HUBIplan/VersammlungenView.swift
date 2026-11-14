import HubiplanKern
import QuickLook
import SwiftUI

/// Tag und Uhrzeit einer Versammlung oder Frist.
func tagUndZeit(_ date: Date?) -> String {
    guard let date else { return "" }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month().year().hour().minute().locale(Locale(identifier: Texte.language)))
}

/// Kurzstand neben „Versammlungen“: die nächste mit Datum, sonst die Zahl der Protokolle.
func versammlungenKurz(_ list: MyMeetings) -> String {
    if let next = list.upcoming.first {
        let day = next.start?.formatted(.dateTime.day().month().year().locale(Locale(identifier: Texte.language))) ?? ""
        return [next.title, day].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    if !list.minutes.isEmpty { return trn("1 Protokoll", "{n} Protokolle", list.minutes.count) }
    return tr("Keine Einladung")
}

/// Hinweise nach einer Aktion und Fehler, oben in der Liste.
private struct Meldungen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let message = model.error {
            Section { Text(message).foregroundStyle(.red) }
        }
        if let notice = model.taskNotice {
            Section { Text(notice).foregroundStyle(.green) }
        }
        if model.previewBusy {
            Section { Text(tr("Datei wird geladen …")).foregroundStyle(.secondary) }
        }
    }
}

/// „Ich“ › Versammlungen: Einladungen mit Tagesordnung, eigene Anträge, freigegebene Protokolle.
struct VersammlungenView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var motionFor: UpcomingMeeting?
    @State private var withdraw: OwnMotion?

    var body: some View {
        List {
            Meldungen()
            if model.meetings?.isEmpty ?? true {
                Text(tr("Zurzeit gibt es keine Einladung und kein Protokoll für dich.")).foregroundStyle(.secondary)
            }
            ForEach(model.meetings?.upcoming ?? []) { meeting in
                Section {
                    kopf(meeting)
                    if !meeting.agenda.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Tagesordnung")).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            ForEach(meeting.sortedAgenda, id: \.position) { point in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(point.line)
                                    if !point.description.isEmpty {
                                        Text(point.description).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.leading, point.level > 0 ? 16 : 0)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if !meeting.motions.isEmpty {
                        Text(tr("Deine Anträge")).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        ForEach(meeting.motions) { motion in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(motion.title + " · " + motion.statusText)
                                if !motion.reply.isEmpty {
                                    Text(tr("Antwort: {antwort}", ["antwort": motion.reply])).font(.footnote).foregroundStyle(.secondary)
                                }
                                if motion.withdrawable && meeting.motionsOpen() {
                                    Button(tr("Antrag zurückziehen"), role: .destructive) { withdraw = motion }
                                        .buttonStyle(.bordered)
                                        .disabled(model.loading)
                                }
                            }
                        }
                    }
                    if meeting.motionsOpen() {
                        Text(tr("Anträge bis {bis}", ["bis": tagUndZeit(meeting.motionUntil.flatMap(Zeit.parse))]))
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(tr("Antrag stellen")) { motionFor = meeting }
                    } else if meeting.motionUntil != nil {
                        Text(tr("Die Frist für Anträge ist vorbei.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let minutes = model.meetings?.minutes, !minutes.isEmpty {
                Section(tr("Protokolle")) {
                    ForEach(minutes) { meeting in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meeting.title)
                            Text(tagUndZeit(meeting.start)).font(.footnote).foregroundStyle(.secondary)
                            Button(tr("Protokoll (PDF)")) { Task { await model.openMinutes(meeting) } }
                                .buttonStyle(.bordered)
                                .disabled(model.previewBusy)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(tr("Versammlungen"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshIch() }
        .quickLookPreview($model.preview)
        .onDisappear { model.taskNotice = nil }
        .sheet(item: $motionFor) { meeting in AntragBlatt(meeting: meeting) }
        .alert(
            tr("Antrag zurückziehen?"),
            isPresented: Binding(get: { withdraw != nil }, set: { if !$0 { withdraw = nil } })
        ) {
            Button(tr("Zurückziehen"), role: .destructive) {
                if let motion = withdraw { Task { await model.withdraw(motion) } }
                withdraw = nil
            }
            Button(tr("Abbrechen"), role: .cancel) { withdraw = nil }
        } message: {
            Text(tr("„{title}“ wird zurückgezogen. Das lässt sich nicht rückgängig machen.", ["title": withdraw?.title ?? ""]))
        }
    }

    @ViewBuilder
    private func kopf(_ meeting: UpcomingMeeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title).font(.headline)
            if !meeting.kindLine.isEmpty { Text(meeting.kindLine).font(.footnote).foregroundStyle(.secondary) }
            Text([tagUndZeit(meeting.start), meeting.location].filter { !$0.isEmpty }.joined(separator: " · "))
            if !meeting.address.isEmpty { Text(meeting.address).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
        if meeting.checkinOpen {
            Text(tr("Die Versammlung läuft. Anmelden und Abstimmen gehen zurzeit im Mitgliederbereich im Browser."))
                .font(.footnote)
            if let access = model.access, let server = model.account?.server,
               let url = URL(string: "\(server)/mein-bereich/versammlungen?zugang=\(access.id)") {
                Button(tr("Im Mitgliederbereich öffnen")) { openURL(url) }
            }
        }
    }
}

/// Antrag zu einer Versammlung stellen.
struct AntragBlatt: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let meeting: UpcomingMeeting
    @State private var title = ""
    @State private var text = ""

    private var ready: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(meeting.title)
                    if let message = model.error { Text(message).foregroundStyle(.red) }
                }
                Section(tr("Titel")) {
                    TextField(tr("Titel"), text: $title)
                        .onChange(of: title) { _, new in if new.count > 300 { title = String(new.prefix(300)) } }
                }
                Section(tr("Begründung")) {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .accessibilityLabel(tr("Begründung"))
                        .onChange(of: text) { _, new in if new.count > 10000 { text = String(new.prefix(10000)) } }
                }
            }
            .navigationTitle(tr("Antrag stellen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Einreichen")) {
                        Task {
                            let sent = await model.submitMotion(
                                meeting,
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            if sent { dismiss() }
                        }
                    }
                    .disabled(!ready || model.loading)
                }
            }
        }
    }
}

/// „Ich“ › Dokumente: freigegebene Dokumente nach Ordnern, nur zum Ansehen.
struct DokumenteView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Meldungen()
            if model.documents?.shown.isEmpty ?? true {
                Text(tr("Für dich sind keine Dokumente freigegeben.")).foregroundStyle(.secondary)
            }
            ForEach(model.documents?.shown ?? []) { folder in
                Section(folder.heading) {
                    ForEach(folder.shown) { document in
                        Button {
                            Task { await model.openDocument(document) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.shownTitle).foregroundStyle(Color.primary)
                                    if !document.line.isEmpty {
                                        Text(document.line).font(.footnote).foregroundStyle(Color.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "doc.text").foregroundStyle(Color.secondary)
                            }
                        }
                        .disabled(model.previewBusy)
                    }
                }
            }
        }
        .navigationTitle(tr("Dokumente"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshIch() }
        .quickLookPreview($model.preview)
    }
}
