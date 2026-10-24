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

/// Money paid out, for the record: an expense, or a Quote Pilot fee marked paid.
struct MoneyOut {
    var date: Day
    var event: String
    var who: String
    var description: String
    var category: String
    var total: Money
    var gst: Money
    var method: String
    var note: String
}

extension Library {
    /// What the Quote Pilot fee is filed under, as an expense.
    public static let appFeeCategory = "Software and subscriptions"

    /// The money record's first row.
    public static let moneyRecordHeader =
        "Date,Type,Event,Document,Quote,Who,Description,Category,Amount ex GST,GST,Total,Method,Owing after,Note"

    /// One financial year's money record for a tax accountant, as CSV: the header row, then a row for
    /// each invoice sent, payment received and receipt sent (Type Income), each expense (Type Expense,
    /// "Expense paid") and each Quote Pilot fee marked paid (Type Expense, "Quote Pilot fee paid") in
    /// that year, by date: on one day, income first, then expenses, then fees.
    ///
    /// - Total is what was invoiced or paid, GST is the GST inside it (0.00 when there's none) and
    ///   Amount ex GST is Total less GST. They're plain numbers, so a spreadsheet can add them up. A
    ///   receipt moves no money, so its amounts are blank.
    /// - Owing after is what the invoice still asked for once the event had happened.
    /// - Who is the client, the supplier, or "Quote Pilot" for the fee.
    /// - Only sent invoices count. A voided invoice is left out altogether: the library keeps no date
    ///   for a void, so there's no row to say when it was cancelled.
    /// - A sent or receipt time counts on the day it fell in `timeZone` (this Mac's); an invoice sent
    ///   with no time recorded (an imported one) counts on its issue date.
    public func moneyRecordCSV(for year: FinancialYear, timeZone: TimeZone = .current) -> String {
        var rows: [(date: Day, group: Int, index: Int, text: String)] = []
        for (index, event) in moneyEvents(timeZone: timeZone).enumerated() where year.contains(event.date) {
            rows.append((event.date, 0, index, moneyRecordRow(event)))
        }
        for (index, out) in moneyOut().enumerated() where year.contains(out.date) {
            rows.append((out.date, 1, index, moneyRecordRow(out)))
        }
        rows.sort { ($0.date, $0.group, $0.index) < ($1.date, $1.group, $1.index) }
        return ([Self.moneyRecordHeader] + rows.map(\.text)).joined(separator: "\n") + "\n"
    }

    /// The financial years with at least one money event, expense or fee paid, oldest first.
    public func moneyRecordYears(timeZone: TimeZone = .current) -> [FinancialYear] {
        let days = moneyEvents(timeZone: timeZone).map(\.date) + moneyOut().map(\.date)
        return Set(days.map(FinancialYear.init(containing:))).sorted { $0.startYear < $1.startYear }
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

    /// Every expense, then every Quote Pilot fee marked paid, each by date (expenses on one day in the
    /// order they were added).
    func moneyOut() -> [MoneyOut] {
        let spent = expenses.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map { MoneyOut(date: $0.element.date, event: "Expense paid", who: $0.element.supplier,
                            description: $0.element.description, category: $0.element.category,
                            total: $0.element.total, gst: $0.element.gst, method: $0.element.method.label,
                            note: $0.element.note) }
        let fees = brand.appFee.paidMonths.compactMap { key, paid -> (CalendarMonth, AppFeePaid)? in
            CalendarMonth(key: key).map { ($0, paid) }
        }
        .sorted { ($0.1.on, $0.0) < ($1.1.on, $1.0) }
        .map { MoneyOut(date: $0.1.on, event: "Quote Pilot fee paid", who: "Quote Pilot",
                        description: "Quote Pilot fee for \($0.0.label)", category: Self.appFeeCategory,
                        total: $0.1.amount, gst: .zero, method: "", note: "") }
        return spent + fees
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
        return [csvField(event.date.iso), "Income", csvField(event.kind.label), csvText(invoice.number),
                csvText(invoice.quoteID.flatMap { quote($0) }?.number ?? ""),
                csvText(client(invoice.clientID)?.name ?? ""), csvText(description), "",
                csvField(amount), csvField(gst), csvField(total), csvField(event.payment?.method.label ?? ""),
                csvField(event.owingAfter.plain), csvText(note)]
            .joined(separator: ",")
    }

    private func moneyRecordRow(_ out: MoneyOut) -> String {
        [csvField(out.date.iso), "Expense", csvField(out.event), "", "", csvText(out.who), csvText(out.description),
         csvText(out.category), csvField((out.total - out.gst).plain), csvField(out.gst.plain), csvField(out.total.plain),
         csvField(out.method), "", csvText(out.note)]
            .joined(separator: ",")
    }

    // MARK: The year's summary

    /// "Summary FY 2026-27.csv": one financial year in two columns (Item, Amount) for the accountant:
    /// income received (with the GST in it), what was invoiced, what was owing at the year's end (or
    /// on `today`, for the year not over yet), expenses by category and in total, the net figure and
    /// net GST, and how many invoices and expenses there were. The money record's rows add up to it.
    public func summaryCSV(for year: FinancialYear, today: Day = .today(), timeZone: TimeZone = .current) -> String {
        func amount(_ money: Money) -> String { money.plain }
        let events = moneyEvents(timeZone: timeZone)

        var received = Money.zero, gstCollected = Money.zero
        for event in events where event.kind == .paymentReceived && year.contains(event.date) {
            let paid = event.payment?.amount ?? .zero
            received += paid
            gstCollected += event.invoice.gstShare(of: paid)
        }
        let sent = events.filter { $0.kind == .invoiceSent && year.contains($0.date) }
        let invoiced = sent.reduce(Money.zero) { $0 + $1.invoice.amount }

        // What sent invoices still asked for on the cut-off day: each invoice's last "owing after".
        let cutoff = min(year.end, today)
        var owingByInvoice: [UUID: Money] = [:]
        for event in events where event.date <= cutoff {
            owingByInvoice[event.invoice.id] = event.owingAfter
        }
        let owing = owingByInvoice.values.reduce(Money.zero) { $0 + max($1, .zero) }
        let owingLabel = today < year.end ? "Owing now (\(today.short))" : "Owing at \(year.end.short)"

        let out = moneyOut().filter { year.contains($0.date) }
        var byCategory: [String: Money] = [:]
        for item in out { byCategory[item.category, default: .zero] += item.total - item.gst }
        let standard = Expense.categories.filter { byCategory[$0] != nil }
        let others = byCategory.keys.filter { !Expense.categories.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let spent = out.reduce(Money.zero) { $0 + $1.total }
        let gstPaid = out.reduce(Money.zero) { $0 + $1.gst }

        var rows: [(String, String)] = [
            ("Financial year", "\(year.label) (\(year.start.short) to \(year.end.short))"),
            ("Income received (GST included)", amount(received)),
            ("Income received ex GST", amount(received - gstCollected)),
            ("GST collected", amount(gstCollected)),
            ("Invoiced in the year (GST included)", amount(invoiced)),
            (owingLabel, amount(owing)),
        ]
        rows += (standard + others).map { ("Expenses: \($0) (ex GST)", amount(byCategory[$0] ?? .zero)) }
        rows += [
            ("Total expenses ex GST", amount(spent - gstPaid)),
            ("GST paid", amount(gstPaid)),
            ("Total expenses (GST included)", amount(spent)),
            ("Net (income ex GST less expenses ex GST)", amount(received - gstCollected - (spent - gstPaid))),
            ("Net GST (GST collected less GST paid)", amount(gstCollected - gstPaid)),
            ("Invoices sent", String(sent.count)),
            ("Expenses", String(out.count)),
        ]
        let lines = ["Item,Amount"] + rows.map { csvText($0.0) + "," + csvField($0.1) }
            + [csvField("Prepared by Quote Pilot on \(today.short). Figures are from Quote Pilot's records; check with your accountant.") + ","]
        return lines.joined(separator: "\n") + "\n"
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
