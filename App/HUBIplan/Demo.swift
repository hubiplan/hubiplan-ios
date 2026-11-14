import Foundation
import HubiplanKern

/// Vorführmodus für Bildschirmfotos und Prüfungen im Simulator: Start mit `-demo 1`.
/// Die App spricht dann mit keinem Server; alle Daten sind erfunden (Demoverein).
enum Demo {
    static var active: Bool { UserDefaults.standard.bool(forKey: "demo") }
    /// Reiter, der beim Start offen sein soll (`-reiter mitteilungen`).
    static var tab: String { UserDefaults.standard.string(forKey: "reiter") ?? "termine" }

    static let account = Account(server: "https://verein.example.de", display: "Erika Musterfrau", email: "erika@example.org")
}

final class DemoStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [DeviceSession.tokenKey: "hpd_demo"]

    func read(_ key: String) -> String? { lock.withLock { values[key] } }
    func write(_ key: String, _ value: String?) { lock.withLock { values[key] = value } }
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
            body = #"{"user":{"email":"erika@example.org","display":"Erika Musterfrau"},"device":{"id":1,"name":"iPhone","platform":"ios","current":true},"portal":[{"id":1,"club_name":"Schützenverein Musterstadt","modules":["events","circulars"]}]}"#
        } else if path.hasSuffix("/events/") {
            let titles = english
                ? ["Platoon meeting", "Shooting practice", "Christmas party", "General assembly"]
                : ["Zugversammlung", "Übungsschießen", "Weihnachtsfeier", "Jahreshauptversammlung"]
            let place = english ? "Clubhouse" : "Vereinsheim"
            body = """
            {"items":[
            {"key":"1","event_id":1,"title":"\(titles[0])","starts_at":"\(day(3, "19:30"))","ends_at":"\(day(3, "21:30"))","location":"\(place)","owner":"Zug 1","rsvp_enabled":true,"my_response":null},
            {"key":"2","event_id":2,"title":"\(titles[1])","starts_at":"\(day(6, "18:00"))","ends_at":"\(day(6, "20:00"))","location":"Schießstand","owner":"Schützenverein Musterstadt","rsvp_enabled":true,"my_response":"yes"},
            {"key":"3","event_id":3,"title":"\(titles[2])","starts_at":"\(day(28, "18:00"))","ends_at":"\(day(28, "23:00"))","location":"\(place)","owner":"Schützenverein Musterstadt","rsvp_enabled":true,"my_response":"no"},
            {"key":"4","event_id":4,"title":"\(titles[3])","starts_at":"\(day(63, "00:00"))","ends_at":"\(day(63, "23:59"))","all_day":true,"owner":"Schützenverein Musterstadt"}
            ]}
            """
        } else if path.hasSuffix("/circulars/") {
            body = english
                ? #"[{"id":2,"subject":"Fall in tonight","sender":"Zug 1","kind_label":"Short message","sent_at":"\#(day(0, "09:00"))","body":"Tonight at **6 pm** at the tent – please be on time.\n\n- Uniform\n- Good mood","channel":"app"},{"id":1,"subject":"Invitation to the general assembly","sender":"Schützenverein Musterstadt","kind_label":"Circular","sent_at":"\#(day(-9, "10:00"))","body":"Dear members,\n\nwe cordially invite you to the general assembly. The agenda is in the members' area.","attachments":[{"id":1,"name":"Agenda.pdf","size":48213}],"channel":"mail"}]"#
                : #"[{"id":2,"subject":"Antreten heute Abend","sender":"Zug 1","kind_label":"Kurzmitteilung","sent_at":"\#(day(0, "09:00"))","body":"Heute um **18 Uhr** am Zelt – bitte pünktlich.\n\n- Uniform\n- Gute Laune","channel":"app"},{"id":1,"subject":"Einladung zur Jahreshauptversammlung","sender":"Schützenverein Musterstadt","kind_label":"Rundschreiben","sent_at":"\#(day(-9, "10:00"))","body":"Liebe Mitglieder,\n\nwir laden herzlich zur Jahreshauptversammlung ein. Die Tagesordnung steht im Mitgliederbereich.","attachments":[{"id":1,"name":"Tagesordnung.pdf","size":48213}],"channel":"mail"}]"#
        } else {
            body = "{}"
        }
        return HttpResponse(status: 200, body: Data(body.utf8))
    }
}
