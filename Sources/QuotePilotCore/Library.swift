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

    public init(brand: Brand = Brand()) {
        format = Library.currentFormat
        self.brand = brand
        clients = []
        quotes = []
        invoices = []
        activity = []
        usedNumbers = []
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

    public mutating func update(_ quote: Quote) throws {
        let index = try quoteIndex(quote.id)
        quotes[index] = quote
    }

    public mutating func update(_ invoice: Invoice) throws {
        let index = try invoiceIndex(invoice.id)
        invoices[index] = invoice
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
