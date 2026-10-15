import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// Where `SizeRecorder` leaves the size its content was given.
private final class PlacedSize {
    var size = CGSize.zero
}

/// Lays out its one child as it asks to be, and notes the size it ended up with, so a test can
/// read how tall a dialog came out in a hosting view.
private struct SizeRecorder: Layout {
    let placed: PlacedSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        placed.size = bounds.size
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

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

    /// Q-0002's PDF with its form flattened away, as printing to PDF does, saved under `name`.
    func flattened(_ model: AppModel, number: String = "Q-0002", keepingKeywords: Bool, name: String) throws -> URL {
        let quote = try #require(model.library.quote(number: number))
        let data = model.pdf(try #require(model.quoteContent(quote.id)))
        return try UIFixture.file(name, UIFixture.flattened(data, keepingKeywords: keepingKeywords))
    }

    /// A PDF with no tick boxes whose quote is known goes straight to the hand-ticking review: no box
    /// first, one line of text in the review saying why.
    @Test func aFlattenedPDFOpensTheHandTickingReviewAtOnce() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0002"))
        model.readReturnedQuote(at: try flattened(model, keepingKeywords: true, name: "Q-0002 printed.pdf"))
        #expect(model.message == nil)
        let review = try review(model)
        #expect(review.source == .byHand)
        #expect(review.accepted.isEmpty)
        #expect(review.quoteID == quote.id)
        #expect(review.fileName == "Q-0002 printed.pdf")
        #expect(review.problems.isEmpty)
        #expect(model.openQuoteID == quote.id)
        #expect(model.library.quote(number: "Q-0002")?.stage == .sent)
    }

    /// The line at the top of the review says where the ticks came from.
    @Test func theReviewsFirstLineSaysWhereItsTicksCameFrom() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: ["01"]))
        #expect(try review(model).intro
            == "From Q-0002 returned.pdf. Check the ticks and change any that are wrong, then confirm.")

        model.dialog = nil
        model.startHandTicking(try #require(model.library.quote(number: "Q-0002")?.id))
        #expect(try review(model).intro == "Tick the lines the client accepted, then confirm.")

        model.dialog = nil
        model.readReturnedQuote(at: try flattened(model, keepingKeywords: true, name: "Q-0002 printed.pdf"))
        #expect(try review(model).intro
            == "This PDF has no tick boxes (it was probably printed or scanned). Tick the lines the client accepted.")
    }

    /// With the keywords gone too, the file's name can still say which quote it is.
    @Test func aFlattenedPDFNamedAfterItsQuoteIsFoundByItsName() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0002"))
        model.readReturnedQuote(at: try flattened(model, keepingKeywords: false, name: "reply for q-0002 (scan).pdf"))
        #expect(model.message == nil)
        #expect(try review(model).quoteID == quote.id)
    }

    /// A number that isn't a quote here, or only starts like one, doesn't identify anything.
    @Test func aFileNameThatDoesntNameAQuoteDoesntIdentifyOne() throws {
        for name in ["Q-0099 reply.pdf", "Q-00021.pdf", "XQ-0002.pdf", "scan.pdf"] {
            let model = try UIFixture.sampleModel()
            model.readReturnedQuote(at: try flattened(model, keepingKeywords: false, name: name))
            #expect(model.message?.title == "No Tick Boxes", "\(name)")
            #expect(model.dialog == nil, "\(name)")
        }
    }

    @Test func aFlattenedPDFWithNoNumberJustSaysSo() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try flattened(model, keepingKeywords: false, name: "scan.pdf"))
        #expect(model.message?.title == "No Tick Boxes")
        #expect(model.message?.choices.count == 1)
        #expect(model.dialog == nil)
    }

    /// Still one box at most: a flattened PDF for a quote that can't take a decision says why.
    @Test func aFlattenedPDFForADraftQuoteIsOneBox() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try flattened(model, number: "Q-0004", keepingKeywords: true, name: "Q-0004 printed.pdf"))
        #expect(model.dialog == nil)
        #expect(model.message?.title == "Can't Record It")
        #expect(model.message?.text == LibraryError.notSent.message)
    }

    /// A decline is one step, not two: the review's own button says what it will do, and no box
    /// asks again.
    @Test func nothingTickedRecordsTheDeclineInOneStep() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: []))
        model.confirmAcceptance(try review(model))
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        let quote = try #require(model.library.quote(number: "Q-0002"))
        #expect(quote.stage == .declined)
        #expect(quote.acceptance?.accepted == [])
        #expect(quote.acceptance?.declined == ["01", "02"])
        #expect(model.library.invoices.count == 3)
        #expect(model.openQuoteID == quote.id)
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

    /// What the review's button says and which warnings show follow the ticks as they are now, not
    /// as they were when the review opened.
    @Test func theButtonAndTheWarningsFollowTheTicks() throws {
        let model = try UIFixture.sampleModel()
        let url = try returned(model, ticking: [])
        // A line added after the client's PDF was made: the PDF doesn't have it.
        var quote = try #require(model.library.quote(number: "Q-0002"))
        quote.addLine(LineItem(title: "Extra", rate: Money(dollars: 50)))
        model.updateQuote(quote)
        model.readReturnedQuote(at: url)
        var review = try review(model)
        #expect(review.lines.map(\.code) == ["01", "02", "03"])
        #expect(review.confirmTitle == "Record as Declined")
        #expect(review.problems == [.missingLines(["03"]), .nothingTicked])

        review.lines[0].accepted = true
        #expect(review.confirmTitle == "Confirm")
        #expect(review.problems == [.missingLines(["03"])])

        // Ticking the line the PDF didn't have means it isn't "marked declined" any more.
        review.lines[2].accepted = true
        #expect(review.problems.isEmpty)

        review.lines[0].accepted = false
        review.lines[2].accepted = false
        #expect(review.confirmTitle == "Record as Declined")
        #expect(review.problems == [.missingLines(["03"]), .nothingTicked])
    }

    /// Hand-ticking starts with nothing ticked on purpose, so it shows no warning for that; the
    /// button still says what recording it now would do.
    @Test func handTickingShowsNoWarningButTheButtonFollowsTheTicks() throws {
        let model = try UIFixture.sampleModel()
        model.startHandTicking(try #require(model.library.quote(number: "Q-0002")?.id))
        var review = try review(model)
        #expect(review.problems.isEmpty)
        #expect(review.confirmTitle == "Record as Declined")
        review.lines[0].accepted = true
        #expect(review.confirmTitle == "Confirm")
        review.lines[0].accepted = false
        #expect(review.problems.isEmpty)

        // The expiry warning still shows.
        model.dialog = nil
        let expired = try #require(model.library.quote(number: "Q-0003"))
        model.startHandTicking(expired.id)
        #expect(try self.review(model).problems == [.expired(validUntil: expired.validUntil)])
    }

    /// Recording over a decision that's already there says so, in the review itself.
    @Test func recordingAgainSaysWhatItReplaces() throws {
        let model = try UIFixture.sampleModel()
        let id = try #require(model.library.quote(number: "Q-0002")?.id)
        model.startHandTicking(id)
        #expect(try review(model).replacementNote == nil)

        // Declined, with no invoice, can still be recorded again.
        model.confirmAcceptance(try review(model))
        #expect(model.library.quote(id)?.stage == .declined)
        model.startHandTicking(id)
        #expect(try review(model).replacementNote == "This replaces the decision recorded on 15 October 2026.")

        // So can accepted without a deposit (the full-amount plan drafts nothing at once).
        var quote = try #require(model.library.quote(id))
        quote.plan = .fullAmount
        model.updateQuote(quote)
        var again = try review(model)
        again.lines[0].accepted = true
        model.confirmAcceptance(again)
        #expect(model.library.quote(id)?.stage == .accepted)
        #expect(model.library.invoices(forQuote: id).isEmpty)
        model.startHandTicking(id)
        #expect(try review(model).replacementNote == "This replaces the decision recorded on 15 October 2026.")
    }

    @Test func theDepositNoteUsesThePlansOwnPercent() {
        let fifty = AcceptanceReviewView.planNote(plan: .fiftyFifty, accepted: Money(dollars: 450), currencyCode: "AUD")
        #expect(fifty.contains("$225.00"))
        #expect(AcceptanceReviewView.planNote(plan: .fullAmount, accepted: Money(dollars: 450), currencyCode: "AUD")
            .hasPrefix("Full amount"))
        #expect(AcceptanceReviewView.planNote(plan: .fiftyFifty, accepted: .zero, currencyCode: "AUD")
            .hasPrefix("Nothing is ticked"))
    }

    /// A hand-ticked review is recorded as ticked by hand, with the file it came from if it had one.
    @Test func aHandTickedReviewIsRecordedByHand() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try flattened(model, keepingKeywords: true, name: "Q-0002 printed.pdf"))
        var review = try review(model)
        #expect(review.source == .byHand)
        review.lines[0].accepted = true
        model.confirmAcceptance(review)
        let recorded = try #require(model.library.quote(number: "Q-0002")?.acceptance)
        #expect(recorded.source == .byHand)
        #expect(recorded.fileName == "Q-0002 printed.pdf")
        #expect(recorded.accepted == ["01"])
        #expect(recorded.declined == ["02"])
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

    // MARK: How tall the review is

    /// The expired quote Q-0003 with eight lines, read from a returned form. With `allWarnings` the
    /// PDF has a line 09 the quote doesn't have and nothing ticked: four warnings (unknown line,
    /// missing lines, nothing ticked, expired). Without, line 01 is ticked: two warnings.
    func eightLineReview(_ model: AppModel, allWarnings: Bool) throws -> AcceptanceReview {
        var quote = try #require(model.library.quote(number: "Q-0003"))
        for number in 2...8 { quote.addLine(LineItem(title: "Extra work \(number)", rate: Money(dollars: 100))) }
        model.updateQuote(quote)
        quote = try #require(model.library.quote(number: "Q-0003"))
        let form = allWarnings
            ? ReturnedForm(quoteNumber: "Q-0003", acceptAll: false, ticked: [], unticked: ["01", "09"])
            : ReturnedForm(quoteNumber: "Q-0003", acceptAll: false, ticked: ["01"], unticked: [])
        let review = AcceptanceReview(quote: quote, proposal: quote.proposal(from: form, today: model.today),
                                      source: .returnedPDF, fileName: "Q-0003 returned.pdf")
        #expect(review.problems.count == (allWarnings ? 4 : 2))
        return review
    }

    /// How tall the review comes out in a window `windowHeight` high, placed the way the dialog
    /// overlay places it: centred, with a margin above and below.
    func reviewHeight(_ review: AcceptanceReview, _ model: AppModel, windowHeight: CGFloat) -> CGFloat {
        let size = CGSize(width: 1240, height: windowHeight)
        let placed = PlacedSize()
        let view = SizeRecorder(placed: placed) { AcceptanceReviewView(model: model, review: review) }
            .padding(.vertical, DialogOverlay.verticalMargin)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        return placed.size.height
    }

    /// The height a 500-high scroll area gets between two 100-high rows (10 apart) when the stack is
    /// offered `offered`.
    func scrollAreaHeight(offered: CGFloat) -> CGFloat {
        let placed = PlacedSize()
        let stack = LeftoverHeightStack(spacing: 10) {
            Color.clear.frame(width: 100, height: 100)
            SizeRecorder(placed: placed) { ScrollView { Color.clear.frame(width: 100, height: 500) } }
                .takesLeftoverHeight()
            Color.clear.frame(width: 100, height: 100)
        }
        let size = CGSize(width: 300, height: offered)
        _ = NSApplication.shared
        let host = NSHostingView(rootView: stack.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        return placed.size.height
    }

    /// The scroll area is as tall as its contents, no taller than what's left of the height offered.
    @Test func theScrollAreaTakesWhatTheOtherRowsLeaveUpToItsContents() {
        #expect(scrollAreaHeight(offered: 2000) == 500)
        #expect(scrollAreaHeight(offered: 720) == 500)
        #expect(scrollAreaHeight(offered: 400) == 180)   // 400 less two rows and two gaps
        #expect(scrollAreaHeight(offered: 150) == 0)     // never negative
    }

    /// Two warnings above eight lines show every line, with no scrolling, in a roomy window (1240 x
    /// 800) and in the smallest one (980 x 620): the review is as tall as its contents.
    @Test func aShortReviewDoesntScroll() throws {
        let model = try UIFixture.sampleModel()
        let review = try eightLineReview(model, allWarnings: false)
        let natural = reviewHeight(review, model, windowHeight: 5000)
        #expect(natural > 500, "the review measured \(natural)")
        #expect(reviewHeight(review, model, windowHeight: 800) == natural)
        #expect(reviewHeight(review, model, windowHeight: 620) == natural, "two warnings need \(natural)")
    }

    /// Four warnings above eight lines is the tallest the review gets. In the smallest window (620
    /// high) it has to stay inside, and it does that by scrolling, not by running off the window.
    @Test func aReviewWithEveryWarningFitsTheSmallestWindow() throws {
        let model = try UIFixture.sampleModel()
        var review = try eightLineReview(model, allWarnings: true)
        // A quote can't be both expired and already decided, but if it could, the extra line fits too.
        review.replacementNote = "This replaces the decision recorded on 15 October 2026."
        let natural = reviewHeight(review, model, windowHeight: 5000)
        let small = reviewHeight(review, model, windowHeight: 620)
        #expect(small <= 620 - 60, "in a 620 window it is \(small) high")
        #expect(natural > small, "unscrolled it would be \(natural)")

        // Through the real overlay: the whole window, the dialog over it.
        model.dialog = .acceptance(review)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "acceptance-review-worst")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// The Record Acceptance… button lives in the editor's header: it has to fit the smallest window.
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

    /// A web link ending in .pdf is not a file: reading it would download it on the main thread.
    /// (A closed local port stands in for the web, so a failing test never leaves the Mac.)
    @Test func aDroppedWebLinkIsRefusedAndNothingChanges() throws {
        let model = try UIFixture.sampleModel()
        let before = model.library
        let link = try #require(URL(string: "http://127.0.0.1:9/Q-0002.pdf"))
        #expect(!model.dropped([link]))
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.library.quotes == before.quotes)
        #expect(model.library.activity.count == before.activity.count)
        // A real PDF dropped with it is still read.
        #expect(model.dropped([link, try returned(model, ticking: ["01"])]))
        #expect(try review(model).accepted == ["01"])
    }

    /// With the library unreadable there's nothing a drop could do, so it says it didn't handle it.
    @Test func aDropIsRefusedWhileTheLibraryCantBeUsed() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        let pdf = try UIFixture.file("Q-0002 returned.pdf", Data("%PDF-1.4".utf8))
        #expect(model.loadState != .ready)
        #expect(!model.dropped([pdf]))
        #expect(model.message == nil)
        #expect(model.dialog == nil)
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
