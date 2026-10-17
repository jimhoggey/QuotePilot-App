import Foundation

// MARK: - Brand

public struct EmailTemplate: Codable, Hashable, Sendable {
    public var subject: String
    public var body: String

    public init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }

    /// Replaces `{key}` placeholders: client, contact, number, amount, due, business.
    public func filled(_ values: [String: String]) -> (subject: String, body: String) {
        func fill(_ text: String) -> String {
            values.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
        }
        return (fill(subject), fill(body))
    }
}

public struct EmailTemplates: Codable, Hashable, Sendable {
    public var quote: EmailTemplate
    public var invoice: EmailTemplate
    public var receipt: EmailTemplate

    public static let standard = EmailTemplates(
        quote: EmailTemplate(
            subject: "Quote {number} from {business}",
            body: """
            Hi {contact},

            Attached is quote {number}. Tick the lines you'd like to go ahead with, or tick Accept all, \
            add your name and the date, then save the PDF and send it back to me.

            Thanks,
            {business}
            """),
        invoice: EmailTemplate(
            subject: "Invoice {number} from {business}",
            body: """
            Hi {contact},

            Attached is invoice {number} for {amount}, due {due}. Payment details are on the invoice.

            Thanks,
            {business}
            """),
        receipt: EmailTemplate(
            subject: "Receipt for invoice {number}",
            body: """
            Hi {contact},

            Thanks for your payment. Attached is your receipt for invoice {number}.

            Thanks,
            {business}
            """)
    )
}

/// The one business identity on every document.
public struct Brand: Codable, Hashable, Sendable {
    public var businessName = ""
    /// Address, email, phone, website: one per line, printed under the business name.
    public var details = ""
    /// Printed with the business details on every quote, invoice and receipt whenever it's filled
    /// in, GST or not.
    public var abn = ""
    /// Bank, BSB and account, or PayID.
    public var paymentDetails = ""
    public var accentHex = "#0B6B66"
    /// File names inside the library's Assets folder.
    public var logoFile: String?
    public var headingFontFile: String?
    /// Which named style of the heading font to use (Bold, ExtraBold Italic, …); nil is the font's own
    /// default. Only meaningful beside `headingFontFile`.
    public var headingFontStyle: FontStyle?
    /// The font for the text of quotes and invoices (lines, addresses, terms, notes), a file name in
    /// Assets like the heading font; nil is the standard Mac font.
    public var bodyFontFile: String?
    /// Which named style of the body font to use; nil is the font's own default.
    public var bodyFontStyle: FontStyle?
    public var quoteTerms = "Prices are fixed for the work listed. Work starts once this quote is accepted."
    public var invoiceTerms = "Please use the invoice number as your payment reference."
    public var emails = EmailTemplates.standard
    public var gstRegistered = false
    public var currencyCode = "AUD"
    public var paymentDueDays = 14
    public var quoteValidDays = 30
    /// The one rate that new lines in hours start at (`LineItem.withHourlyRate`); nil when none is set.
    public var hourlyRate: Money?
    /// Quote Pilot's own fee setting (Brand → Settings), kept with the library. Prints nowhere.
    public var appFee = AppFee()

    public init() {}
}

// MARK: - Clients

public struct Client: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var contactName: String
    public var email: String
    public var phone: String
    public var address: String
    public var notes: String

    public init(id: UUID = UUID(), name: String, contactName: String = "", email: String = "",
                phone: String = "", address: String = "", notes: String = "") {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.address = address
        self.notes = notes
    }

    /// Who "Hi …" is addressed to: the contact's first name, or the business name.
    public var greetingName: String {
        let first = contactName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? name : first
    }
}

// MARK: - Quotes

public enum PaymentPlan: String, Codable, CaseIterable, Sendable {
    case fiftyFifty, fullAmount

    public var depositPercent: Int? { self == .fiftyFifty ? 50 : nil }

    public var summary: String {
        switch self {
        case .fiftyFifty: return "50% when the quote is accepted, 50% on completion"
        case .fullAmount: return "Full amount on completion"
        }
    }
}

public enum QuoteStage: String, Codable, Sendable {
    case draft, sent, accepted, declined
}

public enum AcceptanceSource: String, Codable, Sendable {
    case returnedPDF, byHand
}

/// What the client decided, and how Quote Pilot learned it.
public struct Acceptance: Codable, Hashable, Sendable {
    public var recordedAt: Date
    public var source: AcceptanceSource
    public var fileName: String?
    public var clientName: String
    public var clientDate: String
    public var accepted: [String]
    public var declined: [String]

    public init(recordedAt: Date = Date(), source: AcceptanceSource, fileName: String? = nil,
                clientName: String = "", clientDate: String = "", accepted: [String], declined: [String]) {
        self.recordedAt = recordedAt
        self.source = source
        self.fileName = fileName
        self.clientName = clientName
        self.clientDate = clientDate
        self.accepted = accepted
        self.declined = declined
    }
}

public struct Quote: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var number: String
    public var clientID: UUID?
    /// Shown as the reference, e.g. "Website rebuild, phase 1".
    public var title: String
    public var issued: Day
    public var validUntil: Day
    public var plan: PaymentPlan
    public var taxed: Bool
    public var lines: [LineItem]
    /// The highest line number ever given out on this quote, so a sent quote never reuses a line ID.
    public var lastLineNumber: Int
    /// Plain text; lines starting with a dash, "•" or "*" print as dot points.
    public var summary: String
    /// What the job includes and what it leaves out, one item each; both optional. The PDF prints them
    /// side by side only when either has an item.
    public var included: [String] = []
    public var notIncluded: [String] = []
    public var terms: String
    public var stage: QuoteStage
    public var sentAt: Date?
    public var acceptance: Acceptance?
    public var completedOn: Day?

    public init(id: UUID = UUID(), number: String, clientID: UUID? = nil, title: String = "",
                issued: Day, validUntil: Day, plan: PaymentPlan = .fiftyFifty, taxed: Bool = false,
                lines: [LineItem] = [], summary: String = "", terms: String = "", stage: QuoteStage = .draft) {
        self.id = id
        self.number = number
        self.clientID = clientID
        self.title = title
        self.issued = issued
        self.validUntil = validUntil
        self.plan = plan
        self.taxed = taxed
        self.lines = lines
        self.lastLineNumber = lines.compactMap { Int($0.code) }.max() ?? 0
        self.summary = summary
        self.terms = terms
        self.stage = stage
    }

    public var totals: Totals { Totals(subtotal: lines.subtotal, taxed: taxed) }
    public var acceptedLines: [LineItem] { lines.filter { $0.decision == .accepted } }
    public var acceptedTotals: Totals { Totals(subtotal: acceptedLines.subtotal, taxed: taxed) }

    /// What a dot point may start with, as typed or pasted: a dash of any length, a bullet or an asterisk.
    static let listMarkers: Set<Character> = ["-", "–", "—", "•", "*"]

    /// The items of an Included or Not included box: one per line, without the dot-point marker it
    /// was typed or pasted with, and without blank lines.
    public static func listItems(from text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            var item = Substring(line.trimmingCharacters(in: .whitespaces))
            while let first = item.first, listMarkers.contains(first) {
                item = item.dropFirst().drop(while: { $0.isWhitespace })
            }
            return item.isEmpty ? nil : String(item)
        }
    }
}

// MARK: - Invoices

public enum InvoiceKind: String, Codable, Sendable {
    case deposit, final, full, standalone
}

public enum InvoiceStage: String, Codable, Sendable {
    case draft, sent, void
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable {
    case bankTransfer, cash, card, other

    public var label: String {
        switch self {
        case .bankTransfer: return "Bank transfer"
        case .cash: return "Cash"
        case .card: return "Card"
        case .other: return "Other"
        }
    }
}

public struct Payment: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Day
    public var amount: Money
    public var method: PaymentMethod
    public var note: String

    public init(id: UUID = UUID(), date: Day, amount: Money, method: PaymentMethod = .bankTransfer, note: String = "") {
        self.id = id
        self.date = date
        self.amount = amount
        self.method = method
        self.note = note
    }
}

/// An earlier invoice that a final invoice subtracts: "Less deposit, INV-0004".
public struct Deduction: Codable, Hashable, Sendable {
    public var label: String
    public var invoiceNumber: String
    public var amount: Money

    public init(label: String, invoiceNumber: String, amount: Money) {
        self.label = label
        self.invoiceNumber = invoiceNumber
        self.amount = amount
    }
}

public struct Invoice: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var number: String
    public var clientID: UUID?
    public var quoteID: UUID?
    public var kind: InvoiceKind
    public var title: String
    public var issued: Day
    public var due: Day
    public var taxed: Bool
    public var lines: [LineItem]
    /// Deposit invoices bill this percentage of the lines' total.
    public var depositPercent: Int?
    public var deductions: [Deduction]
    public var terms: String
    public var stage: InvoiceStage
    public var sentAt: Date?
    public var payments: [Payment]
    public var receiptSentAt: Date?

    public init(id: UUID = UUID(), number: String, clientID: UUID? = nil, quoteID: UUID? = nil,
                kind: InvoiceKind, title: String = "", issued: Day, due: Day, taxed: Bool = false,
                lines: [LineItem] = [], terms: String = "", stage: InvoiceStage = .draft) {
        self.id = id
        self.number = number
        self.clientID = clientID
        self.quoteID = quoteID
        self.kind = kind
        self.title = title
        self.issued = issued
        self.due = due
        self.taxed = taxed
        self.lines = lines
        self.depositPercent = nil
        self.deductions = []
        self.terms = terms
        self.stage = stage
        self.payments = []
    }

    /// The lines' totals, before any deposit share or deduction.
    public var lineTotals: Totals { Totals(subtotal: lines.subtotal, taxed: taxed) }

    /// What this invoice asks the client to pay altogether.
    public var amount: Money {
        let base = lineTotals.total
        if let percent = depositPercent { return base.percent(percent) }
        return deductions.reduce(base) { $0 - $1.amount }
    }

    public var paid: Money { payments.reduce(.zero) { $0 + $1.amount } }
    public var owing: Money { amount - paid }
}

// MARK: - Activity

public struct ActivityEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var at: Date
    /// The quote or invoice number it's about, if any.
    public var number: String?
    public var message: String

    public init(id: UUID = UUID(), at: Date, number: String?, message: String) {
        self.id = id
        self.at = at
        self.number = number
        self.message = message
    }
}

// MARK: - Tolerant decoding
// A field added in a later version must not make an older library unreadable, so every
// non-essential field falls back to its default when it's missing.

extension Brand {
    enum CodingKeys: String, CodingKey {
        case businessName, details, abn, paymentDetails, accentHex, logoFile, headingFontFile
        case quoteTerms, invoiceTerms, emails, gstRegistered, currencyCode, paymentDueDays, quoteValidDays
        case hourlyRate, headingFontStyle, bodyFontFile, bodyFontStyle, appFee
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Brand()
        businessName = try c.value(.businessName, or: d.businessName)
        details = try c.value(.details, or: d.details)
        abn = try c.value(.abn, or: d.abn)
        paymentDetails = try c.value(.paymentDetails, or: d.paymentDetails)
        accentHex = try c.value(.accentHex, or: d.accentHex)
        logoFile = try c.decodeIfPresent(String.self, forKey: .logoFile)
        headingFontFile = try c.decodeIfPresent(String.self, forKey: .headingFontFile)
        quoteTerms = try c.value(.quoteTerms, or: d.quoteTerms)
        invoiceTerms = try c.value(.invoiceTerms, or: d.invoiceTerms)
        emails = try c.value(.emails, or: d.emails)
        gstRegistered = try c.value(.gstRegistered, or: d.gstRegistered)
        currencyCode = try c.value(.currencyCode, or: d.currencyCode)
        paymentDueDays = try c.value(.paymentDueDays, or: d.paymentDueDays)
        quoteValidDays = try c.value(.quoteValidDays, or: d.quoteValidDays)
        hourlyRate = try c.decodeIfPresent(Money.self, forKey: .hourlyRate)
        // A style that can't be read is the font's default, not an unreadable library.
        headingFontStyle = try? c.decodeIfPresent(FontStyle.self, forKey: .headingFontStyle)
        bodyFontFile = try c.decodeIfPresent(String.self, forKey: .bodyFontFile)
        bodyFontStyle = try? c.decodeIfPresent(FontStyle.self, forKey: .bodyFontStyle)
        appFee = try c.value(.appFee, or: d.appFee)
    }
}

extension Client {
    enum CodingKeys: String, CodingKey {
        case id, name, contactName, email, phone, address, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        contactName = try c.value(.contactName, or: "")
        email = try c.value(.email, or: "")
        phone = try c.value(.phone, or: "")
        address = try c.value(.address, or: "")
        notes = try c.value(.notes, or: "")
    }
}

extension Quote {
    enum CodingKeys: String, CodingKey {
        case id, number, clientID, title, issued, validUntil, plan, taxed, lines, lastLineNumber
        case summary, included, notIncluded, terms, stage, sentAt, acceptance, completedOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(String.self, forKey: .number)
        clientID = try c.decodeIfPresent(UUID.self, forKey: .clientID)
        title = try c.value(.title, or: "")
        issued = try c.decode(Day.self, forKey: .issued)
        validUntil = try c.decode(Day.self, forKey: .validUntil)
        plan = try c.value(.plan, or: .fiftyFifty)
        taxed = try c.value(.taxed, or: false)
        lines = try c.value(.lines, or: [])
        lastLineNumber = try c.value(.lastLineNumber, or: lines.compactMap { Int($0.code) }.max() ?? 0)
        summary = try c.value(.summary, or: "")
        included = try c.value(.included, or: [])
        notIncluded = try c.value(.notIncluded, or: [])
        terms = try c.value(.terms, or: "")
        stage = try c.value(.stage, or: .draft)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        acceptance = try c.decodeIfPresent(Acceptance.self, forKey: .acceptance)
        completedOn = try c.decodeIfPresent(Day.self, forKey: .completedOn)
    }
}

extension Invoice {
    enum CodingKeys: String, CodingKey {
        case id, number, clientID, quoteID, kind, title, issued, due, taxed, lines, depositPercent
        case deductions, terms, stage, sentAt, payments, receiptSentAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(String.self, forKey: .number)
        clientID = try c.decodeIfPresent(UUID.self, forKey: .clientID)
        quoteID = try c.decodeIfPresent(UUID.self, forKey: .quoteID)
        kind = try c.decode(InvoiceKind.self, forKey: .kind)
        title = try c.value(.title, or: "")
        issued = try c.decode(Day.self, forKey: .issued)
        due = try c.decode(Day.self, forKey: .due)
        taxed = try c.value(.taxed, or: false)
        lines = try c.value(.lines, or: [])
        depositPercent = try c.decodeIfPresent(Int.self, forKey: .depositPercent)
        deductions = try c.value(.deductions, or: [])
        terms = try c.value(.terms, or: "")
        stage = try c.value(.stage, or: .draft)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        payments = try c.value(.payments, or: [])
        receiptSentAt = try c.decodeIfPresent(Date.self, forKey: .receiptSentAt)
    }
}

extension EmailTemplate {
    enum CodingKeys: String, CodingKey {
        case subject, body
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.value(.subject, or: "")
        body = try c.value(.body, or: "")
    }
}

extension EmailTemplates {
    enum CodingKeys: String, CodingKey {
        case quote, invoice, receipt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let standard = EmailTemplates.standard
        quote = try c.value(.quote, or: standard.quote)
        invoice = try c.value(.invoice, or: standard.invoice)
        receipt = try c.value(.receipt, or: standard.receipt)
    }
}

extension Acceptance {
    enum CodingKeys: String, CodingKey {
        case recordedAt, source, fileName, clientName, clientDate, accepted, declined
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        source = try c.decode(AcceptanceSource.self, forKey: .source)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        clientName = try c.value(.clientName, or: "")
        clientDate = try c.value(.clientDate, or: "")
        accepted = try c.value(.accepted, or: [])
        declined = try c.value(.declined, or: [])
    }
}

extension Payment {
    enum CodingKeys: String, CodingKey {
        case id, date, amount, method, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Day.self, forKey: .date)
        amount = try c.decode(Money.self, forKey: .amount)
        method = try c.value(.method, or: .bankTransfer)
        note = try c.value(.note, or: "")
    }
}

extension Deduction {
    enum CodingKeys: String, CodingKey {
        case label, invoiceNumber, amount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.value(.label, or: "Less deposit")
        invoiceNumber = try c.decode(String.self, forKey: .invoiceNumber)
        amount = try c.decode(Money.self, forKey: .amount)
    }
}

extension ActivityEntry {
    enum CodingKeys: String, CodingKey {
        case id, at, number, message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        at = try c.decode(Date.self, forKey: .at)
        number = try c.decodeIfPresent(String.self, forKey: .number)
        message = try c.value(.message, or: "")
    }
}
