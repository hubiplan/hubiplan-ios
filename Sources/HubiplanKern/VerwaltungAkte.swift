import Foundation

// Weitere Teile der Mitgliedsakte: Ehrungen und Würden, Zusatzfelder, Bankverbindung
// (SEPA-Mandat). Verhalten wie in der Android-App.

// MARK: Ehrungen und Würden

public struct AwardItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: Int
    public var titleName: String
    public var validFrom: String
    public var validUntil: String?
    public var note: String

    enum CodingKeys: String, CodingKey {
        case id, title, note
        case titleName = "title_name"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(Int.self, forKey: .title) ?? 0
        titleName = try c.decodeIfPresent(String.self, forKey: .titleName) ?? ""
        validFrom = try c.decodeIfPresent(String.self, forKey: .validFrom) ?? ""
        validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil).flatMap { $0.isEmpty ? nil : $0 }
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    /// Läuft noch (lässt sich beenden).
    public var running: Bool { validUntil == nil }

    public var period: String {
        if let validUntil {
            return tr("vom {von} bis {bis}", ["von": Zeit.plainDate(validFrom), "bis": Zeit.plainDate(validUntil)])
        }
        return tr("seit {von}", ["von": Zeit.plainDate(validFrom)])
    }
}

/// Ehrung oder Würde, die die Einheit vergeben kann.
public struct HonoraryTitle: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isArchived = "is_archived"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

// MARK: Zusatzfelder

public struct FieldDef: Decodable, Equatable, Sendable {
    public var id: Int
    public var label: String
    /// "text", "date", "bool", "number", "choice"
    public var fieldType: String
    public var choices: [String]
    public var repeatable: Bool
    public var helpText: String

    enum CodingKeys: String, CodingKey {
        case id, label, choices, repeatable
        case fieldType = "field_type"
        case helpText = "help_text"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        fieldType = try c.decodeIfPresent(String.self, forKey: .fieldType) ?? "text"
        choices = try c.decodeIfPresent([String].self, forKey: .choices) ?? []
        repeatable = try c.decodeIfPresent(Bool.self, forKey: .repeatable) ?? false
        helpText = try c.decodeIfPresent(String.self, forKey: .helpText) ?? ""
    }
}

/// Zusatzfeld eines Mitglieds mit seinem Wert als Eingabetext: Datum als `TT.MM.JJJJ`,
/// Ja/Nein als "ja", "nein" oder "" (nicht angegeben), Zahl mit Komma.
public struct FieldEntry: Decodable, Equatable, Sendable, Identifiable {
    public var definition: FieldDef
    public var text: String

    public var id: Int { definition.id }

    enum CodingKeys: String, CodingKey { case definition, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        definition = try c.decode(FieldDef.self, forKey: .definition)
        var raw = ""
        // Mehrfachfelder tragen eine Liste; die zeigt und ändert nur der Browser
        if definition.repeatable || !c.contains(.value) || (try? c.decodeNil(forKey: .value)) == true {
            raw = ""
        } else if definition.fieldType == "bool" {
            if let value = try? c.decode(Bool.self, forKey: .value) { raw = value ? "ja" : "nein" }
        } else if let value = try? c.decode(String.self, forKey: .value) {
            raw = value
        } else if let value = try? c.decode(Int.self, forKey: .value) {
            raw = String(value)
        } else if let value = try? c.decode(Double.self, forKey: .value) {
            raw = String(value)
        }
        switch definition.fieldType {
        case "date": text = Zeit.plainDate(raw)
        case "number": text = raw.replacingOccurrences(of: ".", with: ",")
        default: text = raw
        }
    }

    /// Anzeige in der Akte.
    public var shown: String {
        if definition.repeatable { return tr("(mehrere Einträge, im Browser)") }
        if definition.fieldType == "bool" { return text == "ja" ? tr("ja") : text == "nein" ? tr("nein") : "–" }
        return text.isEmpty ? "–" : text
    }
}

public enum MemberFields {
    /// Ausgangswerte für das Blatt (ohne Mehrfachfelder).
    public static func input(_ entries: [FieldEntry]) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: entries.filter { !$0.definition.repeatable }.map { ($0.id, $0.text) })
    }

    /// Geänderte Felder für die Anfrage (`values`): Datum als `JJJJ-MM-TT`, Ja/Nein als
    /// Wahrheitswert, leer löscht. Bei einer ungültigen Eingabe steht der Fehlertext in `error`.
    public static func changes(_ entries: [FieldEntry], input: [Int: String]) -> (values: [String: Any], error: String?) {
        var out: [String: Any] = [:]
        for entry in entries where !entry.definition.repeatable {
            let def = entry.definition
            guard let typed = input[def.id] else { continue }
            let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if text == entry.text.trimmingCharacters(in: .whitespacesAndNewlines) { continue }
            let key = String(def.id)
            if text.isEmpty {
                out[key] = NSNull()
            } else if def.fieldType == "date" {
                guard let iso = MasterData.parseDate(text) else {
                    return (out, tr("{label}: bitte als TT.MM.JJJJ eingeben.", ["label": def.label]))
                }
                out[key] = iso
            } else if def.fieldType == "bool" {
                guard text == "ja" || text == "nein" else {
                    return (out, tr("{label}: bitte ja, nein oder – wählen.", ["label": def.label]))
                }
                out[key] = text == "ja"
            } else if def.fieldType == "number" {
                out[key] = text.replacingOccurrences(of: ",", with: ".")
            } else {
                out[key] = text
            }
        }
        return (out, nil)
    }
}

// MARK: Bankverbindung

public struct MandateItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var reference: String
    public var holder: String
    /// Ganze IBAN; nur in der Antwort mit `full`
    public var iban: String?
    public var ibanMasked: String
    public var signedOn: String?
    public var status: String

    enum CodingKeys: String, CodingKey {
        case id, reference, holder, iban, status
        case ibanMasked = "iban_masked"
        case signedOn = "signed_on"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        reference = try c.decodeIfPresent(String.self, forKey: .reference) ?? ""
        holder = try c.decodeIfPresent(String.self, forKey: .holder) ?? ""
        iban = try c.decodeIfPresent(String.self, forKey: .iban).flatMap { $0.isEmpty ? nil : $0 }
        ibanMasked = try c.decodeIfPresent(String.self, forKey: .ibanMasked) ?? ""
        signedOn = try c.decodeIfPresent(String.self, forKey: .signedOn)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
    }

    public var isActive: Bool { status == "active" }

    /// Kontoinhaber mit IBAN: ganz, wenn sie geladen ist, sonst verdeckt.
    public var line: String {
        "\(holder): \(iban.map(Iban.grouped) ?? ibanMasked)"
    }

    public var detail: String {
        tr("Mandat {nummer}, unterschrieben {datum}", ["nummer": reference, "datum": Zeit.plainDate(signedOn)])
    }
}

public enum Iban {
    public static func compact(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.uppercased()
    }

    /// IBAN in Vierergruppen.
    public static func grouped(_ text: String) -> String {
        let plain = Array(compact(text))
        return stride(from: 0, to: plain.count, by: 4).map { String(plain[$0..<min($0 + 4, plain.count)]) }.joined(separator: " ")
    }
}

/// Neues SEPA-Mandat auf Papier; `signed` als `JJJJ-MM-TT`.
public struct MandateDraft: Equatable, Sendable {
    public var holder: String
    public var iban = ""
    public var bic = ""
    public var signed: String

    public init(holder: String, signed: String) {
        self.holder = holder
        self.signed = signed
    }

    /// Was fehlt; nil, wenn die Angaben reichen (die IBAN prüft der Server).
    public var error: String? {
        if holder.trimmingCharacters(in: .whitespaces).isEmpty { return tr("Bitte den Kontoinhaber angeben.") }
        if Iban.compact(iban).count < 15 { return tr("Bitte eine vollständige IBAN angeben.") }
        return nil
    }

    func body(member: Int) -> [String: Any] {
        [
            "membership": member,
            "holder": String(holder.trimmingCharacters(in: .whitespaces).prefix(70)),
            "iban": String(Iban.compact(iban).prefix(34)),
            "bic": String(Iban.compact(bic).prefix(11)),
            "signed_on": signed,
        ]
    }
}

extension AdminUnit {
    /// Bankverbindung in der Akte sehen bzw. ein neues Mandat eintragen.
    public var showsBank: Bool { !isDepartment && permissions.contains("billing.view") }
    public var canEditBank: Bool { !isDepartment && permissions.contains("billing.edit") }
}

extension AdminClient {
    public func awards(member id: Int) async throws -> [AwardItem] {
        try await api.expect("GET", base + "members/\(id)/honorary-titles/")
    }

    /// Ehrungen und Würden zur Auswahl, ohne archivierte.
    public func honoraryTitles() async throws -> [HonoraryTitle] {
        let list: [HonoraryTitle] = try await api.expect("GET", base + "honorary-titles/")
        return list.filter { !$0.isArchived }
    }

    /// `from` als `JJJJ-MM-TT`.
    public func addAward(member id: Int, title: Int, from: String, note: String) async throws -> AdminChange {
        let short = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return try await change("POST", "members/\(id)/honorary-titles/", ["title": title, "valid_from": from, "note": short])
    }

    public func endAward(member id: Int, award: Int, until: String) async throws -> AdminChange {
        try await change("PATCH", "members/\(id)/honorary-titles/\(award)/", ["valid_until": until])
    }

    /// Zusatzfelder des Mitglieds. Gibt es sie in der Einheit nicht (403, 404), ist die Liste leer.
    public func fields(member id: Int) async throws -> [FieldEntry] {
        do {
            return try await api.expect("GET", base + "members/\(id)/fields/")
        } catch let error as ApiError where error.status == 403 || error.status == 404 {
            return []
        }
    }

    /// `values` aus `MemberFields.changes`.
    public func saveFields(member id: Int, values: [String: Any]) async throws -> AdminChange {
        try await change("PUT", "members/\(id)/fields/", ["values": values])
    }

    /// SEPA-Mandate des Mitglieds; `full`: mit ganzer IBAN (in der App erst nach der
    /// Gerätesperre). Ist SEPA in der Einheit ausgeschaltet (404), ist die Liste leer.
    public func mandates(member id: Int, full: Bool = false) async throws -> [MandateItem] {
        do {
            return try await api.expect("GET", base + "billing/mandates/?mitglied=\(id)" + (full ? "&voll=1" : ""))
        } catch let error as ApiError where error.status == 404 {
            return []
        }
    }

    /// Was ein neues Mandat bewirkt; ändert nichts.
    public func previewBank(member id: Int) async throws -> MemberPreview {
        try await api.expect("POST", base + "members/\(id)/preview/", json: ["action": "bank"])
    }

    public func addMandate(member id: Int, _ draft: MandateDraft) async throws -> AdminChange {
        try await change("POST", "billing/mandates/", draft.body(member: id))
    }
}
