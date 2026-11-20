import XCTest
@testable import HubiplanKern

/// Termin aus einer geteilten Kalenderdatei (.ics) vorausfüllen; gleiche Fälle wie
/// `TerminAusKalenderdateiTest` der Android-App, alle Daten erfunden.
final class TerminAusDateiTests: XCTestCase {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    func testOutlookEinladungMitWindowsZoneUndTeamsLink() throws {
        let ics = [
            "BEGIN:VCALENDAR",
            "METHOD:REQUEST",
            "BEGIN:VTIMEZONE",
            "TZID:W. Europe Standard Time",
            "BEGIN:STANDARD",
            "DTSTART:16010101T030000",
            "END:STANDARD",
            "END:VTIMEZONE",
            "BEGIN:VEVENT",
            "SUMMARY;LANGUAGE=de-DE:Vorstandssitzung",
            "DTSTART;TZID=W. Europe Standard Time:20990305T193000",
            "DTEND;TZID=W. Europe Standard Time:20990305T213000",
            "LOCATION:Vereinsheim\\, Saal",
            "DESCRIPTION:Tagesordnung folgt.\\nTeilnehmen: https://teams.microsoft.com/l/",
            " meetup-join/abc123",
            "BEGIN:VALARM",
            "TRIGGER:-PT15M",
            "SUMMARY:Erinnerung",
            "END:VALARM",
            "END:VEVENT",
            "END:VCALENDAR",
        ].joined(separator: "\r\n")
        let t = try XCTUnwrap(IcsLeser.lesen(ics, timeZone: berlin))
        XCTAssertEqual(t.title, "Vorstandssitzung")
        XCTAssertEqual(t.day, "2099-03-05")
        XCTAssertEqual(t.start, "19:30")
        XCTAssertEqual(t.end, "21:30")
        XCTAssertFalse(t.allDay)
        XCTAssertEqual(t.location, "Vereinsheim, Saal")
        XCTAssertEqual(t.description, "Tagesordnung folgt.\nTeilnehmen: https://teams.microsoft.com/l/meetup-join/abc123")
        XCTAssertEqual(t.videoUrl, "https://teams.microsoft.com/l/meetup-join/abc123")
        XCTAssertFalse(t.repeats)
    }

    func testUtcZeitInDeutscheZeitUndConferenceVorrang() throws {
        let ics = [
            "BEGIN:VCALENDAR",
            "BEGIN:VEVENT",
            "SUMMARY:Sitzung",
            "DTSTART:20990701T170000Z",
            "DURATION:PT90M",
            "CONFERENCE;VALUE=URI;FEATURE=VIDEO:https://cloud.example.org/call/k3x9",
            "DESCRIPTION:Alternativ https://meet.jit.si/Verein",
            "RRULE:FREQ=MONTHLY;COUNT=3",
            "END:VEVENT",
            "END:VCALENDAR",
        ].joined(separator: "\n")
        let t = try XCTUnwrap(IcsLeser.lesen(ics, timeZone: berlin))
        XCTAssertEqual(t.start, "19:00")
        XCTAssertEqual(t.end, "20:30")
        XCTAssertEqual(t.videoUrl, "https://cloud.example.org/call/k3x9")
        XCTAssertTrue(t.repeats)
    }

    func testGanztaegig() throws {
        let ics = "BEGIN:VEVENT\r\nSUMMARY:Arbeitseinsatz\r\nDTSTART;VALUE=DATE:20990307\r\nDTEND;VALUE=DATE:20990308\r\nEND:VEVENT\r\n"
        let t = try XCTUnwrap(IcsLeser.lesen(ics, timeZone: berlin))
        XCTAssertTrue(t.allDay)
        XCTAssertEqual(t.day, "2099-03-07")
        XCTAssertEqual(t.start, "")
        XCTAssertEqual(t.end, "")
        XCTAssertEqual(t.videoUrl, "")
        let date = try XCTUnwrap(t.dayDate(timeZone: berlin))
        XCTAssertEqual(Zeit.day(date, timeZone: berlin), "2099-03-07")
    }

    func testMehrtaegigOhneEndzeit() throws {
        let ics = "BEGIN:VEVENT\nSUMMARY:Ausflug\nDTSTART;TZID=Europe/Berlin:20990310T180000\nDTEND;TZID=Europe/Berlin:20990311T120000\nEND:VEVENT"
        let t = try XCTUnwrap(IcsLeser.lesen(ics, timeZone: berlin))
        XCTAssertEqual(t.start, "18:00")
        XCTAssertEqual(t.end, "")
    }

    func testAbsageUndUnbrauchbaresGebenNil() {
        XCTAssertNil(IcsLeser.lesen("BEGIN:VCALENDAR\nMETHOD:CANCEL\nBEGIN:VEVENT\nSUMMARY:X\nDTSTART:20990101T100000Z\nEND:VEVENT\nEND:VCALENDAR", timeZone: berlin))
        XCTAssertNil(IcsLeser.lesen("BEGIN:VEVENT\nSUMMARY:X\nSTATUS:CANCELLED\nDTSTART:20990101T100000Z\nEND:VEVENT", timeZone: berlin))
        XCTAssertNil(IcsLeser.lesen("BEGIN:VEVENT\nDTSTART:20990101T100000Z\nEND:VEVENT", timeZone: berlin))
        XCTAssertNil(IcsLeser.lesen("BEGIN:VEVENT\nSUMMARY:Ohne Beginn\nEND:VEVENT", timeZone: berlin))
        XCTAssertNil(IcsLeser.lesen("keine Kalenderdatei", timeZone: berlin))
    }

    func testVideolinkImOrt() {
        XCTAssertEqual(IcsLeser.videoLink("Online (https://zoom.us/j/123456)."), "https://zoom.us/j/123456")
        XCTAssertNil(IcsLeser.videoLink("https://www.example.org/anfahrt"))
    }

    func testVorlageFuerNeuenTerminSendetVideolink() throws {
        let ics = "BEGIN:VEVENT\nSUMMARY:Sitzung\nDTSTART;TZID=Europe/Berlin:20990310T180000\nLOCATION:https://cloud.example.org/call/ab12\nEND:VEVENT"
        let draft = try XCTUnwrap(IcsLeser.lesen(ics, timeZone: berlin)).draft
        XCTAssertEqual(draft.start, "18:00")
        let body = try XCTUnwrap(draft.body(rsvpAllowed: true, timeZone: berlin))
        XCTAssertEqual(body["video_url"] as? String, "https://cloud.example.org/call/ab12")
        XCTAssertNil(EventDraft().body(rsvpAllowed: true, timeZone: berlin)?["video_url"])
    }
}
