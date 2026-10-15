import QuotePilotCore
import SwiftUI

/// The main screen: four big readouts, then what's owed, quotes waiting on a reply and what's still
/// to invoice. Double-click a row to open it.
struct DashboardView: View {
    let model: AppModel
    @State private var selectedInvoice: UUID?
    @State private var selectedQuote: UUID?
    @State private var selectedJob: UUID?

    var body: some View {
        let dashboard = model.dashboard
        let liveQuotes = dashboard.openQuotes.filter { !$0.expired }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Readout(title: "Waiting to be paid", value: model.money(dashboard.waitingTotal),
                        note: Self.count(dashboard.waiting.count, "invoice", "invoices"))
                Readout(title: "Overdue", value: model.money(dashboard.overdueTotal),
                        note: Self.overdueNote(dashboard), alert: dashboard.overdueTotal > .zero)
                Readout(title: "Received \(dashboard.financialYear.label)", value: model.money(dashboard.receivedThisYear),
                        note: "This month: \(model.money(dashboard.receivedThisMonth))")
                Readout(title: "Quotes out", value: model.money(dashboard.openQuotesTotal),
                        note: Self.count(liveQuotes, "quote", "quotes") + " waiting on a reply")
            }
            GroupBox("Waiting to be paid") {
                DetailsList(dashboard.waiting, id: \.invoiceID, columns: owingColumns, selection: $selectedInvoice,
                            emptyText: "Nothing waiting. Every sent invoice is paid.",
                            onOpen: { model.openInvoice($0) })
            }
            .frame(maxHeight: .infinity)
            HStack(alignment: .top, spacing: 8) {
                GroupBox("Quotes waiting on a reply") {
                    DetailsList(dashboard.openQuotes, id: \.quoteID, columns: quoteColumns, selection: $selectedQuote,
                                emptyText: "No quotes out.", onOpen: { model.openQuote($0) })
                }
                .frame(minWidth: Self.boxWidth(quoteColumns))
                GroupBox("Still to invoice") {
                    DetailsList(dashboard.toInvoice, id: \.quoteID, columns: jobColumns, selection: $selectedJob,
                                emptyText: "Every accepted job is fully invoiced.", onOpen: { model.openQuote($0) })
                }
                .frame(minWidth: Self.boxWidth(jobColumns))
            }
            .frame(maxHeight: .infinity)
            Text("Invoiced \(dashboard.financialYear.label): \(model.money(dashboard.invoicedThisYear))")
                .font(Win95.body)
                .foregroundStyle(Win95.text)
        }
        .padding(8)
        .groupBoxStyle(.win95)
    }

    private var owingColumns: [DetailsColumn<Dashboard.Owing>] {
        [
            .text("Invoice", width: .fixed(90)) { $0.number },
            .text("Client", width: .flexible(min: 140)) { $0.client },
            .day("Due") { $0.due },
            DetailsColumn("Status", width: .fixed(140), sortValue: { .number($0.daysLate) }) { row, selected in
                StatusLabel.cell(model.library.invoice(row.invoiceID)?.status(on: model.today) ?? .sent, selected: selected)
            },
            .money("Owing", currencyCode: model.currencyCode) { $0.owing },
        ]
    }

    // The two lists along the bottom share the window's width, so their columns are narrow: the
    // client column gives way first, and `boxWidth` keeps the rest whole down to the smallest window.
    private var quoteColumns: [DetailsColumn<Dashboard.OpenQuote>] {
        [
            .text("Quote", width: .fixed(64)) { $0.number },
            .text("Client", width: .flexible(min: 40)) { $0.client },
            .day("Valid until", width: 92) { $0.validUntil },
            DetailsColumn("Status", width: .fixed(88), sortValue: { .number($0.expired ? 1 : 0) }) { row, selected in
                StatusLabel.cell(row.expired ? QuoteStatus.expired : .sent, selected: selected)
            },
            .money("Total", width: 96, currencyCode: model.currencyCode) { $0.total },
        ]
    }

    private var jobColumns: [DetailsColumn<Dashboard.ToInvoice>] {
        [
            .text("Quote", width: .fixed(64)) { $0.number },
            .text("Client", width: .flexible(min: 40)) { $0.client },
            DetailsColumn("Invoiced", width: .fixed(100), sortValue: { .number(Int(Self.share($0) * 1000)) }) { row, _ in
                AnyView(Win95Progress(fraction: Self.share(row))
                    .frame(height: 14)
                    .accessibilityLabel("Invoiced \(Int((Self.share(row) * 100).rounded())) percent"))
            },
            .money("Left to invoice", width: 112, currencyCode: model.currencyCode) { $0.remaining },
        ]
    }

    /// The narrowest a list's group box can be and still show every column whole: the columns at
    /// their smallest, the list's border and the group box's padding, and the scroller when the Mac
    /// shows one beside the rows.
    static func boxWidth<Row>(_ columns: [DetailsColumn<Row>]) -> CGFloat {
        let columnsWidth = columns.reduce(CGFloat(0)) { total, column in
            switch column.width {
            case .fixed(let width): return total + width
            case .flexible(let minimum): return total + minimum
            }
        }
        return columnsWidth + 24 + DetailsLayout.legacyScrollerWidth
    }

    /// "1 invoice, 5 days late": how many are overdue, and the oldest.
    static func overdueNote(_ dashboard: Dashboard) -> String {
        let late = dashboard.waiting.filter { $0.daysLate > 0 }
        guard let oldest = late.map(\.daysLate).max() else { return "Nothing overdue" }
        return count(late.count, "invoice", "invoices") + ", " + count(oldest, "day", "days") + " late"
    }

    static func count(_ number: Int, _ one: String, _ many: String) -> String {
        "\(number) \(number == 1 ? one : many)"
    }

    /// How much of an accepted job is invoiced, from 0 to 1.
    static func share(_ job: Dashboard.ToInvoice) -> Double {
        job.accepted.cents > 0 ? Double(job.invoiced.cents) / Double(job.accepted.cents) : 0
    }
}

/// A headline number in a sunken white panel, 28 points, with a line of detail under it.
struct Readout: View {
    let title: String
    let value: String
    let note: String
    var alert = false

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(Win95.readout)
                    .foregroundStyle(alert ? Win95.overdue : Win95.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .win95Sunken()
                HStack(spacing: 4) {
                    if alert { PixelIconView(.warning) }
                    Text(note)
                        .font(Win95.body)
                        .foregroundStyle(Win95.text)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension StatusLabel {
    /// A quote's status in a list cell: white on a selected row, dark red once expired.
    static func cell(_ status: QuoteStatus, selected: Bool) -> AnyView {
        AnyView(StatusLabel(status.icon, status.label,
                            color: selected ? Win95.highlight : (status == .expired ? Win95.overdue : Win95.text)))
    }

    /// An invoice's status in a list cell: white on a selected row, dark red when overdue.
    static func cell(_ status: InvoiceStatus, selected: Bool) -> AnyView {
        AnyView(StatusLabel(status.icon, status.listLabel,
                            color: selected ? Win95.highlight : (status.isAlert ? Win95.overdue : Win95.text)))
    }
}
