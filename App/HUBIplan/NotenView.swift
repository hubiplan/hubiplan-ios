import HubiplanKern
import PDFKit
import SwiftUI
import UIKit

/// Zeile unter dem Namen einer Mappe: Art, Datum, Zahl der Stücke, Ort.
func mappeZeile(_ mappe: Mappe) -> String {
    var parts: [String] = []
    var head = mappe.kindText
    if mappe.isEvent, let start = Zeit.parse(mappe.startsAt) {
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month().locale(Texte.locale))
        head = head.isEmpty ? day : head + " · " + day
    }
    if !head.isEmpty { parts.append(head) }
    parts.append(trn("1 Stück", "{n} Stücke", mappe.pieces.count))
    if mappe.cancelled { parts.append(tr("abgesagt")) }
    if !mappe.location.isEmpty { parts.append(mappe.location) }
    return parts.joined(separator: " · ")
}

/// Reiter „Noten“: Notenmappen der eigenen Stimme, Suche über alle Mappen, Notenpult.
struct NotenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var path: [String] = Demo.active && ["mappe", "pult"].contains(Demo.section) ? ["folder-1"] : []
    @State private var play: PultStart?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let message = model.error {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button(tr("Erneut versuchen")) { Task { await model.refreshScores() } }
                    }
                }
                if let access = model.access, !access.hasScores {
                    Text(tr("{club} nutzt keine Noten in der App.", ["club": access.clubDisplayName.isEmpty ? access.clubName : access.clubDisplayName]))
                        .foregroundStyle(.secondary)
                } else if let scores = model.scores {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        treffer(NotenSuche.suche(query, in: scores.mappen))
                    } else if scores.mappen.isEmpty {
                        Text(tr("Für deine Stimme sind noch keine Noten freigegeben.")).foregroundStyle(.secondary)
                    } else {
                        if !scores.fixed.isEmpty {
                            Section(tr("Notenmappen")) { ForEach(scores.fixed) { mappe in zeile(mappe) } }
                        }
                        if !scores.events.isEmpty {
                            Section(tr("Proben und Auftritte")) { ForEach(scores.events) { mappe in zeile(mappe) } }
                        }
                    }
                }
            }
            .navigationTitle(tr("Noten"))
            .searchable(text: $query, prompt: tr("Titel, Komponist oder Nummer"))
            .navigationDestination(for: String.self) { key in
                if let mappe = model.scores?.mappen.first(where: { $0.key == key }) {
                    MappeView(mappe: mappe)
                } else {
                    Text(tr("Diese Mappe gibt es nicht mehr.")).foregroundStyle(.secondary)
                }
            }
            .refreshable { await model.refreshScores() }
            .task(id: model.accessId) { await model.refreshScores() }
            .overlay { if model.loading && model.scores == nil { ProgressView() } }
            .fullScreenCover(item: $play) { start in NotenPult(mappe: start.mappe, first: start.piece) }
        }
    }

    private func zeile(_ mappe: Mappe) -> some View {
        NavigationLink(value: mappe.key) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mappe.name).font(.headline)
                Text(mappeZeile(mappe)).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func treffer(_ hits: [NotenSuche.Treffer]) -> some View {
        if hits.isEmpty {
            Text(tr("Kein Stück gefunden.")).foregroundStyle(.secondary)
        }
        ForEach(hits) { hit in
            Button {
                if let place = hit.stellen.first, let index = place.mappe.playable.firstIndex(where: { $0.arrangement == hit.arrangement }) {
                    play = PultStart(mappe: place.mappe, piece: index)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hit.item.title).font(.headline).foregroundStyle(Color.primary)
                    Text(hit.stellen.map { place in
                        place.item.number.isEmpty ? place.mappe.name
                            : tr("{mappe} Nr. {nummer}", ["mappe": place.mappe.name, "nummer": place.item.number])
                    }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(Color.secondary)
                    if hit.item.sheets.isEmpty {
                        Text(tr("Keine Noten für deine Stimme")).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .disabled(hit.item.sheets.isEmpty)
        }
    }
}

/// Womit das Notenpult beginnt.
struct PultStart: Identifiable {
    let mappe: Mappe
    /// Stelle in `mappe.playable`
    let piece: Int
    var id: String { "\(mappe.key)-\(piece)" }
}

/// Eine Mappe: Stücke in Programmreihenfolge, nach Nummer oder nach Titel.
struct MappeView: View {
    let mappe: Mappe
    @State private var sort = "reihenfolge"
    @State private var play: PultStart? 

    init(mappe: Mappe) {
        self.mappe = mappe
        _play = State(initialValue: Demo.active && Demo.section == "pult" ? PultStart(mappe: mappe, piece: 0) : nil)
    }

    private var items: [FolderItem] {
        switch sort {
        case "nummer": return mappe.pieces.sorted { $0.number.compare($1.number, options: .numeric) == .orderedAscending }
        case "titel": return mappe.pieces.sorted { NotenSuche.normalize($0.title) < NotenSuche.normalize($1.title) }
        default: return mappe.items
        }
    }

    var body: some View {
        List {
            Section {
                if mappe.cancelled {
                    Text(tr("Abgesagt: Noten gibt es dafür nicht mehr.")).foregroundStyle(.red)
                }
                Text(mappeZeile(mappe)).font(.footnote).foregroundStyle(.secondary)
                if !mappe.note.isEmpty { Text(mappe.note) }
                if !mappe.playable.isEmpty {
                    Button(tr("Spielen")) { play = PultStart(mappe: mappe, piece: 0) }
                        .buttonStyle(.borderedProminent)
                }
                Picker(tr("Reihenfolge"), selection: $sort) {
                    Text(tr("Reihenfolge")).tag("reihenfolge")
                    if !mappe.isEvent { Text(tr("Nummer")).tag("nummer") }
                    Text(tr("A–Z")).tag("titel")
                }
                .pickerStyle(.segmented)
            }
            Section {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if item.isPiece {
                        Button {
                            if let index = mappe.playable.firstIndex(where: { $0.arrangement == item.arrangement }) {
                                play = PultStart(mappe: mappe, piece: index)
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                if !item.number.isEmpty {
                                    Text(item.number).font(.headline.monospacedDigit()).foregroundStyle(Color.secondary)
                                        .frame(minWidth: 36, alignment: .trailing)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(Color.primary)
                                    if !item.credit.isEmpty {
                                        Text(item.credit).font(.footnote).foregroundStyle(Color.secondary)
                                    }
                                    if item.sheets.isEmpty {
                                        Text(tr("Keine Noten für deine Stimme")).font(.footnote).foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .disabled(item.sheets.isEmpty)
                    } else {
                        Text(item.title.isEmpty ? (item.note.isEmpty ? tr("Pause") : item.note) : item.title)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(mappe.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $play) { start in NotenPult(mappe: start.mappe, first: start.piece) }
    }
}

/// Eine Seite eines Notenblatts, bildschirmfüllend und ohne eigene Gesten.
private struct PdfSeite: UIViewRepresentable {
    let document: PDFDocument
    let page: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.autoScales = true
        view.backgroundColor = .white
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if let target = document.page(at: min(max(page, 0), max(document.pageCount - 1, 0))), view.currentPage !== target {
            view.go(to: target)
        }
        view.autoScales = true
    }
}

/// Notenpult: eine Seite füllt den Bildschirm, Tippen rechts blättert vor, links zurück, die
/// Mitte zeigt die Kopfzeile. Wischen und Tasten (Fußpedal, Tastatur) blättern auch. Der
/// Bildschirm bleibt an.
struct NotenPult: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let mappe: Mappe
    @State private var at: PultStelle
    @State private var document: PDFDocument?
    @State private var failed: String?
    @State private var header = true
    /// Nach dem Zurückblättern in das vorige Stück auf dessen letzte Seite
    @State private var toLast = false
    @FocusState private var focused: Bool

    init(mappe: Mappe, first: Int) {
        self.mappe = mappe
        _at = State(initialValue: PultStelle(piece: first, page: 0))
    }

    private var pieces: [FolderItem] { mappe.playable }
    private var piece: FolderItem? { pieces.indices.contains(at.piece) ? pieces[at.piece] : nil }
    private var pages: Int { document?.pageCount ?? 0 }

    private func step(_ direction: Int) {
        if direction == Blaettern.mitte {
            header.toggle()
            return
        }
        let next = direction == Blaettern.weiter
            ? Blaettern.vor(at, pages: pages, pieces: pieces.count)
            : Blaettern.zurueck(at, previousPages: 1)
        guard let next else {
            header = true
            return
        }
        header = false
        if next.piece != at.piece {
            toLast = direction == Blaettern.rueck
            document = nil
        }
        at = next
    }

    private func load() async {
        guard let piece else { return }
        failed = nil
        let index = at.piece
        guard let data = await model.sheets(of: piece) else {
            if index == at.piece { failed = model.error ?? tr("Die Noten ließen sich nicht laden.") }
            return
        }
        let whole = PDFDocument()
        for part in data {
            if let pdf = PDFDocument(data: part) {
                for number in 0..<pdf.pageCount {
                    if let page = pdf.page(at: number) { whole.insert(page, at: whole.pageCount) }
                }
            } else if let image = UIImage(data: part), let page = PDFPage(image: image) {
                whole.insert(page, at: whole.pageCount)
            }
        }
        guard index == at.piece else { return }
        if whole.pageCount == 0 {
            failed = tr("Die Noten ließen sich nicht laden.")
            return
        }
        if toLast { at = PultStelle(piece: index, page: whole.pageCount - 1) }
        toLast = false
        document = whole
    }

    private var title: String {
        guard let piece else { return mappe.name }
        return piece.number.isEmpty ? piece.title : piece.number + " · " + piece.title
    }

    private var next: String? {
        guard pages > 0, at.page + 1 >= pages, pieces.indices.contains(at.piece + 1) else { return nil }
        return tr("Nächstes: {titel}", ["titel": pieces[at.piece + 1].title])
    }

    var body: some View {
        GeometryReader { area in
            ZStack {
                Color.white.ignoresSafeArea()
                if let document {
                    PdfSeite(document: document, page: at.page)
                        .accessibilityLabel(tr("Seite {seite} von {seiten}", ["seite": at.page + 1, "seiten": pages]))
                } else if let failed {
                    VStack(spacing: 12) {
                        Text(failed).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button(tr("Erneut versuchen")) { Task { await load() } }.buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                step(Blaettern.tippen(x: point.x, y: point.y, width: area.size.width, height: area.size.height))
            }
            .gesture(DragGesture(minimumDistance: 40).onEnded { drag in
                if abs(drag.translation.width) > abs(drag.translation.height) {
                    step(drag.translation.width < 0 ? Blaettern.weiter : Blaettern.rueck)
                }
            })
        }
        .overlay(alignment: .top) {
            if header {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(pages > 0 ? tr("Seite {seite} von {seiten}", ["seite": at.page + 1, "seiten": pages]) + " · " + mappe.name : mappe.name)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(tr("Schließen")) { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(.regularMaterial)
            }
        }
        .overlay(alignment: .bottom) {
            if let next {
                Text(next).font(.footnote).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
        .preferredColorScheme(.light)
        .statusBarHidden(!header)
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.rightArrow, .downArrow, .pageDown, .space, .return]) { _ in
            step(Blaettern.weiter)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .upArrow, .pageUp]) { _ in
            step(Blaettern.rueck)
            return .handled
        }
        .task(id: at.piece) { await load() }
        .onAppear {
            focused = true
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
