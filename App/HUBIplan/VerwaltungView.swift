import HubiplanKern
import SwiftUI

/// Verwaltung für Vorstand und Zugführung: freischalten, entsperren, offene Punkte, Mitglieder.
/// Erreichbar über „Ich“. Der Inhalt ist nur sichtbar, solange der Vorstandsschlüssel offen ist.
struct VerwaltungView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var unitKey: String?

    var body: some View {
        Group {
            if let overview = model.adminOverview, !overview.allUnits.isEmpty {
                if !overview.twoFactor {
                    VerwaltungHinweis(
                        text: tr("Für die Verwaltung in der App ist die Zwei-Faktor-Anmeldung nötig. Bitte im Browser unter „Mein Konto › Anmeldung & Sicherheit“ einrichten, danach hier freischalten."),
                        action: tr("Mein Konto öffnen")
                    ) {
                        if let server = model.account?.server, let url = URL(string: server + "/mein-konto/anmeldung") { openURL(url) }
                    }
                } else if !model.adminSealed {
                    Freischalten()
                } else {
                    VerwaltungSchutz {
                        VerwaltungStart(units: overview.allUnits, until: overview.until, unitKey: $unitKey)
                    }
                }
            } else {
                VerwaltungHinweis(
                    text: tr("Die Verwaltung ist gerade nicht verfügbar. Bitte Verbindung und Berechtigung prüfen."),
                    action: tr("Erneut laden")
                ) {
                    Task { await model.loadAdmin() }
                }
            }
        }
        .navigationTitle(tr("Verwaltung"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Auch bei offener Ansicht nach fünf Minuten Pause sperren
            while !Task.isCancelled {
                model.checkAdminIdle()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}

private struct VerwaltungHinweis: View {
    let text: String
    let action: String
    let run: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                Button(action, action: run).buttonStyle(.bordered)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

/// Zeigt den Inhalt nur bei offenem Vorstandsschlüssel, sonst die Bitte zu entsperren.
/// Im App-Umschalter und bei inaktiver App ist der Inhalt verdeckt.
struct VerwaltungSchutz<Inhalt: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    @ViewBuilder let inhalt: () -> Inhalt

    var body: some View {
        if model.adminOpen {
            inhalt()
                .simultaneousGesture(TapGesture().onEnded { model.adminTouched() })
                .overlay {
                    if phase != .active && !Demo.active {
                        ZStack {
                            Color(.systemBackground)
                            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Color.secondary)
                        }
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    }
                }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Zum Öffnen mit Face ID, Touch ID oder Gerätecode entsperren."))
                    if let message = model.adminError { Text(message).foregroundStyle(.red) }
                    Button(tr("Entsperren")) { Task { await model.openAdmin() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.adminBusy || !model.adminSealed)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .task { await model.openAdmin() }
        }
    }
}

private struct Freischalten: View {
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @State private var code = ""

    var body: some View {
        Form {
            Section {
                SecureField(tr("Passwort"), text: $password)
                    .textContentType(.password)
                TextField(tr("Code aus der Authenticator-App"), text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: code) { _, value in
                        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(8))
                        if digits != value { code = digits }
                    }
            } header: {
                Text(tr("Verwaltung freischalten"))
            } footer: {
                Text(tr("Für Mitglieder und offene Punkte in der App bitte mit Passwort und Zwei-Faktor-Code bestätigen. Die Freischaltung gilt 30 Tage auf diesem iPhone; geöffnet wird jedes Mal mit Face ID, Touch ID oder Gerätecode."))
            }
            if let message = model.adminError {
                Section { Text(message).foregroundStyle(.red) }
            }
            if !Demo.active && !VerwaltungTresor.deviceLock {
                Section {
                    Text(tr("Für die Verwaltung braucht das iPhone einen Gerätecode. Bitte in den Einstellungen einrichten."))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    let entered = (password, code)
                    password = ""
                    code = ""
                    Task { await model.unlockAdmin(password: entered.0, code: entered.1) }
                } label: {
                    if model.adminBusy { ProgressView() } else { Text(tr("Freischalten")) }
                }
                .disabled(model.adminBusy || password.isEmpty || code.count < 6)
            }
        }
    }
}

private struct VerwaltungStart: View {
    @EnvironmentObject private var model: AppModel
    let units: [AdminUnit]
    let until: String?
    @Binding var unitKey: String?
    @State private var open: Int?
    @State private var confirmLock = false
    /// Vorführmodus: für das Bildschirmfoto gleich in die Mitglieder
    @State private var showMembers = Demo.active && ["mitglieder", "mitglied"].contains(Demo.section)

    private var unit: AdminUnit { units.first { $0.key == unitKey } ?? units[0] }

    var body: some View {
        List {
            if let message = model.adminError {
                Section { Text(message).foregroundStyle(.red) }
            }
            Section {
                if units.count > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Verwaltete Einheit")).font(.caption).foregroundStyle(Color.secondary)
                        Picker(tr("Verwaltete Einheit"), selection: Binding(get: { unit.key }, set: { unitKey = $0 })) {
                            ForEach(units, id: \.key) { Text($0.name).tag($0.key) }
                        }
                        .labelsHidden()
                        .padding(.leading, -12)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Verwaltete Einheit")).font(.caption).foregroundStyle(Color.secondary)
                        Text(unit.name)
                    }
                }
            }
            Section {
                if unit.sections.isEmpty {
                    Text(tr("Für deine Rolle gibt es in dieser Fassung der App noch keinen Bereich. Bitte nutze den Browser."))
                        .foregroundStyle(.secondary)
                }
                if unit.sections.contains(.tasks) {
                    NavigationLink {
                        OffenePunkteView(unit: unit)
                    } label: {
                        Bereich(
                            symbol: "tray.full",
                            title: open.map { tr("Zu erledigen ({count})", ["count": $0]) } ?? tr("Zu erledigen"),
                            hint: tr("Datenänderungen, Fotos und Termine, die auf dich warten")
                        )
                    }
                }
                if unit.sections.contains(.members) {
                    NavigationLink {
                        MitgliederView(unit: unit)
                    } label: {
                        Bereich(symbol: "person.2", title: tr("Mitglieder"), hint: tr("Suchen, anrufen, Mitgliedsakte öffnen"))
                    }
                }
            } header: {
                Text(tr("Was möchtest du tun?"))
            } footer: {
                Text(tr("Termine, Kassenbuch, Rechnungen und alles Weitere verwaltest du zurzeit im Browser."))
            }
            Section {
                Button(tr("Verwaltung auf diesem iPhone sperren"), role: .destructive) { confirmLock = true }
            } footer: {
                if let until, let date = Zeit.parse(until) {
                    Text(tr("Freigeschaltet bis {datum}", [
                        "datum": date.formatted(.dateTime.day().month().year().locale(Locale(identifier: Texte.language))),
                    ]))
                }
            }
        }
        .navigationDestination(isPresented: $showMembers) { MitgliederView(unit: unit) }
        .refreshable { await load() }
        .task(id: unit.key) { await load() }
        .confirmationDialog(
            tr("Danach musst du die Verwaltung mit Passwort und Zwei-Faktor-Code neu freischalten."),
            isPresented: $confirmLock, titleVisibility: .visible
        ) {
            Button(tr("Verwaltung sperren"), role: .destructive) { Task { await model.lockAdmin() } }
            Button(tr("Abbrechen"), role: .cancel) {}
        }
    }

    private func load() async {
        open = nil
        guard unit.sections.contains(.tasks) else { return }
        open = await model.verwaltung(unit) { try await $0.tasks().count }
    }
}

private struct Bereich: View {
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(hint).font(.footnote).foregroundStyle(Color.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }
}

/// Offene Punkte der Einheit wie auf der Startseite im Browser (nur lesen).
struct OffenePunkteView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var tasks: [AdminTask]?

    var body: some View {
        VerwaltungSchutz {
            List {
                if let message = model.adminError {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button(tr("Erneut laden")) { Task { await load() } }
                    }
                }
                if let tasks {
                    if tasks.isEmpty {
                        Text(tr("Nichts zu erledigen.")).foregroundStyle(.secondary)
                    } else {
                        Section {
                            ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                                VStack(alignment: .leading, spacing: 2) {
                                    if !task.kindLabel.isEmpty {
                                        Text(task.kindLabel).font(.caption).foregroundStyle(Color.secondary)
                                    }
                                    Text(task.title)
                                    if !task.detail.isEmpty {
                                        Text(task.detail).font(.footnote).foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        } footer: {
                            Text(tr("Bearbeiten kannst du diese Punkte zurzeit im Browser."))
                        }
                    }
                } else if model.adminError == nil {
                    ProgressView()
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationTitle(tr("Zu erledigen"))
    }

    private func load() async {
        if let loaded = await model.verwaltung(unit, { try await $0.tasks() }) { tasks = loaded }
    }
}

/// Mitglieder der Einheit suchen und die Akte öffnen (nur lesen).
struct MitgliederView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var search = ""
    @State private var former = false
    @State private var rows: [MemberRow]?
    @State private var count = 0
    @State private var page = 1
    @State private var more = false
    /// Vorführmodus: für das Bildschirmfoto gleich in eine Akte
    @State private var shown: Int? = Demo.active && Demo.section == "mitglied" ? 1 : nil

    var body: some View {
        VerwaltungSchutz {
            List {
                Picker(tr("Stand"), selection: $former) {
                    Text(tr("Aktuelle")).tag(false)
                    Text(tr("Ehemalige")).tag(true)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                if let message = model.adminError {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button(tr("Erneut laden")) { Task { await load(reset: true) } }
                    }
                }
                if let rows {
                    Section {
                        if rows.isEmpty {
                            Text(tr("Keine Mitglieder gefunden.")).foregroundStyle(.secondary)
                        }
                        ForEach(rows) { row in
                            NavigationLink {
                                MitgliedView(unit: unit, id: row.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.listName)
                                    if !row.listDetail.isEmpty {
                                        Text(row.listDetail).font(.footnote).foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        }
                        if more {
                            Button(tr("Weitere laden")) { Task { await load(reset: false) } }
                        }
                    } header: {
                        Text(trn("1 Mitglied", "{n} Mitglieder", count))
                    }
                } else if model.adminError == nil {
                    ProgressView()
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: tr("Name oder Mitgliedsnummer"))
            .task(id: "\(search)|\(former)") {
                // Beim Tippen kurz warten, damit nicht jeder Buchstabe eine Anfrage auslöst
                if rows != nil { try? await Task.sleep(for: .milliseconds(350)) }
                if !Task.isCancelled { await load(reset: true) }
            }
            .navigationDestination(item: $shown) { MitgliedView(unit: unit, id: $0) }
        }
        .navigationTitle(tr("Mitglieder"))
    }

    private func load(reset: Bool) async {
        let wanted = reset ? 1 : page + 1
        let text = search
        let status = former ? "ehemalig" : "aktiv"
        guard let result = await model.verwaltung(unit, { try await $0.members(search: text, page: wanted, status: status) }) else { return }
        guard text == search, status == (former ? "ehemalig" : "aktiv") else { return }
        rows = reset ? result.results : (rows ?? []) + result.results
        count = result.count
        page = wanted
        more = result.hasMore
    }
}

/// Mitgliedsakte in Kurzform (nur lesen): Stammdaten, Zugehörigkeiten, Kontakt.
struct MitgliedView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    let id: Int
    @State private var member: MemberDetail?

    var body: some View {
        VerwaltungSchutz {
            List {
                if let message = model.adminError {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button(tr("Erneut laden")) { Task { await load() } }
                    }
                }
                if let member {
                    Section {
                        Text(member.name).font(.title3.weight(.semibold))
                        if member.isFormer { Text(tr("Ehemaliges Mitglied")).foregroundStyle(.secondary) }
                        zeile(tr("Mitgliedsart"), member.typeName)
                        zeile(tr("Mitgliedsnummer"), member.clubNumber)
                        if !member.isOrganization { zeile(tr("Geburtsdatum"), Zeit.plainDate(member.birthDate)) }
                        zeile(tr("Mitglied seit"), Zeit.plainDate(member.entryDate))
                        zeile(
                            tr("Untereinheiten"),
                            member.currentDepartments(today: Zeit.day(Date())).map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
                        )
                    }
                    if let contact = member.contact {
                        Section(tr("Kontakt")) {
                            if !contact.phone.isEmpty {
                                verweis("phone", contact.phone, "tel:" + contact.phone.filter { $0.isNumber || $0 == "+" })
                            }
                            if !contact.email.isEmpty {
                                verweis("envelope", contact.email, "mailto:" + contact.email)
                            }
                            zeile(tr("Anschrift"), contact.addressLines.joined(separator: "\n"))
                        }
                    }
                    Section {
                    } footer: {
                        Text(tr("Ändern kannst du die Akte zurzeit im Browser."))
                    }
                } else if model.adminError == nil {
                    ProgressView()
                }
            }
            .task { await load() }
        }
        .navigationTitle(tr("Mitgliedsakte"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func zeile(_ label: String, _ value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(Color.secondary)
                Text(value)
            }
        }
    }

    @ViewBuilder
    private func verweis(_ symbol: String, _ text: String, _ link: String) -> some View {
        if let url = URL(string: link) {
            Link(destination: url) { Label(text, systemImage: symbol) }
        } else {
            Label(text, systemImage: symbol)
        }
    }

    private func load() async {
        let wanted = id
        if let loaded = await model.verwaltung(unit, { try await $0.member(wanted) }) { member = loaded }
    }
}
