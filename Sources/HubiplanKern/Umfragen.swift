import Foundation

// Umfragen und Meinungsbilder im Mitgliederbereich (`/api/portal/<Zugang>/surveys/`),
// Beschreibung in hubiplan/docs/umfragen.md. Verhalten wie in der Android-App (Ich › Umfragen).
// Nichts davon wird auf dem Gerät gespeichert.

/// Eigene Antwort je Frage, wie sie der Server liefert und annimmt.
public struct SurveyAnswerRow: Decodable, Equatable, Sendable {
    public var question: Int
    public var options: [Int]?
    public var value: String?
    public var dates: [String: String]?
    public var quantities: [String: Int]?
    public var text: String?

    public init(question: Int, options: [Int]? = nil, value: String? = nil, dates: [String: String]? = nil,
                quantities: [String: Int]? = nil, text: String? = nil) {
        self.question = question
        self.options = options
        self.value = value
        self.dates = dates
        self.quantities = quantities
        self.text = text
    }
}

public struct SurveyOption: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var label: String
    public var startsAt: String?
    public var endsAt: String?
    public var allDay: Bool
    public var capacity: Int?

    enum CodingKeys: String, CodingKey {
        case id, label, capacity
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        capacity = try c.decodeIfPresent(Int.self, forKey: .capacity)
    }
}

public struct SurveyQuestion: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    /// single, multiple, yesno, dates, quantity, text
    public var kind: String
    public var text: String
    public var required: Bool
    public var maxChoices: Int?
    public var allowMaybe: Bool
    public var options: [SurveyOption]
    /// Mengenauswahl: höchstens so viele Stück zusammen (am Termin 1 + Begleitpersonen)
    public var maxTotal: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, text, required, options
        case maxChoices = "max_choices"
        case allowMaybe = "allow_maybe"
        case maxTotal = "max_total"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        maxChoices = try c.decodeIfPresent(Int.self, forKey: .maxChoices)
        allowMaybe = try c.decodeIfPresent(Bool.self, forKey: .allowMaybe) ?? false
        options = try c.decodeIfPresent([SurveyOption].self, forKey: .options) ?? []
        maxTotal = try c.decodeIfPresent(Int.self, forKey: .maxTotal)
    }

    public var quantityLimit: Int { maxTotal ?? maxChoices ?? 1 }

    /// Startwert im Formular: eigene Antwort, bei Terminfindung jeder Vorschlag „Nein“.
    public func initialRow(_ mine: [SurveyAnswerRow]?) -> SurveyAnswerRow {
        var row = mine?.first { $0.question == id } ?? SurveyAnswerRow(question: id)
        if kind == "dates" && row.dates == nil {
            row.dates = Dictionary(uniqueKeysWithValues: options.map { (String($0.id), "no") })
        }
        return row
    }

    /// Ist die Frage beantwortet? Leere freiwillige Fragen gehen nicht mit.
    public func filled(_ row: SurveyAnswerRow) -> Bool {
        switch kind {
        case "single", "multiple": return !(row.options ?? []).isEmpty
        case "yesno": return !(row.value ?? "").isEmpty
        case "dates": return row.dates != nil
        case "quantity": return (row.quantities ?? [:]).values.contains { $0 > 0 }
        default: return !(row.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct SurveyEventRef: Decodable, Equatable, Sendable {
    public var id: Int
    public var title: String

    enum CodingKeys: String, CodingKey { case id, title }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    }
}

/// Termin, der aus einer Terminfindung entstanden ist („Zusage übernehmen“).
public struct SurveyFollowEvent: Decodable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var startsAt: String?
    public var rsvpEnabled: Bool
    public var saidYes: Bool
    public var response: String?

    enum CodingKeys: String, CodingKey {
        case id, title, response
        case startsAt = "starts_at"
        case rsvpEnabled = "rsvp_enabled"
        case saidYes = "said_yes"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt)
        rsvpEnabled = try c.decodeIfPresent(Bool.self, forKey: .rsvpEnabled) ?? false
        saidYes = try c.decodeIfPresent(Bool.self, forKey: .saidYes) ?? false
        response = try c.decodeIfPresent(String.self, forKey: .response)
    }

    public var start: Date? { startsAt.flatMap(Zeit.parse) }
}

public struct SurveyResultOption: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var label: String
    public var startsAt: String?
    public var endsAt: String?
    public var allDay: Bool
    public var capacity: Int?
    public var count: Int
    public var maybe: Int
    public var names: [String]

    enum CodingKeys: String, CodingKey {
        case id, label, capacity, count, maybe, names
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        capacity = try c.decodeIfPresent(Int.self, forKey: .capacity)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        maybe = try c.decodeIfPresent(Int.self, forKey: .maybe) ?? 0
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
    }
}

public struct SurveyResultValue: Decodable, Equatable, Sendable {
    public var count: Int
    public var names: [String]

    enum CodingKeys: String, CodingKey { case count, names }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
    }
}

public struct SurveyResultText: Decodable, Equatable, Sendable {
    public var text: String
    public var name: String

    enum CodingKeys: String, CodingKey { case text, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

public struct SurveyResultQuestion: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var kind: String
    public var text: String
    public var options: [SurveyResultOption]?
    public var values: [String: SurveyResultValue]?
    public var texts: [SurveyResultText]?
    public var best: [Int]

    enum CodingKeys: String, CodingKey { case id, kind, text, options, values, texts, best }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        options = try c.decodeIfPresent([SurveyResultOption].self, forKey: .options)
        values = try c.decodeIfPresent([String: SurveyResultValue].self, forKey: .values)
        texts = try c.decodeIfPresent([SurveyResultText].self, forKey: .texts)
        best = try c.decodeIfPresent([Int].self, forKey: .best) ?? []
    }
}

public struct SurveyResult: Decodable, Equatable, Sendable {
    public var participants: Int
    /// Anonym und noch keine fünf Antworten: nur die Zahl
    public var hidden: Bool
    public var questions: [SurveyResultQuestion]

    enum CodingKeys: String, CodingKey { case participants, hidden, questions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        participants = try c.decodeIfPresent(Int.self, forKey: .participants) ?? 0
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        questions = try c.decodeIfPresent([SurveyResultQuestion].self, forKey: .questions) ?? []
    }
}

public struct MemberSurvey: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var description: String
    public var unit: String
    public var event: SurveyEventRef?
    /// "open" oder "closed"
    public var status: String
    public var closesAt: String?
    public var anonymous: Bool
    public var resultsMode: String
    public var answered: Bool
    public var canAnswer: Bool
    public var canChange: Bool
    public var mine: [SurveyAnswerRow]?
    public var questions: [SurveyQuestion]
    public var results: SurveyResult?
    public var followEvent: SurveyFollowEvent?

    enum CodingKeys: String, CodingKey {
        case id, title, description, unit, event, status, anonymous, answered, mine, questions, results
        case closesAt = "closes_at"
        case resultsMode = "results_mode"
        case canAnswer = "can_answer"
        case canChange = "can_change"
        case followEvent = "follow_event"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        event = try c.decodeIfPresent(SurveyEventRef.self, forKey: .event)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        closesAt = try c.decodeIfPresent(String.self, forKey: .closesAt)
        anonymous = try c.decodeIfPresent(Bool.self, forKey: .anonymous) ?? false
        resultsMode = try c.decodeIfPresent(String.self, forKey: .resultsMode) ?? "after_answer"
        answered = try c.decodeIfPresent(Bool.self, forKey: .answered) ?? false
        canAnswer = try c.decodeIfPresent(Bool.self, forKey: .canAnswer) ?? false
        canChange = try c.decodeIfPresent(Bool.self, forKey: .canChange) ?? false
        mine = try c.decodeIfPresent([SurveyAnswerRow].self, forKey: .mine)
        questions = try c.decodeIfPresent([SurveyQuestion].self, forKey: .questions) ?? []
        results = try c.decodeIfPresent(SurveyResult.self, forKey: .results)
        followEvent = try c.decodeIfPresent(SurveyFollowEvent.self, forKey: .followEvent)
    }

    public var isOpen: Bool { status == "open" }

    /// Wartet noch auf die eigene Antwort.
    public var waiting: Bool { isOpen && canAnswer && !answered }

    /// „Zusage übernehmen“: Termin aus der Terminfindung, selbst „Ja“ gesagt, noch nicht zugesagt.
    public var canFollow: Bool {
        guard let event = followEvent else { return false }
        return event.saidYes && event.rsvpEnabled && event.response != "yes"
    }

    public func initialDraft() -> [Int: SurveyAnswerRow] {
        Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0.initialRow(mine)) })
    }

    /// Darf abgeschickt werden? Pflichtfragen beantwortet, Mengen und Mehrfachauswahl im Rahmen.
    public func ready(_ draft: [Int: SurveyAnswerRow]) -> Bool {
        questions.allSatisfy { q in
            let row = draft[q.id] ?? SurveyAnswerRow(question: q.id)
            if q.required && !q.filled(row) { return false }
            if q.kind == "quantity" && (row.quantities ?? [:]).values.reduce(0, +) > q.quantityLimit { return false }
            if q.kind == "multiple", let max = q.maxChoices, (row.options ?? []).count > max { return false }
            return true
        }
    }

    /// Nutzlast für POST …/answer/: nur beantwortete Fragen, je Frageart nur das passende Feld.
    public func answerPayload(_ draft: [Int: SurveyAnswerRow]) -> [String: Any] {
        var rows: [[String: Any]] = []
        for q in questions {
            guard let row = draft[q.id], q.filled(row) else { continue }
            var item: [String: Any] = ["question": q.id]
            switch q.kind {
            case "single", "multiple": item["options"] = row.options ?? []
            case "yesno": item["value"] = row.value ?? ""
            case "dates": item["dates"] = row.dates ?? [:]
            case "quantity": item["quantities"] = (row.quantities ?? [:]).filter { $0.value > 0 }
            default: item["text"] = (row.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            rows.append(item)
        }
        return ["answers": rows]
    }
}

public struct SurveyList: Decodable, Equatable, Sendable {
    public var surveys: [MemberSurvey]

    enum CodingKeys: String, CodingKey { case surveys }

    public init(surveys: [MemberSurvey] = []) { self.surveys = surveys }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surveys = try c.decodeIfPresent([MemberSurvey].self, forKey: .surveys) ?? []
    }

    public var waitingCount: Int { surveys.filter(\.waiting).count }

    /// Kurzstand neben „Umfragen“ unter „Ich“.
    public var summary: String {
        let waiting = waitingCount
        if waiting > 0 { return trn("1 wartet auf dich", "{n} warten auf dich", waiting) }
        if surveys.contains(where: \.isOpen) { return tr("alle beantwortet") }
        return tr("Keine offenen Umfragen")
    }
}

/// Ja/Nein/Vielleicht/Enthaltung wie im Browser.
public func surveyValueLabel(_ value: String) -> String {
    switch value {
    case "yes": return tr("Ja")
    case "no": return tr("Nein")
    case "maybe": return tr("Vielleicht")
    default: return tr("Enthaltung")
    }
}

extension PortalAccess {
    /// „Umfragen“ unter „Ich“
    public var hasSurveys: Bool { has(module: "surveys", fallback: surveysEnabled) }
}

extension Api {
    public func memberSurveys(accessId: Int) async throws -> SurveyList {
        try await expect("GET", "/api/portal/\(accessId)/surveys/")
    }

    public func answerSurvey(accessId: Int, surveyId: Int, payload: [String: Any]) async throws -> MemberSurvey {
        try await expect("POST", "/api/portal/\(accessId)/surveys/\(surveyId)/answer/", json: payload)
    }

    public func withdrawSurvey(accessId: Int, surveyId: Int) async throws -> MemberSurvey {
        try await expect("DELETE", "/api/portal/\(accessId)/surveys/\(surveyId)/answer/")
    }

    public func followSurvey(accessId: Int, surveyId: Int) async throws -> MemberSurvey {
        try await expect("POST", "/api/portal/\(accessId)/surveys/\(surveyId)/follow/", json: [:])
    }
}
