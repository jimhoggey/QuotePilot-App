import QuotePilotCore
import SwiftUI

/// The main screen: the Getting started box while the library is new, four big readouts, then three
/// lists in the order the work happens (quotes waiting on a reply, what's still to invoice, what's
/// waiting to be paid). Double-click a row to open it.
struct DashboardView: View {
    let model: AppModel
    @State private var selectedInvoice: UUID?
    @State private var selectedQuote: UUID?
    @State private var selectedJob: UUID?

    var body: some View {
        let dashboard = model.dashboard
        VStack(alignment: .leading, spacing: 8) {
            GettingStartedBox(model: model)
            HStack(alignment: .top, spacing: 8) {
                Readout(title: "Waiting to be paid", value: model.money(dashboard.waitingTotal),
                        note: Self.count(dashboard.waiting.count, "invoice", "invoices"))
                Readout(title: "Overdue", value: model.money(dashboard.overdueTotal),
                        note: Self.overdueNote(dashboard), alert: dashboard.overdueTotal > .zero)
                Readout(title: "Received \(dashboard.financialYear.label)", value: model.money(dashboard.receivedThisYear),
                        note: "This month: \(model.money(dashboard.receivedThisMonth))")
                Readout(title: "Quotes out", value: model.money(dashboard.openQuotesTotal),
                        note: Self.quotesOutNote(dashboard))
            }
            // The lists in the order the work happens: a quote goes out, is accepted and invoiced,
            // then waits to be paid.
            HStack(alignment: .top, spacing: Self.gap) {
                let quoteColumns = Self.quoteColumns(currencyCode: model.currencyCode)
                let jobColumns = Self.jobColumns(currencyCode: model.currencyCode)
                GroupBox(Self.listTitles[0]) {
                    DetailsList(dashboard.openQuotes, id: \.quoteID, columns: quoteColumns, selection: $selectedQuote,
                                emptyText: "No quotes out.", onOpen: { model.openQuote($0) })
                }
                .frame(minWidth: Self.boxWidth(quoteColumns, scroller: DetailsLayout.legacyScrollerWidth))
                GroupBox(Self.listTitles[1]) {
                    DetailsList(dashboard.toInvoice, id: \.quoteID, columns: jobColumns, selection: $selectedJob,
                                emptyText: Self.toInvoiceEmptyText(model.library), onOpen: { model.openQuote($0) })
                }
                .frame(minWidth: Self.boxWidth(jobColumns, scroller: DetailsLayout.legacyScrollerWidth))
            }
            .frame(minHeight: Self.listMinHeight, maxHeight: .infinity)
            GroupBox(Self.listTitles[2]) {
                DetailsList(dashboard.waiting, id: \.invoiceID, columns: owingColumns, selection: $selectedInvoice,
                            emptyText: Self.waitingEmptyText(model.library),
                            onOpen: { model.openInvoice($0) })
            }
            .frame(minHeight: Self.listMinHeight, maxHeight: .infinity)
            Text("Invoiced \(dashboard.financialYear.label): \(model.money(dashboard.invoicedThisYear))")
                .font(Win95.body)
                .foregroundStyle(Win95.text)
        }
        .padding(Self.gap)
        .groupBoxStyle(.win95)
    }

    /// The screen's padding, and the gap between the two lists side by side.
    static let gap: CGFloat = 8

    /// What "Still to invoice" says when it is empty: that nothing is accepted yet while no quote has
    /// been accepted, and that the accepted jobs are done once some have.
    static func toInvoiceEmptyText(_ library: Library) -> String {
        library.quotes.contains { $0.stage == .accepted }
            ? "Every accepted job is fully invoiced." : "Nothing to invoice yet."
    }

    /// What "Waiting to be paid" says when it is empty: that nothing is out while no invoice has been
    /// sent, and that they are all paid once some have.
    static func waitingEmptyText(_ library: Library) -> String {
        library.invoices.contains { $0.stage == .sent }
            ? "Nothing waiting. Every sent invoice is paid." : "Nothing waiting to be paid."
    }

    /// The three lists, in the order the work happens. No numbers: "1 · Quotes waiting" read as
    /// a count ("one quote waiting"), as the step bar's numbers did.
    static let listTitles = ["Quotes waiting on a reply", "Still to invoice", "Waiting to be paid"]

    /// The least height a row of lists gets: its title and padding (26), the column header and two
    /// rows. With the Getting started box showing, this keeps the lists from being squeezed away in the
    /// smallest window (980 x 620), where the Dashboard has 492 points.
    static let listMinHeight: CGFloat = 90

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

    // The two lists that share a row (quotes and jobs) share the window's width, so their columns are narrow: the
    // client column gives way first, and `boxWidth` keeps the rest whole down to the smallest window.
    // Status (80) just holds the icon and "Expired"; Invoiced (76) its header and sort arrow.
    static func quoteColumns(currencyCode: String) -> [DetailsColumn<Dashboard.OpenQuote>] {
        [
            .text("Quote", width: .fixed(64)) { $0.number },
            .text("Client", width: .flexible(min: 40)) { $0.client },
            .day("Valid until", width: 92) { $0.validUntil },
            DetailsColumn("Status", width: .fixed(80), sortValue: { .number($0.expired ? 1 : 0) }) { row, selected in
                StatusLabel.cell(row.expired ? QuoteStatus.expired : .sent, selected: selected)
            },
            .money("Total", width: 96, currencyCode: currencyCode) { $0.total },
        ]
    }

    static func jobColumns(currencyCode: String) -> [DetailsColumn<Dashboard.ToInvoice>] {
        [
            .text("Quote", width: .fixed(64)) { $0.number },
            .text("Client", width: .flexible(min: 40)) { $0.client },
            DetailsColumn("Invoiced", width: .fixed(76), sortValue: { .number(Int(share($0) * 1000)) }) { row, _ in
                AnyView(Win95Progress(fraction: share(row))
                    .frame(height: 14)
                    .accessibilityLabel("Invoiced \(Int((share(row) * 100).rounded())) percent"))
            },
            .money("Left to invoice", width: 112, currencyCode: currencyCode) { $0.remaining },
        ]
    }

    /// The narrowest a list's group box can be and still show every column whole: the columns at
    /// their smallest, the list's border and padding (4), the group box's padding (20), and the
    /// scroller (`scroller` wide) when the Mac shows one beside the rows.
    static func boxWidth<Row>(_ columns: [DetailsColumn<Row>], scroller: CGFloat) -> CGFloat {
        let columnsWidth = columns.reduce(CGFloat(0)) { total, column in
            switch column.width {
            case .fixed(let width): return total + width
            case .flexible(let minimum): return total + minimum
            }
        }
        return columnsWidth + 24 + scroller
    }

    /// The least width the screen needs for the two lists of the shared row to sit side by side with every
    /// column whole: both group boxes at their narrowest, the gap between them and the padding
    /// either side. It has to fit in the 778 points the smallest window (980 wide) leaves beside
    /// the section tree, with a classic scroller in each list.
    static func bottomRowMinimum(scroller: CGFloat) -> CGFloat {
        gap + boxWidth(quoteColumns(currencyCode: "AUD"), scroller: scroller)
            + gap + boxWidth(jobColumns(currencyCode: "AUD"), scroller: scroller) + gap
    }

    /// "1 invoice, 5 days late": how many are overdue, and the oldest.
    static func overdueNote(_ dashboard: Dashboard) -> String {
        let late = dashboard.waiting.filter { $0.daysLate > 0 }
        guard let oldest = late.map(\.daysLate).max() else { return "Nothing overdue" }
        return count(late.count, "invoice", "invoices") + ", " + count(oldest, "day", "days") + " late"
    }

    /// "1 quote waiting on a reply", or "1 waiting on a reply · 2 expired" once some have expired. The
    /// list under it shows expired quotes too, so the note counts them rather than leaving them out.
    /// (Its total counts only the live ones: an expired quote is no longer money on offer.)
    static func quotesOutNote(_ dashboard: Dashboard) -> String {
        let expired = dashboard.openQuotes.filter(\.expired).count
        let live = dashboard.openQuotes.count - expired
        guard expired > 0 else { return count(live, "quote", "quotes") + " waiting on a reply" }
        return "\(live) waiting on a reply · \(expired) expired"
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
