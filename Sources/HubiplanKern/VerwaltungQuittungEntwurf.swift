import Foundation

// Quittungen ohne Netz: Eine unterschriebene Quittung bleibt verschlüsselt auf dem Gerät, bis
// sie auf dem Server abgeschlossen ist und ihre Belegnummer hat. Die zuletzt geladene Auswahl
// (Barkassen, Kategorien, eigene Unterschrift) liegt ebenfalls verschlüsselt dort, damit das
// Blatt auch ohne Verbindung geht. Verhalten wie in der Android-App.

/// Auswahl für Quittungen: Barkassen, Kategorien, hinterlegte Unterschrift des Kassierers.
public struct ReceiptChoices: Codable, Equatable, Sendable {
    public var accounts: [FinanceAccount]
    public var categories: [FinanceCategory]
    public var signature: SignatureShape?

    public init(accounts: [FinanceAccount] = [], categories: [FinanceCategory] = [], signature: SignatureShape? = nil) {
        self.accounts = accounts
        self.categories = categories
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey { case accounts, categories, signature }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([FinanceAccount].self, forKey: .accounts) ?? []
        categories = try c.decodeIfPresent([FinanceCategory].self, forKey: .categories) ?? []
        signature = try c.decodeIfPresent(SignatureShape.self, forKey: .signature)
    }
}

/// Unterschriebene Quittung, die noch nicht abgeschlossen ist.
public struct StoredReceipt: Codable, Equatable, Sendable, Identifiable {
    public var draft: ReceiptDraft
    public var unitId: Int
    public var accountName: String
    public var categoryName: String
    /// Warum der Server die Quittung zuletzt abgelehnt hat
    public var error: String?

    public var id: String { draft.key }

    enum CodingKeys: String, CodingKey {
        case draft, error
        case unitId = "unit_id"
        case accountName = "account_name"
        case categoryName = "category_name"
    }

    /// Aus dem Blatt; nil, solange Angaben oder Unterschriften fehlen.
    public init?(_ draft: ReceiptDraft, unit: AdminUnit, choices: ReceiptChoices) {
        guard draft.formReady, draft.counterpartyReady, draft.treasurerReady(stored: choices.signature != nil) else { return nil }
        self.draft = draft
        unitId = unit.id
        accountName = choices.accounts.first { $0.id == draft.account }?.name ?? ""
        categoryName = choices.categories.first { $0.id == draft.category }?.name ?? ""
        error = nil
    }

    /// Zeile in der Liste „Noch nicht gesendet“.
    public var line: String {
        [tr("Quittung"), Geld.format(draft.parsedAmount), draft.name.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Barkasse und Kategorie neu wählen; beide sind nicht unterschrieben, die Unterschriften
    /// bleiben gültig. Der Fehler ist damit erledigt.
    public func fixed(account: FinanceAccount, category: FinanceCategory) -> StoredReceipt {
        var copy = self
        copy.draft.account = account.id
        copy.accountName = account.name
        copy.draft.category = category.id
        copy.categoryName = category.name
        copy.error = nil
        return copy
    }
}

extension DraftBox {
    static let receiptEnding = ".quittung"

    var receiptNames: [String] { files.names().filter { $0.hasSuffix(DraftBox.receiptEnding) } }

    /// Quittungen, älteste zuerst; `unit`: nur die dieser Einheit.
    public func receipts(unit: Int? = nil) -> [StoredReceipt] {
        receiptNames.compactMap { unseal(StoredReceipt.self, $0) }.filter { unit == nil || $0.unitId == unit }
    }

    /// Quittung sichern (ersetzt eine mit demselben Schlüssel); false, wenn es nicht geklappt hat.
    public func save(_ receipt: StoredReceipt) -> Bool {
        let file = name(receipt.id, ending: DraftBox.receiptEnding)
        guard file != DraftBox.receiptEnding else { return false }
        return seal(receipt, file)
    }

    public func deleteReceipt(_ key: String) {
        files.delete(name(key, ending: DraftBox.receiptEnding))
    }

    private func choicesName(_ unit: Int) -> String { "auswahl-\(unit).dat" }

    /// Zuletzt geladene Auswahl dieser Einheit.
    public func choices(unit: Int) -> ReceiptChoices? {
        unseal(ReceiptChoices.self, choicesName(unit))
    }

    public func saveChoices(_ choices: ReceiptChoices, unit: Int) {
        _ = seal(choices, choicesName(unit))
    }
}

/// Ergebnis von „Quittung abschließen“.
public enum ReceiptOutcome: Equatable, Sendable {
    case finished(CashReceiptItem)
    /// Ohne Verbindung: liegt auf dem Gerät und wird später abgeschlossen
    case kept
}

extension AdminClient {
    /// Auswahl für das Quittungsblatt laden und für später merken. Ohne Verbindung kommt die
    /// gemerkte Auswahl (`offline`); gibt es keine, ist `choices` nil.
    public func receiptChoices(box: DraftBox?) async throws -> (choices: ReceiptChoices?, offline: Bool) {
        do {
            let cash = try await accounts().filter { $0.kind == "cash" }
            let all = try await categories()
            let fresh = ReceiptChoices(accounts: cash, categories: all, signature: try await storedSignature().signature)
            box?.saveChoices(fresh, unit: unit.id)
            return (fresh, false)
        } catch let error as ApiError where error.isOffline {
            return (box?.choices(unit: unit.id), true)
        }
    }

    /// Quittung abschließen: erst dauerhaft sichern, dann senden. Ohne Verbindung bleibt sie auf
    /// dem Gerät (auch mitten im Ablauf: die Kennung auf dem Server ist dann gemerkt, der nächste
    /// Versuch macht dort weiter). Lehnt der Server ab, wird sie wieder entfernt und der Fehler
    /// gemeldet (die Eingaben stehen noch im Blatt; `created` meldet die Kennung dorthin).
    public func submit(_ receipt: StoredReceipt, box: DraftBox, created: (Int) -> Void = { _ in }) async throws -> ReceiptOutcome {
        var current = receipt
        let persisted = box.save(current)
        do {
            let item = try await submitReceipt(current.draft) { id in
                current.draft.serverId = id
                _ = box.save(current)
                created(id)
            }
            box.deleteReceipt(receipt.id)
            return .finished(item)
        } catch let error as ApiError where error.isOffline {
            guard persisted || box.save(current) else { throw error }
            return .kept
        } catch {
            box.deleteReceipt(receipt.id)
            throw error
        }
    }

    /// Liegengebliebene Quittungen dieser Einheit abschließen: fertige löschen, ohne Verbindung
    /// aufhören, bei einer Ablehnung den Fehler merken und weitermachen. 401 (neu freischalten)
    /// wird gemeldet. Gibt die Zahl der abgeschlossenen zurück.
    public func send(receipts box: DraftBox) async throws -> Int {
        var sent = 0
        for receipt in box.receipts(unit: unit.id) {
            var current = receipt
            do {
                _ = try await submitReceipt(current.draft) { id in
                    current.draft.serverId = id
                    _ = box.save(current)
                }
                box.deleteReceipt(receipt.id)
                sent += 1
            } catch let error as ApiError {
                if error.isOffline { break }
                if error.status == 401 { throw error }
                current.error = error.text
                _ = box.save(current)
            }
        }
        return sent
    }
}
