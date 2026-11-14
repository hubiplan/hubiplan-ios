import Foundation
import HubiplanKern

/// Vorführmodus für Bildschirmfotos und Prüfungen im Simulator: Start mit `-demo 1`.
/// Die App spricht dann mit keinem Server; alle Daten sind erfunden (Demoverein).
enum Demo {
    static var active: Bool { UserDefaults.standard.bool(forKey: "demo") }
    /// Reiter, der beim Start offen sein soll (`-reiter mitteilungen`, `ausweis`, `konto`).
    static var tab: String { UserDefaults.standard.string(forKey: "reiter") ?? "termine" }

    /// Abschnitt im Reiter „Ich“, zu dem die Ansicht springt (`-abschnitt rechnungen`).
    static var section: String { UserDefaults.standard.string(forKey: "abschnitt") ?? "" }

    static let account = Account(server: "https://verein.example.de", display: "Erika Musterfrau", email: "erika@example.org")
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

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        let path = URLComponents(string: request.url)?.path ?? ""
        let english = Texte.language == "en"
        let body: String
        if path.hasSuffix("/me/") {
            body = #"{"user":{"email":"erika@example.org","display":"Erika Musterfrau"},"device":{"id":1,"name":"iPhone","platform":"ios","current":true},"portal":[{"id":1,"club_name":"Schützenverein Musterstadt","modules":["events","circulars","card","billing"]}]}"#
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
