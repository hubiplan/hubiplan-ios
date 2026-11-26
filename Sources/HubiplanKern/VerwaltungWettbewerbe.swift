import Foundation

// Verwaltung in der App: Wettbewerbe wie in der Android-App. Eigene, nicht abgeschlossene
// Wettbewerbe; „Standmodus öffnen“ legt einen Standzugang bis zum Ende des Wettbewerbstags an
// (oder nimmt den schon angelegten) und öffnet den Standmodus der Instanz in der App.

extension AdminUnit {
    /// Bereich „Wettbewerbe“: Modul an und Ergebnisse erfassen dürfen, nur in der Einheit selbst.
    /// Ältere Server kennen „competitions.manage“ und „competitions.results“.
    public var showsCompetitions: Bool {
        let rights: Set<String> = ["competitions.manage", "competitions.results", "competitions.edit", "results.edit"]
        return !isDepartment && modules.contains("competitions") && permissions.contains { rights.contains($0) }
    }
}

public struct AdminCompetition: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var date: String
    public var status: String
    public var form: String
    public var own: Bool
    public var location: String
    public var starterCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, date, status, form, own, location
        case starterCount = "starter_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        form = try c.decodeIfPresent(String.self, forKey: .form) ?? ""
        own = try c.decodeIfPresent(Bool.self, forKey: .own) ?? true
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        starterCount = try c.decodeIfPresent(Int.self, forKey: .starterCount)
    }

    public var isFinal: Bool { status == "endgueltig" }
    public var isBird: Bool { form == "vogel" }

    /// „14.06.2027 · Schützenhaus · Vogelschießen · 23 Starter“
    public var line: String {
        var parts = [Zeit.plainDate(date), location.trimmingCharacters(in: .whitespaces)]
        if isBird { parts.append(tr("Vogelschießen")) }
        if let count = starterCount, count > 0 { parts.append(trn("1 Starter", "{n} Starter", count)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Eigene, nicht abgeschlossene Wettbewerbe: heutige und kommende zuerst (nächster oben),
    /// danach vergangene (jüngster oben). `today`: `JJJJ-MM-TT`.
    public static func open(_ all: [AdminCompetition], today: String) -> [AdminCompetition] {
        let rows = all.filter { $0.own && !$0.isFinal }
        let coming = rows.filter { $0.date >= today }.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        let past = rows.filter { $0.date < today }.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
        return coming + past
    }
}

/// Standzugang; `token` kommt nur direkt nach dem Anlegen.
public struct StandAccess: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var label: String
    public var expiresAt: String
    public var active: Bool
    public var token: String?

    enum CodingKeys: String, CodingKey {
        case id, label, active, token
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt) ?? ""
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        token = try c.decodeIfPresent(String.self, forKey: .token)
    }

    /// Noch gültig? Ein unlesbares Datum gilt als abgelaufen.
    public func valid(now: Date) -> Bool {
        guard let end = Zeit.parse(expiresAt) else { return false }
        return end > now
    }
}

/// Inhalt eines Stand-QR-Codes: `https://<Instanz>/stand/zugang/<Schlüssel>`.
public struct StandLink: Equatable, Sendable {
    public let server: String
    public let token: String

    /// Adresse des Standmodus mit Standzugang.
    public static func url(server: String, token: String) -> String {
        var base = server
        while base.hasSuffix("/") { base.removeLast() }
        return "\(base)/stand/zugang/\(token)"
    }

    public var url: String { Self.url(server: server, token: token) }

    public static func parse(_ text: String) -> StandLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed), parts.scheme == "https",
              parts.query == nil, parts.fragment == nil, parts.user == nil, parts.password == nil,
              let origin = httpsOrigin(parts)
        else { return nil }
        let prefix = "/stand/zugang/"
        var path = parts.percentEncodedPath
        guard path.hasPrefix(prefix) else { return nil }
        path.removeFirst(prefix.count)
        while path.hasSuffix("/") { path.removeLast() }
        guard (16...200).contains(path.count),
              path.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        return StandLink(server: origin, token: path)
    }

    /// Darf die eingebettete Ansicht diese Adresse laden? Nur die eigene Instanz über HTTPS,
    /// ohne Benutzerangabe (Sicherheitsprüfung 26.11.2026, SEC-04).
    public static func sameInstance(server: String, url: String) -> Bool {
        guard let a = URLComponents(string: server), let b = URLComponents(string: url),
              a.scheme == "https", b.scheme == "https", let hostA = a.host, let hostB = b.host, !hostA.isEmpty,
              a.user == nil, a.password == nil, b.user == nil, b.password == nil
        else { return false }
        return hostA.lowercased() == hostB.lowercased() && (a.port ?? 443) == (b.port ?? 443)
    }

    /// Regeln für die eingebettete Ansicht (`WKContentRuleList`): Die Seite im Standmodus lädt
    /// nichts von fremden Servern nach (Bilder, Skripte, Abrufe), nur von der eigenen Instanz und
    /// Inhalte ohne Verbindung (`data:`, `blob:`, `about:`). nil: `server` ist keine Adresse der
    /// Form `https://Host[:Port]` (Sicherheitsprüfung 26.11.2026, SEC-04).
    public static func contentRules(server: String) -> String? {
        guard let parts = URLComponents(string: server), parts.scheme == "https", parts.user == nil,
              let origin = httpsOrigin(parts)
        else { return nil }
        // Im Muster sind Punkte und andere Sonderzeichen wörtlich gemeint
        var pattern = ""
        for character in origin {
            if character.isASCII, character.isLetter || character.isNumber || character == "-" || character == ":" || character == "/" {
                pattern.append(character)
            } else if character.isASCII {
                pattern.append("\\")
                pattern.append(character)
            } else {
                return nil
            }
        }
        // Ohne Port in der Adresse gilt 443 auch ausgeschrieben. Je Muster eine Regel: Die Regeln
        // von WebKit kennen kein „oder“.
        var allowed = ["^" + pattern + "/"]
        if parts.port == nil { allowed.append("^" + pattern + ":443/") }
        allowed += ["^data:", "^blob:", "^about:"]
        var rules: [[String: Any]] = [["trigger": ["url-filter": ".*"], "action": ["type": "block"]]]
        for filter in allowed {
            rules.append(["trigger": ["url-filter": filter], "action": ["type": "ignore-previous-rules"]])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Standzugänge, die diese App angelegt hat, bis zu ihrem Ablauf. Der Standmodus hält noch
/// nicht übertragene Eingaben je Standzugang; öffnet die App denselben Wettbewerb erneut, nimmt
/// sie deshalb denselben Zugang statt eines neuen. Liegt im sicheren Speicher des Kontos.
public struct StandStore: Sendable {
    public static let key = "standzugaenge"
    private let store: SecretStore

    public init(store: SecretStore) {
        self.store = store
    }

    private static func name(_ unit: AdminUnit, _ competition: Int) -> String { "\(unit.key):\(competition)" }

    /// Gültige Zugänge mit Schlüssel; abgelaufene und unlesbare fallen dabei heraus.
    private func load(now: Date) -> [String: StandAccess] {
        guard let raw = store.read(Self.key), let all = try? JSONDecoder().decode([String: StandAccess].self, from: Data(raw.utf8)) else {
            return [:]
        }
        return all.filter { $0.value.token != nil && $0.value.valid(now: now) }
    }

    private func save(_ all: [String: StandAccess]) {
        guard !all.isEmpty, let data = try? JSONEncoder().encode(all) else {
            store.write(Self.key, nil)
            return
        }
        store.write(Self.key, String(decoding: data, as: UTF8.self))
    }

    public func get(unit: AdminUnit, competition: Int, now: Date = Date()) -> StandAccess? {
        let all = load(now: now)
        save(all)
        return all[Self.name(unit, competition)]
    }

    public func put(unit: AdminUnit, competition: Int, access: StandAccess, now: Date = Date()) {
        guard access.token != nil else { return }
        var all = load(now: now)
        all[Self.name(unit, competition)] = access
        save(all)
    }

    public func remove(unit: AdminUnit, competition: Int, now: Date = Date()) {
        var all = load(now: now)
        all[Self.name(unit, competition)] = nil
        save(all)
    }

    /// Abmelden: alle Zugänge dieses Kontos vergessen.
    public func clear() {
        store.write(Self.key, nil)
    }
}

extension AdminClient {
    public func competitions() async throws -> [AdminCompetition] {
        let list: Listed<AdminCompetition> = try await api.expect("GET", base + "competitions/")
        return list.rows
    }

    /// Standzugänge eines Wettbewerbs, nur die aktiven.
    public func standAccesses(competition: Int) async throws -> [StandAccess] {
        let list: Listed<StandAccess> = try await api.expect("GET", base + "competitions/\(competition)/stand-access/")
        return list.rows.filter(\.active)
    }

    /// Neuer Standzugang bis zum Ende des Wettbewerbstags; der Schlüssel kommt nur jetzt.
    public func createStandAccess(competition: Int, label: String) async throws -> StandAccess {
        try await api.expect("POST", base + "competitions/\(competition)/stand-access/", json: ["label": String(label.prefix(100))])
    }

    public func endStandAccess(competition: Int, access: Int) async throws {
        let response = try await api.raw("DELETE", base + "competitions/\(competition)/stand-access/\(access)/")
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            throw ApiError(status: response.status, code: fields.code, message: fields.message)
        }
    }
}
