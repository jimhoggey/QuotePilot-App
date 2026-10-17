import Foundation
import QuotePilotCore

/// Where a quote or an invoice is on its way, and the one thing to do next, worked out from the
/// library alone. The step bar in an editor's header draws it; nothing here changes anything.
///
/// This is a learning aid, not a control: the actions are hints, and no button or key depends on them.
/// To take the aid out, delete this file, `StepBar.swift` and `GettingStarted.swift`, the one line in
/// each editor and in the Dashboard that adds them (`StepBar(...)`, which takes the place of a `Spacer()`
/// in each editor's header, and `GettingStartedBox(...)`), and the View → Show Steps item in
/// `Commands.swift`.
struct NextStep: Equatable {
    enum State: Equatable {
        /// Passed: it gets a tick.
        case done
        /// Where the document is now.
        case current
        /// Still to come.
        case todo
        /// Where it ended without getting further: Declined, Expired or Void.
        case stopped
    }

    struct Step: Equatable {
        /// Counted from 1, so a stopped word keeps the place of the step it replaced.
        var number: Int
        var title: String
        var state: State

        var label: String { "\(number) \(title)" }
    }

    /// What the next step is done with. Only `openInvoice` and `openQuote` have a button on the bar;
    /// the others say which of the editor's own buttons does the step, and that button is not changed.
    enum Action: Equatable {
        case send
        case duplicate
        case draftInvoiceNow
        case jobComplete
        case openInvoice(UUID, number: String)
        /// A paid deposit's quote, where Job Complete is.
        case openQuote(UUID, number: String)
        case recordPayment
    }

    /// The document the bar's Open button opens, if the next step has one: its id, its number, and
    /// what it is ("invoice" or "quote").
    var openTarget: (id: UUID, number: String, kind: String)? {
        switch action {
        case .openInvoice(let id, let number)?: return (id, number, "invoice")
        case .openQuote(let id, let number)?: return (id, number, "quote")
        default: return nil
        }
    }

    var steps: [Step]
    /// One short plain sentence, such as "Next: choose the client."
    var sentence: String
    var action: Action?

    static let quoteTitles = ["Draft", "Sent", "Accepted", "Invoiced", "Paid"]
    static let invoiceTitles = ["Draft", "Sent", "Paid"]

    // MARK: Quotes

    static func forQuote(_ quote: Quote, in library: Library, today: Day) -> NextStep {
        let titles = quoteTitles
        switch quote.status(on: today) {
        case .draft:
            let (sentence, action) = draftHint(hasClient: library.client(quote.clientID) != nil,
                                               lines: quote.lines, total: quote.totals.total,
                                               ready: "Next: Send by Mail… to send it to the client.")
            return NextStep(steps: progress(titles, at: 0), sentence: sentence, action: action)

        case .sent:
            // One line at 1240 wide. Record Acceptance… (for a client who just says yes) is its own
            // button in the header, so the sentence doesn't name it.
            return NextStep(steps: progress(titles, at: 1),
                            sentence: "Next: when the client's ticked PDF comes back, drop it here.",
                            action: nil)

        case .expired:
            return NextStep(steps: stopped(titles, at: 2, word: "Expired"),
                            sentence: "This quote has expired. Duplicate it to quote again.",
                            action: .duplicate)

        case .declined:
            return NextStep(steps: stopped(titles, at: 2, word: "Declined"),
                            sentence: "The client declined this quote.", action: nil)

        case .accepted:
            return acceptedQuote(quote, in: library)
        }
    }

    /// An accepted quote: invoicing, then payments. The current step is Accepted until the first
    /// invoice is drafted and Invoiced from then on; every step is done once everything is paid.
    private static func acceptedQuote(_ quote: Quote, in library: Library) -> NextStep {
        let titles = quoteTitles
        let live = library.invoices(forQuote: quote.id)
        let nextKind = library.nextInvoiceKind(forQuote: quote.id)
        let step = live.isEmpty ? 2 : 3

        // An invoice still in draft comes first: it has to be sent before anything else can happen.
        if let draft = live.first(where: { $0.stage == .draft }) {
            return NextStep(steps: progress(titles, at: step),
                            sentence: "Next: open \(draft.number) and send it.",
                            action: .openInvoice(draft.id, number: draft.number))
        }
        switch nextKind {
        case .deposit?:
            return NextStep(steps: progress(titles, at: step),
                            sentence: "Next: Draft Invoice Now for the deposit.", action: .draftInvoiceNow)
        case .full?, .standalone?:
            // (A quote never calls for a standalone invoice; it is listed so the switch is complete.)
            return NextStep(steps: progress(titles, at: step),
                            sentence: "Next: Draft Invoice Now.", action: .draftInvoiceNow)
        case .final?:
            // 50/50 with the deposit out: the balance waits for the job. If the job is already marked
            // complete (the closing invoice was voided), Job Complete is gone and Draft Invoice Now
            // drafts the balance again.
            if quote.completedOn == nil {
                return NextStep(steps: progress(titles, at: step),
                                sentence: "Next: when the job is done, press Job Complete.", action: .jobComplete)
            }
            return NextStep(steps: progress(titles, at: step),
                            sentence: "Next: Draft Invoice Now to bill the rest.", action: .draftInvoiceNow)
        case nil:
            break
        }
        // Everything is drafted and sent.
        if !live.isEmpty, live.allSatisfy({ $0.owing <= .zero }) {
            return NextStep(steps: progress(titles, at: nil),
                            sentence: "Done. Every invoice for this quote is paid.", action: nil)
        }
        return NextStep(steps: progress(titles, at: step),
                        sentence: "Next: record payments on the invoices as they come in.", action: nil)
    }

    // MARK: Invoices

    static func forInvoice(_ invoice: Invoice, in library: Library, today: Day) -> NextStep {
        let titles = invoiceTitles
        switch invoice.stage {
        case .draft:
            let (sentence, action) = draftHint(hasClient: library.client(invoice.clientID) != nil,
                                               lines: invoice.lines, total: invoice.lineTotals.total,
                                               ready: "Next: check it, then Send by Mail…")
            return NextStep(steps: progress(titles, at: 0), sentence: sentence, action: action)

        case .void:
            return NextStep(steps: stopped(titles, at: 2, word: "Void"),
                            sentence: "This invoice is void.", action: nil)

        case .sent:
            // Not special-cased for a deposit that a final invoice deducts: that deposit can still be
            // sent and paid, so the ordinary sentence is the true one, and the editor's own note says
            // what is locked and why.
            // A paid deposit: the balance waits for the job, which is marked done on the quote.
            if invoice.owing <= .zero, invoice.kind == .deposit, let quoteID = invoice.quoteID,
               let quote = library.quote(quoteID), quote.completedOn == nil,
               library.nextInvoiceKind(forQuote: quoteID) == .final {
                return NextStep(steps: progress(titles, at: nil),
                                sentence: "Deposit paid. When the job is done, open \(quote.number) and press Job Complete.",
                                action: .openQuote(quote.id, number: quote.number))
            }
            if invoice.owing <= .zero {
                let sentence = invoice.receiptSentAt == nil
                    ? "Paid in full. Send Receipt… if the client wants one."
                    : "Paid in full. The receipt has been sent."
                return NextStep(steps: progress(titles, at: nil), sentence: sentence, action: nil)
            }
            return NextStep(steps: progress(titles, at: 1),
                            sentence: "Next: when the client pays, record it under New payment.",
                            action: .recordPayment)
        }
    }

    // MARK: Pieces

    /// What a draft needs, in order: a client, some work (at least one line with a title, so a blank
    /// line that Add Line just made doesn't count), a price (a total above $0), then sending. The
    /// total is the lines' own total, with GST if the document is taxed, before any deposit share or
    /// deduction on an invoice. Quotes and invoices share this rule.
    private static func draftHint(hasClient: Bool, lines: [LineItem], total: Money,
                                  ready: String) -> (String, Action?) {
        if !hasClient { return ("Next: choose the client.", nil) }
        let hasWork = lines.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !hasWork { return ("Next: add the work, one line each.", nil) }
        if total <= .zero { return ("Next: give the work a price.", nil) }
        return (ready, .send)
    }

    /// Every title before `current` is done, `current` is where the document is, the rest are still
    /// to come. A nil `current` is a document that has been through all of them.
    private static func progress(_ titles: [String], at current: Int?) -> [Step] {
        titles.enumerated().map { index, title in
            let state: State
            if let current {
                state = index < current ? .done : (index == current ? .current : .todo)
            } else {
                state = .done
            }
            return Step(number: index + 1, title: title, state: state)
        }
    }

    /// The steps up to `index` done, then `word` in the place of the step that was never reached, and
    /// nothing after it.
    private static func stopped(_ titles: [String], at index: Int, word: String) -> [Step] {
        var steps = progress(Array(titles.prefix(index)), at: nil)
        steps.append(Step(number: index + 1, title: word, state: .stopped))
        return steps
    }
}
