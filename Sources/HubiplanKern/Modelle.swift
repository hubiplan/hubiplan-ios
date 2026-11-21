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
    /// Je Plattform (Gesamtaudit 15.11., APP-11); ältere Instanzen kennen nur den Android-Wert
    /// in `minAppVersion`, der für iOS nichts bedeutet.
    public var minAppVersions: [String: Int]
    public var url: String
    public var push: [PushWay]
    /// Anmeldewege mit Passkey (`android`, `browser`); iOS nutzt `browser` (docs/app.md).
    public var passkey: [String]

    enum CodingKeys: String, CodingKey {
        case product, url, push, passkey
        case apiVersion = "api_version"
        case minAppVersion = "min_app_version"
        case minAppVersions = "min_app_versions"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        product = try c.decode(String.self, forKey: .product)
        apiVersion = try c.decode(Int.self, forKey: .apiVersion)
        minAppVersion = try c.decodeIfPresent(Int.self, forKey: .minAppVersion) ?? 1
        minAppVersions = try c.decodeIfPresent([String: Int].self, forKey: .minAppVersions) ?? [:]
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        push = try c.decodeIfPresent([PushWay].self, forKey: .push) ?? []
        passkey = try c.decodeIfPresent([String].self, forKey: .passkey) ?? []
    }
}

extension Instance {
    /// Älteste iOS-Buildnummer, die die Instanz noch bedient (ohne Angabe: jede).
    public var minIosBuild: Int { minAppVersions["ios"] ?? 1 }

    /// Kann diese App (Buildnummer `build`) mit der Instanz arbeiten? Wie Android: Produkt muss
    /// HUBIplan sein, die Fassung mindestens die verlangte. Ohne lesbare Buildnummer
    /// (Entwicklungsfassung, `nil`) entfällt die Versionsprüfung, wie auf dem Server
    /// (devices/views.py, app_too_old).
    public func check(build: Int?) throws {
        guard product == "HUBIplan" else { throw ApiError(status: 0, code: "not_hubiplan") }
        if let build, build < minIosBuild { throw ApiError(status: 0, code: "app_too_old") }
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
    public var pinboardEnabled: Bool
    public var pinboardNew: Int
    /// Auslagen erstatten eingeschaltet und Zahl offener Rückfragen der Kasse
    public var expensesEnabled: Bool
    public var expensesQuestions: Int
    /// Beitragsnachweise: Bereich zeigen und Jahre, für die noch ein Nachweis fehlt
    public var feeProofsEnabled: Bool
    public var feeProofsDue: Int
    /// Hat ein Musikerprofil (für den Bereich „Noten“)
    public var musician: Bool
    /// Wettbewerbe eingeschaltet (nur für Instanzen ohne Modulliste)
    public var competitionsEnabled: Bool
    /// Ansprechpartner einer Organisation, die für Mitarbeiter zahlt (Bereich „Mitarbeiter“)
    public var company: Bool
    /// Modul Meldungen eingeschaltet (nur für Instanzen ohne Modulliste)
    public var entriesEnabled: Bool
    /// Es gibt Objekte, die Mitglieder anfragen dürfen (Bereich „Belegung“)
    public var bookingsEnabled: Bool
    /// Schlüssel für Impressum und Datenschutzhinweise der Einheit (`/impressum/<Schlüssel>`)
    public var imprintKey: String?
    /// Modul Training an, Schießbuch sichtbar und Zahl offener Einchecken (ältere Stände: fehlt)
    public var trainingEnabled: Bool
    public var shootingLogEnabled: Bool
    public var trainingCheckin: Int

    enum CodingKeys: String, CodingKey {
        case id, modules, musician, company
        case competitionsEnabled = "competitions_enabled"
        case entriesEnabled = "entries_enabled"
        case bookingsEnabled = "bookings_enabled"
        case imprintKey = "imprint_key"
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
        case pinboardEnabled = "pinboard_enabled"
        case pinboardNew = "pinboard_new"
        case expensesEnabled = "expenses_enabled"
        case expensesQuestions = "expenses_questions"
        case feeProofsEnabled = "fee_proofs_enabled"
        case feeProofsDue = "fee_proofs_due"
        case trainingEnabled = "training_enabled"
        case shootingLogEnabled = "shooting_log_enabled"
        case trainingCheckin = "training_checkin"
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
        pinboardEnabled = try c.decodeIfPresent(Bool.self, forKey: .pinboardEnabled) ?? false
        pinboardNew = try c.decodeIfPresent(Int.self, forKey: .pinboardNew) ?? 0
        expensesEnabled = try c.decodeIfPresent(Bool.self, forKey: .expensesEnabled) ?? false
        expensesQuestions = try c.decodeIfPresent(Int.self, forKey: .expensesQuestions) ?? 0
        feeProofsEnabled = try c.decodeIfPresent(Bool.self, forKey: .feeProofsEnabled) ?? false
        feeProofsDue = try c.decodeIfPresent(Int.self, forKey: .feeProofsDue) ?? 0
        musician = try c.decodeIfPresent(Bool.self, forKey: .musician) ?? false
        competitionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .competitionsEnabled) ?? false
        company = try c.decodeIfPresent(Bool.self, forKey: .company) ?? false
        entriesEnabled = try c.decodeIfPresent(Bool.self, forKey: .entriesEnabled) ?? false
        bookingsEnabled = try c.decodeIfPresent(Bool.self, forKey: .bookingsEnabled) ?? false
        imprintKey = try c.decodeIfPresent(String.self, forKey: .imprintKey)
        trainingEnabled = try c.decodeIfPresent(Bool.self, forKey: .trainingEnabled) ?? false
        shootingLogEnabled = try c.decodeIfPresent(Bool.self, forKey: .shootingLogEnabled) ?? false
        trainingCheckin = try c.decodeIfPresent(Int.self, forKey: .trainingCheckin) ?? 0
    }

    /// Name der Einheit (Anzeigename, sonst Vereinsname)
    public var title: String { clubDisplayName.isEmpty ? clubName : clubDisplayName }

    /// Zugang als Ansprechpartner einer Organisation (Firma, Verein, Behörde …)
    public var isContact: Bool { memberKind == "organization" && !memberName.isEmpty }

    /// Name der Person dieses Zugangs („Erika Musterfrau“), leer bei älteren Ständen
    public var personName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Beschriftung in der Zugangswahl (UX-Audit 16.11., IOS-07): Verein und Person, damit sich
    /// zwei Zugänge im selben Verein (Familie, Ansprechpartner) unterscheiden lassen.
    public var label: String {
        if isContact {
            return tr("{club}: {member} (Ansprechpartner)", ["club": title, "member": memberName])
        }
        return personName.isEmpty ? title : tr("{club} – {name}", ["club": title, "name": personName])
    }

    /// Satz unter „Mein Konto“: als wer die App gerade auftritt
    public var signedInAs: String {
        isContact
            ? tr("Angemeldet als Ansprechpartner von {member} in {title}", ["member": memberName, "title": title])
            : tr("Angemeldet als Mitglied von {title}", ["title": title])
    }

    /// Meldungen zu Wettbewerben und Anlässen („Gemeldet“ unter „Wettbewerbe“)
    public var hasEntries: Bool { has(module: "entries", fallback: entriesEnabled) }

    /// Bereich „Belegung“: nur, wenn der Server anfragbare Objekte meldet
    public var hasBookings: Bool { bookingsEnabled }

    /// Bereich „Abwesenheiten“: aktives Musikerprofil
    public var hasAbsences: Bool { musician && has(module: "music", fallback: true) }

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
