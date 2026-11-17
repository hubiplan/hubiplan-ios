import HubiplanKern
import SwiftUI

/// Laufende Versammlung: „Ich bin da“ (QR-Code der Leitung), „Online teilnehmen“, „Ich gehe“ und
/// Abstimmen. Fragt alle vier Sekunden nach, solange die Ansicht offen ist (wie Android).
struct VersammlungLiveView: View {
    @EnvironmentObject private var model: AppModel
    let target: LiveTarget
    @State private var state: MeetingLive?
    @State private var error: String?
    @State private var closed = false
    @State private var busy = false
    @State private var scanning = false

    var body: some View {
        List {
            if let error {
                Section { MeldungText(error, .fehler) }
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let state {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title).font(.headline).accessibilityAddTraits(.isHeader)
                        if !state.subline.isEmpty {
                            Text(state.subline).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Text(state.statusText)
                    if state.isOrganization {
                        Text(tr("Organisationsmitglieder trägt die Leitung mit ihrem Vertreter ein."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if state.canCheckin {
                        Button(tr("QR-Code scannen: Ich bin da")) { scanning = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)
                    }
                    if state.canJoinRemote {
                        Button(tr("Online teilnehmen")) {
                            send { api, access in
                                try await api.meetingCheckin(accessId: access, meetingId: target.meetingId, code: nil, remote: true)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                    }
                    if state.present {
                        Button(tr("Ich gehe")) {
                            send { api, access in try await api.meetingLeave(accessId: access, meetingId: target.meetingId) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                    }
                }
                if !state.polls.isEmpty {
                    Section(tr("Abstimmungen")) {
                        ForEach(state.polls) { poll in
                            AbstimmungKarte(poll: poll, busy: busy) { votes in
                                send { api, access in
                                    try await api.meetingVote(accessId: access, meetingId: target.meetingId, pollId: poll.id, votes: votes)
                                }
                            }
                        }
                    }
                }
            } else if closed {
                Text(tr("Die Anmeldung zu dieser Versammlung ist nicht geöffnet.")).foregroundStyle(.secondary)
            } else {
                HStack { Spacer(); Laedt(); Spacer() }
            }
        }
        .navigationTitle(tr("Versammlung läuft"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: target) { await follow() }
        .sheet(isPresented: $scanning) {
            VersammlungScan { text in
                scanning = false
                scanned(text)
            }
        }
    }

    /// Frisch gescannt: gleich anmelden, bevor der Code abläuft; danach nachfragen.
    private func follow() async {
        if let code = target.code {
            await apply(model.liveCall { api, access in
                try await api.meetingCheckin(accessId: access, meetingId: target.meetingId, code: code)
            })
        }
        while !Task.isCancelled {
            let result = await model.liveCall { api, access in
                try await api.meetingLive(accessId: access, meetingId: target.meetingId)
            }
            switch result {
            case .success(let fresh):
                // Neue Abstimmung ansagen, ohne den Fokus zu verschieben (IOS-03)
                if let text = neueAbstimmungAnsage(vorher: state, jetzt: fresh) { Ansage.sagen(text, dringend: true) }
                state = fresh
                closed = false
            case .failure(let failure) where failure.status == 404:
                closed = true
            case .failure(let failure):
                error = failure.text
            case nil:
                return
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }

    private func apply(_ result: Result<MeetingLive, ApiError>?) async {
        switch result {
        case .success(let fresh):
            state = fresh
            error = nil
        case .failure(let failure):
            error = failure.text
        case nil:
            break
        }
    }

    private func send(_ work: @escaping (Api, Int) async throws -> MeetingLive) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            await apply(model.liveCall(work))
            busy = false
        }
    }

    private func scanned(_ text: String) {
        let found = LiveTarget.from(scan: text, server: model.account?.server ?? "", clubId: model.access?.clubId ?? 0)
        guard let next = found.target, next.meetingId == target.meetingId, let code = next.code else {
            error = found.problem ?? tr("Der QR-Code gehört zu einer anderen Versammlung.")
            return
        }
        send { api, access in try await api.meetingCheckin(accessId: access, meetingId: target.meetingId, code: code) }
    }
}

/// Eine Abstimmung: offene Stimmen mit Auswahl, sonst Hinweis oder Ergebnis.
private struct AbstimmungKarte: View {
    let poll: Poll
    let busy: Bool
    let vote: ([Int: Int]) -> Void
    @State private var choice: [Int: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(poll.heading).font(.headline).accessibilityAddTraits(.isHeader)
            Text(poll.details).font(.footnote).foregroundStyle(.secondary)
            let open = poll.openVotes
            if poll.running && !open.isEmpty {
                ForEach(open) { own in
                    Text(own.label).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    ForEach(poll.options) { option in
                        Button {
                            choice[own.attendance] = option.id
                        } label: {
                            HStack {
                                Image(systemName: choice[own.attendance] == option.id ? "largecircle.fill.circle" : "circle")
                                Text(option.label).foregroundStyle(Color.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(choice[own.attendance] == option.id ? [.isSelected] : [])
                    }
                }
                Text(tr("Eine abgegebene Stimme lässt sich nicht mehr ändern."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(open.count > 1 ? tr("Stimmen abgeben") : tr("Stimme abgeben")) {
                    var votes: [Int: Int] = [:]
                    for own in open { votes[own.attendance] = choice[own.attendance] }
                    vote(votes)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || open.contains { choice[$0.attendance] == nil })
            } else if poll.running && !poll.votes.isEmpty {
                Text(tr("Danke, deine Stimme ist abgegeben. Das Ergebnis kommt nach dem Ende."))
            } else if poll.running {
                Text(tr("Abstimmen können nur anwesende Stimmberechtigte."))
            } else if let result = poll.result {
                Text(tr("Ergebnis:")).font(.subheadline.weight(.semibold))
                ForEach(result) { line in Text("\(line.label): \(line.votes)") }
            }
        }
        .padding(.vertical, 4)
    }
}

/// QR-Code der Versammlungsleitung mit der Kamera lesen.
struct VersammlungScan: View {
    @Environment(\.dismiss) private var dismiss
    let found: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if QrScanner.available {
                    QrScanner(found: found)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(tr("Halte die Kamera auf den QR-Code, den die Versammlungsleitung zeigt."))
                        .font(.footnote).foregroundStyle(Color.secondary)
                } else {
                    Text(tr("Die Kamera ist auf diesem Gerät nicht verfügbar oder nicht erlaubt."))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
            }
            .padding()
            .navigationTitle(tr("QR-Code der Versammlung scannen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
            }
        }
    }
}
