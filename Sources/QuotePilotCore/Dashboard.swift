import Foundation

/// An Australian financial year: 1 July to 30 June.
public struct FinancialYear: Hashable, Sendable {
    public let startYear: Int

    public init(startYear: Int) {
        self.startYear = startYear
    }

    public init(containing day: Day) {
        startYear = day.month >= 7 ? day.year : day.year - 1
    }

    public var start: Day { Day(year: startYear, month: 7, day: 1) }
    public var end: Day { Day(year: startYear + 1, month: 6, day: 30) }

    public func contains(_ day: Day) -> Bool { start <= day && day <= end }

    /// "FY 2026–27"
    public var label: String { "FY \(startYear)–" + String(format: "%02d", (startYear + 1) % 100) }
}

/// The main screen's figures, worked out from the library for one day.
public struct Dashboard: Equatable, Sendable {
    public struct Owing: Equatable, Sendable {
        public var invoiceID: UUID
        public var number: String
        public var client: String
        public var owing: Money
        public var due: Day
        /// 0 when not overdue yet.
        public var daysLate: Int
    }

    public struct OpenQuote: Equatable, Sendable {
        public var quoteID: UUID
        public var number: String
        public var client: String
        public var total: Money
        public var validUntil: Day
        public var expired: Bool
    }

    public struct ToInvoice: Equatable, Sendable {
        public var quoteID: UUID
        public var number: String
        public var client: String
        public var accepted: Money
        public var invoiced: Money
        public var remaining: Money { accepted - invoiced }
    }

    public var today: Day
    public var financialYear: FinancialYear
    public var waiting: [Owing]
    public var waitingTotal: Money
    public var overdueTotal: Money
    public var receivedThisMonth: Money
    public var receivedThisYear: Money
    public var invoicedThisYear: Money
    public var openQuotes: [OpenQuote]
    /// Open quotes that haven't expired.
    public var openQuotesTotal: Money
    public var toInvoice: [ToInvoice]
    /// The money still to come from accepted work: for every accepted (or partly accepted) quote not
    /// fully paid yet, its accepted total (with GST when the quote charges it) less every payment on
    /// its live invoices. It covers what is invoiced but unpaid as well as what isn't invoiced yet.
    public var acceptedWorkRemaining: Money
    /// How many accepted jobs `acceptedWorkRemaining` covers.
    public var acceptedJobsOpen: Int
    /// The part of `acceptedWorkRemaining` not invoiced yet: the "Still to invoice" list's sum.
    public var acceptedWorkNotInvoiced: Money

    public init(library: Library, today: Day) {
        self.today = today
        let year = FinancialYear(containing: today)
        financialYear = year
        func clientName(_ id: UUID?) -> String { library.client(id)?.name ?? "No client" }
        func sum(_ amounts: [Money]) -> Money { amounts.reduce(.zero, +) }

        let sent = library.invoices.filter { $0.stage == .sent }

        waiting = sent
            .filter { $0.owing > .zero }
            .map { Owing(invoiceID: $0.id, number: $0.number, client: clientName($0.clientID), owing: $0.owing,
                         due: $0.due, daysLate: max(0, today.days(since: $0.due))) }
            .sorted { a, b in
                if a.daysLate != b.daysLate { return a.daysLate > b.daysLate }
                return a.due < b.due
            }
        waitingTotal = sum(waiting.map(\.owing))
        overdueTotal = sum(waiting.filter { $0.daysLate > 0 }.map(\.owing))

        let payments = sent.flatMap(\.payments)
        receivedThisMonth = sum(payments.filter { $0.date.year == today.year && $0.date.month == today.month }.map(\.amount))
        receivedThisYear = sum(payments.filter { year.contains($0.date) }.map(\.amount))
        invoicedThisYear = sum(sent.filter { year.contains($0.issued) }.map(\.amount))

        openQuotes = library.quotes
            .filter { $0.stage == .sent }
            .map { OpenQuote(quoteID: $0.id, number: $0.number, client: clientName($0.clientID),
                             total: $0.totals.total, validUntil: $0.validUntil, expired: today > $0.validUntil) }
            .sorted { $0.validUntil < $1.validUntil }
        openQuotesTotal = sum(openQuotes.filter { !$0.expired }.map(\.total))

        toInvoice = library.quotes
            .filter { $0.stage == .accepted }
            .map { ToInvoice(quoteID: $0.id, number: $0.number, client: clientName($0.clientID),
                             accepted: $0.acceptedTotals.total, invoiced: library.invoicedAmount(forQuote: $0.id)) }
            .filter { $0.remaining > .zero }
            .sorted { $0.number < $1.number }

        let leftOnJobs = library.quotes
            .filter { $0.stage == .accepted }
            .map { quote in quote.acceptedTotals.total - sum(library.invoices(forQuote: quote.id).map(\.paid)) }
            .filter { $0 > .zero }
        acceptedWorkRemaining = sum(leftOnJobs)
        acceptedJobsOpen = leftOnJobs.count
        acceptedWorkNotInvoiced = sum(toInvoice.map(\.remaining))
    }
}

extension Library {
    /// Payments received in a financial year, oldest first, for tax time.
    public func paymentsCSV(for year: FinancialYear) -> String {
        let pairs: [(Invoice, Payment)] = invoices
            .filter { $0.stage == .sent }
            .flatMap { invoice -> [(Invoice, Payment)] in
                invoice.payments.filter { year.contains($0.date) }.map { (invoice, $0) }
            }
            .sorted { a, b in a.1.date == b.1.date ? a.0.number < b.0.number : a.1.date < b.1.date }
        let rows = pairs.map { pair -> String in
            let (invoice, payment) = pair
            return [csvField(payment.date.iso), csvText(client(invoice.clientID)?.name ?? ""),
                    csvField(invoice.number), csvField(payment.amount.plain), csvField(payment.method.label),
                    csvText(payment.note)]
                .joined(separator: ",")
        }
        return (["Date,Client,Invoice,Amount,Method,Note"] + rows).joined(separator: "\n") + "\n"
    }
}

/// Quotes a CSV field when it holds a comma, a quote mark or any line break (`isNewline` also
/// catches "\r\n", which Swift treats as one Character that isn't equal to "\n").
func csvField(_ text: String) -> String {
    guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

/// Text someone typed, made safe for a spreadsheet: a field starting with =, +, - or @ would run as
/// a formula, so it gets a leading apostrophe.
func csvText(_ text: String) -> String {
    guard let first = text.first, "=+-@".contains(first) else { return csvField(text) }
    return csvField("'" + text)
}
