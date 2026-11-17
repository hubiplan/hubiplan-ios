import Foundation

// Beitragsnachweise im Mitgliederbereich (`/api/portal/<Zugang>/fee-proofs/`), Beschreibung in
// hubiplan/docs/beitragsnachweise.md. Verhalten wie in der Android-App (Ich › Beitragsnachweise):
// Stand und Frist je Beitragsjahr sehen, Nachweis als Foto oder PDF einreichen. Nichts davon
// wird auf dem Gerät gespeichert.

/// Höchstgröße einer Datei wie auf dem Server (10 MB).
public let feeProofMaxBytes = 10 * 1024 * 1024

public struct FeeProof: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var discountName: String
    public var year: Int
    public var yearLabel: String
    public var kind: String
    /// received, question, accepted, rejected
    public var status: String
    public var receivedOn: String?
    public var validUntil: String?
    public var fileName: String
    public var note: String

    enum CodingKeys: String, CodingKey {
        case id, year, kind, status, note
        case discountName = "discount_name"
        case yearLabel = "year_label"
        case receivedOn = "received_on"
        case validUntil = "valid_until"
        case fileName = "file_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        discountName = try c.decodeIfPresent(String.self, forKey: .discountName) ?? ""
        year = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
        yearLabel = try c.decodeIfPresent(String.self, forKey: .yearLabel) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "received"
        receivedOn = try c.decodeIfPresent(String.self, forKey: .receivedOn)
        validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    public var statusLabel: String {
        switch status {
        case "accepted": return tr("anerkannt")
        case "rejected": return tr("abgelehnt")
        case "question": return tr("Rückfrage")
        default: return tr("eingegangen")
        }
    }
}

public struct FeeYearState: Decodable, Equatable, Identifiable, Sendable {
    public var discount: Int
    public var discountName: String
    public var kinds: [String]
    public var year: Int
    public var yearLabel: String
    public var due: String
    public var final: String
    /// accepted, pending, question, open, missing
    public var state: String
    public var applies: Bool
    public var proof: FeeProof?

    public var id: String { "\(discount)-\(year)" }

    enum CodingKeys: String, CodingKey {
        case discount, kinds, year, due, final, state, applies, proof
        case discountName = "discount_name"
        case yearLabel = "year_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        discount = try c.decode(Int.self, forKey: .discount)
        discountName = try c.decodeIfPresent(String.self, forKey: .discountName) ?? ""
        kinds = try c.decodeIfPresent([String].self, forKey: .kinds) ?? []
        year = try c.decode(Int.self, forKey: .year)
        yearLabel = try c.decodeIfPresent(String.self, forKey: .yearLabel) ?? ""
        due = try c.decodeIfPresent(String.self, forKey: .due) ?? ""
        final = try c.decodeIfPresent(String.self, forKey: .final) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "open"
        applies = try c.decodeIfPresent(Bool.self, forKey: .applies) ?? false
        proof = try c.decodeIfPresent(FeeProof.self, forKey: .proof)
    }

    /// Hier lässt sich (noch) etwas einreichen.
    public var canSubmit: Bool { state != "accepted" }

    /// Braucht das Mitglied etwas zu tun?
    public var needsMe: Bool { ["open", "question", "missing"].contains(state) }

    public var label: String {
        switch state {
        case "accepted": return tr("Nachweis anerkannt")
        case "pending": return tr("Nachweis wird geprüft")
        case "question": return tr("Rückfrage")
        case "missing": return tr("Kein Nachweis, normaler Beitrag")
        default: return tr("Nachweis fehlt noch")
        }
    }

    /// Stand in einem Satz (wie im Mitgliederbereich im Browser und in der Android-App).
    public var sentence: String {
        switch state {
        case "accepted":
            if let until = proof?.validUntil { return tr("Anerkannt, gültig bis {day}.", ["day": Zeit.plainDate(until)]) }
            return tr("Anerkannt.")
        case "pending":
            return tr("Eingegangen, der Vorstand prüft ihn noch. Bis dahin gilt die Ermäßigung.")
        case "question":
            if let note = proof?.note, !note.isEmpty { return tr("Rückfrage des Vorstands: {note}", ["note": note]) }
            return tr("Der Vorstand hat eine Rückfrage.")
        case "missing":
            return tr("Bis {day} ist kein Nachweis eingegangen; für dieses Jahr gilt der normale Beitrag.", ["day": Zeit.plainDate(final)])
        default:
            if final != due {
                return tr("Bitte bis {due} einreichen (spätestens {final}).", ["due": Zeit.plainDate(due), "final": Zeit.plainDate(final)])
            }
            return tr("Bitte bis {due} einreichen.", ["due": Zeit.plainDate(due)])
        }
    }
}

public struct FeeProofOverview: Decodable, Equatable, Sendable {
    public var states: [FeeYearState]
    public var proofs: [FeeProof]

    public init(states: [FeeYearState] = [], proofs: [FeeProof] = []) {
        self.states = states
        self.proofs = proofs
    }

    enum CodingKeys: String, CodingKey { case states, proofs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        states = try c.decodeIfPresent([FeeYearState].self, forKey: .states) ?? []
        proofs = try c.decodeIfPresent([FeeProof].self, forKey: .proofs) ?? []
    }
}

/// Kurzstand neben „Beitragsnachweise“ unter „Ich“.
public func feeProofSummary(due: Int) -> String {
    due > 0 ? trn("1 Nachweis fehlt", "{n} Nachweise fehlen", due) : tr("Nachweis für den ermäßigten Beitrag")
}

/// Felder zum Einreichen (ohne Datei).
public func feeProofFields(discount: Int, year: Int, kind: String, note: String) -> [(name: String, value: String)] {
    [("discount", String(discount)), ("year", String(year)), ("kind", kind), ("note", note)]
}

extension Api {
    public func memberFeeProofs(accessId: Int) async throws -> FeeProofOverview {
        try await expect("GET", "/api/portal/\(accessId)/fee-proofs/")
    }

    /// Nachweis (PDF oder Foto) für eine Ermäßigung und ein Beitragsjahr einreichen.
    public func submitFeeProof(accessId: Int, discount: Int, year: Int, kind: String, note: String,
                               fileName: String, type: String, data: Data) async throws -> FeeProofOverview {
        let form = Multipart(fields: feeProofFields(discount: discount, year: year, kind: kind, note: note),
                             file: data, fileName: fileName, fileType: type)
        let response = try await raw("POST", "/api/portal/\(accessId)/fee-proofs/", form: form)
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            let message = fields.message.isEmpty ? fieldMessages(response.body) : fields.message
            throw ApiError(status: response.status, code: fields.code, message: message)
        }
        do {
            return try JSONDecoder().decode(FeeProofOverview.self, from: response.body)
        } catch {
            throw ApiError(status: response.status, code: "format")
        }
    }
}

extension PortalAccess {
    /// Bereich „Beitragsnachweise“ unter „Ich“ (Ermäßigung mit Nachweis; für Ansprechpartner
    /// von Firmen meldet der Server ihn nie an).
    public var hasFeeProofs: Bool { feeProofsEnabled }
}
