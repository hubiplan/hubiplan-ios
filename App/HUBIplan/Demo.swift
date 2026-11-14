import Foundation
import HubiplanKern
import UIKit

/// Vorführmodus für Bildschirmfotos und Prüfungen im Simulator: Start mit `-demo 1`.
/// Die App spricht dann mit keinem Server; alle Daten sind erfunden (Demoverein).
enum Demo {
    static var active: Bool { UserDefaults.standard.bool(forKey: "demo") }
    /// Reiter, der beim Start offen sein soll (`-reiter mitteilungen`, `aufgaben`, `noten`, `ausweis`, `konto`).
    static var tab: String { UserDefaults.standard.string(forKey: "reiter") ?? "termine" }

    /// Abschnitt im Reiter „Ich“, zu dem die Ansicht springt (`-abschnitt rechnungen`, `versammlungen`, `dokumente`, `verwaltung`, `freischalten`, `offen`, `meldungen`, `mitglieder`, `mitglied`, `stammdaten`, `austritt`, `folgen`, `akte`, `ehrung`, `zusatzfelder`, `bank`, `aufnahme`, `dubletten`, `anlaesse`, `ausweispruefung`, `vtermine`, `vtermin`, `neuertermin`, `kasse`, `buchung`, `neuebuchung`, `quittung`, `entwuerfe`, `vrechnungen`, `vrechnung`, `vaufgaben`, `vaufgabe`, `neueaufgabe`, `partner`, `qualifikationen`, `fristen`, `frist`, `wettbewerbe`, `standcode`), im Reiter „Aufgaben“ die Helferdienste (`-abschnitt helfer`).
    static var section: String { UserDefaults.standard.string(forKey: "abschnitt") ?? "" }
    /// Abschnitte, die eine Mitgliedsakte öffnen, und solche für „Neues Mitglied“
    static let akteAbschnitte = ["mitglied", "stammdaten", "austritt", "folgen", "akte", "ehrung", "zusatzfelder", "bank"]
    static let aufnahmeAbschnitte = ["aufnahme", "dubletten"]
    /// Ablage für Buchungsentwürfe im Vorführmodus (nur im Speicher)
    static let box = DraftBox(files: DemoDateien(), secrets: DemoStore())

    /// Zwei erfundene Konten: der Verein und die Kapelle mit eigener Instanz.
    static let accounts = AccountList(accounts: [
        AccountEntry(id: "", server: "https://verein.example.de", display: "Erika Musterfrau", email: "erika@example.org"),
        AccountEntry(id: "kapelle", server: "https://kapelle.example.org", display: "Erika Musterfrau", email: "erika@example.org"),
    ])
}

/// Entwürfe im Vorführmodus: nur im Speicher.
final class DemoDateien: DraftFiles, @unchecked Sendable {
    private let lock = NSLock()
    private var order: [String] = []
    private var data: [String: Data] = [:]

    func names() -> [String] { lock.withLock { order } }
    func read(_ name: String) -> Data? { lock.withLock { data[name] } }
    func write(_ name: String, _ value: Data) -> Bool {
        lock.withLock {
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

extension Demo {
    /// Zwei Entwürfe für das Bildschirmfoto: einer wartet auf Verbindung, einen hat der Server abgelehnt.
    static func fillDrafts(_ box: DraftBox, unit: AdminUnit) {
        let english = Texte.language == "en"
        let rows: [(String, String, String?)] = english
            ? [("Stamps", "12,80", nil), ("Flowers for the anniversary", "18,00", "This category no longer exists.")]
            : [("Briefmarken", "12,80", nil), ("Blumen zum Jubiläum", "18,00", "Diese Kategorie gibt es nicht mehr.")]
        for (index, row) in rows.enumerated() {
            var draft = BookingDraft(key: "demo-\(index)")
            draft.text = row.0
            draft.amount = row.1
            draft.date = Zeit.day(Date())
            draft.account = 1
            guard var stored = StoredBooking(draft, unit: unit, accounts: [], categories: [], jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9])) else { continue }
            stored.accountName = english ? "Cash box" : "Barkasse"
            stored.error = row.2
            _ = box.save(stored)
        }
        // Dazu eine unterschriebene Quittung, die auf die Verbindung wartet
        var receipt = ReceiptDraft(key: "demo-quittung", finalizeKey: "demo-abschluss")
        receipt.name = "Max Mustermann"
        receipt.amount = "25,00"
        receipt.purpose = english ? "Expenses for flowers" : "Auslagen Blumen"
        receipt.account = 1
        receipt.category = 1
        let line = [[[20, 70], [50, 30], [70, 75], [95, 35], [120, 70], [160, 55], [210, 60], [270, 45]]]
        receipt.treasurer = SignatureStrokes(width: 300, height: 100, strokes: line)
        receipt.counterparty = SignatureStrokes(width: 300, height: 100, strokes: line)
        if var kept = StoredReceipt(receipt, unit: unit, choices: ReceiptChoices()) {
            kept.accountName = english ? "Cash box" : "Barkasse"
            _ = box.save(kept)
        }
    }
}

final class DemoStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [DeviceSession.tokenKey: "hpd_demo"]

    func read(_ key: String) -> String? { lock.withLock { values[key] } }
    func write(_ key: String, _ value: String?) { lock.withLock { values[key] = value } }
}

final class DemoCards: CardStore, @unchecked Sendable {
    private let lock = NSLock()
    private var cards: [Int: StoredCard] = [:]

    func load(accessId: Int) -> StoredCard? { lock.withLock { cards[accessId] } }
    func save(accessId: Int, card: StoredCard) { lock.withLock { cards[accessId] = card } }
    func delete(accessId: Int) { lock.withLock { cards[accessId] = nil } }
    func clear() { lock.withLock { cards = [:] } }
}

struct DemoTransport: Transport {
    private func day(_ offset: Int, _ time: String) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return "\(Zeit.day(date))T\(time):00+01:00"
    }

    /// Kassenbuch der Verwaltung: Konten, Kategorien, Buchungen, Belege.
    private func kasse(_ path: String, _ method: String, english: Bool) -> HttpResponse {
        let t = english
            ? ["Current account", "Bank account", "Cash box", "Cash", "Drinks", "Donations", "Other", "Expense", "Income", "Transfer", "Drinks for the platoon meeting", "Beverage store Example", "Donation for the youth group", "Change", "Hall rent"]
            : ["Girokonto", "Bankkonto", "Barkasse", "Bar", "Getränke", "Spenden", "Sonstiges", "Ausgabe", "Einnahme", "Umbuchung", "Getränke Zugversammlung", "Getränkemarkt Beispiel", "Spende für die Jugend", "Wechselgeld", "Saalmiete"]
        let erste = """
        {"id":9,"display_number":"2026-0031","date":"\(day(-2, "00:00").prefix(10))","kind":"expense","kind_label":"\(t[7])","amount":"23.40","account_name":"\(t[2])","category_name":"\(t[4])","text":"\(t[10])","counterparty":"\(t[11])","receipts":[{"id":5,"name":"beleg.jpg","content_type":"image/jpeg"}]}
        """
        let body: String
        if path.contains("/receipts/"), method == "GET" {
            return HttpResponse(status: 200, body: DemoBild.beleg().pngData() ?? Data())
        } else if method != "GET" {
            return HttpResponse(status: 201, body: Data(erste.utf8))
        } else if path.hasSuffix("/accounts/") {
            body = """
            [{"id":1,"name":"\(t[0])","kind":"bank","kind_label":"\(t[1])","balance":"4218.35"},
            {"id":2,"name":"\(t[2])","kind":"cash","kind_label":"\(t[3])","balance":"187.10"}]
            """
        } else if path.hasSuffix("/categories/") {
            body = """
            [{"id":1,"name":"\(t[4])","kind":"expense"},{"id":2,"name":"\(t[5])","kind":"income"},{"id":3,"name":"\(t[6])","kind":"both"}]
            """
        } else if path.hasSuffix("/bookings/") {
            body = """
            {"count":4,"results":[\(erste),
            {"id":8,"display_number":"2026-0030","date":"\(day(-4, "00:00").prefix(10))","kind":"income","kind_label":"\(t[8])","amount":"150.00","account_name":"\(t[0])","category_name":"\(t[5])","text":"\(t[12])","counterparty":"Musterbau GmbH","receipts":[{"id":4,"name":"beleg.pdf","content_type":"application/pdf"}]},
            {"id":7,"display_number":"2026-0029","date":"\(day(-5, "00:00").prefix(10))","kind":"transfer","kind_label":"\(t[9])","amount":"200.00","account_name":"\(t[0])","to_account_name":"\(t[2])","text":"\(t[13])","receipts":[{"id":3,"name":"beleg.jpg","content_type":"image/jpeg"}]},
            {"id":6,"display_number":"2026-0028","date":"\(day(-9, "00:00").prefix(10))","kind":"expense","kind_label":"\(t[7])","amount":"380.00","account_name":"\(t[0])","category_name":"\(t[6])","text":"\(t[14])"}
            ]}
            """
        } else {
            body = erste
        }
        return HttpResponse(status: 200, body: Data(body.utf8))
    }

    /// Wettbewerbe der Verwaltung: Liste, Standzugänge, neuer Standzugang.
    private func wettbewerbe(_ path: String, _ method: String, english: Bool) -> HttpResponse {
        let t = english
            ? ["King's shoot", "Shooting range", "Club championship air rifle", "Clubhouse", "Easter egg shoot", "App (iPhone)"]
            : ["Königsschießen", "Schießstand", "Vereinsmeisterschaft Luftgewehr", "Vereinsheim", "Ostereierschießen", "App (iPhone)"]
        let body: String
        if method == "DELETE" {
            return HttpResponse(status: 204, body: Data())
        } else if method == "POST" {
            return HttpResponse(status: 201, body: Data("""
            {"id":3,"label":"\(t[5])","expires_at":"\(day(0, "23:59"))","active":true,"token":"demo-standzugang-0123456789"}
            """.utf8))
        } else if path.hasSuffix("/stand-access/") {
            body = path.contains("/competitions/1/")
                ? """
                [{"id":1,"label":"\(t[5])","expires_at":"\(day(0, "23:59"))","active":true},{"id":2,"label":"Tablet","expires_at":"\(day(0, "23:59"))","active":true}]
                """
                : "[]"
        } else {
            body = """
            [{"id":3,"title":"\(t[4])","date":"\(day(-200, "00:00").prefix(10))","status":"endgueltig","form":"scheibe","location":"\(t[1])","starter_count":31},
            {"id":2,"title":"\(t[2])","date":"\(day(21, "00:00").prefix(10))","status":"offen","form":"scheibe","location":"\(t[3])","starter_count":12},
            {"id":1,"title":"\(t[0])","date":"\(day(0, "00:00").prefix(10))","status":"laufend","form":"vogel","location":"\(t[1])","starter_count":23}]
            """
        }
        return HttpResponse(status: 200, body: Data(body.utf8))
    }

    /// Geschäftspartner, Qualifikationen und Fristen der Verwaltung (nur lesen).
    private func nachschlagen(_ path: String, english: Bool) -> HttpResponse {
        let body: String
        if path.hasSuffix("/partners/") {
            let t = english
                ? ["Beverage store Example", "Purchasing", "Delivers on Fridays, crates are collected on Mondays.", "Marquee hire Sample", "Example Savings Bank"]
                : ["Getränkemarkt Beispiel", "Einkauf", "Liefert freitags, Leergut wird montags abgeholt.", "Zeltverleih Muster", "Sparkasse Beispielstadt"]
            body = """
            [{"id":1,"name":"\(t[0])","roles":["supplier","sponsor"],"number":"GP-0007","details":{"street":"Musterstraße 12","postcode":"12345","city":"Musterstadt","email":"info@getraenke.example","phone":"+49 30 1234567"},
            "notes":"\(t[2])","contacts":[{"id":1,"last_name":"Beispiel","first_name":"Lena","function":"\(t[1])","email":"lena.beispiel@getraenke.example","phone":"+49 30 1234568","is_primary":true}]},
            {"id":2,"name":"\(t[3])","roles":["venue"],"number":"GP-0004","details":{"city":"Musterdorf"},"contacts":[{"id":2,"last_name":"Probe","first_name":"Jonas"}]},
            {"id":3,"name":"\(t[4])","roles":["bank","donor"],"number":"GP-0001","details":{"city":"Musterstadt"}}]
            """
        } else if path.hasSuffix("/qualifications/") {
            let t = english
                ? ["Range officer", "First aid", "Youth leader card"]
                : ["Schießleiter", "Erste Hilfe", "Jugendleiter-Card"]
            body = """
            [{"id":1,"member":2,"first_name":"Max","last_name":"Mustermann","kind_name":"\(t[1])","valid_until":"\(day(-12, "00:00").prefix(10))","status":"expired"},
            {"id":2,"member":1,"first_name":"Erika","last_name":"Musterfrau","kind_name":"\(t[0])","valid_until":"\(day(40, "00:00").prefix(10))","status":"expiring"},
            {"id":3,"member":4,"first_name":"Lena","last_name":"Beispiel","kind_name":"\(t[2])","valid_until":"\(day(75, "00:00").prefix(10))","status":"expiring"}]
            """
        } else {
            let t = english
                ? ["Report the new board to the register of associations", "Board", "Tax return for the tax office", "Treasurer", "Check the fire extinguishers", "Clubhouse warden", "Update the transparency register", "The documents are with the tax adviser.", "Handed in on time."]
                : ["Neuen Vorstand beim Vereinsregister anmelden", "Vorstand", "Steuererklärung beim Finanzamt", "Kassierer", "Feuerlöscher prüfen lassen", "Hauswart", "Transparenzregister aktualisieren", "Die Unterlagen liegen beim Steuerberater.", "Fristgerecht abgegeben."]
            body = """
            {"items":[
            {"id":2,"title":"\(t[4])","due_date":"\(day(45, "00:00").prefix(10))","status":"planned","role_name":"\(t[5])","interval_months":24},
            {"id":1,"title":"\(t[2])","note":"\(t[7])","due_date":"\(day(-5, "00:00").prefix(10))","status":"overdue","role_name":"\(t[3])","interval_months":36,
            "history":[{"id":1,"done_on":"2023-11-02","note":"\(t[8])","done_by":"Max Mustermann"}]},
            {"id":3,"title":"\(t[0])","due_date":"\(day(20, "00:00").prefix(10))","status":"soon","role_name":"\(t[1])"},
            {"id":4,"title":"\(t[6])","status":"election","role_name":"\(t[1])"}
            ]}
            """
        }
        return HttpResponse(status: 200, body: Data(body.utf8))
    }

    /// „Aufgaben verteilen“ in der Verwaltung: Liste, eine Aufgabe, erledigen, anlegen.
    private func aufgaben(_ path: String, _ method: String, english: Bool) -> HttpResponse {
        let t = english
            ? ["Order the marquee", "Ask three suppliers for a quote and compare prices by the board meeting.", "due 27 Nov 2026, 6:00 pm", "Invite the guests of honour", "due 4 Dec 2026", "Renew the liability insurance", "Quote from last year is in the shared folder.", "Book the band"]
            : ["Festzelt bestellen", "Drei Angebote einholen und bis zur Vorstandssitzung vergleichen.", "bis 27.11.2026, 18:00 Uhr", "Ehrengäste einladen", "bis 04.12.2026", "Haftpflichtversicherung verlängern", "Das Angebot vom letzten Jahr liegt in der Ablage.", "Kapelle buchen"]
        func eine(_ status: String, _ version: Int) -> String {
            """
            {"id":1,"title":"\(t[0])","description":"\(t[1])","due_date":"2026-11-27","due_time":"18:00","timezone":"Europe/Berlin","status":"\(status)","shared":true,"version":\(version),"can_edit":true,"can_complete":true,"local_note":"\(t[6])","due_label":"\(t[2])","highlight":true}
            """
        }
        if method == "PATCH" {
            return HttpResponse(status: 200, body: Data(eine("done", 4).utf8), headers: ["X-Change-Set": "demo", "X-Change-Undoable": "1", "X-Change-Task": "1"])
        } else if method != "GET" {
            return HttpResponse(status: path.hasSuffix("/undo/") ? 200 : 201, body: Data(eine("open", 3).utf8))
        }
        let body: String
        if path.hasSuffix("/todos/") {
            body = """
            {"items":[\(eine("open", 3)),
            {"id":2,"title":"\(t[3])","status":"open","shared":true,"version":1,"can_edit":true,"due_label":"\(t[4])"},
            {"id":3,"title":"\(t[5])","status":"open","version":2,"can_edit":true},
            {"id":4,"title":"\(t[7])","status":"done","shared":true,"version":5,"can_edit":true}
            ]}
            """
        } else {
            body = eine("open", 3)
        }
        return HttpResponse(status: 200, body: Data(body.utf8))
    }

    /// Rechnungen der Verwaltung: Liste, eine Rechnung mit Zahlung, „Bar kassiert“.
    private func rechnungen(_ path: String, _ method: String, english: Bool) -> HttpResponse {
        let t = english
            ? ["open", "paid", "Annual fee 2026", "Platoon 1", "Platoon 2", "Membership fee", "Adults", "Shooting insurance", "Cash", "Cash box", "Current account", "Christmas party", "Sponsorship banner"]
            : ["offen", "bezahlt", "Jahresbeitrag 2026", "Zug 1", "Zug 2", "Mitgliedsbeitrag", "Erwachsene", "Schießversicherung", "Bar", "Barkasse", "Girokonto", "Weihnachtsfeier", "Werbebanner"]
        func eine(_ outstanding: String, _ paid: String, zahlungen: String) -> String {
            """
            {"id":7,"number":"RE-2026-0042","status":"open","status_label":"\(t[0])","recipient_name":"Erika Musterfrau","department_name":"\(t[3])","subject":"\(t[2])",
            "date":"\(day(-20, "00:00").prefix(10))","due_date":"\(day(-6, "00:00").prefix(10))","total":"72.00","paid":"\(paid)","outstanding":"\(outstanding)","overdue":true,
            "lines":[{"text":"\(t[5])","detail":"\(t[6])","amount":"60.00"},{"text":"\(t[7])","detail":"","amount":"12.00"}],
            "payments":[\(zahlungen)]}
            """
        }
        let erste = """
        {"id":3,"date":"\(day(-8, "00:00").prefix(10))","amount":"20.00","method":"cash","method_label":"\(t[8])","account_name":"\(t[9])","booking_number":"2026-0027"}
        """
        let body: String
        if path.hasSuffix("/receipt/") {
            return HttpResponse(status: 404, body: Data("{}".utf8))
        } else if method != "GET" {
            let zweite = """
            {"id":4,"date":"\(day(0, "00:00").prefix(10))","amount":"52.00","method":"cash","method_label":"\(t[8])","account_name":"\(t[9])","booking_number":"2026-0032"}
            """
            var bezahlt = eine("0.00", "72.00", zahlungen: erste + "," + zweite)
            bezahlt = bezahlt.replacingOccurrences(of: #""status":"open","status_label":"\#(t[0])""#, with: #""status":"paid","status_label":"\#(t[1])""#)
            return HttpResponse(
                status: 201, body: Data(#"{"invoice":\#(bezahlt),"payment":4}"#.utf8), headers: ["X-Change-Set": "demo", "X-Change-Undoable": "1"]
            )
        } else if path.hasSuffix("/settings/") {
            body = """
            {"accounts":[{"id":1,"name":"\(t[10])","kind":"bank"},{"id":2,"name":"\(t[9])","kind":"cash"}],"can_edit":true}
            """
        } else if path.hasSuffix("/invoices/") {
            body = """
            {"count":3,"results":[\(eine("52.00", "20.00", zahlungen: erste)),
            {"id":6,"number":"RE-2026-0041","status":"open","status_label":"\(t[0])","recipient_name":"Max Mustermann","department_name":"\(t[4])","subject":"\(t[11])","date":"\(day(-3, "00:00").prefix(10))","due_date":"\(day(11, "00:00").prefix(10))","total":"35.00","paid":"0.00","outstanding":"35.00"},
            {"id":5,"number":"RE-2026-0040","status":"open","status_label":"\(t[0])","recipient_name":"Musterbau GmbH","subject":"\(t[12])","date":"\(day(-5, "00:00").prefix(10))","due_date":"\(day(9, "00:00").prefix(10))","total":"250.00","paid":"0.00","outstanding":"250.00"}
            ]}
            """
        } else {
            body = eine("52.00", "20.00", zahlungen: erste)
        }
        return HttpResponse(status: 200, body: Data(body.utf8))
    }

    /// Termine der Verwaltung: Liste, ein Termin mit Rückmeldungen, Änderungen mit „Rückgängig“.
    private func termine(_ path: String, _ method: String, english: Bool) -> HttpResponse {
        let t = english
            ? ["Platoon meeting", "Shooting practice", "Christmas party", "General assembly", "Clubhouse", "Shooting range", "Platoon 1", "Platoon 2", "Members", "weekly", "Dinner from 7 pm, please bring a small gift for the raffle.", "arrives later"]
            : ["Zugversammlung", "Übungsschießen", "Weihnachtsfeier", "Jahreshauptversammlung", "Vereinsheim", "Schießstand", "Zug 1", "Zug 2", "Mitglieder", "wöchentlich", "Essen ab 19 Uhr, bitte ein kleines Geschenk für die Tombola mitbringen.", "kommt später"]
        let club = "Schützenverein Musterstadt"
        let body: String
        if method != "GET", !(method == "POST" && path.hasSuffix("/events/")) {
            return HttpResponse(status: 200, body: Data("{}".utf8), headers: ["X-Change-Set": "demo", "X-Change-Undoable": "1"])
        } else if path.hasSuffix("/responses/") {
            body = """
            {"summary":{"yes":3,"no":1,"guests":1,"persons":4},"capacity":80,
            "items":[{"membership_id":1,"name":"Erika Musterfrau","departments":"\(t[6])","status":"yes","guests":1,"note":"\(t[11])","source":"member"},
            {"membership_id":2,"name":"Max Mustermann","departments":"\(t[6])","status":"yes","source":"board"},
            {"membership_id":4,"name":"Lena Beispiel","departments":"\(t[7])","status":"yes","source":"member"},
            {"membership_id":5,"name":"Jonas Probe","departments":"\(t[7])","status":"no","source":"member"}],
            "open":[{"membership_id":6,"name":"Anna Vorlage","departments":"\(t[6])"},{"membership_id":7,"name":"Paul Entwurf","departments":"\(t[7])"}]}
            """
        } else if path.hasSuffix("/events/") {
            if method == "POST" {
                return HttpResponse(
                    status: 201, body: Data(#"{"id":9,"title":"\#(t[0])","starts_at":"\#(day(7, "19:00"))","ends_at":"\#(day(7, "21:00"))"}"#.utf8),
                    headers: ["X-Change-Set": "demo", "X-Change-Undoable": "1"]
                )
            }
            body = """
            {"can_manage":true,"rsvp_allowed":true,"items":[
            {"key":"1","event_id":1,"title":"\(t[0])","starts_at":"\(day(3, "19:30"))","ends_at":"\(day(3, "21:30"))","location":"\(t[4])","owner":"\(t[6])","rsvp_enabled":true,"can_edit":true},
            {"key":"2","event_id":2,"title":"\(t[1])","starts_at":"\(day(6, "18:00"))","ends_at":"\(day(6, "20:00"))","original_start":"\(day(6, "18:00"))","location":"\(t[5])","owner":"\(club)","is_series":true,"can_edit":true},
            {"key":"2b","event_id":2,"title":"\(t[1])","starts_at":"\(day(13, "18:00"))","ends_at":"\(day(13, "20:00"))","original_start":"\(day(13, "18:00"))","location":"\(t[5])","owner":"\(club)","is_series":true,"is_cancelled":true,"can_edit":true},
            {"key":"3","event_id":3,"title":"\(t[2])","starts_at":"\(day(28, "18:00"))","ends_at":"\(day(28, "23:00"))","location":"\(t[4])","owner":"\(club)","rsvp_enabled":true,"can_edit":true},
            {"key":"4","event_id":4,"title":"\(t[3])","starts_at":"\(day(63, "00:00"))","ends_at":"\(day(63, "00:00"))","all_day":true,"owner":"\(club)","can_edit":true}
            ]}
            """
        } else {
            body = """
            {"id":3,"title":"\(t[2])","description":"\(t[10])","location":"\(t[4])","starts_at":"\(day(28, "18:00"))","ends_at":"\(day(28, "23:00"))",
            "visibility_label":"\(t[8])","repeat":"none","owner":"\(club)","can_edit":true,
            "rsvp":{"enabled":true,"deadline":"\(day(21, "23:59"))","capacity":80,"free":76,"guests_allowed":true,"max_guests":2,"can_view_list":true,"can_enter":true,
            "summary":{"yes":3,"no":1,"guests":1,"persons":4,"open":2}}}
            """
        }
        return HttpResponse(status: 200, body: Data(body.utf8))
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        let path = URLComponents(string: request.url)?.path ?? ""
        let english = Texte.language == "en"
        let body: String
        if path.hasSuffix("/me/") {
            body = #"{"user":{"email":"erika@example.org","display":"Erika Musterfrau"},"device":{"id":1,"name":"iPhone","platform":"ios","current":true},"portal":[{"id":1,"club_name":"Schützenverein Musterstadt","modules":["events","circulars","card","billing","todos","helpers","meetings","docs","music","scores"],"musician":true}]}"#
        } else if path.hasSuffix("/api/app/v1/admin/") {
            let unlocked = Demo.section != "freischalten"
            let zug = english ? "Platoon 1" : "Zug 1"
            body = """
            {"units":[{"id":1,"name":"Schützenverein Musterstadt","type":"club","permissions":["members.view","members.edit","photos.edit","events.view","events.edit","finance.view","finance.edit","billing.view","billing.edit","todos.view","todos.edit","partners.view","obligations.view","results.edit"],"stufen":true,"modules":["qualifications","obligations","competitions"]}],
            "departments":[{"id":9,"name":"\(zug)","permissions":["members.view"],"stufen":true}],
            "two_factor":true,"unlocked":\(unlocked),"until":"\(day(21, "10:00"))"}
            """
        } else if path.contains("/admin/"), path.contains("/events/") {
            return termine(path, request.method, english: english)
        } else if path.hasSuffix("/admin/signature/") {
            body = #"{"signature":{"w":300,"h":100,"s":[[15,60,40,25,60,70,85,30,110,65,150,50,200,58,280,40]]}}"#
        } else if path.contains("/admin/"), path.contains("/finance/") {
            return kasse(path, request.method, english: english)
        } else if path.contains("/admin/"), path.hasSuffix("/billing/partners/") || path.hasSuffix("/qualifications/") || path.hasSuffix("/obligations/") {
            return nachschlagen(path, english: english)
        } else if path.contains("/admin/"), path.contains("/competitions/") {
            return wettbewerbe(path, request.method, english: english)
        } else if path.hasSuffix("/billing/mandates/") {
            body = #"[{"id":1,"reference":"M-0042-1","holder":"Erika Musterfrau","iban_masked":"DE02 •••• •••• •••• •••• 51","signed_on":"2023-02-01","status":"active"}]"#
        } else if path.contains("/admin/"), path.contains("/billing/") {
            return rechnungen(path, request.method, english: english)
        } else if path.contains("/admin/"), path.contains("/todos/") {
            return aufgaben(path, request.method, english: english)
        } else if path.hasSuffix("/tasks/") {
            let t = english
                ? ["Data change", "New address and phone number", "Photo", "New photo for the membership card", "Event", "Christmas party", "4 replies, 2 open"]
                : ["Datenänderung", "Neue Anschrift und Telefonnummer", "Foto", "Neues Foto für den Ausweis", "Termin", "Weihnachtsfeier", "4 Rückmeldungen, 2 offen"]
            body = """
            {"items":[
            {"kind":"change_request","kind_label":"\(t[0])","title":"Max Mustermann","detail":"\(t[1])","ref":1},
            {"kind":"photo","kind_label":"\(t[2])","title":"Erika Musterfrau","detail":"\(t[3])","membership":1},
            {"kind":"event","kind_label":"\(t[4])","title":"\(t[5])","detail":"\(t[6])","ref":3}
            ]}
            """
        } else if path.hasSuffix("/change-requests/") {
            let note = english ? "We have moved." : "Wir sind umgezogen."
            body = """
            [{"id":1,"member_id":2,"member_name":"Max Mustermann","created_at":"\(day(-2, "18:40"))","message":"\(note)",
            "data":{"street":"Beispielallee 12","phone":"02131 111111"},"previous":{"street":"Musterweg 3","phone":"02131 000001"}},
            {"id":2,"member_id":4,"member_name":"Lena Beispiel","created_at":"\(day(-1, "09:15"))",
            "data":{"email":"lena.beispiel@example.org"},"previous":{"email":"lena@example.org"}}]
            """
        } else if path.hasSuffix("/decide/") || path.hasSuffix("/photo/approve/") {
            return HttpResponse(status: 200, body: Data("{}".utf8), headers: ["X-Change-Set": "demo", "X-Change-Undoable": "1"])
        } else if path.hasSuffix("/undo/") {
            body = "{}"
        } else if path.hasSuffix("/cards/check/") {
            let t = english ? ["Valid", "Full member", "Platoon 1"] : ["Gültig", "Vollmitglied", "Zug 1"]
            body = """
            {"status":"active","status_label":"\(t[0])","first_name":"Erika","last_name":"Musterfrau","member_type":"\(t[1])",
            "club":"Schützenverein Musterstadt","departments":["\(t[2])"],"photo_url":"/api/public/cards/demo/photo/","membership":1}
            """
        } else if path.contains("/photo/") {
            return HttpResponse(status: 200, body: DemoBild.png(neu: path.contains("pending")))
        } else if path.hasSuffix("/birthdays/") {
            body = """
            {"results":[{"member_id":2,"first_name":"Max","last_name":"Mustermann","date":"\(day(4, "00:00").prefix(10))","age":50},
            {"member_id":4,"first_name":"Lena","last_name":"Beispiel","date":"\(day(19, "00:00").prefix(10))","age":18}]}
            """
        } else if path.hasSuffix("/jubilees/") {
            body = """
            {"results":[{"member_id":1,"first_name":"Erika","last_name":"Musterfrau","kind":"membership","years":25,"date":"\(day(40, "00:00").prefix(10))","organization_short":""},
            {"member_id":5,"first_name":"Jonas","last_name":"Probe","kind":"membership","years":10,"date":"\(day(71, "00:00").prefix(10))","organization_short":""}]}
            """
        } else if path.contains("/members/duplicates/") {
            body = #"[{"id":55,"last_name":"Beispiel","first_name":"Lena","birth_date":"2008-03-07"},{"id":4,"last_name":"Beispiel","first_name":"Lena","birth_date":"2008-03-07","already_member_here":true}]"#
        } else if path.hasSuffix("/honorary-titles/") {
            let t = english ? ["Honorary member", "Platoon king", "Golden badge of honour"] : ["Ehrenmitglied", "Zugkönig", "Goldene Ehrennadel"]
            body = path.contains("/members/")
                ? #"[{"id":1,"title":1,"title_name":"\#(t[0])","valid_from":"2020-01-11"},{"id":2,"title":2,"title_name":"\#(t[1])","valid_from":"2018-09-01","valid_until":"2019-08-31"}]"#
                : #"[{"id":1,"name":"\#(t[0])"},{"id":2,"name":"\#(t[1])"},{"id":3,"name":"\#(t[2])"}]"#
        } else if path.hasSuffix("/fields/") {
            let t = english
                ? ["Shooting log no.", "Uniform received", "First aider", "Instrument", "Drum", "Flute", "Courses"]
                : ["Schießbuch-Nr.", "Uniform erhalten", "Ersthelfer", "Instrument", "Trommel", "Flöte", "Lehrgänge"]
            body = #"[{"definition":{"id":1,"label":"\#(t[0])","field_type":"text"},"value":"A-17"},{"definition":{"id":2,"label":"\#(t[1])","field_type":"date"},"value":"2024-05-03"},{"definition":{"id":3,"label":"\#(t[2])","field_type":"bool"},"value":true},{"definition":{"id":4,"label":"\#(t[3])","field_type":"choice","choices":["\#(t[4])","\#(t[5])"]},"value":"\#(t[4])"},{"definition":{"id":5,"label":"\#(t[6])","field_type":"text","repeatable":true},"value":["A"]}]"#
        } else if path.hasSuffix("/member-types/") {
            let t = english ? ["Full member", "Supporting member", "Youth"] : ["Vollmitglied", "Fördermitglied", "Jugend"]
            body = #"[{"id":1,"name":"\#(t[0])"},{"id":2,"name":"\#(t[1])"},{"id":3,"name":"\#(t[2])"}]"#
        } else if path.contains("/admin/"), path.hasSuffix("/departments/") {
            let t = english ? ["Platoon 1", "Platoon 2"] : ["Zug 1", "Zug 2"]
            body = #"[{"id":1,"name":"\#(t[0])"},{"id":2,"name":"\#(t[1])"}]"#
        } else if path.hasSuffix("/preview/") {
            body = english
                ? #"{"title":"Record leaving","consequences":["Erika Musterfrau leaves the club on \#(Zeit.plainDate(String(day(0, "00:00").prefix(10)))).","The membership in Platoon 1 ends on the same day.","Open invoices remain.","The membership card becomes invalid."]}"#
                : #"{"title":"Austritt eintragen","consequences":["Erika Musterfrau tritt zum \#(Zeit.plainDate(String(day(0, "00:00").prefix(10)))) aus dem Verein aus.","Die Zugehörigkeit zu Zug 1 endet am selben Tag.","Offene Rechnungen bleiben bestehen.","Der Mitgliedsausweis wird ungültig."]}"#
        } else if path.hasSuffix("/members/") {
            let t = english ? ["Full member", "Platoon 1", "Platoon 2", "Supporting member", "Youth"] : ["Vollmitglied", "Zug 1", "Zug 2", "Fördermitglied", "Jugend"]
            body = """
            {"count":5,"results":[
            {"id":4,"last_name":"Beispiel","first_name":"Lena","member_type":"\(t[4])","departments":["\(t[2])"],"city":"Musterstadt","status":"active"},
            {"id":3,"kind":"organization","last_name":"Musterbau GmbH","member_type":"\(t[3])","city":"Musterstadt","status":"active"},
            {"id":1,"last_name":"Musterfrau","first_name":"Erika","member_type":"\(t[0])","departments":["\(t[1])"],"city":"Musterstadt","status":"active"},
            {"id":2,"last_name":"Mustermann","first_name":"Max","member_type":"\(t[0])","departments":["\(t[1])"],"city":"Musterstadt","status":"active"},
            {"id":5,"last_name":"Probe","first_name":"Jonas","member_type":"\(t[0])","departments":["\(t[2])"],"city":"Musterdorf","status":"active"}
            ]}
            """
        } else if path.contains("/members/") {
            let t = english ? ["Full member", "Platoon 1"] : ["Vollmitglied", "Zug 1"]
            body = """
            {"id":1,"kind":"person","first_name":"Erika","last_name":"Musterfrau","birth_date":"1984-03-07","club_number":"0042","status":"active","gender":"weiblich",
            "photo":{"approved":{"url":"/api/orgs/1/members/1/photo/"},"pending":{"url":"/api/orgs/1/members/1/photo/pending/"}},
            "current_type":{"member_type":1,"member_type_name":"\(t[0])"},"periods":[{"id":1,"entry_date":"2010-01-01"}],
            "departments":[{"id":1,"department":1,"department_name":"\(t[1])","valid_from":"2010-01-01"}],
            "pays_fee_self":true,"exit_reasons":[{"value":"resignation","label":"\(english ? "Resignation" : "Kündigung")"},{"value":"death","label":"\(english ? "Deceased" : "Verstorben")"}],
            "contact":{"email":"erika@example.org","phone":"02131 000000","street":"Musterweg 1","postal_code":"41468","city":"Musterstadt"}}
            """
        } else if path.hasSuffix("/events/") {
            let titles = english
                ? ["Platoon meeting", "Shooting practice", "Christmas party", "General assembly"]
                : ["Zugversammlung", "Übungsschießen", "Weihnachtsfeier", "Jahreshauptversammlung"]
            let place = english ? "Clubhouse" : "Vereinsheim"
            let group = english ? "Platoon 1" : "Zug 1"
            let range = english ? "Shooting range" : "Schießstand"
            body = """
            {"items":[
            {"key":"1","event_id":1,"title":"\(titles[0])","starts_at":"\(day(3, "19:30"))","ends_at":"\(day(3, "21:30"))","location":"\(place)","owner":"\(group)","rsvp_enabled":true,"my_response":null},
            {"key":"2","event_id":2,"title":"\(titles[1])","starts_at":"\(day(6, "18:00"))","ends_at":"\(day(6, "20:00"))","location":"\(range)","owner":"Schützenverein Musterstadt","rsvp_enabled":true,"my_response":"yes"},
            {"key":"3","event_id":3,"title":"\(titles[2])","starts_at":"\(day(28, "18:00"))","ends_at":"\(day(28, "23:00"))","location":"\(place)","owner":"Schützenverein Musterstadt","rsvp_enabled":true,"my_response":"no"},
            {"key":"4","event_id":4,"title":"\(titles[3])","starts_at":"\(day(63, "00:00"))","ends_at":"\(day(63, "23:59"))","all_day":true,"owner":"Schützenverein Musterstadt"}
            ]}
            """
        } else if path.hasSuffix("/circulars/") {
            body = english
                ? #"[{"id":2,"subject":"Fall in tonight","sender":"Platoon 1","kind_label":"Short message","sent_at":"\#(day(0, "09:00"))","body":"Tonight at **6 pm** at the tent – please be on time.\n\n- Uniform\n- Good mood","channel":"app"},{"id":1,"subject":"Invitation to the general assembly","sender":"Schützenverein Musterstadt","kind_label":"Circular","sent_at":"\#(day(-9, "10:00"))","body":"Dear members,\n\nwe cordially invite you to the general assembly. The agenda is in the members' area.","attachments":[{"id":1,"name":"Agenda.pdf","size":48213}],"channel":"mail"}]"#
                : #"[{"id":2,"subject":"Antreten heute Abend","sender":"Zug 1","kind_label":"Kurzmitteilung","sent_at":"\#(day(0, "09:00"))","body":"Heute um **18 Uhr** am Zelt – bitte pünktlich.\n\n- Uniform\n- Gute Laune","channel":"app"},{"id":1,"subject":"Einladung zur Jahreshauptversammlung","sender":"Schützenverein Musterstadt","kind_label":"Rundschreiben","sent_at":"\#(day(-9, "10:00"))","body":"Liebe Mitglieder,\n\nwir laden herzlich zur Jahreshauptversammlung ein. Die Tagesordnung steht im Mitgliederbereich.","attachments":[{"id":1,"name":"Tagesordnung.pdf","size":48213}],"channel":"mail"}]"#
        } else if path.hasSuffix("/card/") {
            let labels = english
                ? ["Active member", "Full member", "Platoon", "Platoon 1, Band"]
                : ["Aktives Mitglied", "Vollmitglied", "Zug", "Zug 1, Kapelle"]
            body = """
            {"state":"active","url":"https://verein.example.de/ausweis/pruefen/demo-0042",
            "display":{"first_name":"Erika","last_name":"Musterfrau","status":"active","status_label":"\(labels[0])",
            "member_type":"\(labels[1])","club":"Schützenverein Musterstadt","department_label":"\(labels[2])",
            "departments":["\(labels[3])"],"club_number":"0042","theme":{"primary":"0E7C66","on_primary":"FFFFFF"}}}
            """
        } else if path.hasSuffix("/invoices/") {
            let labels = english ? ["Paid", "Open", "Annual fee 2026", "Summer festival tickets"] : ["Bezahlt", "Offen", "Jahresbeitrag 2026", "Karten Sommerfest"]
            body = """
            {"invoices":[
            {"id":2,"number":"R-2026-0031","status":"open","status_label":"\(labels[1])","date":"\(day(-12, "00:00").prefix(10))","due_date":"\(day(9, "00:00").prefix(10))","subject":"\(labels[3])","total":"36.00","outstanding":"36.00","issuer_name":"Schützenverein Musterstadt"},
            {"id":1,"number":"R-2026-0007","status":"paid","status_label":"\(labels[0])","date":"2026-01-15","subject":"\(labels[2])","total":"60.00","outstanding":"0.00","issuer_name":"Schützenverein Musterstadt"}
            ]}
            """
        } else if path.contains("/music/files/") {
            return HttpResponse(status: 200, body: DemoNoten.pdf(pages: path.contains("/files/1/") ? 2 : 1))
        } else if path.hasSuffix("/music/folders/") {
            let t = english
                ? ["March book", "Rehearsal", "Clubhouse", "Christmas concert", "Break"]
                : ["Marschbuch", "Probe", "Vereinsheim", "Weihnachtskonzert", "Pause"]
            let pieces = """
            {"arrangement":1,"title":"Gruß an Musterstadt","composer":"E. Beispiel","number":"1","scores":[{"id":1,"content_type":"application/pdf","url":"/api/portal/1/music/files/1/"}]},
            {"arrangement":2,"title":"Musterstädter Schützenmarsch","composer":"M. Muster","number":"2","scores":[{"id":2,"content_type":"application/pdf","url":"/api/portal/1/music/files/2/"}]},
            {"arrangement":3,"title":"Unter der Vereinsfahne","composer":"E. Beispiel","number":"3","scores":[]}
            """
            body = """
            {"folders":[{"id":1,"key":"folder-1","kind":"marchbook","name":"\(t[0])","items":[\(pieces)]}],
            "events":[{"key":"rehearsal-1","type":"rehearsal","title":"\(t[1])","starts_at":"\(day(3, "19:30"))","location":"\(t[2])","focus":"\(t[3])","items":[
            {"arrangement":2,"title":"Musterstädter Schützenmarsch","scores":[{"id":2,"content_type":"application/pdf","url":"/api/portal/1/music/files/2/"}]},
            {"kind":"pause","title":"\(t[4])"},
            {"arrangement":1,"title":"Gruß an Musterstadt","scores":[{"id":1,"content_type":"application/pdf","url":"/api/portal/1/music/files/1/"}]}]}]}
            """
        } else if path.hasSuffix("/meetings/") {
            let t = english
                ? ["General assembly", "Clubhouse", "Welcome", "Report of the board", "Treasurer's report", "Elections", "New flag", "General assembly last year"]
                : ["Jahreshauptversammlung", "Vereinsheim", "Begrüßung", "Bericht des Vorstands", "Kassenbericht", "Wahlen", "Neue Fahne", "Jahreshauptversammlung im Vorjahr"]
            body = """
            {"upcoming":[{"id":1,"title":"\(t[0])","unit":"Schützenverein Musterstadt","starts_at":"\(day(63, "19:30"))","location":"\(t[1])","address":"Musterweg 1, 41468 Musterstadt","motion_until":"\(day(49, "23:59"))",
            "motions":[{"id":1,"title":"\(t[6])","status":"submitted"}],
            "agenda":[{"position":1,"title":"\(t[2])","number":"1"},{"position":2,"title":"\(t[3])","number":"2"},{"position":3,"title":"\(t[4])","number":"2.1","level":1},{"position":4,"title":"\(t[5])","number":"3"}]}],
            "minutes":[{"id":2,"title":"\(t[7])","starts_at":"\(day(-300, "19:30"))"}]}
            """
        } else if path.hasSuffix("/documents/") {
            let t = english
                ? ["Statutes and rules", "Statutes", "Version 2024", "Shooting rules", "Forms", "Membership application"]
                : ["Satzung und Ordnungen", "Satzung", "Fassung 2024", "Schießordnung", "Formulare", "Aufnahmeantrag"]
            body = """
            {"folders":[{"id":1,"name":"\(t[0])","documents":[
            {"id":1,"title":"\(t[1])","date":"2024-03-01","note":"\(t[2])","current":{"id":1,"name":"satzung.pdf","url":"/api/portal/1/documents/versions/1/"}},
            {"id":2,"title":"\(t[3])","date":"2023-05-12","current":{"id":2,"name":"schiessordnung.pdf","url":"/api/portal/1/documents/versions/2/"}}]},
            {"id":2,"name":"\(t[4])","documents":[
            {"id":3,"title":"\(t[5])","current":{"id":3,"name":"aufnahmeantrag.pdf","url":"/api/portal/1/documents/versions/3/"}}]}]}
            """
        } else if path.hasSuffix("/todos/") {
            let t = english
                ? ["Put up the tent", "Friday from 4 pm at the fairground. Bring gloves.", "by 27 Nov 2026", "Order drinks", "Check the lighting"]
                : ["Zelt aufbauen", "Freitag ab 16 Uhr auf dem Festplatz. Handschuhe mitbringen.", "bis 27.11.2026", "Getränke bestellen", "Beleuchtung prüfen"]
            body = """
            {"items":[
            {"id":1,"title":"\(t[0])","description":"\(t[1])","status":"open","version":2,"due_label":"\(t[2])","can_claim":true},
            {"id":2,"title":"\(t[4])","status":"open","version":1,"claimed":true,"claimed_by_me":true,"can_complete":true},
            {"id":3,"title":"\(t[3])","status":"done","version":4,"can_complete":true}
            ]}
            """
        } else if path.hasSuffix("/helpers/") {
            let t = english
                ? ["Christmas market", "Bar", "Marquee", "Till", "Entrance", "Erika M.", "Max M."]
                : ["Weihnachtsmarkt", "Theke", "Festzelt", "Kasse", "Eingang", "Erika M.", "Max M."]
            body = """
            {"plans":[{"id":1,"title":"\(t[0])","unit":"Schützenverein Musterstadt","signup":"self","max_shifts":2,"duties":[
            {"id":1,"name":"\(t[1])","location":"\(t[2])","min_age":18,"shifts":[
            {"id":1,"starts_at":"\(day(20, "18:00"))","ends_at":"\(day(20, "22:00"))","needed":4,"taken":2,"names":["\(t[5])","\(t[6])"],"mine":1,"can_cancel":true},
            {"id":2,"starts_at":"\(day(21, "18:00"))","ends_at":"\(day(21, "22:00"))","needed":4,"taken":1,"names":["\(t[6])"]}]},
            {"id":2,"name":"\(t[3])","location":"\(t[4])","shifts":[
            {"id":3,"starts_at":"\(day(20, "17:00"))","ends_at":"\(day(20, "20:00"))","needed":2,"taken":2}]}]}],
            "mine":[{"id":1,"plan":"\(t[0])","duty":"\(t[1])","location":"\(t[2])","starts_at":"\(day(20, "18:00"))","ends_at":"\(day(20, "22:00"))"}]}
            """
        } else if path.hasSuffix("/api/portal/1/") {
            let type = english ? "Full member" : "Vollmitglied"
            body = """
            {"first_name":"Erika","last_name":"Musterfrau","birth_date":"1984-03-07","club_number":"0042","member_type":"\(type)",
            "entry_date":"2010-01-01","departments":["\(english ? "Platoon 1" : "Zug 1")"],"status":"active",
            "contact":{"email":"erika@example.org","phone":"02131 000000","street":"Musterweg 1","postal_code":"41468","city":"Musterstadt"}}
            """
        } else {
            body = "{}"
        }
        return HttpResponse(status: 200, body: Data(body.utf8))
    }
}

/// Erfundenes Ausweisfoto für den Vorführmodus: Fläche mit Personensymbol, kein Mensch.
enum DemoBild {
    /// Erfundener Kassenzettel als Belegfoto.
    static func beleg() -> UIImage {
        let size = CGSize(width: 300, height: 420)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 0.97, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let english = Texte.language == "en"
            let lines = english
                ? ["Beverage store Example", "Musterweg 5, Musterstadt", "", "2 crates of water      11.80", "1 crate of juice       11.60", "", "Total              23.40 EUR", "Paid in cash", "Thank you!"]
                : ["Getränkemarkt Beispiel", "Musterweg 5, Musterstadt", "", "2 Kisten Wasser      11,80", "1 Kiste Saft         11,60", "", "Summe            23,40 EUR", "Bar bezahlt", "Vielen Dank!"]
            for (index, line) in lines.enumerated() {
                let font = UIFont.monospacedSystemFont(ofSize: index == 0 ? 17 : 14, weight: index == 0 || index == 6 ? .bold : .regular)
                (line as NSString).draw(at: CGPoint(x: 24, y: 40 + index * 34), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }
        }
    }

    static func png(neu: Bool) -> Data {
        let size = CGSize(width: 280, height: 360)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            (neu ? UIColor.systemTeal : UIColor.systemGray3).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let symbol = UIImage(systemName: "person.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 50, y: 90, width: 180, height: 180))
        }
        return image.pngData() ?? Data()
    }
}

/// Erfundene Notenblätter für den Vorführmodus: leere Notenzeilen mit Seitenzahl.
enum DemoNoten {
    static func pdf(pages: Int) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for page in 1...max(pages, 1) {
                context.beginPage()
                let lines = context.cgContext
                lines.setStrokeColor(UIColor.black.cgColor)
                lines.setLineWidth(0.8)
                for staff in 0..<9 {
                    let top = 90 + CGFloat(staff) * 80
                    for line in 0..<5 {
                        let y = top + CGFloat(line) * 8
                        lines.move(to: CGPoint(x: 45, y: y))
                        lines.addLine(to: CGPoint(x: 550, y: y))
                    }
                    lines.move(to: CGPoint(x: 45, y: top))
                    lines.addLine(to: CGPoint(x: 45, y: top + 32))
                    lines.move(to: CGPoint(x: 550, y: top))
                    lines.addLine(to: CGPoint(x: 550, y: top + 32))
                }
                lines.strokePath()
                ("\(page)" as NSString).draw(
                    at: CGPoint(x: 292, y: 805),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 11)]
                )
            }
        }
    }
}
