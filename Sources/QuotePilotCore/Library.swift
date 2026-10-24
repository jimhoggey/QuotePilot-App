import Foundation

public enum DocumentKind: Sendable {
    case quote, invoice

    var prefix: String { self == .quote ? "Q-" : "INV-" }
}

public enum LibraryError: Error, Equatable, Sendable {
    case notFound
    case notDraft
    case notSent
    case notAccepted
    case nothingAccepted
    case nothingLeftToInvoice
    case alreadyInvoiced
    case isVoid
    case hasPayments
    /// A deposit invoice a live final invoice (its number) still subtracts.
    case deductedByFinal(String)
    case unknownLineCodes([String])
    /// Sent and void invoices are records; only drafts change.
    case notEditable
    case noPayments
    case paymentNotPositive
    /// More than the amount still owing (given).
    case paymentMoreThanOwing(Money)
    /// A client (its name) that a quote or invoice, of any stage, still names.
    case clientInUse(String)
    /// Deleting a deposit invoice while the live final invoice (its number) still subtracts it: the
    /// final goes first.
    case depositStillDeducted(String)
    /// A quote (its number) with invoices (their numbers), deleted without saying they go with it.
    case quoteHasInvoices(quote: String, invoices: [String])
    /// A number (given) another quote or invoice in the library already has.
    case numberInUse(String)
    /// Only a draft's number can be changed: a sent one has gone out with it.
    case numberOnlyOnDrafts
    /// Text (given) that isn't a number of the kind with that prefix.
    case notANumber(String, String)
    /// Numbering can't start again while any quote or invoice is in the library.
    case documentsStillThere
    /// An expense whose GST is more than its total.
    case gstMoreThanTotal
}

/// Everything Quote Pilot knows, saved as one file.
public struct Library: Codable, Sendable {
    public static let currentFormat = 1

    public var format: Int
    public var brand: Brand
    public var clients: [Client]
    public var quotes: [Quote]
    public var invoices: [Invoice]
    /// Newest first.
    public var activity: [ActivityEntry]
    /// Every number ever issued, so deleting a draft never frees its number.
    public var usedNumbers: [String]
    /// What the business paid for, in the order added.
    public var expenses: [Expense]

    public init(brand: Brand = Brand()) {
        format = Library.currentFormat
        self.brand = brand
        clients = []
        quotes = []
        invoices = []
        activity = []
        usedNumbers = []
        expenses = []
    }

    // MARK: Numbering

    /// One past the highest number ever used with that prefix: "Q-0007".
    public func nextNumber(_ kind: DocumentKind) -> String {
        let prefix = kind.prefix
        let highest = usedNumbers
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count)) }
            .max() ?? 0
        return prefix + String(format: "%04d", highest + 1)
    }

    public mutating func takeNumber(_ kind: DocumentKind) -> String {
        let number = nextNumber(kind)
        usedNumbers.append(number)
        return number
    }

    /// Adds numbers that were issued elsewhere (a library a restore replaced, or a PDF already mailed)
    /// to the used ones. Numbers already there are left alone, so it can run twice.
    public mutating func keepUsed(_ numbers: [String]) {
        var known = Set(usedNumbers)
        for number in numbers where known.insert(number).inserted {
            usedNumbers.append(number)
        }
    }

    /// Every number this library has put on a quote or invoice, whether or not `usedNumbers` lists it
    /// (a library saved before that list existed).
    public var documentNumbers: [String] {
        quotes.map(\.number) + invoices.map(\.number)
    }

    // MARK: Lookups

    public func client(_ id: UUID?) -> Client? { clients.first { $0.id == id } }
    public func quote(_ id: UUID) -> Quote? { quotes.first { $0.id == id } }
    public func invoice(_ id: UUID) -> Invoice? { invoices.first { $0.id == id } }

    public func quote(number: String) -> Quote? {
        quotes.first { $0.number.caseInsensitiveCompare(number) == .orderedSame }
    }

    func quoteIndex(_ id: UUID) throws -> Int {
        guard let index = quotes.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        return index
    }

    func invoiceIndex(_ id: UUID) throws -> Int {
        guard let index = invoices.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        return index
    }

    // MARK: Activity

    public mutating func log(_ message: String, number: String? = nil, at time: Date = Date()) {
        activity.insert(ActivityEntry(at: time, number: number, message: message), at: 0)
    }

    // MARK: Creating and editing

    public mutating func addClient(_ client: Client) {
        clients.append(client)
        log("Added client \(client.name)")
    }

    /// Whether `deleteClient` would work: the client exists and no quote or invoice names them. Drafts
    /// and void invoices count too, as each still shows the client on screen and in its PDF.
    public func canDeleteClient(_ id: UUID) -> Bool {
        client(id) != nil && !quotes.contains { $0.clientID == id } && !invoices.contains { $0.clientID == id }
    }

    /// Removes a client nobody has been quoted or invoiced under (a stray "New client", say). A client
    /// with any quote or invoice stays, so no document ever loses the person it was written to.
    public mutating func deleteClient(_ id: UUID) throws {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        guard canDeleteClient(id) else { throw LibraryError.clientInUse(clients[index].name) }
        let name = clients.remove(at: index).name
        // A client with no name yet shows as "(no name)" in the list, so Activity does too.
        log("Deleted client \(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no name)" : name)")
    }

    @discardableResult
    public mutating func newQuote(on day: Day, clientID: UUID? = nil) -> Quote {
        let quote = Quote(number: takeNumber(.quote), clientID: clientID, issued: day,
                          validUntil: day.adding(days: brand.quoteValidDays),
                          taxed: brand.gstRegistered, terms: brand.quoteTerms)
        quotes.append(quote)
        log("Started quote \(quote.number)", number: quote.number)
        return quote
    }

    /// A standalone invoice: extra hourly work, a monthly fee.
    @discardableResult
    public mutating func newInvoice(on day: Day, clientID: UUID? = nil) -> Invoice {
        let invoice = Invoice(number: takeNumber(.invoice), clientID: clientID, kind: .standalone,
                              issued: day, due: day.adding(days: brand.paymentDueDays),
                              taxed: brand.gstRegistered, terms: brand.invoiceTerms)
        invoices.append(invoice)
        log("Started invoice \(invoice.number)", number: invoice.number)
        return invoice
    }

    /// Stores an edited quote. A draft's line IDs are renumbered first, so what's stored is what the PDF
    /// shows and what sending freezes. Once the quote has live invoices, nothing that changes what is
    /// billed may change (its client, plan, tax, or any line's amount, decision or ID, or a line added
    /// or removed); wording and dates may.
    public mutating func update(_ quote: Quote) throws {
        let index = try quoteIndex(quote.id)
        var quote = quote
        quote.renumberLinesIfDraft()
        if !invoices(forQuote: quote.id).isEmpty, quote.billsDifferently(from: quotes[index]) {
            throw LibraryError.alreadyInvoiced
        }
        quotes[index] = quote
    }

    /// Stores the editable parts of a draft invoice: title, dates, terms, lines and tax, and the client
    /// for a standalone invoice (one from a quote keeps the quote's client). Stage, payments, Sent
    /// dates, kind, quote, deposit share and deductions only change through their own actions, so an
    /// editor can never rewrite them. A deposit that a live final invoice subtracts keeps what it
    /// bills, or the final would deduct a different amount than the deposit asks for.
    public mutating func update(_ invoice: Invoice) throws {
        let index = try invoiceIndex(invoice.id)
        let old = invoices[index]
        if let final = liveFinalDeducting(old),
           invoice.lines != old.lines || invoice.taxed != old.taxed || invoice.depositPercent != old.depositPercent
            || invoice.number != old.number || invoice.stage != old.stage || invoice.kind != old.kind
            || invoice.quoteID != old.quoteID || invoice.deductions != old.deductions {
            throw LibraryError.deductedByFinal(final.number)
        }
        guard old.stage == .draft else { throw LibraryError.notEditable }
        var updated = old
        updated.title = invoice.title
        updated.issued = invoice.issued
        updated.due = invoice.due
        updated.terms = invoice.terms
        updated.lines = invoice.lines
        updated.taxed = invoice.taxed
        if old.quoteID == nil { updated.clientID = invoice.clientID }
        invoices[index] = updated
    }

    public mutating func deleteDraft(quote id: UUID) throws {
        let index = try quoteIndex(id)
        guard quotes[index].stage == .draft else { throw LibraryError.notDraft }
        let number = quotes.remove(at: index).number
        log("Deleted draft quote \(number)", number: number)
    }

    public mutating func deleteDraft(invoice id: UUID) throws {
        let index = try invoiceIndex(id)
        guard invoices[index].stage == .draft else { throw LibraryError.notDraft }
        if let final = liveFinalDeducting(invoices[index]) { throw LibraryError.deductedByFinal(final.number) }
        let number = invoices.remove(at: index).number
        log("Deleted draft invoice \(number)", number: number)
    }

    // MARK: Starting fresh

    /// File → Start Fresh: every quote, invoice and payment goes, and Activity, and numbering starts
    /// again at Q-0001 and INV-0001. Brand settings stay, and so do clients unless `removingClients`.
    /// Activity then has the one entry saying so.
    public mutating func startFresh(removingClients: Bool, at time: Date = Date()) {
        quotes = []
        invoices = []
        activity = []
        usedNumbers = []
        if removingClients { clients = [] }
        log(removingClients
            ? "Started fresh: removed every quote, invoice, payment and client, and Activity"
            : "Started fresh: removed every quote, invoice and payment, and Activity", at: time)
    }

    /// Whether numbering can start again at 0001: only with no quotes or invoices at all, so no number
    /// could be on two documents.
    public var canResetNumbers: Bool { quotes.isEmpty && invoices.isEmpty }

    /// File → Reset Quote and Invoice Numbers…: the next quote is Q-0001 and the next invoice INV-0001.
    public mutating func resetNumbers(at time: Date = Date()) throws {
        guard canResetNumbers else { throw LibraryError.documentsStillThere }
        usedNumbers = []
        log("Reset numbering: the next quote is \(nextNumber(.quote)) and the next invoice \(nextNumber(.invoice))", at: time)
    }

    // MARK: JSON

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension Quote {
    /// True when `old`'s invoices would no longer add up under this version: a different plan or tax
    /// setting, a line added or removed, or any line with another quantity, unit, rate, decision or ID.
    /// A different client counts too: an invoice keeps its quote's client, so one job would be split
    /// across two clients. Titles, details, order, summary, terms and dates don't count.
    func billsDifferently(from old: Quote) -> Bool {
        struct Billed: Hashable {
            var id: UUID
            var code: String
            var quantity: Decimal
            var unit: Unit
            var rate: Money
            var decision: LineDecision?

            init(_ line: LineItem) {
                id = line.id
                code = line.code
                quantity = line.quantity
                unit = line.unit
                rate = line.rate
                decision = line.decision
            }
        }
        return plan != old.plan || taxed != old.taxed || clientID != old.clientID
            || lines.count != old.lines.count
            || Set(lines.map(Billed.init)) != Set(old.lines.map(Billed.init))
    }
}

// MARK: - Limits

extension Library {
    /// The most a rate, payment or deduction may be, either way: $10,000,000. The editors never take
    /// more, and a file holding more is a slip or damage: adding amounts that large can overflow,
    /// which would stop the app every time it opened.
    public static let amountLimit = Money(cents: 1_000_000_000)
    /// The most a line's quantity may be. It's never below 0.
    public static let quantityLimit: Decimal = 100_000
    /// The brand's day counts (payment due after, quotes valid for). Beyond this, working out a due
    /// date could land past the year 9999 that a `Day` can hold.
    public static let dayCountLimit = 0...365

    public static func allows(_ amount: Money) -> Bool {
        // A range check, not abs(): abs(Int.min) traps.
        (-amountLimit.cents...amountLimit.cents).contains(amount.cents)
    }

    public static func allows(quantity: Decimal) -> Bool {
        !quantity.isNaN && quantity >= 0 && quantity <= quantityLimit
    }

    /// A plain sentence for each number past those limits; empty when the library is fine. A
    /// library with problems loads as unreadable, so the app never works with numbers it can't add up.
    public func problems() -> [String] {
        let currency = brand.currencyCode
        var found: [String] = []
        if !Library.dayCountLimit.contains(brand.paymentDueDays) {
            found.append("Brand: payment is due after \(brand.paymentDueDays) days, outside 0 to 365.")
        }
        if !Library.dayCountLimit.contains(brand.quoteValidDays) {
            found.append("Brand: quotes are valid for \(brand.quoteValidDays) days, outside 0 to 365.")
        }
        // The same limit as a line's rate, but never below 0: a discount is a line, not an hourly rate.
        if let rate = brand.hourlyRate, rate < .zero || !Library.allows(rate) {
            found.append("Brand: the hourly rate is \(rate.formatted(currencyCode: currency)), outside "
                + "\(Money.zero.formatted(currencyCode: currency)) to \(Library.amountLimit.formatted(currencyCode: currency)).")
        }
        // A NaN is outside the range too: every comparison with it is false.
        if !AppFee.percentLimit.contains(brand.appFee.percent) {
            found.append("Brand: the Quote Pilot fee is \(brand.appFee.percent)%, outside 0 to 100%.")
        }
        let over = "over the \(Library.amountLimit.formatted(currencyCode: currency)) limit"
        for (month, paid) in brand.appFee.paidMonths.sorted(by: { $0.key < $1.key }) where !Library.allows(paid.amount) {
            found.append("Brand: the Quote Pilot fee paid for \(month) is \(paid.amount.formatted(currencyCode: currency)), \(over).")
        }
        func check(_ lines: [LineItem], of number: String) {
            for (index, line) in lines.enumerated() {
                let name = "\(number) line \(line.code.isEmpty ? String(index + 1) : line.code)"
                if !Library.allows(line.rate) {
                    found.append("\(name) has a rate of \(line.rate.formatted(currencyCode: currency)), \(over).")
                }
                if !Library.allows(quantity: line.quantity) {
                    found.append("\(name) has a quantity of \(line.quantity), outside 0 to 100,000.")
                }
            }
        }
        for quote in quotes {
            check(quote.lines, of: quote.number)
        }
        for invoice in invoices {
            check(invoice.lines, of: invoice.number)
            if let percent = invoice.depositPercent, !(0...100).contains(percent) {
                found.append("\(invoice.number) has a deposit of \(percent)%, outside 0 to 100%.")
            }
            for payment in invoice.payments where !Library.allows(payment.amount) {
                found.append("\(invoice.number) has a payment of \(payment.amount.formatted(currencyCode: currency)), \(over).")
            }
            for deduction in invoice.deductions where !Library.allows(deduction.amount) {
                found.append("\(invoice.number) takes off \(deduction.amount.formatted(currencyCode: currency)) for \(deduction.invoiceNumber), \(over).")
            }
        }
        for expense in expenses {
            let name = "The expense from \(expense.supplier.isEmpty ? "(no supplier)" : expense.supplier) on \(expense.date.short)"
            if !Library.allows(expense.total) || !Library.allows(expense.gst) {
                found.append("\(name) is \(expense.total.formatted(currencyCode: currency)) with \(expense.gst.formatted(currencyCode: currency)) GST, \(over).")
            } else if expense.gst > expense.total {
                found.append("\(name) has more GST (\(expense.gst.formatted(currencyCode: currency))) than its total (\(expense.total.formatted(currencyCode: currency))).")
            }
        }
        return found
    }

    /// `opening`, then the first three problems, then how many more there are.
    static func describe(_ problems: [String], opening: String) -> String {
        var text = ([opening] + problems.prefix(3)).joined(separator: " ")
        if problems.count > 3 { text += " And \(problems.count - 3) more." }
        return text
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when the file was saved before that field existed.
    func value<T: Decodable>(_ key: Key, or fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}

extension Library {
    enum CodingKeys: String, CodingKey {
        case format, brand, clients, quotes, invoices, activity, usedNumbers, expenses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.value(.format, or: Library.currentFormat)
        brand = try c.value(.brand, or: Brand())
        clients = try c.value(.clients, or: [])
        quotes = try c.value(.quotes, or: [])
        invoices = try c.value(.invoices, or: [])
        activity = try c.value(.activity, or: [])
        usedNumbers = try c.value(.usedNumbers, or: [])
        expenses = try c.value(.expenses, or: [])
    }
}
