import Foundation

// Kacheln der Übersicht (`/api/portal/<Zugang>/home-tiles/` für Mitglieder,
// `/api/app/v1/admin/u/<Einheit>/home-tiles/` für die Verwaltung), Beschreibung in
// hubiplan/docs/app.md. Dieselben Kacheln wie auf der Startseite im Browser und in der
// Android-App: Der Server liefert fertige Texte und ob gerade ein Anlass besteht. Ohne eigene
// Wahl („bei Anlass“) erscheint eine Kachel nur mit Anlass.

public enum TileState: String, CaseIterable, Sendable {
    case auto, on, off

    /// Beschriftung wie unter „Startseite anpassen“ im Browser
    public var label: String {
        switch self {
        case .auto: return tr("bei Anlass")
        case .on: return tr("immer")
        case .off: return tr("nie")
        }
    }
}

public struct TileFigure: Decodable, Equatable, Sendable {
    public var label: String
    public var value: String
    /// nil, "good", "warn" oder "bad"
    public var tone: String?

    enum CodingKeys: String, CodingKey { case label, value, tone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        tone = try c.decodeIfPresent(String.self, forKey: .tone)
    }
}

public struct TileRow: Decodable, Equatable, Sendable {
    public var title: String
    public var detail: String
    /// Pfad auf der eigenen Instanz (öffnet im Browser)
    public var link: String?
    public var tone: String?

    enum CodingKeys: String, CodingKey { case title, detail, link, tone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link)
        tone = try c.decodeIfPresent(String.self, forKey: .tone)
    }
}

public struct TileContent: Decodable, Equatable, Sendable {
    public var figures: [TileFigure]
    public var rows: [TileRow]
    public var text: String
    public var link: String?
    public var linkLabel: String
    /// Aktueller Anlass; leer = keiner
    public var reason: String

    enum CodingKeys: String, CodingKey {
        case figures, rows, text, link, reason
        case linkLabel = "link_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        figures = try c.decodeIfPresent([TileFigure].self, forKey: .figures) ?? []
        rows = try c.decodeIfPresent([TileRow].self, forKey: .rows) ?? []
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link)
        linkLabel = try c.decodeIfPresent(String.self, forKey: .linkLabel) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

public struct HomeTile: Decodable, Equatable, Identifiable, Sendable {
    public var key: String
    public var title: String
    public var description: String
    public var state: TileState
    public var urgent: Bool
    public var shown: Bool
    /// nil bei „nie“
    public var content: TileContent?

    public var id: String { key }

    enum CodingKeys: String, CodingKey { case key, title, description, state, urgent, shown, content }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        state = TileState(rawValue: try c.decodeIfPresent(String.self, forKey: .state) ?? "") ?? .auto
        urgent = try c.decodeIfPresent(Bool.self, forKey: .urgent) ?? false
        shown = try c.decodeIfPresent(Bool.self, forKey: .shown) ?? false
        content = try c.decodeIfPresent(TileContent.self, forKey: .content)
    }
}

public struct HomeTiles: Decodable, Equatable, Sendable {
    public var scope: String
    public var tiles: [HomeTile]

    /// Kacheln, die die Übersicht zeigt (Reihenfolge wie vom Server)
    public var visible: [HomeTile] { tiles.filter(\.shown) }

    enum CodingKeys: String, CodingKey { case scope, tiles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? ""
        tiles = try c.decodeIfPresent([HomeTile].self, forKey: .tiles) ?? []
    }
}

extension Api {
    /// Kacheln der Übersicht im Mitgliederbereich (wie die Startseite im Browser).
    public func memberTiles(accessId: Int) async throws -> HomeTiles {
        try await expect("GET", "/api/portal/\(accessId)/home-tiles/")
    }

    /// Auswahl einer Kachel speichern; gilt auch für die Startseite im Browser.
    public func setMemberTile(accessId: Int, key: String, state: TileState) async throws -> HomeTiles {
        try await expect("PUT", "/api/portal/\(accessId)/home-tiles/", json: ["key": key, "state": state.rawValue])
    }
}

extension AdminClient {
    /// Kacheln der Übersicht in der Verwaltung; Untereinheiten haben keine.
    public func tiles() async throws -> HomeTiles? {
        if unit.isDepartment { return nil }
        let list: HomeTiles = try await api.expect("GET", base + "home-tiles/")
        return list
    }

    public func setTile(key: String, state: TileState) async throws -> HomeTiles? {
        if unit.isDepartment { return nil }
        let list: HomeTiles = try await api.expect("PUT", base + "home-tiles/", json: ["key": key, "state": state.rawValue])
        return list
    }
}
