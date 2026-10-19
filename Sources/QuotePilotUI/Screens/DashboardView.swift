import QuotePilotCore
import SwiftUI

/// The main screen: the Getting started box while the library is new, four big readouts (the money
/// pipeline: quoted, accepted but not invoiced, invoiced but not paid, paid), then three lists in the
/// order the work happens (quotes waiting on a reply, what's still to invoice, what's waiting to be
/// paid). Double-click a row to open it.
struct DashboardView: View {
    let model: AppModel
    @State private var selectedInvoice: UUID?
    @State private var selectedQuote: UUID?
    @State private var selectedJob: UUID?

    var body: some View {
        let dashboard = model.dashboard
        VStack(alignment: .leading, spacing: 8) {
            GettingStartedBox(model: model)
            // One stage of the money each, left to right, so no dollar is in two boxes. Each total is the
            // sum of the list behind it.
            HStack(alignment: .top, spacing: 8) {
                Readout(title: "Quotes out", value: model.money(dashboard.openQuotesTotal),
                        note: Self.quotesOutNote(dashboard))
                Readout(title: "Not invoiced yet", value: model.money(dashboard.toInvoiceTotal),
                        note: Self.notInvoicedNote(dashboard))
                Readout(title: "Waiting to be paid", value: model.money(dashboard.waitingTotal),
                        note: Self.waitingNote(dashboard))
                Readout(title: "Received \(dashboard.financialYear.label)", value: model.money(dashboard.receivedThisYear),
                        note: Self.receivedNote(dashboard, currencyCode: model.currencyCode))
            }
            // The money closest to hand on top: what's waiting to be paid and what's still to invoice,
            // side by side; the quotes waiting on a reply below them (the user's order, 19 Oct 2026).
            HStack(alignment: .top, spacing: Self.gap) {
                let owingColumns = Self.owingColumns(currencyCode: model.currencyCode) { row in
                    model.library.invoice(row.invoiceID)?.status(on: model.today) ?? .sent
                }
                let jobColumns = Self.jobColumns(currencyCode: model.currencyCode)
                GroupBox(Self.listTitles[0]) {
                    DetailsList(dashboard.waiting, id: \.invoiceID, columns: owingColumns, selection: $selectedInvoice,
                                emptyText: Self.waitingEmptyText(model.library),
                                onOpen: { model.openInvoice($0) })
                }
                .frame(minWidth: Self.boxWidth(owingColumns, scroller: DetailsLayout.legacyScrollerWidth))
                GroupBox(Self.listTitles[1]) {
                    DetailsList(dashboard.toInvoice, id: \.quoteID, columns: jobColumns, selection: $selectedJob,
                                emptyText: Self.toInvoiceEmptyText(model.library), onOpen: { model.openQuote($0) })
                }
                .frame(minWidth: Self.boxWidth(jobColumns, scroller: DetailsLayout.legacyScrollerWidth))
            }
            .frame(minHeight: Self.listMinHeight, maxHeight: .infinity)
            GroupBox(Self.listTitles[2]) {
                DetailsList(dashboard.openQuotes, id: \.quoteID, columns: Self.quoteColumns(currencyCode: model.currencyCode),
                            selection: $selectedQuote, emptyText: "No quotes out.", onOpen: { model.openQuote($0) })
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

    /// The three lists: the two side by side on top, then the one below. No numbers: "1 · Quotes
    /// waiting" read as a count ("one quote waiting"), as the step bar's numbers did.
    static let listTitles = ["Waiting to be paid", "Still to invoice", "Quotes waiting on a reply"]

    /// The least height a row of lists gets: its title and padding (26), the column header and two
    /// rows. With the Getting started box showing, this keeps the lists from being squeezed away in the
    /// smallest window (980 x 620), where the Dashboard has 492 points.
    static let listMinHeight: CGFloat = 90

    // The two lists that share the top row (waiting and jobs) share the window's width, so their columns are
    // narrow: the client column gives way first, and `boxWidth` keeps the rest whole down to the smallest
    // window. Invoice (72) holds "INV-0002", Due (92) "10 Oct 2026", Status (112) the icon and
    // "Overdue 12 d"; on the jobs list Invoiced (64) its bar and Left to invoice (100) its header.
    // Together they fill the 778 points of the smallest window exactly (`bottomRowMinimum`).
    static func owingColumns(currencyCode: String,
                             status: @escaping (Dashboard.Owing) -> InvoiceStatus) -> [DetailsColumn<Dashboard.Owing>] {
        [
            .text("Invoice", width: .fixed(72)) { $0.number },
            .text("Client", width: .flexible(min: 40)) { $0.client },
            .day("Due", width: 92) { $0.due },
            DetailsColumn("Status", width: .fixed(112), sortValue: { .number($0.daysLate) }) { row, selected in
                StatusLabel.cell(status(row), selected: selected)
            },
            .money("Owing", width: 88, currencyCode: currencyCode) { $0.owing },
        ]
    }

    // The quotes list sits alone on its row, so its client column has the room; Status (80) holds the
    // icon and "Expired".
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
            DetailsColumn("Invoiced", width: .fixed(64), sortValue: { .number(Int(share($0) * 1000)) }) { row, _ in
                AnyView(Win95Progress(fraction: share(row))
                    .frame(height: 14)
                    .accessibilityLabel("Invoiced \(Int((share(row) * 100).rounded())) percent"))
            },
            .money("Left to invoice", width: 100, currencyCode: currencyCode) { $0.remaining },
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
        gap + boxWidth(owingColumns(currencyCode: "AUD") { _ in .sent }, scroller: scroller)
            + gap + boxWidth(jobColumns(currencyCode: "AUD"), scroller: scroller) + gap
    }

    /// "Quoted, waiting on a reply", with "· 2 expired" once some have expired. The list under it shows
    /// expired quotes too, so the note counts them rather than leaving them out. (The total counts only
    /// the live ones: an expired quote is no longer money on offer.)
    static func quotesOutNote(_ dashboard: Dashboard) -> String {
        let expired = dashboard.openQuotes.filter(\.expired).count
        let note = "Quoted, waiting on a reply"
        return expired > 0 ? note + " · \(expired) expired" : note
    }

    /// "Accepted, not invoiced yet · 1 job": the rows of the "Still to invoice" list.
    static func notInvoicedNote(_ dashboard: Dashboard) -> String {
        "Accepted, not invoiced yet · " + count(dashboard.toInvoice.count, "job", "jobs")
    }

    /// "Invoiced, not paid yet · 2 invoices": the rows of the "Waiting to be paid" list. Overdue
    /// invoices show in red there and are counted in the status bar.
    static func waitingNote(_ dashboard: Dashboard) -> String {
        "Invoiced, not paid yet · " + count(dashboard.waiting.count, "invoice", "invoices")
    }

    /// "Paid this financial year · This month $1,995.00".
    static func receivedNote(_ dashboard: Dashboard, currencyCode: String) -> String {
        "Paid this financial year · This month " + dashboard.receivedThisMonth.formatted(currencyCode: currencyCode)
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

    /// How far a long note may shrink before it is cut off. In the smallest window (980 wide) each
    /// readout has about 164 points inside its frame, and "Paid this financial year · This month
    /// $12,345.00" needs about 286 at full size.
    static let noteMinimumScale: CGFloat = 0.55

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(Win95.readout)
                    .foregroundStyle(Win95.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .win95Sunken()
                Text(note)
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.noteMinimumScale)
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
