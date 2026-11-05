import Foundation

// MARK: - Brand

public struct EmailTemplate: Codable, Hashable, Sendable {
    public var subject: String
    public var body: String

    public init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }

    /// Replaces `{key}` placeholders: client, contact, number, amount, due, business, and for several
    /// invoices together count and list.
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
    /// Several invoices to one client in one email (Send Together): {count} and {list}, one line per
    /// invoice with its amount and due date, and {amount}, their total.
    public var together: EmailTemplate
    /// A statement of what a client owes: {list}, one line per invoice still owing, and {amount}, the total.
    public var statement: EmailTemplate

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
            """),
        together: EmailTemplate(
            subject: "Invoices from {business}",
            body: """
            Hi {contact},

            Attached are {count} invoices:

            {list}

            Total: {amount}. Payment details are on each invoice. You're welcome to pay them in one \
            transfer; please put the invoice numbers in the reference.

            Thanks,
            {business}
            """),
        statement: EmailTemplate(
            subject: "Statement from {business}",
            body: """
            Hi {contact},

            Attached is a statement of your account. These invoices are still owing:

            {list}

            Total owing: {amount}. Payment details are on the statement; please put the invoice numbers \
            in the reference. If you've paid already, thank you, and please ignore this.

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
    /// Draft quotes with a total above this are 50/50, and the rest are the full amount on completion,
    /// until a quote's plan is chosen by hand (`Quote.planIsAutomatic`). $0 turns the rule off.
    public var splitAbove = Money(dollars: 1000)
    /// Brand → Documents: the custom split's share billed when a quote is accepted, such as 30 for
    /// 30/70, which quotes offer beside 50/50 and the full amount. Nil when there's none.
    public var customSplit: Int?
    /// Brand → Settings: a Done tick box on each quote line, for the user's own tracking.
    public var showsDoneColumn = false
    /// Quote Pilot's own fee setting (Brand → Settings), kept with the library. Prints nowhere.
    public var appFee = AppFee()
    /// Brand → Documents: invoices that start with a title and lines filled in, such as "Billing for
    /// meeting time" with an hour of meeting time. New Invoice offers them once there are any.
    public var invoiceTemplates: [InvoiceTemplate] = []

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

    /// The name as lists, messages and Activity show it: "(no name)" until one is typed.
    public var shownName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no name)" : name
    }

    /// Who "Hi …" is addressed to: the contact's first name, or the business name.
    public var greetingName: String {
        let first = contactName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? name : first
    }
}

// MARK: - Quotes

public enum PaymentPlan: String, Codable, CaseIterable, Sendable {
    /// The custom split is Brand's (`Brand.customSplit`), such as 30% when accepted and 70% on completion.
    case fiftyFifty, fullAmount, customSplit

    /// The custom splits Brand → Documents offers: the share billed when a quote is accepted.
    public static let customSplits = [10, 20, 25, 30, 40, 60, 70, 75, 80, 90]
    /// The shares a saved custom split may have; anything else makes the library unreadable.
    static let splitRange = 1...99

    /// "30/70"
    public static func splitName(_ percent: Int) -> String { "\(percent)/\(100 - percent)" }

    /// The share billed when the quote is accepted, or nil when the full amount is billed on completion.
    public func depositPercent(customSplit: Int?) -> Int? {
        switch self {
        case .fiftyFifty: return 50
        case .fullAmount: return nil
        case .customSplit: return customSplit ?? 50
        }
    }

    /// A plan with its amounts for `total`, as the quote prints it: "30% ($450.00) when the quote is
    /// accepted, 70% ($1,050.00) on completion", or "Full amount ($1,500.00) on completion". The two
    /// parts add up to the total to the cent.
    public static func summary(depositPercent: Int?, total: Money, currencyCode: String) -> String {
        let money = { (amount: Money) in amount.formatted(currencyCode: currencyCode) }
        guard let percent = depositPercent else { return "Full amount (\(money(total))) on completion" }
        let now = total.percent(percent)
        return "\(percent)% (\(money(now))) when the quote is accepted, \(100 - percent)% (\(money(total - now))) on completion"
    }

    /// Brand's rule (`Brand.splitAbove`): 50/50 for a total above `splitAbove`, otherwise the full
    /// amount on completion. Nil while the rule is off ($0).
    public static func automatic(for total: Money, splitAbove: Money) -> PaymentPlan? {
        guard splitAbove > .zero else { return nil }
        return total > splitAbove ? .fiftyFifty : .fullAmount
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
    /// True while the plan follows Brand's rule (`Brand.splitAbove`): set on a new quote, and
    /// cleared for good once the plan is chosen by hand.
    public var planIsAutomatic = false
    /// The custom split's share billed on acceptance (`PaymentPlan.customSplit`): Brand's while the
    /// quote is a draft (`follow(customSplit:)`), kept as it was once the quote is sent.
    public var customSplit: Int?
    /// The lines the user has ticked Done while doing the work: their own tracker, never printed and
    /// never part of what's billed, so it can change at any stage.
    public var doneLines: Set<UUID> = []

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

    /// The share billed when the quote is accepted, or nil when it's paid in full on completion.
    public var depositPercent: Int? { plan.depositPercent(customSplit: customSplit) }

    /// The plans the quote offers: the custom split only when there is one.
    public var plans: [PaymentPlan] { customSplit == nil ? [.fiftyFifty, .fullAmount] : PaymentPlan.allCases }

    /// `plan` with this quote's amounts, as the quote prints it (`PaymentPlan.summary`).
    public func summary(of plan: PaymentPlan, currencyCode: String) -> String {
        PaymentPlan.summary(depositPercent: plan.depositPercent(customSplit: customSplit), total: totals.total,
                            currencyCode: currencyCode)
    }

    /// A draft follows Brand's custom split; with none left, a draft on the custom split goes back to 50/50.
    mutating func follow(customSplit: Int?) {
        self.customSplit = customSplit
        if customSplit == nil, plan == .customSplit { plan = .fiftyFifty }
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

/// A starting point for one-off invoices (Brand → Documents): its title becomes the invoice's
/// Reference and names it in New Invoice's menu; its lines are copied in.
public struct InvoiceTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var title = ""
    public var lines: [LineItem] = []

    public init(title: String = "", lines: [LineItem] = []) {
        self.title = title
        self.lines = lines
    }

    /// The title as menus and messages show it: "(no title)" until one is typed.
    public var shownTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no title)" : title
    }
}

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
        case hourlyRate, headingFontStyle, bodyFontFile, bodyFontStyle, appFee, splitAbove, customSplit, showsDoneColumn
        case invoiceTemplates
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
        splitAbove = try c.value(.splitAbove, or: d.splitAbove)
        customSplit = try c.decodeIfPresent(Int.self, forKey: .customSplit)
        showsDoneColumn = try c.value(.showsDoneColumn, or: d.showsDoneColumn)
        invoiceTemplates = try c.value(.invoiceTemplates, or: d.invoiceTemplates)
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
        case summary, included, notIncluded, terms, stage, sentAt, acceptance, completedOn, planIsAutomatic, customSplit
        case doneLines
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
        // Quotes from before the rule keep the plan they have.
        planIsAutomatic = try c.value(.planIsAutomatic, or: false)
        customSplit = try c.decodeIfPresent(Int.self, forKey: .customSplit)
        doneLines = try c.value(.doneLines, or: [])
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
        case quote, invoice, receipt, together, statement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let standard = EmailTemplates.standard
        quote = try c.value(.quote, or: standard.quote)
        invoice = try c.value(.invoice, or: standard.invoice)
        receipt = try c.value(.receipt, or: standard.receipt)
        together = try c.value(.together, or: standard.together)
        statement = try c.value(.statement, or: standard.statement)
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
