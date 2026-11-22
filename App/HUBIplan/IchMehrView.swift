import HubiplanKern
import PassKit
import SwiftUI

// Weitere Teile von „Ich“ wie in der Android-App: Lastschrift, Ergebnisse und Ranglisten,
// Mitarbeiter einer Organisation und der Ausweis in Apple Wallet.

/// Lastschriftmandat unter den Rechnungen; ändern geht im Browser.
struct MeinMandat: View {
    let state: MandateState

    var body: some View {
        if state.shown {
            IchAbschnitt(title: tr("Lastschrift")) {
                if let mandate = state.mandate {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(mandate.lines, id: \.self) { Text($0).font(.hubi(.footnote)) }
                    }
                    .accessibilityElement(children: .combine)
                    if !state.creditorId.isEmpty {
                        Text(tr("Gläubiger-ID von {club}: {x1}", ["club": state.clubName, "x1": state.creditorId]))
                            .font(.hubi(.footnote)).foregroundStyle(.secondary)
                    }
                    Text(tr("Ändern oder widerrufen geht im Browser unter „Mein Bereich › Rechnungen“."))
                        .font(.hubi(.footnote)).foregroundStyle(.secondary)
                } else {
                    Text(tr("Du hast kein Lastschriftmandat erteilt. Das geht im Browser unter „Mein Bereich › Rechnungen“."))
                        .font(.hubi(.footnote))
                }
            }
        }
    }
}

/// „Ich“ › Ergebnisse: eigene Starts und Titel, darunter die Ranglisten wie auf der Webseite.
struct ErgebnisseView: View {
    @EnvironmentObject private var model: AppModel
    @State private var results: MyResults?
    @State private var rankings: Rankings?
    @State private var entries: [MyEntry]?
    @State private var error: String?
    @State private var all = false
    @State private var open: String?

    var body: some View {
        List {
            if let error {
                Section {
                    MeldungText(error, .fehler)
                    Button(tr("Erneut versuchen")) { Task { await load() } }
                }
            }
            if model.access?.hasEntries == true {
                GemeldetAbschnitt(entries: entries)
            }
            if model.access?.hasResults != false {
            Section(tr("Meine Ergebnisse")) {
                if let results {
                    if results.isEmpty {
                        Text(tr("Noch keine Ergebnisse.")).foregroundStyle(.secondary)
                    }
                    if !results.grants.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Titel und Auszeichnungen")).font(.hubi(.subheadline).weight(.semibold)).accessibilityAddTraits(.isHeader)
                            ForEach(results.grants) { Text($0.line) }
                        }
                    }
                    ForEach(all ? results.starts : Array(results.starts.prefix(5))) { start in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(start.title).font(.hubi(.subheadline).weight(.semibold))
                            if !start.meta.isEmpty { Text(start.meta).font(.hubi(.footnote)).foregroundStyle(.secondary) }
                            ForEach(start.results.indices, id: \.self) { Text(start.results[$0].line) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if !all && results.starts.count > 5 {
                        Button(tr("Alle {size} Wettbewerbe zeigen", ["size": results.starts.count])) { all = true }
                    }
                } else if error == nil {
                    Laedt()
                }
            }
            }
            // Ohne veröffentlichte Wettbewerbe bleibt der Abschnitt weg
            if let rankings, !rankings.competitions.isEmpty {
                Section(tr("Ranglisten")) {
                    ForEach(rankings.competitions) { competition in
                        DisclosureGroup(
                            isExpanded: Binding(get: { open == competition.id }, set: { open = $0 ? competition.id : nil })
                        ) {
                            RanglisteView(id: competition.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(competition.title)
                                if !competition.line.isEmpty {
                                    Text(competition.line).font(.hubi(.footnote)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tr("Wettbewerbe"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: model.accessId) { await load() }
    }

    private func load() async {
        if model.access?.hasEntries == true {
            switch await model.portalCall({ api, access in try await api.myEntries(accessId: access) }) {
            case .success(let fresh): entries = fresh
            case .failure(let failure): error = failure.text
            case nil: return
            }
        }
        guard model.access?.hasResults != false else { return }
        switch await model.portalCall({ api, access in try await api.myResults(accessId: access) }) {
        case .success(let fresh):
            results = fresh
            error = nil
        case .failure(let failure):
            error = failure.text
        case nil:
            return
        }
        if case .success(let fresh) = await model.portalCall({ api, access in try await api.rankings(accessId: access) }) {
            rankings = fresh
        }
    }
}

/// Eine Rangliste; solange der Wettbewerb läuft, fragt sie wie die Webseite nach neuen Ständen.
private struct RanglisteView: View {
    @EnvironmentObject private var model: AppModel
    let id: String
    @State private var detail: RankingDetail?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error { MeldungText(error, .fehler) }
            if let detail {
                if !detail.final {
                    Text(detail.live ? tr("Läuft noch – der Stand aktualisiert sich selbst.") : tr("Vorläufiges Ergebnis"))
                        .font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
                ForEach(detail.titles.indices, id: \.self) { index in
                    Text("\(detail.titles[index].title): \(detail.titles[index].name)").bold()
                }
                if !detail.prizes.isEmpty {
                    Text(tr("Preise")).font(.hubi(.subheadline).weight(.semibold)).accessibilityAddTraits(.isHeader)
                    ForEach(detail.prizes.indices, id: \.self) { Text(detail.prizes[$0].line) }
                }
                ForEach(detail.scorings.indices, id: \.self) { index in
                    let scoring = detail.scorings[index]
                    Text(scoring.name).font(.hubi(.subheadline).weight(.semibold)).accessibilityAddTraits(.isHeader)
                    if scoring.rows.isEmpty {
                        Text(tr("Noch keine Ergebnisse.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                    }
                    ForEach(scoring.rows.indices, id: \.self) { row in
                        Text(scoring.rows[row].line).fontWeight(scoring.rows[row].prize ? .semibold : .regular)
                    }
                    if !scoring.complete {
                        Text(tr("Gezeigt werden die Preisplätze.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                    }
                }
            } else if error == nil {
                Laedt().font(.hubi(.footnote))
            }
        }
        .padding(.vertical, 4)
        .task(id: id) { await follow() }
    }

    /// Laden; live nur den kleinen Stand abfragen und bei Änderung neu laden.
    private func follow() async {
        switch await model.portalCall({ api, access in try await api.ranking(accessId: access, id: id) }) {
        case .success(let fresh): detail = fresh
        case .failure(let failure):
            error = failure.text
            return
        case nil: return
        }
        while let current = detail, let pause = current.pollEvery, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pause) * 1_000_000_000)
            guard case .success(let version) = await model.portalCall({ api, access in
                try await api.rankingVersion(accessId: access, id: id)
            }) else { continue }
            if version.version != current.version || version.final,
               case .success(let fresh) = await model.portalCall({ api, access in try await api.ranking(accessId: access, id: id) }) {
                detail = fresh
            }
        }
    }
}

/// „Ich“ › Mitarbeiter: Für wen die Organisation zahlt, und neue Mitarbeiter melden.
struct MitarbeiterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var data: CompanyOverview?
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Section {
                    MeldungText(error, .fehler)
                    Button(tr("Erneut versuchen")) { Task { await load() } }
                }
            }
            if let data {
                if data.companies.isEmpty {
                    Text(tr("Die Firma zahlt für niemanden.")).foregroundStyle(.secondary)
                }
                ForEach(data.companies) { company in
                    Section(company.name) {
                        if company.members.isEmpty {
                            Text(tr("Noch niemand.")).foregroundStyle(.secondary)
                        }
                        ForEach(company.members) { member in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                if !member.line.isEmpty { Text(member.line).font(.hubi(.footnote)).foregroundStyle(.secondary) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if data.canReport {
                            MitarbeiterMelden(company: company)
                        }
                    }
                }
                Section {
                    Text(tr("Die Zahlung für jemanden beenden geht im Browser.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
                }
            } else if error == nil {
                Laedt()
            }
        }
        .navigationTitle(tr("Mitarbeiter"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: model.accessId) { await load() }
    }

    private func load() async {
        switch await model.portalCall({ api, access in try await api.myCompanies(accessId: access) }) {
        case .success(let fresh):
            data = fresh
            error = nil
        case .failure(let failure): error = failure.text
        case nil: break
        }
    }
}

/// Neuen Mitarbeiter melden: Die Person bekommt eine Mail mit dem Link zum Online-Antrag.
private struct MitarbeiterMelden: View {
    @EnvironmentObject private var model: AppModel
    let company: CompanyEntry
    @State private var first = ""
    @State private var last = ""
    @State private var email = ""
    @State private var busy = false
    @State private var message: String?
    @State private var problem: String?

    private var ready: Bool {
        !first.trimmingCharacters(in: .whitespaces).isEmpty && !last.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Neuen Mitarbeiter melden")).font(.hubi(.subheadline).weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(tr("Die Person bekommt eine Mail mit dem Link zum Online-Antrag.")).font(.hubi(.footnote)).foregroundStyle(.secondary)
            TextField(tr("Vorname"), text: $first).textContentType(.givenName)
                .textInputAutocapitalization(.words).weiterFeld()
            TextField(tr("Nachname"), text: $last).textContentType(.familyName)
                .textInputAutocapitalization(.words).weiterFeld()
            TextField(tr("E-Mail"), text: $email)
                .submitLabel(.done)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if let problem { MeldungText(problem, .fehler) }
            if let message { MeldungText(message, .gut) }
            Button(busy ? tr("Wird gesendet …") : tr("Melden")) { Task { await report() } }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !ready)
        }
        .textFieldStyle(.roundedBorder)
        .padding(.vertical, 4)
    }

    private func report() async {
        busy = true
        problem = nil
        message = nil
        defer { busy = false }
        let to = email.trimmingCharacters(in: .whitespaces)
        let result = await model.portalCall { api, access in
            try await api.reportEmployee(
                accessId: access, company: company.id,
                firstName: first.trimmingCharacters(in: .whitespaces),
                lastName: last.trimmingCharacters(in: .whitespaces), email: to
            )
        }
        switch result {
        case .success:
            message = tr("Mail an {email} gesendet.", ["email": to])
            first = ""
            last = ""
            email = ""
        case .failure(let failure): problem = failure.text
        case nil: break
        }
    }
}

/// Ausweis zu Apple Wallet hinzufügen. Der Pass zeigt nur an; ob der Ausweis gilt, zeigt die
/// Prüfung des QR-Codes.
struct WalletKnopf: View {
    @EnvironmentObject private var model: AppModel
    @State private var pass: PKPass?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        if PKAddPassesViewController.canAddPasses() {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await load() }
                } label: {
                    Label(busy ? tr("Wird geladen …") : tr("Zu Apple Wallet hinzufügen"), systemImage: "wallet.pass")
                }
                .buttonStyle(.bordered)
                .disabled(busy)
                Text(tr("Der Wallet-Pass zeigt deinen Ausweis an. Ob er gilt, zeigt nur die Prüfung des QR-Codes."))
                    .font(.hubi(.footnote)).foregroundStyle(.secondary)
                if let error { MeldungText(error, .fehler).font(.hubi(.footnote)) }
            }
            .sheet(isPresented: Binding(get: { pass != nil }, set: { if !$0 { pass = nil } })) {
                if let pass { PassBlatt(pass: pass).ignoresSafeArea() }
            }
        }
    }

    private func load() async {
        busy = true
        error = nil
        defer { busy = false }
        switch await model.portalCall({ api, access in try await api.walletPass(accessId: access) }) {
        case .success(let data):
            do {
                pass = try PKPass(data: data)
            } catch {
                self.error = tr("Der Wallet-Pass ließ sich nicht öffnen.")
            }
        case .failure(let failure): error = failure.text
        case nil: break
        }
    }
}

/// Systemblatt „Zu Wallet hinzufügen“.
private struct PassBlatt: UIViewControllerRepresentable {
    let pass: PKPass

    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
