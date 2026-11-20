import Foundation

// Pinnwand im Mitgliederbereich (`/api/portal/<Zugang>/pinboard/`), Beschreibung in
// hubiplan/docs/app.md. Verhalten wie in der Android-App (Ich › Pinnwand): kurze Beiträge des
// Vereins und der eigenen Untereinheiten, kein Chat. Wer in HUBIplan schreiben darf, bekommt
// `targets`. Nichts davon wird auf dem Gerät gespeichert.

public struct PinPhoto: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var url: String
    public var width: Int
    public var height: Int

    enum CodingKeys: String, CodingKey { case id, url, width, height }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
    }
}

public struct PinTarget: Decodable, Equatable, Sendable {
    /// leer: der Verein selbst
    public var department: Int?
    public var name: String

    enum CodingKeys: String, CodingKey { case department, name }

    public init(department: Int?, name: String) {
        self.department = department
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        department = try c.decodeIfPresent(Int.self, forKey: .department)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

public struct PinNotice: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var text: String
    public var unit: String
    public var from: String
    public var author: String
    public var pinned: Bool
    public var visibleUntil: String?
    public var createdAt: String?
    public var editedAt: String?
    public var pushed: Bool
    public var version: Int
    public var canEdit: Bool
    public var photos: [PinPhoto]
    /// Seit dem letzten Lesen neu
    public var isNew: Bool

    enum CodingKeys: String, CodingKey {
        case id, text, unit, from, author, pinned, pushed, version, photos
        case visibleUntil = "visible_until"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case canEdit = "can_edit"
        case isNew = "new"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        visibleUntil = try c.decodeIfPresent(String.self, forKey: .visibleUntil)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        editedAt = try c.decodeIfPresent(String.self, forKey: .editedAt)
        pushed = try c.decodeIfPresent(Bool.self, forKey: .pushed) ?? false
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        photos = try c.decodeIfPresent([PinPhoto].self, forKey: .photos) ?? []
        isNew = try c.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
    }

    /// Zweite Zeile: wer, geändert, bis wann (Zeitpunkt setzt die Oberfläche davor).
    public var line: String {
        var parts: [String] = []
        if !author.isEmpty { parts.append(author) }
        if editedAt != nil { parts.append(tr("geändert")) }
        if let until = visibleUntil { parts.append(tr("sichtbar bis {day}", ["day": Zeit.plainDate(until)])) }
        return parts.joined(separator: " · ")
    }
}

public struct PinboardList: Decodable, Equatable, Sendable {
    public var notices: [PinNotice]
    public var targets: [PinTarget]
    public var maxPhotos: Int
    public var maxText: Int

    enum CodingKeys: String, CodingKey {
        case notices, targets
        case maxPhotos = "max_photos"
        case maxText = "max_text"
    }

    public init(notices: [PinNotice] = [], targets: [PinTarget] = []) {
        self.notices = notices
        self.targets = targets
        maxPhotos = 6
        maxText = 2000
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notices = try c.decodeIfPresent([PinNotice].self, forKey: .notices) ?? []
        targets = try c.decodeIfPresent([PinTarget].self, forKey: .targets) ?? []
        maxPhotos = try c.decodeIfPresent(Int.self, forKey: .maxPhotos) ?? 6
        maxText = try c.decodeIfPresent(Int.self, forKey: .maxText) ?? 2000
    }

    /// Beiträge seit dem letzten Lesen
    public var newCount: Int { notices.filter(\.isNew).count }

    /// Darf dieses Konto schreiben (Verein oder eine Untereinheit)?
    public var canWrite: Bool { !targets.isEmpty }

    /// Kurzstand neben „Pinnwand“ unter „Ich“.
    public var summary: String {
        if newCount > 0 { return trn("1 neuer Beitrag", "{n} neue Beiträge", newCount) }
        if notices.isEmpty { return tr("Noch keine Beiträge") }
        return tr("Kurze Neuigkeiten aus dem Verein")
    }
}

/// Felder eines neuen Beitrags für das Formular (Fotos gehen als „photos“ mit).
public func pinNoticeFields(text: String, department: Int?, pinned: Bool, push: Bool) -> [(name: String, value: String)] {
    var fields: [(name: String, value: String)] = [("text", text.trimmingCharacters(in: .whitespacesAndNewlines))]
    if let department { fields.append(("department", String(department))) }
    fields.append(("pinned", pinned ? "1" : "0"))
    fields.append(("push", push ? "1" : "0"))
    return fields
}

extension PortalAccess {
    /// „Pinnwand“ unter „Ich“ (ältere Server ohne Pinnwand: aus)
    public var hasPinboard: Bool { pinboardEnabled }
}

extension Api {
    /// Beiträge; `seen: false` lässt den Zähler „neu“ stehen (Kurzstand unter „Ich“).
    public func memberPinboard(accessId: Int, seen: Bool = true) async throws -> PinboardList {
        try await expect("GET", "/api/portal/\(accessId)/pinboard/" + (seen ? "" : "?seen=0"))
    }

    /// Neuer Beitrag mit Fotos in einem Schritt; `key` schützt vor doppeltem Anlegen.
    public func createPinNotice(
        accessId: Int, text: String, department: Int?, pinned: Bool, push: Bool, photos: [Data], key: String
    ) async throws -> PinNotice {
        let files = photos.enumerated().map { (name: "foto-\($0.offset + 1).jpg", data: $0.element, type: "image/jpeg") }
        let form = Multipart(
            fields: pinNoticeFields(text: text, department: department, pinned: pinned, push: push),
            files: files, fileField: "photos"
        )
        let response = try await raw("POST", "/api/portal/\(accessId)/pinboard/", form: form, extra: [SignedFormat.idempotencyHeader: key])
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            let message = fields.message.isEmpty ? fieldMessages(response.body) : fields.message
            throw ApiError(status: response.status, code: fields.code, message: message)
        }
        do {
            return try JSONDecoder().decode(PinNotice.self, from: response.body)
        } catch {
            throw ApiError(status: response.status, code: "format")
        }
    }

    public func pinPinNotice(accessId: Int, notice: PinNotice, pinned: Bool) async throws -> PinNotice {
        try await expect("PATCH", "/api/portal/\(accessId)/pinboard/\(notice.id)/", json: ["pinned": pinned, "version": notice.version])
    }

    public func deletePinNotice(accessId: Int, id: Int) async throws {
        let _: Ignored = try await expect("DELETE", "/api/portal/\(accessId)/pinboard/\(id)/")
    }
}
