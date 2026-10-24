import QuotePilotCore
import SwiftUI

/// Clients: the list on the left, the selected client's details on the right.
struct ClientsView: View {
    @Bindable var model: AppModel

    /// The clients the list shows: all of them, or those matching the search.
    static func visibleClients(_ model: AppModel) -> [Client] {
        let query = model.findText[.clients, default: ""]
        return model.library.clients.filter {
            Find.matches(query, [$0.name, $0.contactName, $0.email, $0.phone])
        }
    }

    var body: some View {
        let clients = Self.visibleClients(model)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                // The list is only 400 wide in the smallest window. The buttons keep their full width
                // (fixedSize) and Find takes what's left, right after them, so the count sits under the list.
                HStack(spacing: 6) {
                    Button("New Client") { model.newClient() }
                        .buttonStyle(.win95)
                        .fixedSize()
                        .disabled(!model.canEdit)
                    Button("Delete Client") { model.deleteSelectedClient() }
                        .buttonStyle(.win95)
                        .fixedSize()
                        .disabled(!model.canDeleteClient)
                        .help(model.deleteClientHelp)
                    FindField(text: model.findBinding(.clients), request: model.findRequest)
                    Spacer()
                }
                DetailsList(clients, id: \.id, columns: columns, selection: $model.selectedClientID,
                            sort: DetailsSort(column: 0),
                            emptyText: model.findText[.clients, default: ""].isEmpty
                                ? "No clients yet. Press New Client to add one."
                                : "No clients match \"\(model.findText[.clients, default: ""])\".")
                Text(DashboardView.count(clients.count, "client", "clients"))
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // At the window's smallest (980 wide) the list and the details have 754 points between
            // them, so their minimums (400 + 320) must fit, or the row spills over the section tree.
            .frame(minWidth: 400, maxWidth: .infinity)
            Group {
                if let id = model.selectedClientID, model.library.client(id) != nil {
                    // A fresh form for each client, so a field's undo history or half-typed text can
                    // never land on the next client chosen.
                    ClientForm(model: model, clientID: id)
                        .id(id)
                } else {
                    Text("Select a client to see their details.")
                        .font(Win95.label)
                        .foregroundStyle(Win95.highlight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Win95.desktop)
                        .overlay(Bevel(.sunken))
                }
            }
            // 440 wide when there's room; it gives up room to the list only down to 320.
            .frame(minWidth: 320, idealWidth: 440, maxWidth: 440)
            .layoutPriority(1)
        }
        .padding(8)
    }

    /// The three text columns share the list's width equally, and their minimums add up to what
    /// fits in the list at the smallest window; unequal minimums would overflow it before that.
    private var columns: [DetailsColumn<Client>] {
        [
            .text("Name", width: .flexible(min: 100)) { $0.name.isEmpty ? "(no name)" : $0.name },
            .text("Contact", width: .flexible(min: 100)) { $0.contactName },
            .text("Email", width: .flexible(min: 100)) { $0.email },
            .text("Quotes", width: .fixed(70), alignment: .trailing, monospaced: true,
                  sortValue: { client in .number(model.library.quotes.filter { $0.clientID == client.id }.count) }) { client in
                String(model.library.quotes.filter { $0.clientID == client.id }.count)
            },
        ]
    }
}

/// One client's details. Every change saves as you type.
struct ClientForm: View {
    let model: AppModel
    let clientID: UUID

    var body: some View {
        let client = model.clientBinding(clientID)
        let summary = ClientSummary(library: model.library, clientID: clientID)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Client") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95FieldRow("Business:") { Win95TextField("Business name", text: client.name) }
                        Win95FieldRow("Contact:") { Win95TextField("Contact name", text: client.contactName) }
                        Win95FieldRow("Email:") { Win95TextField("Email", text: client.email) }
                        if !client.wrappedValue.email.isEmpty, !client.wrappedValue.email.contains("@") {
                            NoteBanner("That doesn't look like an email address.", warning: true)
                        }
                        Win95FieldRow("Phone:") { Win95TextField("Phone", text: client.phone) }
                        Win95FieldRow("Address:") { Win95TextEditor("Address", text: client.address).frame(height: 54) }
                    }
                }
                GroupBox("Notes") {
                    Win95TextEditor("Notes", text: client.notes)
                        .frame(height: 80)
                }
                GroupBox("Work") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95FieldRow("Quotes:") { Text(String(summary.quotes)).font(Win95.money) }
                        Win95FieldRow("Invoiced:") { Text(model.money(summary.invoiced)).font(Win95.money) }
                        Win95FieldRow("Paid:") { Text(model.money(summary.paid)).font(Win95.money) }
                        Win95FieldRow("Owing:") { Text(model.money(summary.owing)).font(Win95.money) }
                        Button("New Quote for This Client") { model.newQuote(for: clientID) }
                            .buttonStyle(.win95)
                    }
                    .foregroundStyle(Win95.text)
                }
            }
            // Greyed out while the fee lock is on; it still scrolls.
            .disabled(!model.canEdit)
            .padding(.trailing, 6)
        }
        .groupBoxStyle(.win95)
    }
}

/// What a client has been quoted, invoiced and paid. Draft and void invoices don't count.
struct ClientSummary: Equatable {
    var quotes: Int
    var invoiced: Money
    var paid: Money
    var owing: Money

    init(library: Library, clientID: UUID) {
        quotes = library.quotes.filter { $0.clientID == clientID }.count
        let sent = library.invoices.filter { $0.clientID == clientID && $0.stage == .sent }
        invoiced = sent.reduce(.zero) { $0 + $1.amount }
        paid = sent.reduce(.zero) { $0 + $1.paid }
        owing = sent.reduce(.zero) { $0 + max($1.owing, .zero) }
    }
}
