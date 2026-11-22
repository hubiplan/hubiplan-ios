import HubiplanKern
import SwiftUI

/// Zeile mit Symbol, die anruft, eine E-Mail beginnt oder die Karten öffnet.
private struct KontaktVerweis: View {
    let symbol: String
    let text: String
    let link: String

    var body: some View {
        if let url = URL(string: link) {
            Link(destination: url) { Label(text, systemImage: symbol) }
        } else {
            Label(text, systemImage: symbol)
        }
    }
}

private func telefonLink(_ phone: String) -> String { "tel:" + phone.filter { $0.isNumber || $0 == "+" } }

private func kartenLink(_ address: String) -> String {
    "maps://?q=" + (address.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
}

/// Geschäftspartner nachschlagen: Suche, Liste und Akte mit Anrufen und E-Mail.
struct GeschaeftspartnerView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var search = ""
    @State private var rows: [PartnerItem]?
    @State private var demoShown = false
    @State private var shown: Int?

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let rows {
                    Section {
                        if rows.isEmpty {
                            Text(tr("Keine Geschäftspartner gefunden.")).foregroundStyle(.secondary)
                        }
                        ForEach(rows) { partner in
                            NavigationLink {
                                GeschaeftspartnerAkte(partner: partner)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(partner.name)
                                    if !partner.listDetail.isEmpty {
                                        Text(partner.listDetail).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        if !rows.isEmpty { Text(trn("1 Geschäftspartner", "{n} Geschäftspartner", rows.count)) }
                    } footer: {
                        Text(tr("Geschäftspartner anlegen und ändern geht im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: tr("Name, Ort oder Ansprechpartner"))
            .task(id: search) {
                // Beim Tippen kurz warten, damit nicht jeder Buchstabe eine Anfrage auslöst
                if rows != nil { try? await Task.sleep(for: .milliseconds(350)) }
                if !Task.isCancelled { await load() }
            }
            .navigationDestination(item: $shown) { id in
                if let partner = rows?.first(where: { $0.id == id }) { GeschaeftspartnerAkte(partner: partner) }
            }
        }
        .navigationTitle(tr("Geschäftspartner"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let text = search
        guard let result = await model.verwaltung(unit, { try await $0.partners(search: text) }), text == search else { return }
        rows = result
        // Vorführmodus: für das Bildschirmfoto gleich in eine Akte
        if Demo.active, Demo.section == "partner", !demoShown {
            demoShown = true
            shown = result.first?.id
        }
    }
}

/// Akte eines Geschäftspartners (nur lesen).
private struct GeschaeftspartnerAkte: View {
    let partner: PartnerItem

    var body: some View {
        List {
            Section {
                Text(partner.name).font(.hubi(.title3).weight(.semibold))
                if !partner.headline.isEmpty { Text(partner.headline).foregroundStyle(Color.secondary) }
            }
            let details = partner.details
            if !details.phone.isEmpty || !details.email.isEmpty || !details.address.isEmpty {
                Section(tr("Kontakt")) {
                    if !details.phone.isEmpty { KontaktVerweis(symbol: "phone", text: details.phone, link: telefonLink(details.phone)) }
                    if !details.email.isEmpty { KontaktVerweis(symbol: "envelope", text: details.email, link: "mailto:" + details.email) }
                    if !details.address.isEmpty { KontaktVerweis(symbol: "mappin.and.ellipse", text: details.address, link: kartenLink(details.address)) }
                }
            }
            if !partner.contacts.isEmpty {
                Section(tr("Ansprechpartner")) {
                    ForEach(partner.contacts) { contact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.fullName.isEmpty ? contact.lastName : contact.fullName)
                            if !contact.info.isEmpty {
                                Text(contact.info).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                            }
                        }
                        if !contact.phone.isEmpty { KontaktVerweis(symbol: "phone", text: contact.phone, link: telefonLink(contact.phone)) }
                        if !contact.email.isEmpty { KontaktVerweis(symbol: "envelope", text: contact.email, link: "mailto:" + contact.email) }
                    }
                }
            }
            if !partner.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section(tr("Notizen")) { Text(partner.notes) }
            }
        }
        .navigationTitle(tr("Partnerakte"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Qualifikationen: Nachweise, die bald ablaufen, oder alle; führt in die Mitgliedsakte.
struct QualifikationenView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var soonOnly = true
    @State private var rows: [QualificationRow]?

    var body: some View {
        VerwaltungSchutz {
            List {
                Picker(tr("Stand"), selection: $soonOnly) {
                    Text(tr("Läuft bald ab")).tag(true)
                    Text(tr("Alle")).tag(false)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                VerwaltungMeldung { await load() }
                if let rows {
                    Section {
                        if rows.isEmpty {
                            Text(soonOnly ? tr("Kein Nachweis läuft bald ab.") : tr("Noch keine Nachweise.")).foregroundStyle(.secondary)
                        }
                        ForEach(rows) { row in
                            NavigationLink {
                                MitgliedView(unit: unit, id: row.member)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                    Text(row.detail).font(.hubi(.footnote)).foregroundStyle(row.urgent ? Color.fehlerText : Color.secondary)
                                }
                            }
                        }
                    } header: {
                        if !rows.isEmpty { Text(trn("1 Nachweis", "{n} Nachweise", rows.count)) }
                    } footer: {
                        Text(tr("Nachweise eintragen und ändern geht im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task(id: soonOnly) { await load() }
        }
        .navigationTitle(tr("Qualifikationen"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        let filter = soonOnly
        guard let result = await model.verwaltung(unit, { try await $0.qualifications(soonOnly: filter) }), filter == soonOnly else { return }
        rows = result
    }
}

/// Fristen: Pflichten des Fristenkalenders, überfällige zuerst (nur lesen).
struct FristenView: View {
    @EnvironmentObject private var model: AppModel
    let unit: AdminUnit
    @State private var rows: [ObligationItem]?
    @State private var demoShown = false
    @State private var shown: Int?

    var body: some View {
        VerwaltungSchutz {
            List {
                VerwaltungMeldung { await load() }
                if let rows {
                    Section {
                        if rows.isEmpty {
                            Text(tr("Noch keine Pflichten eingetragen.")).foregroundStyle(.secondary)
                        }
                        ForEach(rows) { item in
                            NavigationLink {
                                FristSeite(item: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    Text(item.line).font(.hubi(.footnote)).foregroundStyle(item.urgent ? Color.fehlerText : Color.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text(tr("Pflichten anlegen und als erledigt eintragen geht im Browser."))
                    }
                } else if model.adminError == nil {
                    Laedt()
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .navigationDestination(item: $shown) { id in
                if let item = rows?.first(where: { $0.id == id }) { FristSeite(item: item) }
            }
        }
        .navigationTitle(tr("Fristen"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        guard let result = await model.verwaltung(unit, { try await $0.obligations() }) else { return }
        rows = result
        // Vorführmodus: für das Bildschirmfoto gleich in eine Pflicht
        if Demo.active, Demo.section == "frist", !demoShown {
            demoShown = true
            shown = result.first?.id
        }
    }
}

/// Eine Pflicht mit Verlauf (nur lesen).
private struct FristSeite: View {
    let item: ObligationItem

    var body: some View {
        List {
            Section {
                Text(item.title).font(.hubi(.title3).weight(.semibold))
                Text(item.line).foregroundStyle(item.urgent ? Color.fehlerText : Color.primary)
                if let text = item.repeatText {
                    Text(text).font(.hubi(.footnote)).foregroundStyle(Color.secondary)
                }
                if !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(item.note) }
            }
            if !item.history.isEmpty {
                Section(tr("Verlauf")) {
                    ForEach(item.history) { Text($0.line).font(.hubi(.footnote)) }
                }
            }
        }
        .navigationTitle(tr("Pflicht"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
