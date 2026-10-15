import QuotePilotCore
import SwiftUI

/// Invoices: the list, with the selected invoice's PDF beside it. Editing arrives in plan 2b.
struct InvoicesView: View {
    @Bindable var model: AppModel

    var body: some View {
        let rows = model.library.invoices.map { InvoiceRow($0, library: model.library, today: model.today) }
        GeometryReader { geometry in
            let layout = Self.layout(width: geometry.size.width)
            let columns = Self.columns(showKind: layout.showKind, currencyCode: model.currencyCode)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    NoteBanner("Invoices are drafted from accepted quotes. Drafting, sending and recording payments arrive in the next build.")
                    DetailsList(rows, id: \.id, columns: columns, selection: $model.selectedInvoiceID,
                                sort: DetailsSort(column: 0, ascending: false),
                                emptyText: "No invoices yet.")
                        // A sort is a column number, so a different set of columns starts afresh.
                        .id(layout.showKind)
                }
                .frame(minWidth: layout.listMinimum, maxWidth: .infinity)
                GroupBox("Preview") {
                    if let id = model.selectedInvoiceID, model.library.invoice(id) != nil {
                        LivePDFPreview(model: model, content: model.invoiceContent(id))
                    } else {
                        Text("Select an invoice to see it.")
                            .font(Win95.label)
                            .foregroundStyle(Win95.highlight)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Win95.desktop)
                            .overlay(Bevel(.sunken))
                    }
                }
                .frame(width: layout.previewWidth)
                .frame(maxHeight: .infinity)
            }
            .padding(8)
        }
        .groupBoxStyle(.win95)
    }

    // MARK: Fitting the window

    /// How the screen shares its width between the list and the preview.
    struct Layout: Equatable {
        /// Whether the Kind column is shown.
        var showKind: Bool
        /// The least the list needs for its columns not to be cut.
        var listMinimum: CGFloat
        var previewWidth: CGFloat
    }

    /// The preview is never under 220 (the quote editor's minimum), and about a third of the width
    /// up to 520. The window is at least 980 wide, which leaves 778 beside the section tree; all
    /// seven columns need about 595 of that, which would squeeze the preview to nothing, so the
    /// Kind column (the least useful) is dropped until the preview can have 300.
    static func layout(width: CGFloat) -> Layout {
        let available = width - 24 // the padding either side, and the gap between list and preview
        let fullMinimum = listMinimum(columns(showKind: true, currencyCode: "AUD"))
        let showKind = available - fullMinimum >= 300
        let minimum = showKind ? fullMinimum : listMinimum(columns(showKind: false, currencyCode: "AUD"))
        let wanted = min(available * 0.35, 520)
        let preview = max(220, min(wanted, available - minimum)).rounded(.down)
        return Layout(showKind: showKind, listMinimum: minimum, previewWidth: preview)
    }

    static func columns(showKind: Bool, currencyCode: String) -> [DetailsColumn<InvoiceRow>] {
        var columns: [DetailsColumn<InvoiceRow>] = [
            .text("Invoice", width: .fixed(72)) { $0.number },
            .text("Client", width: .flexible(min: 64)) { $0.client },
        ]
        if showKind {
            columns.append(.text("Kind", width: .fixed(60)) { $0.kind })
        }
        columns += [
            .day("Due", width: 92) { $0.due },
            DetailsColumn("Status", width: .fixed(114), sortValue: { .text($0.status.listLabel) }) { row, selected in
                StatusLabel.cell(row.status, selected: selected)
            },
            .money("Amount", width: 86, currencyCode: currencyCode) { $0.amount },
            .money("Owing", width: 86, currencyCode: currencyCode) { $0.owing },
        ]
        return columns
    }

    /// The least the list can be without cutting its columns: their widths, the sunken border and
    /// padding (4) and the strip a classic scroller takes (up to 16).
    private static func listMinimum(_ columns: [DetailsColumn<InvoiceRow>]) -> CGFloat {
        columns.reduce(20) { total, column in
            switch column.width {
            case .fixed(let width): return total + width
            case .flexible(let minimum): return total + minimum
            }
        }
    }
}

/// One invoice as the list shows it. A void invoice owes nothing.
struct InvoiceRow: Identifiable {
    let id: UUID
    let number: String
    let client: String
    let kind: String
    let due: Day
    let status: InvoiceStatus
    let amount: Money
    let owing: Money

    init(_ invoice: Invoice, library: Library, today: Day) {
        id = invoice.id
        number = invoice.number
        client = library.client(invoice.clientID)?.name ?? "No client"
        kind = invoice.kind.columnLabel
        due = invoice.due
        status = invoice.status(on: today)
        amount = invoice.amount
        owing = invoice.stage == .void ? .zero : max(invoice.owing, .zero)
    }
}

extension InvoiceKind {
    var columnLabel: String {
        switch self {
        case .deposit: return "Deposit"
        case .final: return "Final"
        case .full: return "Full"
        case .standalone: return "One-off"
        }
    }
}
