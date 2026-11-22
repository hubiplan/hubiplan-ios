import HubiplanKern
import SwiftUI
import UIKit

/// Ein Termin mit allen Angaben (UX-Audit 16.11., IOS-04), wie in der Android-App
/// (`EventsPane.kt`): Zeit, Ort mit Anfahrt, Beschreibung, Anhänge und die eigene Rückmeldung
/// mit „Vielleicht“, Begleitpersonen, Bemerkung und „Rückmeldung zurücknehmen“.
/// Datum, Ort und Absage gelten für den gewählten Einzeltermin, nicht für die ganze Serie.
struct TerminDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    let event: Occurrence
    let series: Bool

    @State private var detail: EventDetail?
    @State private var loadError: String?
    @State private var guests = 0
    @State private var note = ""
    /// Anhänge nur ansehen, solange diese Ansicht oben liegt (andere Reiter haben ihre eigene Vorschau)
    @State private var onTop = true

    private var busy: Bool { model.rsvpBusy.contains(event.eventId) }

    var body: some View {
        List {
            if let loadError {
                Section {
                    MeldungText(loadError, .fehler)
                    Button(tr("Erneut versuchen")) { Task { await load() } }
                }
            }
            kopf
            if let detail {
                ort(detail)
                if !event.isCancelled, !detail.isCancelled, let video = detail.video ?? event.video, video.openable {
                    videoraum(video)
                }
                if !detail.description.isEmpty {
                    Section(tr("Beschreibung")) { Text(detail.description) }
                }
                if !detail.programme.isEmpty {
                    Section(tr("Ablauf")) { Text(detail.programme) }
                }
                if !detail.attachments.isEmpty {
                    Section(tr("Anhänge")) {
                        ForEach(detail.attachments) { file in
                            Button {
                                Task { await model.openAttachment(detail, file) }
                            } label: {
                                Label(file.name, systemImage: "doc")
                            }
                            .disabled(model.previewBusy)
                        }
                        if model.previewBusy { Laedt(text: tr("Datei wird geladen …")) }
                    }
                }
                if detail.rsvp.enabled { rueckmeldung(detail) }
                if let reg = detail.registration, reg.enabled, reg.canRegister {
                    TeilnahmeSection(eventId: detail.id, start: event.startsAt)
                }
            } else if loadError == nil {
                Section { Laedt() }
            }
        }
        // Der Titel des Termins steht groß in der Karte darunter, nicht zweimal
        .navigationTitle(tr("Termin"))
        // iPad quer: Zusage und Absage nicht über die ganze Breite
        .lesebreite()
        .zurueckSchutz()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: event.eventId) { await load() }
        .onAppear { onTop = true }
        .onDisappear { onTop = false }
        .quickLookPreview(onTop ? $model.preview : .constant(nil))
    }

    private func load() async {
        switch await model.eventDetail(event) {
        case .success(let fresh):
            loadError = nil
            take(fresh)
        case .failure(let failure):
            loadError = failure.text
        case nil:
            break
        }
    }

    private func take(_ fresh: EventDetail) {
        detail = fresh
        guests = fresh.rsvp.mine?.guests ?? 0
        note = fresh.rsvp.mine?.note ?? ""
    }

    @ViewBuilder
    private var kopf: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.hubi(.title3).bold())
                    .strikethrough(event.isCancelled)
                    .accessibilityAddTraits(.isHeader)
                Text(terminWann(event))
                if series {
                    Text(tr("Termin einer Serie")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                let owner = detail?.owner ?? event.owner
                if !owner.isEmpty {
                    Text(owner).font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                if event.nurVorstand || detail?.nurVorstand == true {
                    Abzeichen(tr("nur Vorstand"), .hinweis)
                }
            }
            if event.isCancelled || (!series && detail?.isCancelled == true) {
                let text = event.note.isEmpty ? (series ? "" : detail?.cancelNote ?? "") : event.note
                MeldungText(text.isEmpty ? tr("Abgesagt") : tr("Abgesagt: {text}", ["text": text]), .fehler)
            } else if !event.note.isEmpty {
                Text(event.note)
            }
        }
    }

    /// Ort mit Anfahrt: „In Karten öffnen“ (Apple Karten), dazu die Links des Servers.
    @ViewBuilder
    private func ort(_ detail: EventDetail) -> some View {
        let location = event.location.isEmpty ? detail.location : event.location
        let address = event.address.isEmpty ? detail.address : event.address
        let lines = [location, address].filter { !$0.isEmpty }
        if !lines.isEmpty || !detail.directions.isEmpty {
            Section(tr("Ort und Anfahrt")) {
                if !lines.isEmpty { Text(lines.joined(separator: "\n")) }
                if !detail.directions.isEmpty {
                    Text(tr("Anfahrt: {text}", ["text": detail.directions])).font(.hubi(.footnote))
                }
                if let maps = Karten.url(name: location, address: address, latitude: detail.latitude, longitude: detail.longitude) {
                    Button {
                        openURL(maps)
                    } label: {
                        Label(tr("In Karten öffnen"), systemImage: "map")
                    }
                }
                if let osm = detail.mapLinks.osm.flatMap(URL.init(string:)), osm.scheme == "https" {
                    Button(tr("Route in OpenStreetMap")) { openURL(osm) }
                }
                if let google = detail.mapLinks.google.flatMap(URL.init(string:)), google.scheme == "https" {
                    Button(tr("Route in Google Maps")) { openURL(google) }
                }
            }
        }
    }

    /// Videoraum (Nextcloud Talk): Link öffnet Safari oder die Talk-App, Passwort zum Kopieren.
    @ViewBuilder
    private func videoraum(_ video: VideoRoom) -> some View {
        Section(tr("Videoraum")) {
            if let url = URL(string: video.url), url.scheme == "https" {
                Button {
                    openURL(url)
                } label: {
                    Label(tr("Videoraum öffnen"), systemImage: "video")
                }
            }
            if !video.password.isEmpty {
                Text(tr("Passwort: {password}", ["password": video.password])).textSelection(.enabled)
                Button(tr("Passwort kopieren")) { UIPasteboard.general.string = video.password }
            }
        }
    }

    @ViewBuilder
    private func rueckmeldung(_ detail: EventDetail) -> some View {
        let rsvp = detail.rsvp
        Section {
            if series {
                Text(tr("Bei Serien gilt die Rückmeldung für alle Termine der Serie.")).font(.hubi(.footnote))
            }
            if let deadline = rsvp.deadline, let date = Zeit.parse(deadline) {
                Text(tr("Anmeldeschluss: {date}", [
                    "date": Zeit.datumUhrzeit(date),
                ]))
            }
            if let free = rsvp.free {
                Text(trn("Noch 1 Platz frei", "Noch {n} Plätze frei", free))
            }
            Abzeichen(
                Rueckmeldung.abzeichen(abgesagt: false, rsvp: true, antwort: rsvp.mine?.status) ?? "",
                Design.zustand(abgesagt: false, antwort: rsvp.mine?.status)
            )
            .accessibilityHidden(true)
            Text(Rueckmeldung.stand(rsvp.mine))
            if let mine = rsvp.mine, !mine.note.isEmpty {
                Text(mine.note).font(.hubi(.footnote)).foregroundStyle(.secondary)
            }
            if !rsvp.canRespond {
                if !rsvp.reason.isEmpty { Text(rsvp.reason).font(.hubi(.footnote)) }
            } else {
                if rsvp.mine != nil {
                    Text(tr("Du kannst deine Rückmeldung bis zum Anmeldeschluss jederzeit ändern."))
                        .font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                if rsvp.guestsAllowed {
                    Stepper(value: $guests, in: 0...max(0, rsvp.maxGuests)) {
                        Text(tr("Begleitpersonen: {guests}", ["guests": guests]))
                    }
                    .disabled(busy)
                }
                if rsvp.noteAllowed {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rsvp.noteQuestion.isEmpty ? tr("Bemerkung (optional)") : rsvp.noteQuestion)
                            .font(.hubi(.footnote))
                        TextField("", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .accessibilityLabel(rsvp.noteQuestion.isEmpty ? tr("Bemerkung (optional)") : rsvp.noteQuestion)
                            .onChange(of: note) { _, now in
                                if now.count > Rueckmeldung.maxNote { note = String(now.prefix(Rueckmeldung.maxNote)) }
                            }
                    }
                    .disabled(busy)
                }
                let sentNote = rsvp.noteAllowed ? note : ""
                ViewThatFits(in: .horizontal) {
                    HStack { antwortKnoepfe(rsvp, sentNote) }
                    VStack(alignment: .leading) { antwortKnoepfe(rsvp, sentNote) }
                }
                .disabled(busy)
                if rsvp.mine != nil {
                    Button(tr("Rückmeldung zurücknehmen"), role: .destructive) { antworten(nil, 0, "") }
                        .buttonStyle(.borderless)
                        .disabled(busy)
                }
            }
            if busy { Laedt(text: tr("Wird gesendet …")) }
            if let failure = model.rsvpErrors[event.eventId] {
                MeldungText(failure, .fehler)
            } else if let notice = model.rsvpNotices[event.eventId] {
                MeldungText(notice, .gut)
            }
        } header: {
            Text(tr("Rückmeldung"))
        }
    }

    @ViewBuilder
    private func antwortKnoepfe(_ rsvp: Rsvp, _ sentNote: String) -> some View {
        Button(tr("Zusagen")) { antworten("yes", guests, sentNote) }
            .buttonStyle(.borderedProminent)
        Button(tr("Absagen")) { antworten("no", 0, sentNote) }
            .buttonStyle(.bordered)
        if rsvp.maybeAllowed {
            Button(tr("Vielleicht")) { antworten("maybe", 0, sentNote) }
                .buttonStyle(.bordered)
        }
    }

    private func antworten(_ status: String?, _ guests: Int, _ note: String) {
        Task {
            if let fresh = await model.respond(event, status: status, guests: guests, note: note) {
                take(fresh)
            } else if model.rsvpErrors[event.eventId] == nil {
                // Ältere Stände antworten ohne Termin: neu laden
                await load()
            }
        }
    }
}

/// Link für Apple Karten (öffnet die App „Karten“): mit Koordinaten genau, sonst über die Anschrift.
enum Karten {
    static func url(name: String, address: String, latitude: Double?, longitude: Double?) -> URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        var query: [URLQueryItem] = []
        if let latitude, let longitude {
            query.append(URLQueryItem(name: "ll", value: String(format: "%.5f,%.5f", latitude, longitude)))
            if !name.isEmpty { query.append(URLQueryItem(name: "q", value: name)) }
        } else if !address.isEmpty {
            query.append(URLQueryItem(name: "address", value: [name, address].filter { !$0.isEmpty }.joined(separator: ", ")))
        } else {
            return nil
        }
        parts?.queryItems = query
        return parts?.url
    }
}
