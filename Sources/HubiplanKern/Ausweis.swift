import Foundation

public struct CardTheme: Codable, Equatable, Sendable {
    public var primary: String
    public var onPrimary: String

    enum CodingKeys: String, CodingKey {
        case primary
        case onPrimary = "on_primary"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primary = try c.decodeIfPresent(String.self, forKey: .primary) ?? ""
        onPrimary = try c.decodeIfPresent(String.self, forKey: .onPrimary) ?? ""
    }
}

/// Welche Wallet der Betreiber eingerichtet und die Einheit eingeschaltet hat.
public struct CardWallet: Codable, Equatable, Sendable {
    public var google: Bool
    public var apple: Bool

    enum CodingKeys: String, CodingKey { case google, apple }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        google = try c.decodeIfPresent(Bool.self, forKey: .google) ?? false
        apple = try c.decodeIfPresent(Bool.self, forKey: .apple) ?? false
    }
}

/// Was auf dem Ausweis steht.
public struct CardDisplay: Codable, Equatable, Sendable {
    /// "organization": Ausweis einer Organisation, Name ganz in `lastName`, Logo statt Foto
    public var kind: String
    public var firstName: String
    public var lastName: String
    /// "active", "future" oder "inactive"
    public var status: String
    public var statusLabel: String
    public var memberType: String?
    public var club: String
    public var federation: String?
    public var departmentLabel: String
    public var departments: [String]
    public var clubNumber: String
    public var photoUrl: String?
    public var logoUrl: String?
    public var theme: CardTheme?

    enum CodingKeys: String, CodingKey {
        case kind, status, club, federation, departments, theme
        case firstName = "first_name"
        case lastName = "last_name"
        case statusLabel = "status_label"
        case memberType = "member_type"
        case departmentLabel = "department_label"
        case clubNumber = "club_number"
        case photoUrl = "photo_url"
        case logoUrl = "logo_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "person"
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "inactive"
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        memberType = try c.decodeIfPresent(String.self, forKey: .memberType)
        club = try c.decodeIfPresent(String.self, forKey: .club) ?? ""
        federation = try c.decodeIfPresent(String.self, forKey: .federation)
        departmentLabel = try c.decodeIfPresent(String.self, forKey: .departmentLabel) ?? ""
        departments = try c.decodeIfPresent([String].self, forKey: .departments) ?? []
        clubNumber = try c.decodeIfPresent(String.self, forKey: .clubNumber) ?? ""
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl)
        theme = try c.decodeIfPresent(CardTheme.self, forKey: .theme)
    }

    public var isOrganization: Bool { kind == "organization" }

    public var name: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    /// Erste Zeile im Ausweis: Vorname, bei Organisationen ein fester Hinweis.
    public var firstLine: String { isOrganization ? tr("Organisationsmitglied") : firstName }
}

/// Antwort von `/api/portal/<Zugang>/card/`.
public struct CardState: Codable, Equatable, Sendable {
    /// "none", "active" oder "revoked"
    public var state: String
    /// Inhalt des QR-Codes (Prüfseite des Ausweises)
    public var url: String?
    public var display: CardDisplay?
    public var wallet: CardWallet?

    enum CodingKeys: String, CodingKey { case state, url, display, wallet }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "none"
        url = try c.decodeIfPresent(String.self, forKey: .url)
        display = try c.decodeIfPresent(CardDisplay.self, forKey: .display)
        wallet = try c.decodeIfPresent(CardWallet.self, forKey: .wallet)
    }

    /// Gültig und vorzeigbar: nur solche Ausweise legt die App für die Anzeige ohne Netz ab.
    public var showable: Bool {
        state == "active" && display != nil && !(url ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Ausweis, wie er zuletzt vom Server kam, mit Foto und Wappen (ohne Netz anzeigen).
public struct StoredCard: Codable, Equatable, Sendable {
    /// Älter als das gilt der Stand als alt und wird mit Datum gezeigt.
    public static let staleAfter: TimeInterval = 24 * 60 * 60

    public var card: CardState
    public var savedAt: Date
    public var photo: Data?
    public var logo: Data?

    public init(card: CardState, savedAt: Date, photo: Data? = nil, logo: Data? = nil) {
        self.card = card
        self.savedAt = savedAt
        self.photo = photo
        self.logo = logo
    }

    public func stale(now: Date = Date()) -> Bool { now.timeIntervalSince(savedAt) > Self.staleAfter }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data) -> StoredCard? { try? JSONDecoder().decode(StoredCard.self, from: data) }
}

/// Ablage der Ausweise eines Kontos (App: geschützte Dateien, Tests: im Speicher).
public protocol CardStore: Sendable {
    func load(accessId: Int) -> StoredCard?
    func save(accessId: Int, card: StoredCard)
    func delete(accessId: Int)
    /// Alles dieses Kontos löschen (Verbindung trennen).
    func clear()
}

/// Was der Reiter „Ausweis“ zeigt.
public enum CardAnzeige: Equatable, Sendable {
    case loading
    /// Ohne Netz und noch nichts gespeichert
    case offlineEmpty
    case revoked
    /// Kein gültiger Ausweis (Mitgliedschaft noch nicht begonnen oder beendet)
    case none
    /// Ausweis vorzeigen; `note`: Hinweis „ohne Netz, Stand …“ zeigen
    case card(StoredCard, note: Bool)

    public static func from(stored: StoredCard?, offline: Bool, now: Date = Date()) -> CardAnzeige {
        guard let stored else { return offline ? .offlineEmpty : .loading }
        if stored.card.state == "revoked" { return .revoked }
        guard stored.card.showable else { return .none }
        return .card(stored, note: offline || stored.stale(now: now))
    }
}

public enum Farbe {
    /// `#RRGGBB` (auch ohne `#`) als Rot, Grün, Blau von 0 bis 1; sonst nil.
    public static func rgb(_ hex: String?) -> (red: Double, green: Double, blue: Double)? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.utf8.count == 6, text.allSatisfy({ $0.isASCII && $0.isHexDigit }), let value = UInt32(text, radix: 16) else {
            return nil
        }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

extension Api {
    public func card(accessId: Int) async throws -> CardState {
        try await expect("GET", "/api/portal/\(accessId)/card/")
    }

    /// Bild mit Geräteschlüssel laden (Pfad aus der Schnittstelle); nil, wenn es nicht zu holen ist.
    public func image(_ path: String) async -> Data? {
        guard let response = try? await raw("GET", path, accept: false),
              (200...299).contains(response.status), !response.body.isEmpty
        else { return nil }
        return response.body
    }

    /// Ausweis abrufen und für die Anzeige ohne Netz ablegen. Gesperrte oder nicht mehr gültige
    /// Ausweise werden aus der Ablage gelöscht (nichts mehr vorzeigen).
    public func refreshCard(accessId: Int, store: CardStore, now: Date = Date()) async throws -> StoredCard {
        let card = try await self.card(accessId: accessId)
        guard card.showable, let display = card.display else {
            store.delete(accessId: accessId)
            return StoredCard(card: card, savedAt: now)
        }
        var photo: Data?
        var logo: Data?
        if let path = display.photoUrl { photo = await image(path) }
        if let path = display.logoUrl { logo = await image(path) }
        let fresh = StoredCard(card: card, savedAt: now, photo: photo, logo: logo)
        store.save(accessId: accessId, card: fresh)
        return fresh
    }
}
