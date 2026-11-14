import HubiplanKern
import SwiftUI

/// Reiter „Neues“: Mitteilungen des Vereins.
struct MitteilungenView: View {
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
                if model.circulars.isEmpty && !model.loading && model.error == nil {
                    Text(tr("Noch keine Mitteilungen.")).foregroundStyle(.secondary)
                }
                ForEach(model.circulars) { item in
                    NavigationLink {
                        MitteilungView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.subject).font(.headline)
                            Text(kopfzeile(item)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(tr("Neues"))
            .refreshable { await model.refresh() }
            .overlay { if model.loading && model.circulars.isEmpty { ProgressView() } }
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
    @Environment(\.openURL) private var openURL
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
                Text(item.subject).font(.title2.bold())
                Text(kopfzeile(item)).font(.footnote).foregroundStyle(.secondary)
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
                    ForEach(item.attachments) { file in
                        Label(file.name, systemImage: "paperclip")
                    }
                    if let access = model.access, let server = model.account?.server,
                       let target = CircularText.webUrl(server: server, access: access.id, circular: item.id),
                       let url = URL(string: target) {
                        Button(tr("Anhänge im Browser öffnen")) { openURL(url) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
