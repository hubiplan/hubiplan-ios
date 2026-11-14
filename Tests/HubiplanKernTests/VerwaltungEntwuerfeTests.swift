import XCTest
@testable import HubiplanKern

final class MemoryFiles: DraftFiles, @unchecked Sendable {
    private let lock = NSLock()
    private var order: [String] = []
    private var data: [String: Data] = [:]
    var failWrites = false

    func names() -> [String] { lock.withLock { order } }
    func read(_ name: String) -> Data? { lock.withLock { data[name] } }
    func write(_ name: String, _ value: Data) -> Bool {
        lock.withLock {
            if failWrites { return false }
            if data[name] == nil { order.append(name) }
            data[name] = value
            return true
        }
    }
    func delete(_ name: String) {
        lock.withLock {
            data[name] = nil
            order.removeAll { $0 == name }
        }
    }
}

final class VerwaltungEntwuerfeTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let jpeg = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
    private struct KeinNetz: Error {}
    private let offline: Result<HttpResponse, Error> = .failure(KeinNetz())

    override func setUp() {
        Texte.language = "de"
    }

    private func decode<T: Decodable>(_ text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    private func verwaltung(_ net: FakeTransport, unit: Int = 4) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: AdminUnit(id: unit, name: "Verein"))
    }

    private func entwurf(_ key: String, unit: Int = 4, text: String = "Getränke") throws -> StoredBooking {
        let accounts: [FinanceAccount] = try decode(#"[{"id":2,"name":"Barkasse","kind":"cash"},{"id":3,"name":"Girokonto","kind":"bank"}]"#)
        let categories: [FinanceCategory] = try decode(#"[{"id":5,"name":"Feste","kind":"expense"},{"id":6,"name":"Spenden","kind":"income"}]"#)
        var draft = BookingDraft(key: key)
        draft.amount = "23,40"
        draft.date = "14.11.2026"
        draft.text = " \(text) "
        draft.counterparty = "Getränkemarkt Beispiel"
        draft.account = 2
        draft.category = 5
        return try XCTUnwrap(StoredBooking(draft, unit: AdminUnit(id: unit, name: "Verein"), accounts: accounts, categories: categories, jpeg: jpeg))
    }

    func testEntwurfAusFormular() throws {
        let stored = try entwurf("k-1")
        XCTAssertEqual(stored.date, "2026-11-14")
        XCTAssertEqual(stored.amount, "23.40")
        XCTAssertEqual(stored.accountName, "Barkasse")
        XCTAssertEqual(stored.categoryName, "Feste")
        XCTAssertEqual(stored.text, "Getränke")
        XCTAssertEqual(stored.line, "14.11.2026 · 23,40 € · Getränke")
        XCTAssertEqual(stored.fields.map(\.name), ["date", "kind", "amount", "account", "category", "text", "counterparty"])
        XCTAssertEqual(stored.fields.map(\.value), ["2026-11-14", "expense", "23.40", "2", "5", "Getränke", "Getränkemarkt Beispiel"])
        // Unvollständig oder ohne Foto: kein Entwurf
        var draft = BookingDraft(key: "k-2")
        draft.amount = "1"
        XCTAssertNil(StoredBooking(draft, unit: AdminUnit(id: 4, name: "Verein"), accounts: [], categories: [], jpeg: jpeg))
        draft.date = "14.11.2026"
        draft.text = "x"
        draft.account = 2
        XCTAssertNil(StoredBooking(draft, unit: AdminUnit(id: 4, name: "Verein"), accounts: [], categories: [], jpeg: Data()))
        XCTAssertNotNil(StoredBooking(draft, unit: AdminUnit(id: 4, name: "Verein"), accounts: [], categories: [], jpeg: jpeg))
        // Korrigieren: neues Konto, Fehler erledigt
        var failed = stored
        failed.error = "Das Konto gibt es nicht mehr."
        let accounts: [FinanceAccount] = try decode(#"[{"id":3,"name":"Girokonto","kind":"bank"}]"#)
        let fixed = failed.fixed(account: accounts[0], category: nil)
        XCTAssertEqual(fixed.account, 3)
        XCTAssertEqual(fixed.accountName, "Girokonto")
        XCTAssertNil(fixed.category)
        XCTAssertNil(fixed.error)
        XCTAssertEqual(fixed.fields.map(\.name), ["date", "kind", "amount", "account", "text", "counterparty"])
    }

    func testAblageVerschluesselt() throws {
        let files = MemoryFiles()
        let secrets = MemoryStore()
        let box = DraftBox(files: files, secrets: secrets)
        XCTAssertEqual(box.count, 0)
        XCTAssertEqual(box.list(), [])
        XCTAssertNil(secrets.read("entwurfsschluessel"))
        XCTAssertTrue(box.save(try entwurf("k-1")))
        XCTAssertTrue(box.save(try entwurf("k-2", unit: 9)))
        XCTAssertNotNil(secrets.read("entwurfsschluessel"))
        XCTAssertEqual(files.names(), ["k-1.bin", "k-2.bin"])
        // Auf der Platte steht nichts im Klartext
        let sealed = try XCTUnwrap(files.read("k-1.bin"))
        XCTAssertNil(sealed.range(of: Data("Getränke".utf8)))
        XCTAssertNil(sealed.range(of: Data("unit_id".utf8)))
        XCTAssertEqual(box.list().map(\.key), ["k-1", "k-2"])
        XCTAssertEqual(box.list(unit: 9).map(\.key), ["k-2"])
        XCTAssertEqual(box.list().first?.photo, jpeg)
        // Gleicher Schlüssel ersetzt
        XCTAssertTrue(box.save(try entwurf("k-1", text: "Getränke und Eis")))
        XCTAssertEqual(box.count, 2)
        XCTAssertEqual(box.list(unit: 4).first?.text, "Getränke und Eis")
        // Dateiname nur aus harmlosen Zeichen
        XCTAssertTrue(box.save(try entwurf("../x/y")))
        XCTAssertEqual(files.names().last, "xy.bin")
        XCTAssertFalse(box.save(try entwurf("../")))
        box.delete("../x/y")
        box.delete("k-2")
        XCTAssertEqual(files.names(), ["k-1.bin"])
        // Andere Dateien des Ordners zählen nicht
        XCTAssertTrue(files.write("auswahl-4.dat", Data([1])))
        XCTAssertEqual(box.count, 1)
        box.clear()
        XCTAssertEqual(files.names(), [])
        XCTAssertNil(secrets.read("entwurfsschluessel"))
    }

    func testUnlesbareBleibenLiegen() throws {
        let files = MemoryFiles()
        let secrets = MemoryStore()
        let box = DraftBox(files: files, secrets: secrets)
        XCTAssertTrue(box.save(try entwurf("k-1")))
        XCTAssertTrue(files.write("kaputt.bin", Data([1, 2, 3])))
        XCTAssertEqual(box.count, 2)
        XCTAssertEqual(box.unreadable, 1)
        XCTAssertEqual(box.list().map(\.key), ["k-1"])
        // Schlüssel weg (z. B. Schlüsselbund geleert): nichts mehr lesbar, aber nichts gelöscht
        secrets.write("entwurfsschluessel", nil)
        XCTAssertEqual(box.list(), [])
        XCTAssertEqual(box.unreadable, 2)
        XCTAssertEqual(files.names().count, 2)
        XCTAssertEqual(box.discardUnreadable(), 2)
        XCTAssertEqual(box.count, 0)
        // Speichern scheitert: kein Erfolg melden
        files.failWrites = true
        XCTAssertFalse(box.save(try entwurf("k-3")))
    }

    func testBuchenMitEntwurf() async throws {
        let files = MemoryFiles()
        let box = DraftBox(files: files, secrets: MemoryStore())
        let net = FakeTransport([
            FakeTransport.json(201, #"{"id":10,"display_number":"2026-0032","kind":"expense","amount":"23.40"}"#),
            offline,
            FakeTransport.json(400, #"{"detail":"Das Buchungsjahr ist abgeschlossen."}"#),
        ])
        let client = verwaltung(net)
        let booked = try await client.book(try entwurf("k-1"), box: box)
        XCTAssertEqual(booked, .booked("2026-0032"))
        XCTAssertEqual(box.count, 0)
        XCTAssertEqual(net.seen[0].headers["Idempotency-Key"], "k-1")
        // Ohne Verbindung: bleibt als Entwurf
        let kept = try await client.book(try entwurf("k-2"), box: box)
        XCTAssertEqual(kept, .kept)
        XCTAssertEqual(box.list().map(\.key), ["k-2"])
        // Abgelehnt: Entwurf wieder weg, Fehler gemeldet
        do {
            _ = try await client.book(try entwurf("k-3"), box: box)
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.message, "Das Buchungsjahr ist abgeschlossen.")
        }
        XCTAssertEqual(box.list().map(\.key), ["k-2"])
        // Ohne Verbindung und der Entwurf lässt sich nicht sichern: Fehler statt stillem Verlust
        files.failWrites = true
        let lost = FakeTransport([offline])
        do {
            _ = try await verwaltung(lost).book(try entwurf("k-4"), box: box)
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertTrue(error.isOffline)
        }
    }

    func testEntwuerfeSenden() async throws {
        let box = DraftBox(files: MemoryFiles(), secrets: MemoryStore())
        for key in ["k-1", "k-2", "k-3", "k-4"] { XCTAssertTrue(box.save(try entwurf(key))) }
        XCTAssertTrue(box.save(try entwurf("k-9", unit: 9)))
        let net = FakeTransport([
            FakeTransport.json(201, #"{"id":10,"display_number":"2026-0032"}"#),
            FakeTransport.json(400, #"{"detail":"Das Konto gibt es nicht mehr."}"#),
            FakeTransport.json(201, #"{"id":11,"display_number":"2026-0033"}"#),
            offline,
        ])
        let sent = try await verwaltung(net).send(drafts: box)
        XCTAssertEqual(sent, 2)
        XCTAssertEqual(net.seen.map { $0.headers["Idempotency-Key"] }, ["k-1", "k-2", "k-3", "k-4"])
        // Abgelehnter behält seinen Fehler, der ohne Verbindung bleibt unverändert, fremde Einheit unberührt
        let rest = box.list()
        XCTAssertEqual(rest.map(\.key), ["k-2", "k-4", "k-9"])
        XCTAssertEqual(rest.map(\.error), ["Das Konto gibt es nicht mehr.", nil, nil])
        // Neu freischalten nötig: melden, Entwürfe bleiben
        let locked = FakeTransport([FakeTransport.json(401, #"{"detail":"Bitte neu freischalten."}"#)])
        do {
            _ = try await verwaltung(locked).send(drafts: box)
            XCTFail("401 erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 401)
        }
        XCTAssertEqual(box.count, 3)
        XCTAssertEqual(box.list(unit: 4).first?.error, "Das Konto gibt es nicht mehr.")
    }
}
