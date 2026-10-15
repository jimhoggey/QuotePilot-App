import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct QuoteLifecycleTests {
    let today = Fixture.today

    @Test func statusFollowsStageAndDates() {
        let (library, id) = Fixture.libraryWithQuote(stage: .draft)
        var quote = library.quote(id)!
        #expect(quote.status(on: today) == .draft)
        quote.stage = .sent
        #expect(quote.status(on: quote.validUntil) == .sent)
        #expect(quote.status(on: quote.validUntil.adding(days: 1)) == .expired)
        quote.stage = .accepted
        quote.lines[2].decision = .declined
        #expect(quote.status(on: today) == .accepted(partly: true))
        #expect(QuoteStatus.accepted(partly: true).label == "Accepted, partly")
        quote.stage = .declined
        #expect(quote.status(on: today) == .declined)
    }

    @Test func lineIDsFollowTheOrderOnlyWhileDraft() {
        let (library, id) = Fixture.libraryWithQuote(stage: .draft)
        var quote = library.quote(id)!
        quote.lines.swapAt(0, 2)
        quote.renumberLinesIfDraft()
        #expect(quote.lines.map(\.title) == ["Extra screens", "Build", "Discovery"])
        #expect(quote.lineCodes == ["01", "02", "03"])
        quote.stage = .sent
        quote.lines.swapAt(0, 2)
        quote.renumberLinesIfDraft()
        #expect(quote.lineCodes == ["03", "02", "01"])
        #expect(quote.nextLineCode() == "04")
    }

    @Test func aSentQuoteNeverReusesALineID() {
        let (library, id) = Fixture.libraryWithQuote()
        var quote = library.quote(id)!
        quote.lines.remove(at: 2)
        quote.addLine(LineItem(title: "Training session", rate: Money(dollars: 200)))
        #expect(quote.lineCodes == ["01", "02", "04"])
    }

    @Test func markingSentRecordsTheTimeAndLogs() throws {
        var (library, id) = Fixture.libraryWithQuote(stage: .draft)
        let moment = Date(timeIntervalSince1970: 1_792_000_000)
        try library.markSent(quote: id, at: moment)
        let quote = library.quote(id)!
        #expect(quote.stage == .sent)
        #expect(quote.sentAt == moment)
        #expect(library.activity.first?.message == "Marked quote Q-0001 as sent")
    }

    @Test func acceptAllAcceptsEveryLine() {
        let (library, id) = Fixture.libraryWithQuote()
        let form = ReturnedForm(quoteNumber: "Q-0001", acceptAll: true, ticked: [], unticked: ["01", "02", "03"])
        let proposal = library.quote(id)!.proposal(from: form, today: today)
        #expect(proposal.accepted == ["01", "02", "03"])
        #expect(proposal.declined == [])
        #expect(proposal.problems == [])
    }

    @Test func tickedLinesAreAcceptedAndTheRestDeclined() {
        let (library, id) = Fixture.libraryWithQuote()
        let form = ReturnedForm(quoteNumber: "q-0001", acceptAll: false, ticked: ["01", "03"], unticked: ["02"],
                                clientName: "Sam Example", clientDate: "16/10/2026")
        let proposal = library.quote(id)!.proposal(from: form, today: today)
        #expect(proposal.accepted == ["01", "03"])
        #expect(proposal.declined == ["02"])
        #expect(proposal.clientName == "Sam Example")
        #expect(proposal.clientDate == "16/10/2026")
        #expect(proposal.problems == [])
    }

    @Test func nothingTickedIsFlagged() {
        let (library, id) = Fixture.libraryWithQuote()
        let form = ReturnedForm(quoteNumber: "Q-0001", acceptAll: false, ticked: [], unticked: ["01", "02", "03"])
        let proposal = library.quote(id)!.proposal(from: form, today: today)
        #expect(proposal.accepted == [])
        #expect(proposal.declined == ["01", "02", "03"])
        #expect(proposal.problems == [.nothingTicked])
    }

    @Test func proposalFlagsLinesTheClientNeverSaw() {
        // The client's PDF had 01–03. Since then 03 was removed and 04 added.
        let (library, id) = Fixture.libraryWithQuote()
        var quote = library.quote(id)!
        quote.lines.remove(at: 2)
        quote.addLine(LineItem(title: "Training session", rate: Money(dollars: 200)))
        let form = ReturnedForm(quoteNumber: "Q-0001", acceptAll: false, ticked: ["01", "03"], unticked: ["02"])
        let proposal = quote.proposal(from: form, today: today)
        #expect(proposal.accepted == ["01"])
        #expect(proposal.declined == ["02", "04"])
        #expect(proposal.problems == [.unknownLines(["03"]), .missingLines(["04"])])
        #expect(AcceptanceProblem.missingLines(["04"]).message
                == "Line 04 wasn't on the PDF the client saw, so it's marked declined.")
    }

    @Test func wrongQuoteAndExpiryAreFlagged() {
        let (library, id) = Fixture.libraryWithQuote()
        let quote = library.quote(id)!
        let form = ReturnedForm(quoteNumber: "Q-0009", acceptAll: true, ticked: [], unticked: quote.lineCodes)
        let proposal = quote.proposal(from: form, today: quote.validUntil.adding(days: 3))
        #expect(proposal.problems == [.wrongQuote(found: "Q-0009", expected: "Q-0001"),
                                      .expired(validUntil: quote.validUntil)])
        #expect(AcceptanceProblem.wrongQuote(found: "Q-0009", expected: "Q-0001").message
                == "This PDF is for quote Q-0009, not Q-0001.")
    }

    @Test func recordingAcceptanceSetsDecisionsAndLogs() throws {
        var (library, id) = Fixture.libraryWithQuote()
        try library.recordAcceptance(Acceptance(source: .returnedPDF, fileName: "Q-0001 signed.pdf",
                                                clientName: "Sam Example", accepted: ["01", "02"], declined: ["03"]),
                                     forQuote: id)
        let quote = library.quote(id)!
        #expect(quote.stage == .accepted)
        #expect(quote.lines.map(\.decision) == [.accepted, .accepted, .declined])
        #expect(quote.acceptedTotals.total == Money(dollars: 1080))
        #expect(quote.acceptance?.clientName == "Sam Example")
        #expect(library.activity.first?.message
                == "Recorded acceptance of Q-0001 from Q-0001 signed.pdf: accepted lines 01, 02; declined line 03")
    }

    @Test func decliningEverythingDeclinesTheQuote() throws {
        var (library, id) = Fixture.libraryWithQuote()
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: [], declined: ["01", "02", "03"]), forQuote: id)
        #expect(library.quote(id)!.stage == .declined)
        #expect(library.activity.first?.message == "Recorded acceptance of Q-0001 by hand: all lines declined")
    }

    @Test func unknownLineIDsChangeNothing() {
        var (library, id) = Fixture.libraryWithQuote()
        #expect(throws: LibraryError.unknownLineCodes(["09"])) {
            try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["09"], declined: []), forQuote: id)
        }
        #expect(library.quote(id)!.stage == .sent)
        #expect(library.quote(id)!.lines.allSatisfy { $0.decision == nil })
    }
}
