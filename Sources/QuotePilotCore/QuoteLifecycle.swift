import Foundation

public enum QuoteStatus: Equatable, Sendable {
    case draft, sent, expired, declined
    case accepted(partly: Bool)

    public var label: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .expired: return "Expired"
        case .declined: return "Declined"
        case .accepted(let partly): return partly ? "Accepted, partly" : "Accepted"
        }
    }
}

extension Quote {
    public func status(on today: Day) -> QuoteStatus {
        switch stage {
        case .draft: return .draft
        case .sent: return today > validUntil ? .expired : .sent
        case .accepted: return .accepted(partly: lines.contains { $0.decision == .declined })
        case .declined: return .declined
        }
    }

    public var lineCodes: [String] { lines.map(\.code) }

    /// While a quote is a draft, line IDs follow the order of the lines. Once sent they never change,
    /// because the client's ticks refer to them.
    public mutating func renumberLinesIfDraft() {
        guard stage == .draft else { return }
        for index in lines.indices {
            lines[index].code = String(format: "%02d", index + 1)
        }
        lastLineNumber = lines.count
    }

    /// The ID the next new line gets: one past the highest ever given out on this quote.
    public func nextLineCode() -> String {
        String(format: "%02d", lastLineNumber + 1)
    }

    /// Adds a line with a fresh ID. Drafts then renumber to keep IDs in order.
    public mutating func addLine(_ line: LineItem) {
        var line = line
        line.code = nextLineCode()
        lastLineNumber += 1
        lines.append(line)
        renumberLinesIfDraft()
    }
}

/// What a returned quote said: read from the PDF form by QuotePilotPDF, or ticked by hand.
public struct ReturnedForm: Equatable, Sendable {
    public var quoteNumber: String
    public var acceptAll: Bool
    public var ticked: [String]
    public var unticked: [String]
    public var clientName: String
    public var clientDate: String

    public init(quoteNumber: String, acceptAll: Bool, ticked: [String], unticked: [String],
                clientName: String = "", clientDate: String = "") {
        self.quoteNumber = quoteNumber
        self.acceptAll = acceptAll
        self.ticked = ticked
        self.unticked = unticked
        self.clientName = clientName
        self.clientDate = clientDate
    }
}

public enum AcceptanceProblem: Equatable, Sendable {
    case wrongQuote(found: String, expected: String)
    /// On the PDF, but no longer on the quote.
    case unknownLines([String])
    /// On the quote, but not on the PDF the client saw.
    case missingLines([String])
    case nothingTicked
    case expired(validUntil: Day)

    /// A blocking problem means the PDF doesn't belong to this quote (or names lines it doesn't have),
    /// so spec §7 says it changes nothing: the review sheet must not offer to confirm it. The others
    /// are warnings the user can read and still confirm.
    public var isBlocking: Bool {
        switch self {
        case .wrongQuote, .unknownLines: return true
        case .missingLines, .nothingTicked, .expired: return false
        }
    }

    public var message: String {
        switch self {
        case .wrongQuote(let found, let expected):
            return "This PDF is for quote \(found), not \(expected)."
        case .unknownLines(let codes):
            return "The PDF has \(lineList(codes)) that this quote no longer has."
        case .missingLines(let codes):
            let verb = codes.count == 1 ? "wasn't" : "weren't"
            return "\(lineList(codes).capitalizedFirst) \(verb) on the PDF the client saw, so it's marked declined."
        case .nothingTicked:
            return "Nothing is ticked. Either the client declined everything, or their PDF app didn't keep the ticks."
        case .expired(let validUntil):
            return "This quote expired on \(validUntil.long)."
        }
    }
}

/// What Quote Pilot thinks the client decided. Nothing changes until it's confirmed.
public struct AcceptanceProposal: Equatable, Sendable {
    public var accepted: [String]
    public var declined: [String]
    public var clientName: String
    public var clientDate: String
    public var problems: [AcceptanceProblem]

    /// False while any problem is blocking: the review sheet shows it and offers no Confirm.
    public var canBeConfirmed: Bool { !problems.contains(where: \.isBlocking) }
}

extension Quote {
    public func proposal(from form: ReturnedForm, today: Day) -> AcceptanceProposal {
        var problems: [AcceptanceProblem] = []
        if form.quoteNumber.caseInsensitiveCompare(number) != .orderedSame {
            problems.append(.wrongQuote(found: form.quoteNumber, expected: number))
        }
        let codes = lineCodes
        let onForm = form.ticked + form.unticked
        let unknown = onForm.filter { !codes.contains($0) }.sorted()
        if !unknown.isEmpty { problems.append(.unknownLines(unknown)) }
        let missing = codes.filter { !onForm.contains($0) }
        if !missing.isEmpty { problems.append(.missingLines(missing)) }
        if !form.acceptAll && form.ticked.isEmpty { problems.append(.nothingTicked) }
        if status(on: today) == .expired { problems.append(.expired(validUntil: validUntil)) }

        // "Accept all" covers only the lines that were on the client's form: a line added later is
        // declined (and flagged above), never accepted on the client's behalf.
        let accepted = codes.filter { form.acceptAll ? onForm.contains($0) : form.ticked.contains($0) }
        return AcceptanceProposal(accepted: accepted,
                                  declined: codes.filter { !accepted.contains($0) },
                                  clientName: form.clientName,
                                  clientDate: form.clientDate,
                                  problems: problems)
    }
}

extension Library {
    public mutating func markSent(quote id: UUID, at time: Date = Date()) throws {
        let index = try quoteIndex(id)
        if quotes[index].stage == .draft {
            quotes[index].renumberLinesIfDraft()
            quotes[index].stage = .sent
        }
        quotes[index].sentAt = time
        log("Marked quote \(quotes[index].number) as sent", number: quotes[index].number, at: time)
    }

    /// Records what the client decided. Refused once the quote has invoices, so totals already
    /// billed can't shift underneath them.
    public mutating func recordAcceptance(_ acceptance: Acceptance, forQuote id: UUID) throws {
        let index = try quoteIndex(id)
        guard !invoices.contains(where: { $0.quoteID == id && $0.stage != .void }) else {
            throw LibraryError.alreadyInvoiced
        }
        let codes = quotes[index].lineCodes
        let unknown = (acceptance.accepted + acceptance.declined).filter { !codes.contains($0) }
        guard unknown.isEmpty else { throw LibraryError.unknownLineCodes(unknown) }

        for line in quotes[index].lines.indices {
            let code = quotes[index].lines[line].code
            quotes[index].lines[line].decision = acceptance.accepted.contains(code) ? .accepted : .declined
        }
        quotes[index].acceptance = acceptance
        quotes[index].stage = acceptance.accepted.isEmpty ? .declined : .accepted

        let number = quotes[index].number
        let how = acceptance.source == .returnedPDF ? "from \(acceptance.fileName ?? "the returned PDF")" : "by hand"
        var outcome = acceptance.accepted.isEmpty ? "all lines declined" : "accepted \(lineList(acceptance.accepted))"
        if !acceptance.accepted.isEmpty && !acceptance.declined.isEmpty {
            outcome += "; declined \(lineList(acceptance.declined))"
        }
        log("Recorded acceptance of \(number) \(how): \(outcome)", number: number, at: acceptance.recordedAt)
    }
}

/// "line 03" or "lines 01, 02".
func lineList(_ codes: [String]) -> String {
    (codes.count == 1 ? "line " : "lines ") + codes.joined(separator: ", ")
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
