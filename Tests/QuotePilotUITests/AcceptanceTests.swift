import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct AcceptanceTests {
    /// The sample's sent quote Q-0002 (01 Menu board design $450, 02 Printing 2 × $85), as the
    /// client sends it back.
    func returned(_ model: AppModel, ticking codes: [String], acceptAll: Bool = false) throws -> URL {
        let quote = try #require(model.library.quote(number: "Q-0002"))
        let data = model.pdf(try #require(model.quoteContent(quote.id)))
        return try UIFixture.file("Q-0002 returned.pdf",
                                  UIFixture.fill(data, ticking: codes, acceptAll: acceptAll, name: "Alex Sample", date: "16/10/2026"))
    }

    func review(_ model: AppModel) throws -> AcceptanceReview {
        guard case .acceptance(let review) = model.dialog else {
            Issue.record("Expected the acceptance review, found \(String(describing: model.dialog))")
            throw CancellationError()
        }
        return review
    }

    @Test func aReturnedPDFOpensTheReviewAndChangesNothingYet() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: ["01"]))
        let review = try review(model)
        #expect(review.accepted == ["01"])
        #expect(review.declined == ["02"])
        #expect(review.clientName == "Alex Sample")
        #expect(review.clientDate == "16/10/2026")
        #expect(review.source == .returnedPDF)
        #expect(review.fileName == "Q-0002 returned.pdf")
        #expect(review.canBeConfirmed)
        #expect(model.library.quote(number: "Q-0002")?.stage == .sent)
        #expect(model.openQuoteID == review.quoteID)
    }

    @Test func confirmingRecordsItAndOpensTheDeposit() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: [], acceptAll: true))
        model.confirmAcceptance(try review(model))
        let quote = try #require(model.library.quote(number: "Q-0002"))
        #expect(quote.stage == .accepted)
        #expect(quote.acceptance?.fileName == "Q-0002 returned.pdf")
        let deposit = try #require(model.library.invoices(forQuote: quote.id).first)
        #expect(deposit.kind == .deposit)
        #expect(deposit.amount == Money(dollars: 310))
        #expect(model.dialog == nil)
        #expect(model.section == .invoices)
        #expect(model.selectedInvoiceID == deposit.id)
    }

    @Test func aChangedTickIsWhatGetsRecorded() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: ["01", "02"]))
        var review = try review(model)
        review.lines[1].accepted = false
        model.confirmAcceptance(review)
        let quote = try #require(model.library.quote(number: "Q-0002"))
        #expect(quote.lines.map(\.decision) == [.accepted, .declined])
    }

    @Test func aPDFForAnotherQuoteChangesNothing() throws {
        let sample = try UIFixture.sampleModel()
        let url = try returned(sample, ticking: ["01"])
        let other = try UIFixture.model()
        other.readReturnedQuote(at: url)
        #expect(other.dialog == nil)
        #expect(other.message?.title == "No Such Quote")
        #expect(other.library.quotes.isEmpty)
    }

    @Test func linesTheQuoteNoLongerHasBlockConfirming() throws {
        let model = try UIFixture.sampleModel()
        let url = try returned(model, ticking: ["01", "02"])
        var quote = try #require(model.library.quote(number: "Q-0002"))
        quote.lines.removeLast()
        model.updateQuote(quote)
        model.readReturnedQuote(at: url)
        let review = try review(model)
        #expect(!review.canBeConfirmed)
        model.confirmAcceptance(review)
        #expect(model.library.quote(number: "Q-0002")?.stage == .sent)
    }

    @Test func aFlattenedPDFOffersHandTicking() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0002"))
        let data = model.pdf(try #require(model.quoteContent(quote.id)))
        let url = try UIFixture.file("Q-0002 printed.pdf", UIFixture.flattened(data, keepingKeywords: true))
        model.readReturnedQuote(at: url)
        let box = try #require(model.message)
        #expect(box.title == "No Tick Boxes")
        model.respond(try #require(box.choices.first { $0.title == "Tick by Hand" }))
        let review = try review(model)
        #expect(review.source == .byHand)
        #expect(review.accepted.isEmpty)
        #expect(review.quoteID == quote.id)
    }

    @Test func aFlattenedPDFWithNoNumberJustSaysSo() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0002"))
        let data = model.pdf(try #require(model.quoteContent(quote.id)))
        model.readReturnedQuote(at: try UIFixture.file("scan.pdf", UIFixture.flattened(data, keepingKeywords: false)))
        #expect(model.message?.title == "No Tick Boxes")
        #expect(model.message?.choices.count == 1)
        #expect(model.dialog == nil)
    }

    @Test func nothingTickedAsksBeforeRecordingADecline() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: []))
        model.confirmAcceptance(try review(model))
        #expect(model.library.quote(number: "Q-0002")?.stage == .sent)
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first { $0.title == "Record as Declined" }))
        #expect(model.library.quote(number: "Q-0002")?.stage == .declined)
        #expect(model.library.invoices.count == 3)
    }

    @Test func handTickingStartsUntickedAndOnlyForSentQuotes() throws {
        let model = try UIFixture.sampleModel()
        let sent = try #require(model.library.quote(number: "Q-0002"))
        model.startHandTicking(sent.id)
        let review = try review(model)
        #expect(review.source == .byHand)
        #expect(review.accepted.isEmpty)
        model.dialog = nil
        let draft = try #require(model.library.quote(number: "Q-0004"))
        model.startHandTicking(draft.id)
        #expect(model.dialog == nil)
        #expect(model.message?.text == LibraryError.notSent.message)
    }

    @Test func theReviewDraws() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: ["01"]))
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "acceptance-review")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// The tallest the review gets: warnings above eight lines, in the smallest window.
    @Test func aTallReviewDrawsInTheSmallestWindow() throws {
        let model = try UIFixture.sampleModel()
        let expired = try #require(model.library.quote(number: "Q-0003"))
        let data = model.pdf(try #require(model.quoteContent(expired.id)))
        let url = try UIFixture.file("Q-0003 returned.pdf", UIFixture.fill(data, ticking: ["01"], name: "Sam Example", date: "16/10/2026"))
        var quote = expired
        for number in 2...8 { quote.addLine(LineItem(title: "Extra work \(number)", rate: Money(dollars: 100))) }
        model.updateQuote(quote)
        model.readReturnedQuote(at: url)
        let review = try review(model)
        #expect(review.lines.count == 8)
        #expect(review.problems.count == 2)
        #expect(review.canBeConfirmed)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "acceptance-review-small")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// The sent quote's header now has Record Acceptance… too: it has to fit the smallest window.
    @Test func aSentQuoteDrawsInTheSmallestWindow() throws {
        let model = try UIFixture.sampleModel()
        model.openQuote(try #require(model.library.quote(number: "Q-0002")?.id))
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "sent-quote-small")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    // MARK: Dropping a PDF and the open panel

    @Test func aDroppedPDFIsReadAndOtherFilesAreRefused() throws {
        let model = try UIFixture.sampleModel()
        let url = try returned(model, ticking: ["01"])
        let notes = try UIFixture.file("notes.txt", Data("hello".utf8))
        #expect(!model.dropped([notes]))
        #expect(model.dialog == nil)
        #expect(model.message == nil)
        #expect(model.dropped([notes, url]))
        #expect(try review(model).accepted == ["01"])
    }

    /// A message box, a dialog or a panel is modal: a drop behind it must not replace what's showing.
    @Test func aDropBehindAMessageBoxOrADialogIsIgnored() throws {
        let model = try UIFixture.sampleModel()
        let url = try returned(model, ticking: ["01"])
        var beeps = 0
        model.beep = { beeps += 1 }

        model.show(title: "Careful", text: "Read this first.")
        #expect(!model.dropped([url]))
        #expect(model.message?.title == "Careful")
        #expect(model.dialog == nil)

        model.message = nil
        model.startHandTicking(try #require(model.library.quote(number: "Q-0002")?.id))
        let open = try review(model)
        #expect(!model.dropped([url]))
        #expect(try review(model) == open)

        model.dialog = nil
        model.choosingFile = .returnedQuote
        #expect(!model.dropped([url]))
        #expect(model.dialog == nil)
        #expect(beeps == 3)
    }

    @Test func theOpenPanelReadsTheFileItWasOpenedFor() throws {
        let model = try UIFixture.sampleModel()
        let url = try returned(model, ticking: ["01"])
        model.choosingFile = .returnedQuote
        model.fileChosen(.success(url))
        #expect(model.choosingFile == nil)
        #expect(try review(model).accepted == ["01"])
    }

    /// SwiftUI may flip `isPresented` back (clearing `choosingFile`) before it reports the file.
    @Test func theFileIsStillReadWhenThePanelClosesBeforeItReports() throws {
        let model = try UIFixture.sampleModel()
        let url = try returned(model, ticking: ["01"])
        model.choosingFile = .returnedQuote
        model.choosingFile = nil
        model.fileChosen(.success(url))
        #expect(try review(model).accepted == ["01"])

        // The answer is used once: a file nobody asked for is left alone.
        model.dialog = nil
        model.fileChosen(.success(url))
        #expect(model.dialog == nil)
        #expect(model.message == nil)
    }

    @Test func cancellingTheOpenPanelSaysNothingButARealFailureDoes() throws {
        let model = try UIFixture.sampleModel()
        model.choosingFile = .returnedQuote
        model.fileChosen(.failure(CocoaError(.userCancelled)))
        #expect(model.choosingFile == nil)
        #expect(model.message == nil)

        model.choosingFile = .returnedQuote
        model.fileChosen(.failure(CocoaError(.fileReadNoPermission)))
        #expect(model.message?.title == "Couldn't open that file")
    }
}
