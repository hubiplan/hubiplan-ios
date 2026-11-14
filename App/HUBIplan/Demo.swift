import Foundation
import HubiplanKern
import UIKit

/// Vorführmodus für Bildschirmfotos und Prüfungen im Simulator: Start mit `-demo 1`.
/// Die App spricht dann mit keinem Server; alle Daten sind erfunden (Demoverein).
enum Demo {
    static var active: Bool { UserDefaults.standard.bool(forKey: "demo") }
    /// Reiter, der beim Start offen sein soll (`-reiter mitteilungen`, `aufgaben`, `noten`, `ausweis`, `konto`).
    static var tab: String { UserDefaults.standard.string(forKey: "reiter") ?? "termine" }

    /// Abschnitt im Reiter „Ich“, zu dem die Ansicht springt (`-abschnitt rechnungen`, `versammlungen`, `dokumente`, `verwaltung`, `freischalten`, `offen`, `meldungen`, `mitglieder`, `mitglied`, `ausweispruefung`), im Reiter „Aufgaben“ die Helferdienste (`-abschnitt helfer`).
    static var section: String { UserDefaults.standard.string(forKey: "abschnitt") ?? "" }

    /// Zwei erfundene Konten: der Verein und die Kapelle mit eigener Instanz.
    static let accounts = AccountList(accounts: [
        AccountEntry(id: "", server: "https://verein.example.de", display: "Erika Musterfrau", email: "erika@example.org"),
        AccountEntry(id: "kapelle", server: "https://kapelle.example.org", display: "Erika Musterfrau", email: "erika@example.org"),
    ])
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
            body = #"{"user":{"email":"erika@example.org","display":"Erika Musterfrau"},"device":{"id":1,"name":"iPhone","platform":"ios","current":true},"portal":[{"id":1,"club_name":"Schützenverein Musterstadt","modules":["events","circulars","card","billing","todos","helpers","meetings","docs","music","scores"],"musician":true}]}"#
        } else if path.hasSuffix("/api/app/v1/admin/") {
            let unlocked = Demo.section != "freischalten"
            let zug = english ? "Platoon 1" : "Zug 1"
            body = """
            {"units":[{"id":1,"name":"Schützenverein Musterstadt","type":"club","permissions":["members.view","members.edit","photos.edit","events.view"],"stufen":true}],
            "departments":[{"id":9,"name":"\(zug)","permissions":["members.view"],"stufen":true}],
            "two_factor":true,"unlocked":\(unlocked),"until":"\(day(21, "10:00"))"}
            """
        } else if path.hasSuffix("/tasks/") {
            let t = english
                ? ["Data change", "New address and phone number", "Photo", "New photo for the membership card", "Event", "Christmas party", "12 replies, 3 open"]
                : ["Datenänderung", "Neue Anschrift und Telefonnummer", "Foto", "Neues Foto für den Ausweis", "Termin", "Weihnachtsfeier", "12 Rückmeldungen, 3 offen"]
            body = """
            {"items":[
            {"kind":"change_request","kind_label":"\(t[0])","title":"Max Mustermann","detail":"\(t[1])","ref":1},
            {"kind":"photo","kind_label":"\(t[2])","title":"Erika Musterfrau","detail":"\(t[3])","membership":1},
            {"kind":"event","kind_label":"\(t[4])","title":"\(t[5])","detail":"\(t[6])"}
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
            {"id":1,"kind":"person","first_name":"Erika","last_name":"Musterfrau","birth_date":"1984-03-07","club_number":"0042","status":"active",
            "photo":{"approved":{"url":"/api/orgs/1/members/1/photo/"},"pending":{"url":"/api/orgs/1/members/1/photo/pending/"}},
            "current_type":{"member_type":1,"member_type_name":"\(t[0])"},"periods":[{"id":1,"entry_date":"2010-01-01"}],
            "departments":[{"id":1,"department":1,"department_name":"\(t[1])","valid_from":"2010-01-01"}],
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
