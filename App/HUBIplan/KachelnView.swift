import HubiplanKern
import SwiftUI

/// Übersicht mit den Kacheln der Startseite (hubiplan backend/hometiles), wie `TilesOverview` in
/// Android: Kacheln mit Anlass erscheinen von selbst, „Kacheln anpassen“ stellt jede auf
/// „bei Anlass“, „immer“ oder „nie“. Ohne Antwort des Servers bleibt die Übersicht weg.
struct KachelnUebersicht: View {
    @EnvironmentObject private var model: AppModel
    let reloadKey: String
    let load: () async -> HomeTiles?
    let save: (String, TileState) async -> HomeTiles?
    @State private var data: HomeTiles?
    @State private var customizing = false

    var body: some View {
        Group {
            if let tiles = data, !tiles.tiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tiles.visible) { KachelKarte(tile: $0, server: model.account?.server ?? "") }
                    Button(tiles.visible.isEmpty ? tr("Kacheln einblenden") : tr("Kacheln anpassen")) { customizing = true }
                        .font(.hubi(.footnote))
                }
                .sheet(isPresented: $customizing) {
                    KachelnAnpassen(data: $data, save: save)
                }
            }
        }
        .task(id: reloadKey) { data = await load() }
    }
}

private func toneColor(_ tone: String?) -> Color {
    switch tone {
    case "bad": return .red
    case "warn": return .orange
    case "good": return .green
    default: return .primary
    }
}

private struct KachelKarte: View {
    let tile: HomeTile
    let server: String
    @Environment(\.openURL) private var openURL

    private func open(_ path: String?) {
        if let path, let link = serverLink(server: server, path: path), let url = URL(string: link) { openURL(url) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.title).font(.hubi(.headline)).accessibilityAddTraits(.isHeader)
            if let c = tile.content {
                if !c.reason.isEmpty {
                    Text(c.reason).font(.hubi(.subheadline).weight(.semibold)).foregroundStyle(Color.accentColor)
                }
                if !c.figures.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(Array(c.figures.enumerated()), id: \.offset) { _, f in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(f.label).font(.hubi(.caption)).foregroundStyle(Color.secondary)
                                Text(f.value).font(.hubi(.headline)).foregroundStyle(toneColor(f.tone))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                ForEach(Array(c.rows.enumerated()), id: \.offset) { _, r in
                    let row = VStack(alignment: .leading, spacing: 1) {
                        Text(r.title).font(.hubi(.body).weight(.semibold)).foregroundStyle(toneColor(r.tone))
                        if !r.detail.isEmpty { Text(r.detail).font(.hubi(.subheadline)).foregroundStyle(Color.secondary) }
                    }
                    .frame(maxWidth: .infinity, minHeight: r.link == nil ? nil : 44, alignment: .leading)
                    if r.link != nil {
                        Button { open(r.link) } label: { row.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityHint(tr("Öffnen"))
                    } else {
                        row
                    }
                }
                if !c.text.isEmpty {
                    Text(c.text).font(.hubi(.subheadline)).foregroundStyle(Color.secondary)
                }
                if let link = c.link {
                    Button(c.linkLabel.isEmpty ? tr("Öffnen") : c.linkLabel) { open(link) }
                        .font(.hubi(.subheadline))
                }
            } else {
                Text(tile.description).font(.hubi(.subheadline)).foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct KachelnAnpassen: View {
    @Binding var data: HomeTiles?
    let save: (String, TileState) async -> HomeTiles?
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(tr("„Bei Anlass“ zeigt eine Kachel nur, wenn gerade etwas ansteht. Die Auswahl gilt auch für die Startseite im Browser."))
                        .font(.hubi(.footnote))
                        .foregroundStyle(.secondary)
                }
                ForEach(data?.tiles ?? []) { tile in
                    Section {
                        Picker(tile.title, selection: Binding(
                            get: { tile.state },
                            set: { state in
                                guard state != tile.state else { return }
                                busy = true
                                Task {
                                    if let fresh = await save(tile.key, state) { data = fresh }
                                    busy = false
                                }
                            }
                        )) {
                            ForEach(TileState.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(busy)
                    } header: {
                        Text(tile.title)
                    } footer: {
                        if !tile.description.isEmpty { Text(tile.description) }
                    }
                }
            }
            .navigationTitle(tr("Kacheln anpassen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { dismiss() } }
            }
        }
    }
}
