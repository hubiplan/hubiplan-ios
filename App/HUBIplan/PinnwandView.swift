import HubiplanKern
import SwiftUI

// „Ich“ › Pinnwand, wie in der Android-App: kurze Beiträge des Vereins und der eigenen
// Untereinheiten mit Fotos, kein Chat. Wer in HUBIplan schreiben darf, schreibt auch hier.
// Fotos werden verkleinert und ohne Aufnahmedaten gesendet (BelegWahl), nichts bleibt auf dem Gerät.

struct PinnwandView: View {
    @EnvironmentObject private var model: AppModel
    @State private var writing = false
    @State private var notice: String?
    @State private var removing: PinNotice?

    var body: some View {
        let list = model.pinboard ?? PinboardList()
        List {
            if let message = model.error {
                Section { MeldungText(message, .fehler) }
            }
            if let notice {
                Section { MeldungText(notice, .gut) }
            }
            if list.canWrite {
                Section {
                    Button(tr("Beitrag schreiben")) {
                        notice = nil
                        writing = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if list.notices.isEmpty {
                Text(tr("Hier stehen kurze Neuigkeiten aus dem Verein, zum Beispiel ein Foto vom Sommerfest oder eine geänderte Treffpunktzeit."))
                    .foregroundStyle(.secondary)
            }
            ForEach(list.notices) { item in
                PinBeitrag(notice: item) { pinned in
                    Task { await model.pin(item, pinned: pinned) }
                } remove: {
                    removing = item
                }
            }
        }
        .navigationTitle(tr("Pinnwand"))
        .task { await model.reloadPinboard() }
        .refreshable { await model.reloadPinboard() }
        .sheet(isPresented: $writing) {
            NavigationStack {
                PinFormular(list: list) {
                    writing = false
                    notice = tr("Beitrag veröffentlicht.")
                    Task { await model.reloadPinboard() }
                }
            }
        }
        .confirmationDialog(
            tr("Beitrag löschen?"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { item in
            Button(tr("Beitrag löschen"), role: .destructive) {
                Task {
                    if await model.removePin(item) { notice = tr("Beitrag gelöscht.") }
                }
            }
        }
    }
}

/// Ein Beitrag: Herkunft, Text, Fotos; anheften und löschen für Schreibberechtigte.
private struct PinBeitrag: View {
    let notice: PinNotice
    let pin: (Bool) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if notice.pinned {
                    Image(systemName: "pin.fill").accessibilityLabel(tr("Angeheftet"))
                }
                Text(notice.from.isEmpty ? notice.unit : notice.from).font(.headline)
                if notice.isNew {
                    ZustandText(tr("neu"), .gut).font(.footnote)
                }
            }
            Text(notice.text).textSelection(.enabled)
            if !notice.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(notice.photos.enumerated()), id: \.element.id) { index, photo in
                            PinFoto(photo: photo, label: tr("Foto {n}", ["n": index + 1]))
                        }
                    }
                }
            }
            Text([zeitpunkt, notice.line].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if notice.canEdit {
                HStack {
                    Button(notice.pinned ? tr("Nicht mehr anheften") : tr("Anheften")) { pin(!notice.pinned) }
                        .buttonStyle(.bordered)
                    Button(tr("Beitrag löschen"), role: .destructive) { remove() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var zeitpunkt: String {
        guard let iso = notice.createdAt, let date = Zeit.parse(iso) else { return "" }
        return date.formatted(.dateTime.day().month().year().hour().minute().locale(Texte.locale))
    }
}

/// Foto eines Beitrags; geladen mit dem Geräteschlüssel, groß ansehen per Tippen.
private struct PinFoto: View {
    @EnvironmentObject private var model: AppModel
    let photo: PinPhoto
    let label: String
    @State private var image: UIImage?
    @State private var big = false

    var body: some View {
        Group {
            if let image {
                Button { big = true } label: {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 140, height: 140).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .accessibilityLabel(label)
            }
        }
        .task(id: photo.id) {
            if image == nil, let data = await model.portalImage(photo.url) { image = UIImage(data: data) }
        }
        .sheet(isPresented: $big) {
            NavigationStack {
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(label) }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { big = false } }
                }
            }
        }
    }
}

/// Neuer Beitrag: wo, Text, Fotos, anheften, Push.
private struct PinFormular: View {
    @EnvironmentObject private var model: AppModel
    let list: PinboardList
    let done: () -> Void
    @State private var target = 0
    @State private var text = ""
    @State private var pinned = false
    @State private var push = false
    @State private var photos: [Data] = []
    @State private var busy = false
    @State private var failure: String?
    /// Ein Schlüssel je Formular: erneutes Senden nach einem Abbruch legt nichts doppelt an
    @State private var key = UUID().uuidString

    var body: some View {
        Form {
            if list.targets.count > 1 {
                Picker(tr("Wo?"), selection: $target) {
                    ForEach(list.targets.indices, id: \.self) { i in
                        Text(list.targets[i].name).tag(i)
                    }
                }
            }
            Section {
                BeschriftetesFeld(label: tr("Text"), text: $text, axis: .vertical)
            } footer: {
                Text(tr("{n} von {max} Zeichen", ["n": text.count, "max": list.maxText]))
            }
            Section {
                ForEach(photos.indices, id: \.self) { i in
                    HStack {
                        if let image = UIImage(data: photos[i]) {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 72, height: 72)
                                .accessibilityLabel(tr("Foto {n}", ["n": i + 1]))
                        }
                        Spacer()
                        Button(tr("Entfernen"), role: .destructive) { photos.remove(at: i) }
                    }
                }
                if photos.count < list.maxPhotos {
                    BelegWahl(again: false) { jpeg in
                        photos.append(jpeg)
                    } failed: { message in
                        failure = message
                    }
                }
            } header: {
                Text(tr("Fotos"))
            }
            Section {
                Toggle(tr("Oben anheften"), isOn: $pinned)
                Toggle(tr("Mitglieder per Push benachrichtigen"), isOn: $push)
            }
            if let failure {
                Section { MeldungText(failure, .fehler) }
            }
        }
        .tastaturFuehrung()
        .navigationTitle(tr("Neuer Beitrag"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Veröffentlichen")) { Task { await send() } }
                    .disabled(busy || leer || text.count > list.maxText)
            }
        }
        .eingabeschutz(!text.isEmpty || !photos.isEmpty, disabled: busy)
    }

    private var leer: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() async {
        busy = true
        failure = nil
        defer { busy = false }
        let department = list.targets.indices.contains(target) ? list.targets[target].department : nil
        let text = text, pinned = pinned, push = push, photos = photos, key = key
        switch await model.portalCall({ api, access in
            try await api.createPinNotice(
                accessId: access, text: text, department: department, pinned: pinned, push: push, photos: photos, key: key
            )
        }) {
        case .success:
            done()
        case .failure(let error):
            failure = error.status == 0
                ? tr("Ohne Verbindung: Der Beitrag bleibt hier stehen. Bitte später erneut senden.")
                : error.text
        case nil:
            break
        }
    }
}
