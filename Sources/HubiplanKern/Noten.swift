import Foundation

/// Eine Notendatei der eigenen Stimme (neueste Fassung).
public struct ScoreFile: Decodable, Equatable, Identifiable, Sendable {
    public static let pdf = "application/pdf"

    public var id: Int
    public var title: String
    public var instrument: String
    public var position: Int
    /// Fassungs-ID: ändert sie sich, lädt die App neu
    public var version: Int
    public var filename: String
    public var contentType: String
    /// "musicxml", "mei", "abc", "midi" oder leer (PDF, Bild)
    public var notation: String
    /// Zusätzliche Formate, die der Server setzt: musicxml, pdf, midi
    public var formats: [String]
    public var url: String

    enum CodingKeys: String, CodingKey {
        case id, title, instrument, position, version, filename, notation, formats, url
        case contentType = "content_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        instrument = try c.decodeIfPresent(String.self, forKey: .instrument) ?? ""
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        notation = try c.decodeIfPresent(String.self, forKey: .notation) ?? ""
        formats = try c.decodeIfPresent([String].self, forKey: .formats) ?? []
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }

    /// Hörbeispiel (MIDI-Datei), nie als Notenbild.
    public var isAudio: Bool { notation == "midi" }
    public var isImage: Bool { contentType.hasPrefix("image/") }

    /// Notenbild: PDF/Bild direkt, MusicXML/MEI/ABC als vom Server gesetztes PDF.
    public var isSheet: Bool { !isAudio && (contentType == Self.pdf || isImage || formats.contains("pdf")) }

    /// Format, in dem die App das Notenbild lädt ("" = Original).
    public var sheetFormat: String { contentType == Self.pdf || isImage ? "" : "pdf" }
}

/// Ein Eintrag einer Mappe: Stück, Pause oder Ansage.
public struct FolderItem: Decodable, Equatable, Sendable {
    public var kind: String
    public var arrangement: Int?
    public var title: String
    public var composer: String
    public var arrangementName: String
    public var arranger: String
    public var scores: [ScoreFile]
    public var position: Int
    /// Nummer in der Mappe (Marschbuch „27“, „27a“); leer bei Terminen
    public var number: String
    public var note: String

    enum CodingKeys: String, CodingKey {
        case kind, arrangement, title, composer, arranger, scores, position, number, note
        case arrangementName = "arrangement_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "piece"
        arrangement = try c.decodeIfPresent(Int.self, forKey: .arrangement)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        composer = try c.decodeIfPresent(String.self, forKey: .composer) ?? ""
        arrangementName = try c.decodeIfPresent(String.self, forKey: .arrangementName) ?? ""
        arranger = try c.decodeIfPresent(String.self, forKey: .arranger) ?? ""
        scores = try c.decodeIfPresent([ScoreFile].self, forKey: .scores) ?? []
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    public var isPiece: Bool { arrangement != nil }

    /// Notenbilder in der Reihenfolge, in der sie gespielt werden.
    public var sheets: [ScoreFile] {
        scores.filter(\.isSheet).sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }

    /// Komponist und Bearbeitung unter dem Titel.
    public var credit: String { [composer, arrangementName].filter { !$0.isEmpty }.joined(separator: " · ") }
}

struct ScoreFolder: Decodable {
    var id: Int
    var key: String
    var canLead: Bool
    var kind: String
    var name: String
    var note: String
    var items: [FolderItem]

    enum CodingKeys: String, CodingKey {
        case id, key, kind, name, note, items
        case canLead = "can_lead"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        key = try c.decode(String.self, forKey: .key)
        canLead = try c.decodeIfPresent(Bool.self, forKey: .canLead) ?? false
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "other"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        items = try c.decodeIfPresent([FolderItem].self, forKey: .items) ?? []
    }
}

struct ScoreEvent: Decodable {
    var key: String
    var liveKey: String
    var canLead: Bool
    var type: String
    var title: String
    var startsAt: String
    var location: String
    var cancelled: Bool
    var focus: String
    var items: [FolderItem]

    enum CodingKeys: String, CodingKey {
        case key, type, title, location, cancelled, focus, items
        case startsAt = "starts_at"
        case liveKey = "live_key"
        case canLead = "can_lead"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        liveKey = try c.decodeIfPresent(String.self, forKey: .liveKey) ?? ""
        canLead = try c.decodeIfPresent(Bool.self, forKey: .canLead) ?? false
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "rehearsal"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        cancelled = try c.decodeIfPresent(Bool.self, forKey: .cancelled) ?? false
        focus = try c.decodeIfPresent(String.self, forKey: .focus) ?? ""
        items = try c.decodeIfPresent([FolderItem].self, forKey: .items) ?? []
    }
}

/// Einheitliche Sicht auf feste Mappe und Termin-Mappe für Liste, Suche und Notenpult.
public struct Mappe: Equatable, Identifiable, Sendable {
    public var key: String
    public var name: String
    /// "marchbook", "repertoire", "other", "performance" oder "rehearsal"
    public var kind: String
    public var startsAt: String
    public var location: String
    public var cancelled: Bool
    public var note: String
    public var items: [FolderItem]
    /// Ziel für die Live-Vorgabe der Leitung (folder-…, performance-…, rehearsal-…)
    public var liveKey: String = ""
    /// Darf Stücke an alle senden (Dirigent, Leitung)
    public var canLead: Bool = false

    public var id: String { key }
    public var isEvent: Bool { kind == "performance" || kind == "rehearsal" }
    public var pieces: [FolderItem] { items.filter(\.isPiece) }
    /// Stücke, zu denen es Noten für die eigene Stimme gibt (das spielt das Notenpult).
    public var playable: [FolderItem] { pieces.filter { !$0.sheets.isEmpty } }

    /// Art der Mappe in Worten; leer bei „sonstige“.
    public var kindText: String {
        switch kind {
        case "marchbook": return tr("Marschbuch")
        case "repertoire": return tr("Repertoire")
        case "performance": return tr("Auftritt")
        case "rehearsal": return tr("Probe")
        default: return ""
        }
    }
}

/// Notenmappen des eigenen Musikerprofils: feste Mappen und Termine.
public struct ScoreFolders: Decodable, Equatable, Sendable {
    /// Feste Mappen zuerst, dann Termine.
    public var mappen: [Mappe]

    enum CodingKeys: String, CodingKey { case folders, events }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let folders = try c.decodeIfPresent([ScoreFolder].self, forKey: .folders) ?? []
        let events = try c.decodeIfPresent([ScoreEvent].self, forKey: .events) ?? []
        mappen = folders.map {
            Mappe(key: $0.key, name: $0.name, kind: $0.kind, startsAt: "", location: "", cancelled: false, note: $0.note, items: $0.items,
                  liveKey: $0.key, canLead: $0.canLead)
        } + events.map {
            Mappe(key: $0.key, name: $0.title, kind: $0.type, startsAt: $0.startsAt, location: $0.location, cancelled: $0.cancelled, note: $0.focus, items: $0.items,
                  liveKey: $0.liveKey.isEmpty ? $0.key : $0.liveKey, canLead: $0.canLead)
        }
    }

    public var fixed: [Mappe] { mappen.filter { !$0.isEvent } }
    public var events: [Mappe] { mappen.filter(\.isEvent) }
}

/// Suche über alle eigenen Mappen, auf dem Gerät: ohne Groß-/Kleinschreibung, Umlaute tolerant
/// („ae“ findet „ä“), Wortanfänge („alte kam“ findet „Alte Kameraden“), Nummern zuerst.
public enum NotenSuche {
    public struct Stelle: Equatable, Sendable {
        public var mappe: Mappe
        public var item: FolderItem
    }

    /// Ein Treffer je Stück (Arrangement), mit allen Mappen, in denen es steht.
    public struct Treffer: Equatable, Identifiable, Sendable {
        public var arrangement: Int
        public var item: FolderItem
        public var stellen: [Stelle]
        public var rang: Int
        public var id: Int { arrangement }
    }

    public static func normalize(_ text: String) -> String {
        let lower = text.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
        // Übrige Akzente weg (é → e)
        return String(String.UnicodeScalarView(
            lower.decomposedStringWithCanonicalMapping.unicodeScalars.filter { !(0x0300...0x036F).contains($0.value) }
        ))
    }

    public static func words(_ text: String) -> [String] {
        normalize(text).split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// Rang eines Stücks für die Anfrage, kleiner ist besser; `nil`: kein Treffer.
    /// 0 Nummer genau · 1 Nummer beginnt so · 2 Titel beginnt so · 3 alle Wörter als Wortanfang.
    public static func rang(_ query: String, _ item: FolderItem, mappe: Mappe? = nil) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, item.isPiece else { return nil }
        let number = normalize(item.number)
        let nq = normalize(q).replacingOccurrences(of: " ", with: "")
        if !number.isEmpty, number == nq { return 0 }
        if !number.isEmpty, nq.contains(where: \.isNumber), number.hasPrefix(nq) { return 1 }
        let tokens = words(q)
        guard !tokens.isEmpty else { return nil }
        let title = words(item.title)
        if title.joined(separator: " ").hasPrefix(tokens.joined(separator: " ")) { return 2 }
        let all = title + words(item.composer) + words(item.arranger) + words(item.arrangementName)
            + words(mappe?.name ?? "") + words(item.number)
        return tokens.allSatisfy { token in all.contains { $0.hasPrefix(token) } } ? 3 : nil
    }

    /// Alle Treffer über `mappen`, bestes zuerst, gleiches Stück nur einmal.
    public static func suche(_ query: String, in mappen: [Mappe]) -> [Treffer] {
        var order: [Int] = []
        var found: [Int: [(Stelle, Int)]] = [:]
        for mappe in mappen {
            for item in mappe.pieces {
                guard let id = item.arrangement, let r = rang(query, item, mappe: mappe) else { continue }
                if found[id] == nil { order.append(id) }
                found[id, default: []].append((Stelle(mappe: mappe, item: item), r))
            }
        }
        let hits: [Treffer] = order.compactMap { id in
            guard let places = found[id], let best = places.min(by: { $0.1 < $1.1 }) else { return nil }
            return Treffer(arrangement: id, item: best.0.item, stellen: places.map(\.0), rang: best.1)
        }
        return hits.sorted { ($0.rang, normalize($0.item.title)) < ($1.rang, normalize($1.item.title)) }
    }
}

/// Stelle im Notenpult: Stück `piece` der Mappe, Seite `page` dieses Stücks.
public struct PultStelle: Equatable, Sendable {
    public var piece: Int
    public var page: Int

    public init(piece: Int, page: Int) {
        self.piece = piece
        self.page = page
    }
}

/// Blätterlogik ohne Oberfläche, damit sie sich prüfen lässt.
public enum Blaettern {
    public static let weiter = 1
    public static let rueck = -1
    /// Tippen in die Bildmitte: Kopfzeile zeigen
    public static let mitte = 2

    /// Weiter. Am Ende eines Stücks geht es zum nächsten; am Ende der Mappe bleibt die Stelle (`nil`).
    public static func vor(_ at: PultStelle, pages: Int, pieces: Int) -> PultStelle? {
        if at.page + 1 < max(pages, 1) { return PultStelle(piece: at.piece, page: at.page + 1) }
        return at.piece + 1 < pieces ? PultStelle(piece: at.piece + 1, page: 0) : nil
    }

    /// Zurück; am Anfang eines Stücks auf die letzte Seite des vorigen (`previousPages`).
    public static func zurueck(_ at: PultStelle, previousPages: Int) -> PultStelle? {
        if at.page > 0 { return PultStelle(piece: at.piece, page: at.page - 1) }
        if at.piece == 0 { return nil }
        return PultStelle(piece: at.piece - 1, page: max(previousPages, 1) - 1)
    }

    /// Tippen: linkes Drittel zurück, rechte zwei Drittel vor (große Vor-Fläche ist Absicht);
    /// die Bildmitte holt die Kopfzeile.
    public static func tippen(x: Double, y: Double, width: Double, height: Double) -> Int {
        if width <= 0 || height <= 0 { return 0 }
        if x < width / 3 { return rueck }
        if x < width * 2 / 3, y > height / 3, y < height * 2 / 3 { return mitte }
        return weiter
    }
}

extension PortalAccess {
    /// Bereich „Noten“: Musiker, Module Musik und Notenarchiv an.
    public var hasScores: Bool { musician && has(module: "music") && has(module: "scores") }
}

extension Api {
    public func scoreFolders(accessId: Int) async throws -> ScoreFolders {
        try await expect("GET", "/api/portal/\(accessId)/music/folders/")
    }

    /// Pfad einer Notendatei des eigenen Mitgliederbereichs, sonst `nil`. `format` "" oder "pdf".
    static func scorePath(accessId: Int, path: String, format: String) -> String? {
        let prefix = "/api/portal/\(accessId)/music/files/"
        let base = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard base.hasPrefix(prefix) else { return nil }
        var number = base.dropFirst(prefix.count)
        while number.last == "/" { number.removeLast() }
        guard !number.isEmpty, number.count <= 18, number.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return format == "pdf" ? base + "?format=pdf" : base
    }

    /// Notenbild laden (PDF oder Bild). Der Pfad kommt aus der Mappe und wird geprüft.
    public func scoreFile(accessId: Int, file: ScoreFile) async throws -> Data {
        guard let path = Api.scorePath(accessId: accessId, path: file.url, format: file.sheetFormat) else {
            throw ApiError(status: 0, code: "format")
        }
        return try await self.file(path)
    }
}
