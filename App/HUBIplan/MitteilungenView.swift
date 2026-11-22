import HubiplanKern
import QuickLook
import SwiftUI

/// Reiter „Neues“: Mitteilungen des Vereins.
struct MitteilungenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sending = Demo.active && Demo.section == "senden"
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            List {
                if let notice {
                    Section { MeldungText(notice, .gut) }
                }
                if model.offlineSince != nil {
                    OfflineStand()
                } else if let message = model.error {
                    Section {
                        MeldungText(message, .fehler)
                        Button(tr("Erneut versuchen")) { Task { await model.refresh() } }
                    }
                }
                if model.circulars.isEmpty && !model.loading && model.error == nil {
                    Text(tr("Noch keine Mitteilungen.")).foregroundStyle(.secondary)
                }
                ForEach(model.circulars) { item in
                    NavigationLink {
                        MitteilungView(item: item)
                    } label: {
                        let unread = model.unreadCirculars.contains(item.id)
                        VStack(alignment: .leading, spacing: 4) {
                            // Neu: Punkt und Wort, nicht nur Farbe (IOS-22)
                            if unread {
                                Text(tr("● neu")).font(.hubi(.footnote).bold()).foregroundStyle(Color.accentColor)
                            }
                            Text(item.subject).font(unread ? .hubi(.headline).weight(.heavy) : .hubi(.headline))
                            Text(kopfzeile(item)).font(.hubi(.footnote)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle(tr("Mitteilungen"))
            .zugangsWahl()
            .toolbar {
                if let senders = model.senders, !senders.senders.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            notice = nil
                            sending = true
                        } label: {
                            Label(tr("Kurzmitteilung senden"), systemImage: "square.and.pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { sending && !(model.senders?.senders.isEmpty ?? true) }, set: { sending = $0 })) {
                if let senders = model.senders {
                    SendenView(senders: senders) { text in
                        notice = text
                        Task { await model.refresh() }
                    }
                }
            }
            .refreshable { await model.refresh() }
            .lesebreite()
            .overlay { if model.loading && model.circulars.isEmpty { Laedt() } }
        }
    }
}

/// Absender, Art und Datum in einer Zeile; das Datum bricht nicht mitten um.
func kopfzeile(_ item: CircularItem) -> String {
    var parts = [item.sender, item.kindLabel].filter { !$0.isEmpty }
    if let sent = item.sent {
        parts.append(sent.formatted(.dateTime.day().month().year().locale(Texte.locale))
            .replacingOccurrences(of: " ", with: "\u{00A0}"))
    }
    return parts.joined(separator: " · ")
}

struct MitteilungView: View {
    @EnvironmentObject private var model: AppModel
    let item: CircularItem

    /// Zeile mit **fett**, *kursiv* und Links (nur https, http, mailto).
    private func zeile(_ text: String) -> AttributedString {
        var out = AttributedString()
        for span in CircularText.inline(text) {
            var piece = AttributedString(span.text)
            if span.bold && span.italic {
                piece.font = .body.bold().italic()
            } else if span.bold {
                piece.font = .body.bold()
            } else if span.italic {
                piece.font = .body.italic()
            }
            if let link = span.link, let url = URL(string: link) {
                piece.link = url
            }
            out.append(piece)
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.subject).font(.hubi(.title2).bold())
                Text(kopfzeile(item)).font(.hubi(.footnote)).foregroundStyle(.secondary)
                ForEach(Array(CircularText.blocks(item.body ?? "").enumerated()), id: \.offset) { _, block in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(block.lines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if block.kind == "ul" { Text("•") }
                                if block.kind == "ol" { Text("\(index + 1).") }
                                Text(zeile(line))
                            }
                        }
                    }
                }
                if !item.attachments.isEmpty {
                    Divider()
                    // Antippen öffnet den Anhang in der App (IOS-22, wie Android AND-15)
                    ForEach(item.attachments) { file in
                        Button {
                            Task { await model.openCircularAttachment(item, file) }
                        } label: {
                            Label(file.name, systemImage: "paperclip")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .disabled(model.previewBusy || model.offlineSince != nil)
                        .accessibilityHint(tr("Anhang öffnen"))
                    }
                    if model.previewBusy { Laedt(text: tr("Datei wird geladen …")) }
                    if let message = model.error, model.offlineSince == nil {
                        MeldungText(message, .fehler).font(.hubi(.footnote))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
        .navigationTitle(item.sender.isEmpty ? tr("Mitteilung") : item.sender)
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($model.preview)
        .onAppear { model.circularOpened(item) }
    }
}
