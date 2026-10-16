import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The step bar in the first row of a quote's or invoice's header: that it shows steps as words and
/// never as bare numbers, where it sits and how it gives way at the smallest window, and that
/// switching it off leaves nothing behind. Made-up data only.
@MainActor
@Suite struct StepBarTests {
    /// The section's width at the smallest window (980 less the tree, its gap and the padding), and at
    /// 1240: the same figure the header-fit tests use. The header's own 8-pt padding is inside it.
    static let smallSection: CGFloat = 980 - 190 - 4 - 4 - 4
    static let wideSection: CGFloat = 1240 - 190 - 4 - 4 - 4

    /// A private preferences store, so no test reads or writes the real one.
    func defaults(showSteps: Bool = true) -> UserDefaults {
        let suite = "QuotePilotTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        store.set(showSteps, forKey: StepPreferences.showStepsKey)
        return store
    }

    func size<V: View>(_ view: V, width: CGFloat? = nil) -> CGSize {
        _ = NSApplication.shared
        let root = width.map { AnyView(view.frame(width: $0)) } ?? AnyView(view)
        return NSHostingView(rootView: root).fittingSize
    }

    func quote(_ model: AppModel, _ number: String) throws -> Quote {
        try #require(model.library.quote(number: number))
    }

    func invoice(_ model: AppModel, _ number: String) throws -> Invoice {
        try #require(model.library.invoices.first { $0.number == number })
    }

    func next(_ model: AppModel, quote number: String) throws -> NextStep {
        NextStep.forQuote(try quote(model, number), in: model.library, today: model.today)
    }

    func next(_ model: AppModel, invoice number: String) throws -> NextStep {
        NextStep.forInvoice(try invoice(model, number), in: model.library, today: model.today)
    }

    /// A step list built by hand, for the states that are awkward to reach.
    func steps(_ words: [(String, NextStep.State)]) -> NextStep {
        NextStep(steps: words.enumerated().map { NextStep.Step(number: $0 + 1, title: $1.0, state: $1.1) },
                 sentence: "", action: nil)
    }

    // MARK: Words, not numbers

    @Test func aQuotesStepsAreWordsInOrder() throws {
        let model = try UIFixture.sampleModel()
        #expect(StepProgress.words(try next(model, quote: "Q-0004")) == ["Draft", "Sent", "Accepted", "Invoiced", "Paid"])
        #expect(StepProgress.label == "Progress:")
    }

    @Test func anInvoicesStepsAreWordsInOrder() throws {
        let model = try UIFixture.sampleModel()
        #expect(StepProgress.words(try next(model, invoice: "INV-0002")) == ["Draft", "Sent", "Paid"])
    }

    @Test func nothingThatIsShownOfTheStepsIsANumber() throws {
        let sample = try UIFixture.sampleModel()
        let drafted = try UIFixture.model(UIFixture.invoicedLibrary().library)
        var every: [NextStep] = []
        for number in ["Q-0001", "Q-0002", "Q-0003", "Q-0004"] { every.append(try next(sample, quote: number)) }
        for number in ["INV-0001", "INV-0002", "INV-0003"] { every.append(try next(sample, invoice: number)) }
        every.append(NextStep.forQuote(try #require(drafted.library.quotes.first), in: drafted.library, today: drafted.today))
        every.append(steps([("Draft", .done), ("Sent", .done), ("Declined", .stopped)]))
        for next in every {
            // The full row is the label, then each word with an arrow between: all that is drawn.
            let row = ([StepProgress.label] + StepProgress.words(next)).joined(separator: " ")
            let digits = row.filter { $0.isNumber }
            #expect(digits.isEmpty, "\"\(row)\" has a number in it")
        }
    }

    @Test func theShortFormNamesWhereTheDocumentIsNow() throws {
        let model = try UIFixture.sampleModel()
        #expect(StepProgress.compact(try next(model, quote: "Q-0004")) == "Draft (step 1 of 5)")
        #expect(StepProgress.compact(try next(model, quote: "Q-0002")) == "Sent (step 2 of 5)")
        #expect(StepProgress.compact(try next(model, quote: "Q-0001")) == "Invoiced (step 4 of 5)")
        #expect(StepProgress.compact(try next(model, invoice: "INV-0002")) == "Sent (step 2 of 3)")
    }

    @Test func aStoppedDocumentIsJustItsStopWordWithNoLaterSteps() throws {
        let model = try UIFixture.sampleModel()
        let expired = try next(model, quote: "Q-0003")
        #expect(StepProgress.words(expired) == ["Draft", "Sent", "Expired"])
        #expect(StepProgress.compact(expired) == "Expired")
        let declined = steps([("Draft", .done), ("Sent", .done), ("Declined", .stopped)])
        #expect(StepProgress.compact(declined) == "Declined")
        let void = steps([("Draft", .done), ("Sent", .done), ("Void", .stopped)])
        #expect(StepProgress.compact(void) == "Void")
    }

    @Test func aDocumentThatHasBeenThroughEveryStepSaysSo() throws {
        let model = try UIFixture.sampleModel()
        // INV-0001 is paid in full.
        let paid = try next(model, invoice: "INV-0001")
        #expect(paid.steps.allSatisfy { $0.state == .done })
        #expect(StepProgress.compact(paid) == "All steps done")
    }

    // MARK: The first row at the smallest window

    /// The first row's own width (the bar adds nothing to it) must fit the section at 980, as it did
    /// before the bar. The header-fit tests in InvoiceEditorTests measure the whole header the same way.
    @Test func theFirstRowStillFitsTheSmallestWindow() throws {
        let model = try UIFixture.sampleModel()
        for number in ["Q-0001", "Q-0002", "Q-0003", "Q-0004"] {
            let found = try quote(model, number)
            let needed = size(QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults()).titleRow(found)).width
            #expect(needed <= Self.smallSection, "\(number)'s first row needs \(needed) of \(Self.smallSection)")
        }
        for number in ["INV-0001", "INV-0002", "INV-0003"] {
            let found = try invoice(model, number)
            let needed = size(InvoiceEditorView(model: model, invoiceID: found.id, stepDefaults: defaults()).titleRow(found)).width
            #expect(needed <= Self.smallSection, "\(number)'s first row needs \(needed) of \(Self.smallSection)")
        }
    }

    /// The bar's ideal width is nothing: it takes what is left and asks for none, so a long sentence
    /// can't make the header ask for more than it had.
    @Test func theBarAsksForNoRoomOfItsOwn() throws {
        let model = try UIFixture.sampleModel()
        let found = try quote(model, "Q-0002")   // the longest sentence
        let on = QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults())
        let off = QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults(showSteps: false))
        let onWidth = size(on.titleRow(found)).width
        let offWidth = size(off.titleRow(found)).width
        #expect(onWidth <= offWidth, "with the bar the first row wants \(onWidth), without it \(offWidth)")
    }

    // MARK: Pictures

    /// The first and last column, within `xs`, that has a pixel in rows `ys` which is not the window's
    /// grey; nil when there is none.
    func ink(_ rep: NSBitmapImageRep, xs: Range<Int>, ys: Range<Int>) -> ClosedRange<Int>? {
        var first: Int?, last: Int?
        for x in xs {
            for y in ys where !isFace(rep, x: x, y: y) {
                first = first ?? x
                last = x
                break
            }
        }
        guard let first, let last else { return nil }
        return first...last
    }

    func isFace(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Bool {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return true }
        let grey = 192.0 / 255.0
        return abs(color.redComponent - grey) < 0.02 && abs(color.greenComponent - grey) < 0.02
            && abs(color.blueComponent - grey) < 0.02
    }

    /// Whether two pictures match pixel for pixel in a block of the first; the second is read `down`
    /// rows lower, for a header that grew above that block.
    func same(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, xs: Range<Int>, ys: Range<Int>, down: Int = 0) -> Bool {
        for x in xs {
            for y in ys {
                guard let one = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let two = b.colorAt(x: x, y: y + down)?.usingColorSpace(.sRGB),
                      abs(one.redComponent - two.redComponent) < 0.01,
                      abs(one.greenComponent - two.greenComponent) < 0.01,
                      abs(one.blueComponent - two.blueComponent) < 0.01
                else { return false }
            }
        }
        return true
    }

    /// How many pixels in a block are reddish: strongly red, little green or blue. (The small bold
    /// text is anti-aliased, so few of its pixels are the pure overdue red.)
    func redPixels(_ rep: NSBitmapImageRep, xs: Range<Int>, ys: Range<Int>) -> Int {
        var count = 0
        for x in xs {
            for y in ys {
                if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   color.redComponent > 0.55, color.greenComponent < 0.4, color.blueComponent < 0.4 { count += 1 }
            }
        }
        return count
    }

    /// A header drawn at `width`, with the top of it at the top of the picture.
    func picture<V: View>(_ header: V, width: CGFloat, name: String) throws -> NSBitmapImageRep {
        let framed = header.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        return try #require(Snapshot.render(framed, size: CGSize(width: width, height: 140), name: name))
    }

    /// Line 1 of the bar sits level with the title's first line.
    let line1Rows = 12..<26

    // MARK: Which form shows

    /// A document's header as the editor draws it, and what is needed to find the bar in a picture of it.
    struct Case {
        var name: String
        var next: NextStep
        /// The first row's own width: everything in it but the bar.
        var rowWidth: CGFloat
        var header: AnyView
        /// Where, across the section, line 1 of the bar can be: from the end of the title's first line
        /// to short of the total (and, on an invoice, the "Owing" label before it).
        var from: Int
        var gapBeforeTotal: Int
    }

    func cases(_ model: AppModel) throws -> [Case] {
        var made: [Case] = []
        for number in ["Q-0001", "Q-0002", "Q-0003", "Q-0004"] {
            let found = try quote(model, number)
            let editor = QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults())
            made.append(Case(name: number, next: try next(model, quote: number),
                             rowWidth: size(editor.titleRow(found)).width, header: AnyView(editor.header(found)),
                             from: 245, gapBeforeTotal: 230))
        }
        for number in ["INV-0001", "INV-0002", "INV-0003"] {
            let found = try invoice(model, number)
            let editor = InvoiceEditorView(model: model, invoiceID: found.id, stepDefaults: defaults())
            made.append(Case(name: number, next: try next(model, invoice: number),
                             rowWidth: size(editor.titleRow(found)).width, header: AnyView(editor.header(found)),
                             from: 285, gapBeforeTotal: 285))
        }
        return made
    }

    /// At 1240 the whole row of steps shows; at 980 the same document shows the whole row if it fits
    /// and otherwise the short form. Which one comes from the room the first row leaves (the section
    /// less the row's own width), and the pixels agree: line 1 is as wide as that form and stops short
    /// of the total.
    @Test func theFullRowShowsAtTheWideWindowAndTheShortFormWhenTheSmallestNeedsIt() throws {
        let model = try UIFixture.sampleModel()
        var seenFull = 0, seenShort = 0
        for item in try cases(model) {
            let full = size(StepProgressRow(next: item.next, compact: false)).width
            let short = size(StepProgressRow(next: item.next, compact: true)).width
            for (section, label) in [(Self.wideSection, "1240"), (Self.smallSection, "980")] {
                let room = section - item.rowWidth - StepBarRegion.leadingGap
                let expectFull = full <= room
                // The short form is shown whenever there is room for its minimum; below that, nothing.
                let expectShown = expectFull || room >= StepBarRegion.minimumWidth
                let rep = try picture(item.header, width: section, name: "stepbar-\(item.name)-\(label)")
                let columns = item.from..<(Int(section) - item.gapBeforeTotal)
                let line = ink(rep, xs: columns, ys: line1Rows)
                if section == Self.wideSection {
                    #expect(expectFull, "\(item.name) should show the whole row at 1240 (needs \(full) of \(room))")
                    // The sentence fits on one line too, so it doesn't crowd the buttons under it.
                    let sentence = size(Text(item.next.sentence).font(Win95.small).fixedSize()).width
                    #expect(sentence <= room, "\(item.name)'s sentence needs \(sentence) of \(room) at 1240")
                }
                if !expectShown {
                    #expect(line == nil, "\(item.name) at \(label): no room, so no bar")
                    continue
                }
                let drawn = try #require(line, "\(item.name) at \(label) shows no steps")
                let wanted = expectFull ? full : min(short, room)
                // (The ink stops short of the form's width by the padding after its last word.)
                #expect(abs(CGFloat(drawn.count) - wanted) <= 20,
                        "\(item.name) at \(label): line 1 is \(drawn.count) wide, wanted about \(wanted)")
                if expectFull { seenFull += 1 } else { seenShort += 1 }
            }
        }
        #expect(seenFull > 0 && seenShort > 0, "the sample should reach both forms (full \(seenFull), short \(seenShort))")
    }

    /// The widest first row there is (a completed job beside the status and a total in the millions)
    /// leaves the bar almost no room at 980. It then gives way entirely, and the total and the buttons
    /// are where they always were.
    @Test func whenThereIsNoRoomTheBarLeavesIt() throws {
        let done = try UIFixture.sampleModel()
        let id = try quote(done, "Q-0001").id
        done.completeJob(id)
        var big = try quote(done, "Q-0001")
        big.lines[0].rate = Money(dollars: 3_000_000)   // not saved (an invoiced quote's prices are locked)
        let editor = QuoteEditorView(model: done, quoteID: id, stepDefaults: defaults())
        let room = Self.smallSection - size(editor.titleRow(big)).width - StepBarRegion.leadingGap
        #expect(room < StepBarRegion.minimumWidth, "this should be a row the bar can't fit in (room \(room))")
        let rep = try picture(editor.header(big), width: Self.smallSection, name: "stepbar-no-room")
        // Between the end of the title's first line and the total, which starts about 250 from the edge.
        #expect(ink(rep, xs: 250..<(Int(Self.smallSection) - 260), ys: line1Rows) == nil)
    }

    // MARK: The sentence

    @Test func aLongSentenceTakesTwoLinesAtTheMostAndNeverMakesTheBarWiderThanItsRoom() throws {
        let model = try UIFixture.sampleModel()
        var next = try next(model, quote: "Q-0002")
        let twoLines = StepBarRegion.progressHeight + StepBarRegion.lineGap + 30
        for room in [260.0, 400.0, 560.0] as [CGFloat] {
            let usual = size(StepBarRegion(next: next, compact: true, open: { _ in }), width: room).height
            #expect(usual <= twoLines, "the usual sentence is \(usual) high in \(room)")
        }
        next.sentence = next.sentence + " " + next.sentence + " " + next.sentence
        let long = size(StepBarRegion(next: next, compact: true, open: { _ in }), width: 260)
        #expect(long.height <= twoLines, "three times the words are \(long.height) high")
        #expect(long.width == 260)
        // And its ideal width, which is what the header's own width is made of, doesn't grow with it.
        let ideal = size(StepBarRegion(next: next, compact: false, open: { _ in })).width
        let steps = size(StepProgressRow(next: next, compact: false)).width + StepBarRegion.leadingGap
        #expect(ideal <= steps + 1, "the bar asks for \(ideal), its steps need \(steps)")
    }

    @Test func theOpenInvoiceButtonIsOnlyThereWhenThereIsADraftToOpen() throws {
        let drafted = try UIFixture.model(UIFixture.invoicedLibrary().library)
        let quote = try #require(drafted.library.quotes.first)
        let next = NextStep.forQuote(quote, in: drafted.library, today: drafted.today)
        guard case .openInvoice(let id, let number) = next.action else {
            Issue.record("Expected the Open button's action, got \(String(describing: next.action))")
            return
        }
        #expect(number == "INV-0001")
        #expect(id == drafted.library.invoices.first?.id)
        // The button makes the sentence's line a little taller than the same sentence without it.
        var plain = next
        plain.action = nil
        let with = size(StepBarRegion(next: next, compact: false, open: { _ in }), width: 600).height
        let without = size(StepBarRegion(next: plain, compact: false, open: { _ in }), width: 600).height
        #expect(with > without)
    }

    // MARK: Switching it off

    @Test func withShowStepsOffTheHeaderIsAsItWasBeforeTheBar() throws {
        let model = try UIFixture.sampleModel()
        let found = try quote(model, "Q-0004")   // a one-line sentence: the header is the same height either way
        let on = QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults())
        let off = QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults(showSteps: false))
        for section in [Self.wideSection, Self.smallSection] {
            let withBar = try picture(on.header(found), width: section, name: "stepbar-on-\(Int(section))")
            let without = try picture(off.header(found), width: section, name: "stepbar-off-\(Int(section))")
            let height = Int(size(off.header(found), width: section).height)
            #expect(Int(size(on.header(found), width: section).height) == height, "a one-line bar leaves the header as tall as it was")
            // With it off the space between the title block and the total is empty window grey ...
            let between = 245..<(Int(section) - 230)
            #expect(ink(without, xs: between, ys: 8..<50) == nil)
            #expect(ink(withBar, xs: between, ys: 8..<50) != nil)
            // ... and every other pixel of the header is where it was: the left end of the first row,
            // the total, and the buttons below.
            let width = Int(section)
            #expect(same(withBar, without, xs: 0..<245, ys: 0..<height), "the left of the header moved")
            #expect(same(withBar, without, xs: (width - 195)..<width, ys: 0..<height), "the total or the buttons moved")
        }
    }

    @Test func aSecondLineOnTheSentenceDoesNotMoveTheTotalOrTheTitleOrTheButtons() throws {
        let model = try UIFixture.sampleModel()
        let found = try quote(model, "Q-0002")   // the longest sentence: two lines at 980
        let on = QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults())
        let off = QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults(showSteps: false))
        let section = Self.smallSection
        let withBar = try picture(on.header(found), width: section, name: "stepbar-two-lines-on")
        let without = try picture(off.header(found), width: section, name: "stepbar-two-lines-off")
        let heightOn = Int(size(on.header(found), width: section).height)
        let heightOff = Int(size(off.header(found), width: section).height)
        #expect(heightOn > heightOff, "the second line should have made the first row taller")
        #expect(heightOn - heightOff <= 12, "the header grew by \(heightOn - heightOff)")
        let width = Int(section)
        // The total and the All Quotes button stay level with the title, as they were ...
        #expect(same(withBar, without, xs: (width - 195)..<width, ys: 0..<(heightOff - 44)), "the total moved")
        #expect(same(withBar, without, xs: 0..<245, ys: 0..<(heightOff - 44)), "the left of the first row moved")
        // ... and the buttons under them span the same columns, only lower by what the row grew. (The
        // rows are looked at from the bottom of each header, where the buttons are; the half-point the
        // row grows by can land their text a pixel either side, so the picture is not compared pixel
        // for pixel there.)
        let buttonsOn = ink(withBar, xs: 0..<width, ys: (heightOn - 31)..<(heightOn - 8))
        let buttonsOff = ink(without, xs: 0..<width, ys: (heightOff - 31)..<(heightOff - 8))
        #expect(buttonsOn != nil && buttonsOn == buttonsOff, "the buttons moved sideways: \(String(describing: buttonsOn)) against \(String(describing: buttonsOff))")
    }

    @Test func showStepsIsOnUntilItIsTurnedOffAndThenTheBarIsGone() throws {
        let model = try UIFixture.sampleModel()
        let id = try quote(model, "Q-0004").id
        let store = defaults()
        store.removeObject(forKey: StepPreferences.showStepsKey)
        let shown = size(StepBar(model: model, document: .quote(id), defaults: store), width: Self.smallSection)
        #expect(shown.height > 0, "on by default")
        store.set(false, forKey: StepPreferences.showStepsKey)
        let hidden = size(StepBar(model: model, document: .quote(id), defaults: store), width: Self.smallSection)
        #expect(hidden == size(Spacer(), width: Self.smallSection), "off: nothing is drawn, only the spacer the header always had")
        store.set(true, forKey: StepPreferences.showStepsKey)
        #expect(size(StepBar(model: model, document: .quote(id), defaults: store), width: Self.smallSection).height == shown.height)
    }

    @Test func aDocumentThatIsGoneShowsNoBar() throws {
        let model = try UIFixture.sampleModel()
        let missing = StepBar(model: model, document: .quote(UUID()), defaults: defaults())
        let spacer = size(Spacer(), width: Self.smallSection)
        #expect(size(missing, width: Self.smallSection) == spacer)
        let missingInvoice = StepBar(model: model, document: .invoice(UUID()), defaults: defaults())
        #expect(size(missingInvoice, width: Self.smallSection) == spacer)
    }

    // MARK: In the editors

    /// There is no strip under the header any more: the form and the preview start right under it, so
    /// with a one-line sentence the editor is as tall with the bar as without.
    @Test func theEditorsHaveNoStripUnderTheirHeader() throws {
        let model = try UIFixture.sampleModel()
        let found = try quote(model, "Q-0004")
        let on = size(QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults()), width: Self.smallSection).height
        let off = size(QuoteEditorView(model: model, quoteID: found.id, stepDefaults: defaults(showSteps: false)),
                       width: Self.smallSection).height
        #expect(on == off, "with the bar the editor is \(on) high, without it \(off)")
    }

    @Test func theQuoteEditorShowsTheBarOnADraftWithAnInvoice() throws {
        let model = try UIFixture.model(UIFixture.invoicedLibrary().library)
        model.openQuote(try #require(model.library.quotes.first).id)
        for (width, height, name) in [(1240, 800, "step-bar-open-invoice"), (980, 620, "step-bar-open-invoice-small")] {
            let rep = Snapshot.render(RootView(model: model), size: CGSize(width: width, height: height), name: name)
            #expect(rep.map(Snapshot.hasContent) == true)
        }
    }

    @Test func anExpiredQuoteShowsItsWordInTheOverdueColour() throws {
        let model = try UIFixture.sampleModel()
        model.openQuote(try quote(model, "Q-0003").id)
        let rep = try #require(Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "step-bar-expired"))
        #expect(Snapshot.hasContent(rep))
        // The bar's line 1 starts to the right of the title block (the status label under the title is
        // red as well, which is why only line 1's rows and columns are looked at).
        #expect(redPixels(rep, xs: 470..<900, ys: 110..<126) > 10, "Expired should be drawn in the overdue red")
        model.openQuote(try quote(model, "Q-0004").id)
        let draft = try #require(Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "step-bar-draft"))
        #expect(redPixels(draft, xs: 470..<900, ys: 110..<126) == 0, "a draft has nothing in red")
    }

    @Test func anInvoiceEditorShowsTheBarAtBothSizes() throws {
        let model = try UIFixture.sampleModel()
        model.openInvoice(try invoice(model, "INV-0002").id)
        for (width, height, name) in [(1240, 800, "step-bar-invoice"), (980, 620, "step-bar-invoice-small")] {
            let rep = Snapshot.render(RootView(model: model), size: CGSize(width: width, height: height), name: name)
            #expect(rep.map(Snapshot.hasContent) == true)
        }
    }
}
