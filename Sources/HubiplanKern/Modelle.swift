import Foundation

// Antworten der App-Schnittstelle (`/api/app/v1/`, Beschreibung in hubiplan/docs/app.md).
// Unbekannte Felder werden ignoriert, damit neue Server-Versionen die App nicht stören;
// fehlende Felder älterer Server bekommen Vorgaben.

/// Push-Weg, den die Instanz anbietet (`instance/` › `push`).
public struct PushWay: Decodable, Equatable, Sendable {
    public var kind: String
    public var gateway: String
    public var vapidPublicKey: String

    enum CodingKeys: String, CodingKey {
        case kind, gateway
        case vapidPublicKey = "vapid_public_key"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        gateway = try c.decodeIfPresent(String.self, forKey: .gateway) ?? ""
        vapidPublicKey = try c.decodeIfPresent(String.self, forKey: .vapidPublicKey) ?? ""
    }
}

/// Selbstauskunft der Instanz ohne Anmeldung.
public struct Instance: Decodable, Equatable, Sendable {
    public var product: String
    public var apiVersion: Int
    public var minAppVersion: Int
    public var url: String
    public var push: [PushWay]
    /// Anmeldewege mit Passkey (`android`, `browser`); iOS nutzt `browser` (docs/app.md).
    public var passkey: [String]

    enum CodingKeys: String, CodingKey {
        case product, url, push, passkey
        case apiVersion = "api_version"
        case minAppVersion = "min_app_version"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        product = try c.decode(String.self, forKey: .product)
        apiVersion = try c.decode(Int.self, forKey: .apiVersion)
        minAppVersion = try c.decodeIfPresent(Int.self, forKey: .minAppVersion) ?? 1
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        push = try c.decodeIfPresent([PushWay].self, forKey: .push) ?? []
        passkey = try c.decodeIfPresent([String].self, forKey: .passkey) ?? []
    }
}

public struct AppUser: Decodable, Equatable, Sendable {
    public var email: String
    public var display: String
}

public struct DeviceInfo: Decodable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var platform: String
    public var lastSeenAt: String?
    public var current: Bool
    /// Härtung H7: nil = Server kennt keine Schlüsselpaare (ältere Instanz)
    public var key: Bool?
    public var renewDue: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, platform, current, key
        case lastSeenAt = "last_seen_at"
        case renewDue = "renew_due"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? "ios"
        lastSeenAt = try c.decodeIfPresent(String.self, forKey: .lastSeenAt)
        current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
        key = try c.decodeIfPresent(Bool.self, forKey: .key)
        renewDue = try c.decodeIfPresent(Bool.self, forKey: .renewDue) ?? false
    }
}

/// Antwort auf das Verbinden: Geräteschlüssel `hpd_…`, Gerät und Konto.
public struct Paired: Decodable, Equatable, Sendable {
    public var token: String
    public var device: DeviceInfo
    public var user: AppUser
}

/// Neuer Geräteschlüssel nach der Erneuerung (H7).
public struct Renewed: Decodable, Equatable, Sendable {
    public var token: String
    public var device: DeviceInfo
}

struct RenewChallenge: Decodable {
    var challenge: String
}

/// Zugang zum Mitgliederbereich einer Einheit.
public struct PortalAccess: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var clubName: String
    public var clubId: Int
    public var clubDisplayName: String
    public var firstName: String
    public var lastName: String
    /// "organization": Zugang als Ansprechpartner einer Organisation
    public var memberKind: String
    public var memberName: String
    /// Eingeschaltete Module der Einheit (ältere Stände: fehlt)
    public var modules: [String]?
    public var eventsEnabled: Bool
    /// Helferdienste eingeschaltet (nur für Instanzen ohne Modulliste)
    public var helpersEnabled: Bool
    /// Versammlungen und Dokumente eingeschaltet (nur für Instanzen ohne Modulliste)
    public var meetingsEnabled: Bool
    public var docsEnabled: Bool
    /// Umfragen eingeschaltet (nur für Instanzen ohne Modulliste) und Zahl unbeantworteter
    public var surveysEnabled: Bool
    public var surveysOpen: Int
    /// Hat ein Musikerprofil (für den Bereich „Noten“)
    public var musician: Bool
    /// Wettbewerbe eingeschaltet (nur für Instanzen ohne Modulliste)
    public var competitionsEnabled: Bool
    /// Ansprechpartner einer Organisation, die für Mitarbeiter zahlt (Bereich „Mitarbeiter“)
    public var company: Bool

    enum CodingKeys: String, CodingKey {
        case id, modules, musician, company
        case competitionsEnabled = "competitions_enabled"
        case clubName = "club_name"
        case clubId = "club_id"
        case clubDisplayName = "club_display_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case memberKind = "member_kind"
        case memberName = "member_name"
        case eventsEnabled = "events_enabled"
        case helpersEnabled = "helpers_enabled"
        case meetingsEnabled = "meetings_enabled"
        case docsEnabled = "docs_enabled"
        case surveysEnabled = "surveys_enabled"
        case surveysOpen = "surveys_open"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        clubName = try c.decode(String.self, forKey: .clubName)
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId) ?? 0
        clubDisplayName = try c.decodeIfPresent(String.self, forKey: .clubDisplayName) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        memberKind = try c.decodeIfPresent(String.self, forKey: .memberKind) ?? "person"
        memberName = try c.decodeIfPresent(String.self, forKey: .memberName) ?? ""
        modules = try c.decodeIfPresent([String].self, forKey: .modules)
        eventsEnabled = try c.decodeIfPresent(Bool.self, forKey: .eventsEnabled) ?? true
        helpersEnabled = try c.decodeIfPresent(Bool.self, forKey: .helpersEnabled) ?? false
        meetingsEnabled = try c.decodeIfPresent(Bool.self, forKey: .meetingsEnabled) ?? false
        docsEnabled = try c.decodeIfPresent(Bool.self, forKey: .docsEnabled) ?? false
        surveysEnabled = try c.decodeIfPresent(Bool.self, forKey: .surveysEnabled) ?? false
        surveysOpen = try c.decodeIfPresent(Int.self, forKey: .surveysOpen) ?? 0
        musician = try c.decodeIfPresent(Bool.self, forKey: .musician) ?? false
        competitionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .competitionsEnabled) ?? false
        company = try c.decodeIfPresent(Bool.self, forKey: .company) ?? false
    }

    /// Modul eingeschaltet? Ohne Modulliste (ältere Instanz) gilt der einzelne Schalter.
    public func has(module: String, fallback: Bool = false) -> Bool {
        modules?.contains(module) ?? fallback
    }
}

public struct Me: Decodable, Equatable, Sendable {
    public var user: AppUser
    public var device: DeviceInfo
    public var portal: [PortalAccess]
}
