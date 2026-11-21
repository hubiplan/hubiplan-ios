import XCTest
@testable import HubiplanKern

/// Sammelbestellungen unter „Ich“, gleiche Fälle wie `BestellungenTest` in Android. Alle Daten erfunden.
final class BestellungenTests: XCTestCase {
    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let list = #"""
    {"campaigns":[
      {"id":7,"title":"Vereinskleidung 2027","deadline":"2099-06-30","state":"open","from":"Musikverein Musterdorf",
       "club_pays":false,"ordered":false,"can_order":false,"order":null},
      {"id":5,"title":"Größen für Jacken","deadline":"2099-01-31","state":"closed","from":"Musikverein Musterdorf",
       "club_pays":true,"ordered":true,"can_order":false,
       "order":{"id":3,"lines":[{"article":1,"name":"Jacke","variant":"50","quantity":1,"price":null,"amount":null}],
                "note":"","total":null,"handed_out":true,"handed_out_at":"2099-02-10T10:00:00Z",
                "updated_at":"2099-01-20T10:00:00Z","invoice":null}}]}
    """#

    private let detail = #"""
    {"id":7,"title":"Vereinskleidung 2027","deadline":"2099-06-30","state":"open","from":"Musikverein Musterdorf",
     "club_pays":false,"ordered":false,"can_order":true,"order":null,"text":"Ausgabe beim Sommerfest",
     "articles":[
       {"id":1,"name":"Poloshirt","text":"","price":"25.00","variants":["S","M","L"],"variant_label":"Größe",
        "max_per_member":3,"max_total":null},
       {"id":2,"name":"Festschrift","text":"","price":"10.00","variants":[],"variant_label":"",
        "max_per_member":null,"max_total":50,"left":12}]}
    """#

    func testListeLesen() throws {
        let l = try JSONDecoder().decode(OrderCampaignList.self, from: Data(list.utf8))
        XCTAssertEqual(l.campaigns.count, 2)
        XCTAssertEqual(l.openCount, 1)
        XCTAssertEqual(l.summary, "1 offen, jetzt bestellen")
        XCTAssertEqual(OrderCampaignList().summary, "Gerade keine Sammelbestellung")
        XCTAssertEqual(l.campaigns[0].line, "Musikverein Musterdorf · Bestellen bis 30.06.2099")
        XCTAssertEqual(l.campaigns[1].line, "Musikverein Musterdorf · Bestellfrist vorbei (31.01.2099) · Der Verein bezahlt")
        XCTAssertFalse(l.campaigns[1].showPrices)
        let own = try XCTUnwrap(l.campaigns[1].order)
        XCTAssertTrue(own.handedOut)
        XCTAssertEqual(own.linesText, "1 × Jacke (50)")
        XCTAssertEqual(own.values, ["1|50": 1])
        Texte.language = "en"
        XCTAssertEqual(OrderCampaignList().summary, "No group order at the moment")
    }

    func testBestellungZusammenstellen() throws {
        let c = try JSONDecoder().decode(OrderCampaign.self, from: Data(detail.utf8))
        XCTAssertTrue(c.canOrder)
        XCTAssertEqual(c.articles[0].limitText, "höchstens 3 je Mitglied")
        XCTAssertEqual(c.articles[1].limitText, "noch 12 von 50 verfügbar")
        XCTAssertEqual(c.articles[1].choices, [""])
        let values = [orderKey(1, "M"): 2, orderKey(1, "L"): 0, orderKey(2, ""): 1]
        let inputs = orderInputs(c.articles, values)
        XCTAssertEqual(inputs, [OrderInput(article: 1, variant: "M", quantity: 2), OrderInput(article: 2, variant: "", quantity: 1)])
        XCTAssertEqual(orderTotal(c.articles, inputs), "60.00")
        // Größenabfrage ohne Preis: keine Summe
        var free = c.articles
        for i in free.indices { free[i].price = nil }
        XCTAssertNil(orderTotal(free, inputs))
        let payload = orderPayload(inputs, note: "  Name: Kim  ")
        XCTAssertEqual(payload["note"] as? String, "Name: Kim")
        XCTAssertEqual((payload["lines"] as? [[String: Any]])?.count, 2)
    }

    func testIchZeigtBestellungenNurMitModul() throws {
        let on = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV","orders_enabled":true,"orders_open":2}"#.utf8))
        XCTAssertTrue(on.hasOrders)
        XCTAssertEqual(on.ordersOpen, 2)
        let off = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV"}"#.utf8))
        XCTAssertFalse(off.hasOrders)
    }
}
