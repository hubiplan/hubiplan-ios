import HubiplanKern
import SwiftUI

// Einlass vor Ort (HUBIplan A6/A7, wie Android): Karten mit der Kamera scannen, Personen ohne
// Karte von Hand einlassen, offene Beträge an der Abendkasse über die Rechnung bar kassieren.
// Die Liste lädt sich alle 10 Sekunden neu; ohne Netz bleibt sie lesbar und Einlässe von Hand
// warten auf das Netz.

private func uhrzeit(_ iso: String) -> String {
    guard let date = Zeit.parse(iso) else { return iso }
    return Zeit.datumUhrzeit(date)
}

struct EinlassView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let eventId: Int
    @State private var list: CheckInList?
    @State private var last: CheckInResult?
    @State private var pending: [PendingCheckIn] = []
    @State private var offline = false
    @State private var search = ""
    @State private var code = ""
    @State private var scanning = false
    @State private var busy = false

    private enum Ausgang {
        case done(CheckInResult)
        case offline
    }

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let list {
                    Section {
                        Text(list.title).font(.hubi(.title3).weight(.semibold))
                        Text(list.stand)
                        if offline {
                            MeldungText(tr("Ohne Netz: Die Liste ist vielleicht nicht aktuell."), .fehler)
                        }
                        if !pending.isEmpty {
                            Text(tr("Warten auf Netz: {n}", ["n": pending.count])).foregroundStyle(Color.fehlerText)
                        }
                    }
                    if list.canEdit {
                        Section {
                            if QrScanner.available {
                                Button(tr("Mit der Kamera scannen")) { scanning = true }
                            } else {
                                KameraHinweis(alternative: tr("Ohne Kamera suchst du die Person in der Liste und lässt sie dort ein."))
                            }
                            // Handscanner tippen den Code wie eine Tastatur ein
                            TextField(tr("Code der Eintrittskarte"), text: $code)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.done)
                                .onSubmit {
                                    let scanned = code
                                    code = ""
                                    if !scanned.trimmingCharacters(in: .whitespaces).isEmpty {
                                        Task { await send(nil, code: scanned) }
                                    }
                                }
                        }
                        .disabled(busy)
                    }
                    if let last {
                        Section {
                            MeldungText(last.message, last.good ? .gut : .fehler)
                            if let p = last.participant {
                                Text(p.name)
                                Text(p.detail).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                            }
                        }
                    }
                    Section {
                        TextField(tr("Name suchen"), text: $search)
                            .suchFeld()
                            .autocorrectionDisabled()
                        let rows = list.filtered(search)
                        if rows.isEmpty { Text(tr("Keine Treffer.")).foregroundStyle(.secondary) }
                        ForEach(rows) { row in zeile(row, list) }
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(nanoseconds: checkInRefreshSeconds * 1_000_000_000)
                }
            }
        }
        .navigationTitle(tr("Einlass"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanning) {
            KartenScan { text in
                scanning = false
                Task { await send(nil, code: text) }
            }
        }
    }

    @ViewBuilder
    private func zeile(_ row: CheckInRow, _ list: CheckInList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.minor ? row.name + " · " + tr("minderjährig") : row.name).font(.hubi(.headline))
            Text(row.detail).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
            if let at = row.checkedInAt {
                Text(tr("eingelassen {when}", ["when": uhrzeit(at)]) + (row.checkedInVia.isEmpty ? "" : " · " + row.checkedInVia))
                    .foregroundStyle(Color.gutText)
            }
            ForEach(Array(row.bookings.enumerated()), id: \.offset) { _, b in
                Text(b.name + " · " + (b.redeemedAt.map { tr("eingelöst {when}", ["when": uhrzeit($0)]) } ?? tr("noch nicht eingelöst")))
                    .font(.hubi(.footnote))
            }
            HStack {
                if list.canEdit && !row.checkedIn {
                    Button(tr("Einlassen")) { Task { await send(row, code: nil) } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(tr("{name} einlassen", ["name": row.name]))
                }
                if list.canEdit && row.checkedIn {
                    Button(tr("Einlass zurücknehmen")) { Task { await send(row, code: nil, undo: true) } }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(tr("Einlass von {name} zurücknehmen", ["name": row.name]))
                }
                if list.canCash, row.owes, let invoice = row.invoiceId {
                    NavigationLink {
                        RechnungView(unit: unit, id: invoice)
                    } label: {
                        Text(tr("Bar kassieren") + " · " + Geld.format(row.outstanding))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(busy)
        }
    }

    private func load() async {
        let id = eventId
        let queue = pending
        let result = await model.verwaltung(unit) { client -> CheckInList? in
            do {
                // Erst nachreichen, was ohne Netz abgehakt wurde
                for step in queue {
                    _ = try await client.checkIn(id, participant: step.participant, undo: step.undo)
                }
                return try await client.checkIns(id)
            } catch let failure as ApiError where failure.code == "offline" && list != nil {
                return nil
            }
        }
        if let fresh = result ?? nil {
            pending = pending.filter { step in !queue.contains(step) }
            list = fresh.with(pending: pending, now: Date().ISO8601Format())
            offline = false
        } else if result != nil {
            offline = true
        }
    }

    private func send(_ row: CheckInRow?, code: String?, undo: Bool = false) async {
        busy = true
        defer { busy = false }
        let id = eventId
        let outcome = await model.verwaltung(unit) { client -> Ausgang in
            do {
                return .done(try await client.checkIn(id, code: code, participant: row?.id, undo: undo))
            } catch let failure as ApiError where failure.code == "offline" && row != nil {
                return .offline
            }
        }
        switch outcome {
        case .done(let r)?:
            last = r
            if let p = r.participant { list = list?.with(p) }
        case .offline?:
            if let row {
                let step = PendingCheckIn(participant: row.id, undo: undo)
                pending = PendingCheckIn.queue(pending, step)
                list = list?.with(pending: [step], now: Date().ISO8601Format())
                offline = true
            }
        case nil:
            break
        }
    }
}

/// Eintrittskarte mit der Kamera lesen.
private struct KartenScan: View {
    @Environment(\.dismiss) private var dismiss
    let found: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                QrScanner(found: found)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(tr("Halte die Kamera auf den QR-Code der Eintrittskarte."))
                    .font(.hubi(.footnote)).foregroundStyle(Color.secondary)
            }
            .padding()
            .navigationTitle(tr("Eintrittskarte scannen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
            }
        }
    }
}
