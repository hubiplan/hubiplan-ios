import Foundation

// Buchungen der Kasse ohne Netz: Die Buchung mit Belegfoto bleibt als Entwurf auf dem Gerät,
// bis sie gesendet ist. Das ist die einzige Ausnahme von „keine Verwaltungsdaten auf dem
// Gerät“: Jede Datei ist mit einem Schlüssel aus dem Schlüsselbund verschlüsselt und wird nach
// dem Senden gelöscht. Verhalten wie in der Android-App.

/// Buchung, die noch nicht gesendet ist, mit allem, was zum Senden und Anzeigen nötig ist.
public struct StoredBooking: Codable, Equatable, Sendable, Identifiable {
    /// Zugleich `Idempotency-Key`: erneutes Senden bucht nicht doppelt.
    public var key: String
    public var unitId: Int
    public var unitName: String
    /// `JJJJ-MM-TT`
    public var date: String
    /// "expense" oder "income"
    public var kind: String
    /// Betrag wie „23.40“
    public var amount: String
    public var account: Int
    public var accountName: String
    public var category: Int?
    public var categoryName: String
    public var text: String
    public var counterparty: String
    /// Belegfoto (JPEG)
    public var photo: Data
    /// Warum der Server die Buchung zuletzt abgelehnt hat
    public var error: String?

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, date, kind, amount, account, category, text, counterparty, photo, error
        case unitId = "unit_id"
        case unitName = "unit_name"
        case accountName = "account_name"
        case categoryName = "category_name"
    }

    /// Entwurf aus dem Formular; nil, solange Angaben fehlen (siehe `BookingDraft.fields`).
    public init?(_ draft: BookingDraft, unit: AdminUnit, accounts: [FinanceAccount], categories: [FinanceCategory], jpeg: Data) {
        guard let fields = draft.fields(categories: categories), let account = draft.account, !jpeg.isEmpty else { return nil }
        let value = Dictionary(fields.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        key = draft.key
        unitId = unit.id
        unitName = unit.name
        date = value["date"] ?? ""
        kind = draft.kind
        amount = value["amount"] ?? ""
        self.account = account
        accountName = accounts.first { $0.id == account }?.name ?? ""
        let chosen = value["category"].flatMap { Int($0) }
        category = chosen
        categoryName = categories.first { $0.id == chosen }?.name ?? ""
        text = value["text"] ?? ""
        counterparty = value["counterparty"] ?? ""
        photo = jpeg
        error = nil
    }

    /// Felder der Anfrage, wie `AdminClient.book` sie erwartet.
    public var fields: [(name: String, value: String)] {
        var out: [(name: String, value: String)] = [
            ("date", date), ("kind", kind), ("amount", amount), ("account", String(account)),
        ]
        if let category { out.append(("category", String(category))) }
        out.append(("text", text))
        if !counterparty.isEmpty { out.append(("counterparty", counterparty)) }
        return out
    }

    /// Zeile in der Liste „Noch nicht gesendet“.
    public var line: String {
        [Zeit.plainDate(date), Geld.format(amount), text].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Konto und Kategorie neu wählen (z. B. wenn es das Konto nicht mehr gibt); der Fehler ist damit erledigt.
    public func fixed(account: FinanceAccount, category: FinanceCategory?) -> StoredBooking {
        var copy = self
        copy.account = account.id
        copy.accountName = account.name
        copy.category = category?.id
        copy.categoryName = category?.name ?? ""
        copy.error = nil
        return copy
    }
}

/// Ablage für verschlüsselte Dateien eines Kontos (in der App: ein Ordner im App-Speicher,
/// ohne Sicherung).
public protocol DraftFiles: Sendable {
    /// Dateinamen, älteste zuerst.
    func names() -> [String]
    func read(_ name: String) -> Data?
    func write(_ name: String, _ data: Data) -> Bool
    func delete(_ name: String)
    /// Letzte Änderung der Ablage (in der App: Änderungsdatum des Ordners); nil, wenn unbekannt.
    /// Dient der Quarantäne als Alter, wenn `konto.json` fehlt oder unlesbar ist.
    func lastChange() -> Date?
}

extension DraftFiles {
    public func lastChange() -> Date? { nil }
}

/// Entwürfe eines Kontos. Der Schlüssel liegt im Schlüsselbund (`secrets`), die Dateien liegen
/// verschlüsselt in `files`.
public struct DraftBox: Sendable {
    static let keyName = "entwurfsschluessel"
    static let ending = ".bin"
    let files: DraftFiles
    let secrets: SecretStore

    public init(files: DraftFiles, secrets: SecretStore) {
        self.files = files
        self.secrets = secrets
    }

    /// Schlüssel lesen; `create`: bei Bedarf neu anlegen.
    func key(create: Bool) -> SymmetricKey? {
        if let stored = secrets.read(DraftBox.keyName), let data = Base64Url.decode(stored), data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard create else { return nil }
        let fresh = SymmetricKey(size: .bits256)
        let text = fresh.withUnsafeBytes { Base64Url.encode(Data($0)) }
        secrets.write(DraftBox.keyName, text)
        // Nur verwenden, wenn er wirklich gespeichert ist: sonst wäre der Entwurf später unlesbar
        return secrets.read(DraftBox.keyName) == text ? fresh : nil
    }

    func name(_ key: String, ending: String = DraftBox.ending) -> String {
        String(key.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(64)) + ending
    }

    private var draftNames: [String] { files.names().filter { $0.hasSuffix(DraftBox.ending) } }

    /// Datei entschlüsseln und lesen; nil, wenn sie fehlt oder sich nicht mehr öffnen lässt.
    func unseal<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let key = key(create: false), let sealed = files.read(name),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key)
        else { return nil }
        return try? JSONDecoder().decode(type, from: plain)
    }

    /// Verschlüsselt ablegen; false, wenn es nicht geklappt hat.
    func seal<T: Encodable>(_ value: T, _ name: String) -> Bool {
        guard let key = key(create: true), let plain = try? JSONEncoder().encode(value),
              let sealed = try? AES.GCM.seal(plain, using: key).combined
        else { return false }
        return files.write(name, sealed)
    }

    private func open(_ name: String) -> StoredBooking? { unseal(StoredBooking.self, name) }

    /// Entwürfe, älteste zuerst; `unit`: nur die dieser Einheit.
    public func list(unit: Int? = nil) -> [StoredBooking] {
        draftNames.compactMap(open).filter { unit == nil || $0.unitId == unit }
    }

    /// Entwurf sichern (ersetzt einen mit demselben Schlüssel); false, wenn es nicht geklappt hat.
    public func save(_ draft: StoredBooking) -> Bool {
        let file = name(draft.key)
        guard file != DraftBox.ending else { return false }
        return seal(draft, file)
    }

    public func delete(_ key: String) {
        files.delete(name(key))
    }

    /// Anzahl der Buchungen und Quittungen ohne Entschlüsseln (z. B. als Warnung vor dem Trennen
    /// der Verbindung).
    public var count: Int { draftNames.count + receiptNames.count }

    private var broken: [String] {
        draftNames.filter { open($0) == nil } + receiptNames.filter { unseal(StoredReceipt.self, $0) == nil }
    }

    /// Dateien (Buchungen und Quittungen), die sich nicht mehr lesen lassen. Sie bleiben liegen
    /// und werden gezählt, nie still ausgeblendet.
    public var unreadable: Int { broken.count }

    /// Nur auf ausdrücklichen Wunsch: unlesbare Dateien löschen. Gibt die Anzahl zurück.
    public func discardUnreadable() -> Int {
        let gone = broken
        gone.forEach(files.delete)
        return gone.count
    }

    /// Alles dieses Kontos löschen (Verbindung trennen): Dateien und Schlüssel.
    public func clear() {
        files.names().forEach(files.delete)
        secrets.write(DraftBox.keyName, nil)
    }
}

/// Ergebnis von „Buchen“ aus dem Formular.
public enum BookingOutcome: Equatable, Sendable {
    /// Gebucht; Nummer der Buchung
    case booked(String)
    /// Ohne Verbindung: liegt als Entwurf auf dem Gerät und wird später gesendet
    case kept
}

extension ApiError {
    /// Keine Verbindung zum Server (kein Netz, Zeitüberschreitung).
    public var isOffline: Bool { status == 0 && code == "offline" }
}

extension AdminClient {
    /// Buchen mit Entwurf: erst dauerhaft sichern, dann senden. Bricht die App mitten im
    /// Aufruf ab, geht die Buchung nicht verloren; der `Idempotency-Key` verhindert doppeltes
    /// Buchen beim späteren Senden. Lehnt der Server ab, wird der Entwurf wieder entfernt und
    /// der Fehler gemeldet (die Eingaben stehen noch im Formular).
    public func book(_ draft: StoredBooking, box: DraftBox) async throws -> BookingOutcome {
        let persisted = box.save(draft)
        do {
            let booked = try await book(fields: draft.fields, jpeg: draft.photo, key: draft.key)
            box.delete(draft.key)
            return .booked(booked.displayNumber)
        } catch let error as ApiError where error.isOffline {
            // Ohne gesicherten Entwurf ginge die Buchung verloren: dann den Fehler zeigen
            guard persisted || box.save(draft) else { throw error }
            return .kept
        } catch {
            box.delete(draft.key)
            throw error
        }
    }

    /// Entwürfe dieser Einheit senden: gesendete löschen, ohne Verbindung aufhören, bei einer
    /// Ablehnung den Fehler am Entwurf merken und weitermachen. 401 (neu freischalten) wird
    /// gemeldet. Gibt die Zahl der gesendeten zurück.
    public func send(drafts box: DraftBox) async throws -> Int {
        var sent = 0
        for draft in box.list(unit: unit.id) {
            do {
                _ = try await book(fields: draft.fields, jpeg: draft.photo, key: draft.key)
                box.delete(draft.key)
                sent += 1
            } catch let error as ApiError {
                if error.isOffline { break }
                if error.status == 401 { throw error }
                var failed = draft
                failed.error = error.text
                _ = box.save(failed)
            }
        }
        return sent
    }
}
