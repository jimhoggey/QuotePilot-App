import QuotePilotCore
import SwiftUI

/// Quotes: the list, or the editor when a quote is open.
struct QuotesView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let id = model.openQuoteID, model.library.quote(id) != nil {
            QuoteEditorView(model: model, quoteID: id)
        } else {
            QuoteListView(model: model)
        }
    }
}

/// One quote as the list shows it.
struct QuoteRow: Identifiable {
    let id: UUID
    let number: String
    let client: String
    let title: String
    let issued: Day
    let status: QuoteStatus
    let total: Money

    init(_ quote: Quote, library: Library, today: Day) {
        id = quote.id
        number = quote.number
        client = library.client(quote.clientID)?.name ?? "No client"
        title = quote.title
        issued = quote.issued
        status = quote.status(on: today)
        total = quote.totals.total
    }
}

struct QuoteListView: View {
    @Bindable var model: AppModel

    var body: some View {
        let rows = model.library.quotes.map { QuoteRow($0, library: model.library, today: model.today) }
        let selected = model.selectedQuoteID.flatMap { model.library.quote($0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button("New Quote") { model.newQuote() }
                    .buttonStyle(.win95)
                Button("Open") { if let selected { model.openQuote(selected.id) } }
                    .buttonStyle(.win95)
                    .disabled(selected == nil)
                Button("Duplicate") { if let selected { model.duplicateQuote(selected.id) } }
                    .buttonStyle(.win95)
                    .disabled(selected == nil)
                Button("Delete Draft") { if let selected { model.deleteDraftQuote(selected.id) } }
                    .buttonStyle(.win95)
                    .disabled(selected?.stage != .draft)
                Spacer()
                Text(DashboardView.count(rows.count, "quote", "quotes"))
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
            }
            DetailsList(rows, id: \.id, columns: columns, selection: $model.selectedQuoteID,
                        sort: DetailsSort(column: 0, ascending: false),
                        emptyText: "No quotes yet. Press New Quote (⌘N) to write one.",
                        onOpen: { model.openQuote($0) },
                        rowMenu: { id in AnyView(menu(id)) })
        }
        .padding(8)
    }

    private var columns: [DetailsColumn<QuoteRow>] {
        [
            .text("Quote", width: .fixed(80)) { $0.number },
            .text("Client", width: .flexible(min: 140)) { $0.client },
            .text("Title", width: .flexible(min: 140)) { $0.title },
            .day("Issued") { $0.issued },
            DetailsColumn("Status", width: .fixed(150), sortValue: { .text($0.status.label) }) { row, selected in
                StatusLabel.cell(row.status, selected: selected)
            },
            .money("Total", currencyCode: model.currencyCode) { $0.total },
        ]
    }

    @ViewBuilder
    private func menu(_ id: UUID) -> some View {
        Button("Open") { model.openQuote(id) }
        Button("Duplicate") { model.duplicateQuote(id) }
        if model.library.quote(id)?.stage == .draft {
            Divider()
            Button("Delete Draft…") { model.deleteDraftQuote(id) }
        }
    }
}
