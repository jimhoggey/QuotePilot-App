import Foundation

/// One thing that happened to money, for the accountant's record: an invoice sent, a payment received
/// or a receipt sent.
struct MoneyEvent {
    enum Kind: Int {
        case invoiceSent, paymentReceived, receiptSent

        var label: String {
            switch self {
            case .invoiceSent: return "Invoice sent"
            case .paymentReceived: return "Payment received"
            case .receiptSent: return "Receipt sent"
            }
        }
    }

    var date: Day
    var kind: Kind
    var invoice: Invoice
    var payment: Payment?
    /// A payment's place in its invoice's list, which keeps two payments on one day in order.
    var order = 0
    /// What the invoice still asked for once this had happened.
    var owingAfter = Money.zero

    /// By date, then event, then invoice number, then payment order.
    static func inOrder(_ a: MoneyEvent, _ b: MoneyEvent) -> Bool {
        (a.date, a.kind.rawValue, a.invoice.number, a.order) < (b.date, b.kind.rawValue, b.invoice.number, b.order)
    }
}

extension Library {
    /// The money record's first row.
    public static let moneyRecordHeader =
        "Date,Event,Invoice,Quote,Client,Description,Amount,GST,Total,Method,Owing after,Note"

    /// One financial year's money record for a tax accountant, as CSV: the header row, then a row for
    /// each invoice sent, payment received and receipt sent in that year, by date and then event.
    ///
    /// - Total is what was invoiced or paid, GST is the GST inside it (0.00 when the invoice has no GST)
    ///   and Amount is Total less GST. They're plain numbers, so a spreadsheet can add them up. A receipt
    ///   moves no money, so its amounts are blank.
    /// - Owing after is what the invoice still asked for once the event had happened.
    /// - Only sent invoices count. A voided invoice is left out altogether: the library keeps no date
    ///   for a void, so there's no row to say when it was cancelled.
    /// - A sent or receipt time counts on the day it fell in `timeZone` (this Mac's); an invoice sent
    ///   with no time recorded (an imported one) counts on its issue date.
    public func moneyRecordCSV(for year: FinancialYear, timeZone: TimeZone = .current) -> String {
        let rows = moneyEvents(timeZone: timeZone).filter { year.contains($0.date) }.map(moneyRecordRow)
        return ([Self.moneyRecordHeader] + rows).joined(separator: "\n") + "\n"
    }

    /// The financial years with at least one money event, oldest first.
    public func moneyRecordYears(timeZone: TimeZone = .current) -> [FinancialYear] {
        Set(moneyEvents(timeZone: timeZone).map { FinancialYear(containing: $0.date) })
            .sorted { $0.startYear < $1.startYear }
    }

    /// Every money event of every sent invoice, in order, each with what was owing after it.
    func moneyEvents(timeZone: TimeZone) -> [MoneyEvent] {
        invoices.filter { $0.stage == .sent }.flatMap { invoice -> [MoneyEvent] in
            let sentOn = invoice.sentAt.map { Day($0, timeZone: timeZone) } ?? invoice.issued
            var events = [MoneyEvent(date: sentOn, kind: .invoiceSent, invoice: invoice)]
            events += invoice.payments.enumerated().map { index, payment in
                MoneyEvent(date: payment.date, kind: .paymentReceived, invoice: invoice, payment: payment, order: index)
            }
            if let receipt = invoice.receiptSentAt {
                events.append(MoneyEvent(date: Day(receipt, timeZone: timeZone), kind: .receiptSent, invoice: invoice))
            }
            events.sort(by: MoneyEvent.inOrder)
            var owing = invoice.amount
            for index in events.indices {
                owing -= events[index].payment?.amount ?? .zero
                events[index].owingAfter = owing
            }
            return events
        }
        .sorted(by: MoneyEvent.inOrder)
    }

    private func moneyRecordRow(_ event: MoneyEvent) -> String {
        let invoice = event.invoice
        var amount = "", gst = "", total = ""
        if let money = event.kind == .invoiceSent ? invoice.amount : event.payment?.amount {
            let tax = invoice.gstShare(of: money)
            amount = (money - tax).plain
            gst = tax.plain
            total = money.plain
        }
        let description = invoice.title.isEmpty
            ? invoice.lines.map(\.title).filter { !$0.isEmpty }.joined(separator: ", ")
            : invoice.title
        let note: String
        switch event.kind {
        case .invoiceSent: note = invoice.moneyRecordNote
        case .paymentReceived: note = event.payment?.note ?? ""
        case .receiptSent: note = ""
        }
        return [csvField(event.date.iso), csvField(event.kind.label), csvText(invoice.number),
                csvText(invoice.quoteID.flatMap { quote($0) }?.number ?? ""),
                csvText(client(invoice.clientID)?.name ?? ""), csvText(description),
                csvField(amount), csvField(gst), csvField(total), csvField(event.payment?.method.label ?? ""),
                csvField(event.owingAfter.plain), csvText(note)]
            .joined(separator: ",")
    }
}

extension Invoice {
    /// The GST inside `amount`, part of what this invoice asks for, in the same proportion as its lines'
    /// GST to their total, to the nearest cent. Nothing when the invoice has no GST.
    func gstShare(of amount: Money) -> Money {
        let totals = lineTotals
        guard totals.gst != .zero, totals.total != .zero else { return .zero }
        var exact = Decimal(amount.cents) * Decimal(totals.gst.cents) / Decimal(totals.total.cents)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 0, .plain)
        return Money(cents: NSDecimalNumber(decimal: rounded).intValue)
    }

    /// Why a deposit or final invoice's total isn't the job's: "Deposit (50%)", "Less deposit INV-0001".
    var moneyRecordNote: String {
        var parts = depositPercent.map { ["Deposit (\($0)%)"] } ?? []
        parts += deductions.map { "\($0.label) \($0.invoiceNumber)" }
        return parts.joined(separator: "; ")
    }
}
