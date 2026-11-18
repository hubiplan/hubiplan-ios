import Foundation

// Neues Mitglied aufnehmen (Person oder Organisation). Vor der Aufnahme sucht die App nach
// möglichen Dubletten, wie in der Android-App.

/// Mögliche Dublette: Person oder Organisation, die es in HUBIplan schon gibt.
public struct DuplicateItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var lastName: String
    public var firstName: String
    public var birthDate: String?
    public var alreadyMemberHere: Bool
    public var kind: String

    enum CodingKeys: String, CodingKey {
        case id, kind
        case lastName = "last_name"
        case firstName = "first_name"
        case birthDate = "birth_date"
        case alreadyMemberHere = "already_member_here"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate).flatMap { $0.isEmpty ? nil : $0 }
        alreadyMemberHere = try c.decodeIfPresent(Bool.self, forKey: .alreadyMemberHere) ?? false
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "person"
    }

    public var isOrganization: Bool { kind == "organization" }

    public var name: String {
        isOrganization ? lastName : [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public var detail: String {
        let first = isOrganization ? tr("Organisation") : birthDate.map { Zeit.plainDate($0) } ?? tr("ohne Geburtsdatum")
        return alreadyMemberHere ? first + " · " + tr("schon Mitglied hier") : first
    }
}

/// Formular „Neues Mitglied“. Texte wie eingegeben; `entry` als `JJJJ-MM-TT`.
public struct AdmitDraft: Equatable, Sendable {
    public var organization = false
    public var firstName = ""
    public var lastName = ""
    /// `TT.MM.JJJJ`, freiwillig
    public var birthDate = ""
    public var gender = ""
    public var title = ""
    public var nameSuffix = ""
    public var email = ""
    public var phone = ""
    public var street = ""
    public var postalCode = ""
    public var city = ""
    public var type: Int?
    public var department: Int?
    public var entry: String

    public init(entry: String) {
        self.entry = entry
    }

    private func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Etwas eingetragen, das beim Abbrechen verloren ginge (UX-Audit 16.11., IOS-09). Art,
    /// Untereinheit und Eintritt setzt das Blatt selbst vor; sie zählen nicht.
    public var hasInput: Bool {
        [firstName, lastName, birthDate, gender, title, nameSuffix, email, phone, street, postalCode, city]
            .contains { !clean($0).isEmpty }
    }

    var birthIso: String? { clean(birthDate).isEmpty ? nil : MasterData.parseDate(birthDate) }

    /// Was fehlt; nil, wenn das Formular abgeschickt werden kann.
    public var error: String? {
        if organization, clean(lastName).isEmpty { return tr("Bitte den Namen der Organisation angeben.") }
        if !organization, clean(firstName).isEmpty || clean(lastName).isEmpty { return tr("Bitte Vor- und Nachname angeben.") }
        if !organization, !clean(birthDate).isEmpty, birthIso == nil { return tr("Bitte das Geburtsdatum als TT.MM.JJJJ eingeben.") }
        if [street, postalCode, city].contains(where: { clean($0).isEmpty }) { return tr("Bitte die vollständige Anschrift angeben.") }
        if type == nil { return tr("Bitte eine Mitgliedsart wählen.") }
        if MasterData.parseDate(entry) == nil { return tr("Bitte das Eintrittsdatum angeben.") }
        return nil
    }

    /// Inhalt der Aufnahme. `person`: gefundene Person oder Organisation, die Mitglied wird.
    /// Name und Geburtsdatum gehen immer mit; damit prüft der Server den Treffer.
    public func body(person: Int?) -> [String: Any]? {
        guard error == nil, let type else { return nil }
        var out: [String: Any] = [
            "member_type": type, "entry_date": entry, "last_name": clean(lastName),
            "email": clean(email), "phone": clean(phone), "street": clean(street),
            "postal_code": clean(postalCode), "city": clean(city),
        ]
        if organization {
            out["kind"] = "organization"
            out["name_suffix"] = clean(nameSuffix)
        } else {
            out["first_name"] = clean(firstName)
            out["birth_date"] = birthIso.map { $0 as Any } ?? NSNull()
            out["title"] = clean(title)
            if person == nil { out["gender"] = gender }
        }
        if let person { out["person"] = person }
        if let department { out["department_ids"] = [department] }
        return out
    }
}

extension AdminUnit {
    /// Neue Mitglieder aufnehmen: nur in der Einheit mit „Mitglieder bearbeiten“.
    public var canAdmitMembers: Bool { canManageMembers }
}

extension AdminClient {
    /// Mögliche Dubletten zum Formular: bei Personen gleicher Name und Geburtstag (ohne
    /// Geburtsdatum nur eigene Mitglieder), bei Organisationen gleicher Name.
    public func duplicates(_ draft: AdmitDraft) async throws -> [DuplicateItem] {
        let name = queryValue(draft.lastName.trimmingCharacters(in: .whitespacesAndNewlines))
        if draft.organization {
            return try await api.expect("GET", base + "members/duplicates/?typ=organisation&name=\(name)")
        }
        let first = queryValue(draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await api.expect("GET", base + "members/duplicates/?name=\(name)&vorname=\(first)&geburtsdatum=\(draft.birthIso ?? "")")
    }

    /// Mitglied aufnehmen; `key` schützt vor doppelter Aufnahme bei erneutem Senden.
    public func admit(body: [String: Any], key: String) async throws -> MemberDetail {
        let response = try await api.raw("POST", base + "members/admit/", json: body, extra: [SignedFormat.idempotencyHeader: key])
        return try decoded(response)
    }
}
