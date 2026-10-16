import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The rules behind the step bar. Made-up data only; `UIFixture.today` is 15 October 2026.
@MainActor
@Suite struct NextStepTests {
    let today = UIFixture.today

    /// A library with one quote on `plan`, with a client and two lines unless asked otherwise.
    func library(client: Bool = true, lines: Int = 2, plan: PaymentPlan = .fiftyFifty,
                 issued: Day = UIFixture.today) throws -> (library: Library, quote: UUID) {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        let sample = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example")
        library.addClient(sample)
        var quote = library.newQuote(on: issued, clientID: client ? sample.id : nil)
        quote.plan = plan
        for (index, title) in ["Design", "Build"].prefix(lines).enumerated() {
            quote.addLine(LineItem(title: title, rate: Money(dollars: 600 * (index + 1))))
        }
        try library.update(quote)
        return (library, quote.id)
    }

    func sent(_ made: (library: Library, quote: UUID)) throws -> (library: Library, quote: UUID) {
        var library = made.library
        try library.markSent(quote: made.quote)
        return (library, made.quote)
    }

    func accepted(_ made: (library: Library, quote: UUID)) throws -> (library: Library, quote: UUID) {
        var library = try sent(made).library
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: []),
                                     forQuote: made.quote)
        return (library, made.quote)
    }

    func next(_ made: (library: Library, quote: UUID)) throws -> NextStep {
        NextStep.forQuote(try #require(made.library.quote(made.quote)), in: made.library, today: today)
    }

    func next(invoice id: UUID, in library: Library) throws -> NextStep {
        NextStep.forInvoice(try #require(library.invoice(id)), in: library, today: today)
    }

    func states(_ next: NextStep) -> [NextStep.State] { next.steps.map(\.state) }

    // MARK: Quote steps

    @Test func aQuoteHasFiveNumberedSteps() throws {
        let next = try self.next(try library())
        #expect(next.steps.map(\.label) == ["1 Draft", "2 Sent", "3 Accepted", "4 Invoiced", "5 Paid"])
    }

    @Test func aDraftWithNoClientSaysToChooseOne() throws {
        let next = try self.next(try library(client: false))
        #expect(states(next) == [.current, .todo, .todo, .todo, .todo])
        #expect(next.sentence == "Next: choose the client.")
        #expect(next.action == nil)
    }

    @Test func aClientIsChosenBeforeTheWorkIsAdded() throws {
        // No client and no lines: the client comes first.
        let next = try self.next(try library(client: false, lines: 0))
        #expect(next.sentence == "Next: choose the client.")
    }

    @Test func aDraftWithNoLinesSaysToAddTheWork() throws {
        let next = try self.next(try library(lines: 0))
        #expect(states(next) == [.current, .todo, .todo, .todo, .todo])
        #expect(next.sentence == "Next: add the work, one line each.")
        #expect(next.action == nil)
    }

    @Test func aReadyDraftSaysToSend() throws {
        let next = try self.next(try library())
        #expect(states(next) == [.current, .todo, .todo, .todo, .todo])
        #expect(next.sentence == "Next: Send by Mail… to send it to the client.")
        #expect(next.action == .send)
    }

    /// A library with one draft quote holding exactly `lines`, with a client unless asked otherwise.
    func draft(_ lines: [LineItem], client: Bool = true, taxed: Bool = false) throws -> (library: Library, quote: UUID) {
        var library = Library()
        let sample = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example")
        library.addClient(sample)
        var quote = library.newQuote(on: today, clientID: client ? sample.id : nil)
        quote.taxed = taxed
        for line in lines { quote.addLine(line) }
        try library.update(quote)
        return (library, quote.id)
    }

    let notYetReady = "Next: Send by Mail… to send it to the client."

    @Test func aBlankLineIsNotTheWorkAdded() throws {
        // What Add Line makes: no title, no price.
        let next = try self.next(try draft([.blank(hourlyRate: nil)]))
        #expect(states(next) == [.current, .todo, .todo, .todo, .todo])
        #expect(next.sentence == "Next: add the work, one line each.")
        #expect(next.action == nil)
        // Several blank lines are no more than one.
        let several = try self.next(try draft([.blank(hourlyRate: nil), .blank(hourlyRate: nil)]))
        #expect(several.sentence == "Next: add the work, one line each.")
    }

    @Test func aLineWithAPriceButNoTitleIsNotTheWorkAdded() throws {
        let next = try self.next(try draft([LineItem(title: "", rate: Money(dollars: 500))]))
        #expect(next.sentence == "Next: add the work, one line each.")
        #expect(next.action == nil)
        // A title of spaces is no title.
        let spaces = try self.next(try draft([LineItem(title: "   ", rate: Money(dollars: 500))]))
        #expect(spaces.sentence == "Next: add the work, one line each.")
        #expect(spaces.action == nil)
    }

    @Test func aTitledLineAtNothingSaysToGiveItAPrice() throws {
        let next = try self.next(try draft([LineItem(title: "Design", rate: .zero)]))
        #expect(states(next) == [.current, .todo, .todo, .todo, .todo])
        #expect(next.sentence == "Next: give the work a price.")
        #expect(next.action == nil)
        // Every titled line at nothing, and a blank one beside them: still no price.
        let several = try self.next(try draft([LineItem(title: "Design", rate: .zero),
                                               LineItem(title: "Build", rate: .zero),
                                               .blank(hourlyRate: nil)]))
        #expect(several.sentence == "Next: give the work a price.")
        #expect(several.action == nil)
    }

    @Test func aQuantityOfNothingLeavesTheTotalAtNothing() throws {
        let next = try self.next(try draft([LineItem(title: "Design", quantity: 0, rate: Money(dollars: 600))]))
        #expect(next.sentence == "Next: give the work a price.")
    }

    @Test func aTitleAndATotalAboveNothingIsReady() throws {
        let next = try self.next(try draft([LineItem(title: "Design", rate: Money(cents: 1))]))
        #expect(next.sentence == notYetReady)
        #expect(next.action == .send)
        // One priced line is enough; the other may stay at nothing.
        let mixed = try self.next(try draft([LineItem(title: "Design", rate: .zero),
                                             LineItem(title: "Build", rate: Money(dollars: 1200))]))
        #expect(mixed.sentence == notYetReady)
        #expect(mixed.action == .send)
        // GST doesn't change it.
        let taxed = try self.next(try draft([LineItem(title: "Design", rate: Money(dollars: 600))], taxed: true))
        #expect(taxed.action == .send)
    }

    @Test func aDiscountThatTakesTheTotalToNothingOrBelowIsNotReady() throws {
        let next = try self.next(try draft([LineItem(title: "Design", rate: Money(dollars: 600)),
                                            LineItem(title: "Discount", rate: Money(dollars: -600))]))
        #expect(next.sentence == "Next: give the work a price.")
        #expect(next.action == nil)
    }

    @Test func theClientStillComesBeforeTheWorkAndThePrice() throws {
        #expect(try self.next(try draft([.blank(hourlyRate: nil)], client: false)).sentence == "Next: choose the client.")
        #expect(try self.next(try draft([LineItem(title: "Design", rate: .zero)], client: false)).sentence
                == "Next: choose the client.")
        #expect(try self.next(try draft([], client: false)).sentence == "Next: choose the client.")
    }

    @Test func theHintMovesOnAsTheLineIsFilledIn() throws {
        var made = try draft([.blank(hourlyRate: nil)])
        var quote = try #require(made.library.quote(made.quote))
        #expect(try self.next(made).sentence == "Next: add the work, one line each.")
        quote.lines[0].title = "Design"
        try made.library.update(quote)
        #expect(try self.next(made).sentence == "Next: give the work a price.")
        quote.lines[0].rate = Money(dollars: 600)
        try made.library.update(quote)
        #expect(try self.next(made).sentence == notYetReady)
        #expect(try self.next(made).action == .send)
    }

    @Test func aSentQuoteWaitsForTheClientAndNamesNoButton() throws {
        let next = try self.next(try sent(try library()))
        #expect(states(next) == [.done, .current, .todo, .todo, .todo])
        #expect(next.sentence == "Next: when the client's ticked PDF comes back, drop it here.")
        #expect(next.action == nil)
    }

    @Test func aQuoteSentButPastItsDateHasExpired() throws {
        let old = try library(issued: today.adding(days: -40))
        let next = try self.next(try sent(old))
        #expect(states(next) == [.done, .done, .stopped])
        #expect(next.steps.map(\.label) == ["1 Draft", "2 Sent", "3 Expired"])
        #expect(next.sentence == "This quote has expired. Duplicate it to quote again.")
        #expect(next.action == .duplicate)
    }

    @Test func aQuoteIsStillOpenOnItsLastDay() throws {
        // 30 days from issue is the last day it can be accepted.
        let edge = try library(issued: today.adding(days: -30))
        #expect(states(try self.next(try sent(edge))) == [.done, .current, .todo, .todo, .todo])
    }

    @Test func aDeclinedQuoteStopsAtDeclined() throws {
        var (library, id) = try sent(try self.library())
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: [], declined: ["01", "02"]), forQuote: id)
        let next = try self.next((library, id))
        #expect(states(next) == [.done, .done, .stopped])
        #expect(next.steps.last?.title == "Declined")
        #expect(next.sentence == "The client declined this quote.")
        #expect(next.action == nil)
    }

    // MARK: Accepted quotes

    @Test func anAcceptedFiftyFiftyQuoteWithNothingDraftedCallsForTheDeposit() throws {
        let next = try self.next(try accepted(try library()))
        #expect(states(next) == [.done, .done, .current, .todo, .todo])
        #expect(next.sentence == "Next: Draft Invoice Now for the deposit.")
        #expect(next.action == .draftInvoiceNow)
    }

    @Test func aDraftInvoiceOnAnAcceptedQuoteIsOpenedAndSent() throws {
        var (library, id) = try accepted(try self.library())
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        let next = try self.next((library, id))
        #expect(states(next) == [.done, .done, .done, .current, .todo])
        #expect(next.sentence == "Next: open \(deposit.number) and send it.")
        #expect(next.action == .openInvoice(deposit.id, number: deposit.number))
    }

    @Test func withTheDepositSentTheJobIsWhatsLeft() throws {
        var (library, id) = try accepted(try self.library())
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        let next = try self.next((library, id))
        #expect(states(next) == [.done, .done, .done, .current, .todo])
        #expect(next.sentence == "Next: when the job is done, press Job Complete.")
        #expect(next.action == .jobComplete)
    }

    @Test func aFullAmountQuoteWithNothingInvoicedCallsForTheInvoice() throws {
        let next = try self.next(try accepted(try library(plan: .fullAmount)))
        #expect(states(next) == [.done, .done, .current, .todo, .todo])
        #expect(next.sentence == "Next: Draft Invoice Now.")
        #expect(next.action == .draftInvoiceNow)
    }

    @Test func withEveryInvoiceSentThePaymentsAreWhatsLeft() throws {
        var (library, id) = try accepted(try self.library())
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: today, amount: deposit.amount), toInvoice: deposit.id)
        let final = try #require(try library.completeJob(quote: id, on: today))
        try library.markSent(invoice: final.id)
        let next = try self.next((library, id))
        #expect(states(next) == [.done, .done, .done, .current, .todo])
        #expect(next.sentence == "Next: record payments on the invoices as they come in.")
        #expect(next.action == nil)
    }

    @Test func aFullAmountInvoiceSentAndUnpaidIsTheSame() throws {
        var (library, id) = try accepted(try self.library(plan: .fullAmount))
        let full = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: full.id)
        let next = try self.next((library, id))
        #expect(states(next) == [.done, .done, .done, .current, .todo])
        #expect(next.sentence == "Next: record payments on the invoices as they come in.")
    }

    @Test func whenEverythingIsPaidEveryStepIsDone() throws {
        var (library, id) = try accepted(try self.library())
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: today, amount: deposit.amount), toInvoice: deposit.id)
        let final = try #require(try library.completeJob(quote: id, on: today))
        try library.markSent(invoice: final.id)
        try library.recordPayment(Payment(date: today, amount: final.owing), toInvoice: final.id)
        let next = try self.next((library, id))
        #expect(states(next) == [.done, .done, .done, .done, .done])
        #expect(next.sentence == "Done. Every invoice for this quote is paid.")
        #expect(next.action == nil)
    }

    @Test func aVoidedClosingInvoiceCallsForDraftInvoiceNowAgain() throws {
        var (library, id) = try accepted(try self.library())
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        let final = try #require(try library.completeJob(quote: id, on: today))
        try library.markSent(invoice: final.id)
        try library.voidInvoice(final.id)
        let next = try self.next((library, id))
        // The job is marked complete, so Job Complete is gone; Draft Invoice Now drafts the balance.
        #expect(next.sentence == "Next: Draft Invoice Now to bill the rest.")
        #expect(next.action == .draftInvoiceNow)
    }

    @Test func voidingEveryInvoiceSendsTheQuoteBackToAccepted() throws {
        var (library, id) = try accepted(try self.library(plan: .fullAmount))
        let full = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: full.id)
        try library.voidInvoice(full.id)
        let next = try self.next((library, id))
        #expect(states(next) == [.done, .done, .current, .todo, .todo])
        #expect(next.sentence == "Next: Draft Invoice Now.")
    }

    @Test func aPartlyAcceptedQuoteFollowsTheSameSteps() throws {
        var (library, id) = try sent(try self.library())
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: ["02"]), forQuote: id)
        let next = try self.next((library, id))
        #expect(states(next) == [.done, .done, .current, .todo, .todo])
        #expect(next.sentence == "Next: Draft Invoice Now for the deposit.")
    }

    // MARK: The sample library

    @Test func theSampleQuotesEachSayWhatComesNext() throws {
        let model = try UIFixture.sampleModel()
        func next(_ number: String) throws -> NextStep {
            NextStep.forQuote(try #require(model.library.quote(number: number)), in: model.library, today: model.today)
        }
        // Q-0001: accepted, deposit paid, the rest waits for the job.
        let one = try next("Q-0001")
        #expect(states(one) == [.done, .done, .done, .current, .todo])
        #expect(one.action == .jobComplete)
        // Q-0002: sent last week.
        #expect(states(try next("Q-0002")) == [.done, .current, .todo, .todo, .todo])
        // Q-0003: sent 40 days ago.
        #expect(try next("Q-0003").steps.last?.title == "Expired")
        // Q-0004: a draft with a client and a line.
        #expect(try next("Q-0004").action == .send)
    }

    // MARK: Invoices

    func invoiceLibrary(client: Bool = true, lines: Int = 1) -> (library: Library, invoice: UUID) {
        var library = Library()
        let sample = Client(name: "Sample Client Pty Ltd")
        library.addClient(sample)
        var invoice = library.newInvoice(on: today, clientID: client ? sample.id : nil)
        invoice.lines = (0..<lines).map { LineItem(title: "Monthly care \($0 + 1)", rate: Money(dollars: 150)) }
        try? library.update(invoice)
        return (library, invoice.id)
    }

    @Test func anInvoiceHasThreeNumberedSteps() throws {
        let made = invoiceLibrary()
        let next = try self.next(invoice: made.invoice, in: made.library)
        #expect(next.steps.map(\.label) == ["1 Draft", "2 Sent", "3 Paid"])
    }

    @Test func aDraftInvoiceIsCheckedThenSent() throws {
        let made = invoiceLibrary()
        let next = try self.next(invoice: made.invoice, in: made.library)
        #expect(states(next) == [.current, .todo, .todo])
        #expect(next.sentence == "Next: check it, then Send by Mail…")
        #expect(next.action == .send)
    }

    @Test func aDraftInvoiceWithNoClientOrNoWorkSaysSo() throws {
        let noClient = invoiceLibrary(client: false)
        let first = try self.next(invoice: noClient.invoice, in: noClient.library)
        #expect(first.sentence == "Next: choose the client.")
        #expect(first.action == nil)
        let noLines = invoiceLibrary(lines: 0)
        let second = try self.next(invoice: noLines.invoice, in: noLines.library)
        #expect(second.sentence == "Next: add the work, one line each.")
        #expect(second.action == nil)
    }

    /// A library with one draft invoice holding exactly `lines`, with a client unless asked otherwise.
    func invoiceDraft(_ lines: [LineItem], client: Bool = true,
                      taxed: Bool = false) throws -> (library: Library, invoice: UUID) {
        var library = Library()
        let sample = Client(name: "Sample Client Pty Ltd")
        library.addClient(sample)
        var invoice = library.newInvoice(on: today, clientID: client ? sample.id : nil)
        invoice.taxed = taxed
        invoice.lines = lines
        try library.update(invoice)
        return (library, invoice.id)
    }

    @Test func aDraftInvoiceWithOnlyABlankLineStillSaysToAddTheWork() throws {
        let blank = try invoiceDraft([.blank(hourlyRate: nil)])
        let first = try self.next(invoice: blank.invoice, in: blank.library)
        #expect(states(first) == [.current, .todo, .todo])
        #expect(first.sentence == "Next: add the work, one line each.")
        #expect(first.action == nil)
        // A price with no title is not the work either, nor is a title of spaces.
        for title in ["", "  "] {
            let untitled = try invoiceDraft([LineItem(title: title, rate: Money(dollars: 150))])
            let next = try self.next(invoice: untitled.invoice, in: untitled.library)
            #expect(next.sentence == "Next: add the work, one line each.", "title \"\(title)\"")
            #expect(next.action == nil)
        }
    }

    @Test func aDraftInvoiceWithATitledLineAtNothingSaysToGiveItAPrice() throws {
        let made = try invoiceDraft([LineItem(title: "Monthly care", rate: .zero), .blank(hourlyRate: nil)])
        let next = try self.next(invoice: made.invoice, in: made.library)
        #expect(states(next) == [.current, .todo, .todo])
        #expect(next.sentence == "Next: give the work a price.")
        #expect(next.action == nil)
    }

    @Test func aDraftInvoiceWithATitleAndATotalAboveNothingIsReady() throws {
        let made = try invoiceDraft([LineItem(title: "Monthly care", rate: Money(cents: 1))])
        let next = try self.next(invoice: made.invoice, in: made.library)
        #expect(next.sentence == "Next: check it, then Send by Mail…")
        #expect(next.action == .send)
        let taxed = try invoiceDraft([LineItem(title: "Monthly care", rate: Money(dollars: 150))], taxed: true)
        #expect(try self.next(invoice: taxed.invoice, in: taxed.library).action == .send)
    }

    @Test func aDraftInvoiceNeedsItsClientBeforeTheWorkAndThePrice() throws {
        for lines in [[LineItem](), [.blank(hourlyRate: nil)], [LineItem(title: "Monthly care", rate: .zero)]] {
            let made = try invoiceDraft(lines, client: false)
            let next = try self.next(invoice: made.invoice, in: made.library)
            #expect(next.sentence == "Next: choose the client.")
            #expect(next.action == nil)
        }
    }

    @Test func aSentInvoiceWithMoneyOwingWaitsForThePayment() throws {
        var made = invoiceLibrary()
        try made.library.markSent(invoice: made.invoice)
        let next = try self.next(invoice: made.invoice, in: made.library)
        #expect(states(next) == [.done, .current, .todo])
        #expect(next.sentence == "Next: when the client pays, record it under New payment.")
        #expect(next.action == .recordPayment)
    }

    @Test func aPartPaidInvoiceIsStillWaiting() throws {
        var made = invoiceLibrary()
        try made.library.markSent(invoice: made.invoice)
        try made.library.recordPayment(Payment(date: today, amount: Money(dollars: 50)), toInvoice: made.invoice)
        let next = try self.next(invoice: made.invoice, in: made.library)
        #expect(states(next) == [.done, .current, .todo])
        #expect(next.action == .recordPayment)
    }

    @Test func anOverdueInvoiceIsStillOnTheSentStep() throws {
        var made = invoiceLibrary()
        try made.library.markSent(invoice: made.invoice)
        let late = NextStep.forInvoice(try #require(made.library.invoice(made.invoice)), in: made.library,
                                       today: today.adding(days: 60))
        #expect(states(late) == [.done, .current, .todo])
    }

    @Test func aPaidInvoiceIsDoneAndOffersTheReceiptWithoutNaggingForIt() throws {
        var made = invoiceLibrary()
        try made.library.markSent(invoice: made.invoice)
        try made.library.recordPayment(Payment(date: today, amount: Money(dollars: 150)), toInvoice: made.invoice)
        let next = try self.next(invoice: made.invoice, in: made.library)
        #expect(states(next) == [.done, .done, .done])
        #expect(next.sentence == "Paid in full. Send Receipt… if the client wants one.")
        #expect(next.action == nil)
        // Once the receipt has gone there is nothing left to suggest.
        try made.library.markReceiptSent(invoice: made.invoice)
        let after = try self.next(invoice: made.invoice, in: made.library)
        #expect(after.sentence == "Paid in full. The receipt has been sent.")
    }

    @Test func aVoidInvoiceStopsAtVoid() throws {
        var made = invoiceLibrary()
        try made.library.markSent(invoice: made.invoice)
        try made.library.voidInvoice(made.invoice)
        let next = try self.next(invoice: made.invoice, in: made.library)
        #expect(states(next) == [.done, .done, .stopped])
        #expect(next.steps.map(\.label) == ["1 Draft", "2 Sent", "3 Void"])
        #expect(next.sentence == "This invoice is void.")
        #expect(next.action == nil)
    }

    @Test func theSampleInvoicesEachSayWhatComesNext() throws {
        let model = try UIFixture.sampleModel()
        func next(_ number: String) throws -> NextStep {
            let invoice = try #require(model.library.invoices.first { $0.number == number })
            return NextStep.forInvoice(invoice, in: model.library, today: model.today)
        }
        #expect(states(try next("INV-0001")) == [.done, .done, .done])   // the paid deposit
        #expect(try next("INV-0002").action == .recordPayment)           // sent, overdue
        #expect(try next("INV-0003").action == .recordPayment)           // part paid
    }

    // MARK: A deposit that the final invoice deducts

    /// A deducted deposit can still be sent and paid, so it keeps the ordinary sentence; the
    /// editor's own note (`InvoiceRules`) is what says it is locked.
    @Test func aDepositTheFinalDeductsKeepsTheOrdinarySentenceForItsState() throws {
        var (library, id) = try UIFixture.invoicedLibrary()
        let deposit = try #require(library.invoices.first)
        _ = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.finalDeducting(deposit.id) != nil)

        let draft = try self.next(invoice: deposit.id, in: library)
        #expect(draft.sentence == "Next: check it, then Send by Mail…")
        #expect(draft.action == .send)

        try library.markSent(invoice: deposit.id)
        let sentOne = try self.next(invoice: deposit.id, in: library)
        #expect(sentOne.sentence == "Next: when the client pays, record it under New payment.")
        #expect(sentOne.action == .recordPayment)

        try library.recordPayment(Payment(date: today, amount: deposit.amount), toInvoice: deposit.id)
        let paid = try self.next(invoice: deposit.id, in: library)
        #expect(paid.sentence == "Paid in full. Send Receipt… if the client wants one.")
    }
}
