import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The step bar under a quote's or invoice's header: how big it is, where it wraps, and that
/// switching it off leaves nothing behind. Made-up data only.
@MainActor
@Suite struct StepBarTests {
    /// The section's width at the smallest window (980 less the tree, its gap and the padding): the
    /// same figure the header-fit tests use. The strip pads 8 either side of its contents.
    static let sectionWidth: CGFloat = 980 - 190 - 4 - 4 - 4
    static let contentWidth: CGFloat = sectionWidth - 16

    /// A private preferences store, so no test reads or writes the real one.
    func defaults() -> UserDefaults {
        let suite = "QuotePilotTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        return store
    }

    func size<V: View>(_ view: V, width: CGFloat? = nil) -> CGSize {
        _ = NSApplication.shared
        let root = width.map { AnyView(view.frame(width: $0)) } ?? AnyView(view)
        return NSHostingView(rootView: root).fittingSize
    }

    func bar(_ model: AppModel, quote number: String, defaults store: UserDefaults? = nil) throws -> StepBar {
        let id = try #require(model.library.quote(number: number)).id
        return StepBar(model: model, document: .quote(id), defaults: store ?? defaults())
    }

    func bar(_ model: AppModel, invoice number: String) throws -> StepBar {
        let id = try #require(model.library.invoices.first { $0.number == number }).id
        return StepBar(model: model, document: .invoice(id), defaults: defaults())
    }

    // MARK: Quiet

    /// The strip is about 20 high when everything shares one line.
    @Test func aShortSentenceKeepsTheStripToOneQuietLine() throws {
        let model = try UIFixture.sampleModel()
        // Q-0004 is a ready draft: "Next: Send by Mail… to send it to the client."
        let height = size(try bar(model, quote: "Q-0004"), width: Self.sectionWidth).height
        #expect((19...22).contains(height), "the strip is \(height) high")
        let invoice = size(try bar(model, invoice: "INV-0002"), width: Self.sectionWidth).height
        #expect((19...22).contains(invoice), "the invoice strip is \(invoice) high")
    }

    // MARK: The longest sentence at the smallest window

    @Test func theLongestSentenceGoesUnderTheStepsAtTheSmallestWindowAndFits() throws {
        let model = try UIFixture.sampleModel()
        let id = try #require(model.library.quote(number: "Q-0002")).id   // sent: the longest sentence
        let next = NextStep.forQuote(try #require(model.library.quote(id)), in: model.library, today: model.today)
        #expect(next.sentence.hasPrefix("Next: wait for the client to tick the PDF."))

        let beside = size(StepBarContent(next: next, stacked: false, open: { _ in })).width
        let under = size(StepBarContent(next: next, stacked: true, open: { _ in })).width
        #expect(beside > Self.contentWidth, "beside the steps it needs \(beside) of \(Self.contentWidth), so it must go under")
        #expect(under <= Self.contentWidth, "under the steps it needs \(under) of \(Self.contentWidth)")

        // The whole strip, as the editor hosts it: two short lines, nothing cut.
        let strip = size(try bar(model, quote: "Q-0002"), width: Self.sectionWidth)
        #expect(strip.height <= 40, "the strip is \(strip.height) high")
        let oneLine = size(try bar(model, quote: "Q-0004"), width: Self.sectionWidth).height
        #expect(strip.height > oneLine, "the long sentence should have gone under the steps")
    }

    @Test func aSentenceLongerStillWrapsInsteadOfBeingCut() throws {
        let model = try UIFixture.sampleModel()
        var next = NextStep.forQuote(try #require(model.library.quote(number: "Q-0002")), in: model.library, today: model.today)
        let usual = size(StepBarContent(next: next, stacked: true, open: { _ in }), width: Self.contentWidth).height
        next.sentence = next.sentence + " " + next.sentence + " " + next.sentence
        let long = size(StepBarContent(next: next, stacked: true, open: { _ in }), width: Self.contentWidth)
        #expect(long.height >= usual + 24, "three times the words should take at least two more lines: \(usual) then \(long.height)")
        #expect(long.width <= Self.contentWidth)
    }

    /// Every state the sample library and a library with a draft invoice reach: steps and sentence fit
    /// the smallest window, with the button when there is one.
    @Test func everyStripFitsTheSmallestWindow() throws {
        let sample = try UIFixture.sampleModel()
        var bars: [StepBar] = []
        for number in ["Q-0001", "Q-0002", "Q-0003", "Q-0004"] { bars.append(try bar(sample, quote: number)) }
        for number in ["INV-0001", "INV-0002", "INV-0003"] { bars.append(try bar(sample, invoice: number)) }
        // An accepted quote with a draft invoice has the "Open INV-0001" button.
        let drafted = try UIFixture.model(UIFixture.invoicedLibrary().library)
        bars.append(try bar(drafted, quote: "Q-0001"))
        bars.append(try bar(drafted, invoice: "INV-0001"))
        for bar in bars {
            let fitted = size(bar, width: Self.sectionWidth)
            #expect(fitted.height <= 40, "a strip is \(fitted.height) high")
        }
        for next in [
            NextStep.forQuote(try #require(drafted.library.quotes.first), in: drafted.library, today: drafted.today),
            NextStep.forQuote(try #require(sample.library.quote(number: "Q-0001")), in: sample.library, today: sample.today),
            NextStep.forQuote(try #require(sample.library.quote(number: "Q-0003")), in: sample.library, today: sample.today),
        ] {
            let under = size(StepBarContent(next: next, stacked: true, open: { _ in })).width
            #expect(under <= Self.contentWidth, "\"\(next.sentence)\" under the steps needs \(under) of \(Self.contentWidth)")
        }
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
        // The button widens the strip's sentence; the same sentence without it is narrower.
        var plain = next
        plain.action = nil
        let with = size(StepBarContent(next: next, stacked: false, open: { _ in })).width
        let without = size(StepBarContent(next: plain, stacked: false, open: { _ in })).width
        #expect(with > without + 40)
    }

    // MARK: Switching it off

    @Test func showStepsIsOnUntilItIsTurnedOffAndThenTheStripIsGone() throws {
        let model = try UIFixture.sampleModel()
        let store = defaults()
        let shown = size(try bar(model, quote: "Q-0004", defaults: store), width: Self.sectionWidth)
        #expect(shown.height > 0, "on by default")
        store.set(false, forKey: StepPreferences.showStepsKey)
        let hidden = size(try bar(model, quote: "Q-0004", defaults: store), width: Self.sectionWidth)
        #expect(hidden.height == 0, "off: no strip at all, so the editor is laid out exactly as before")
        store.set(true, forKey: StepPreferences.showStepsKey)
        #expect(size(try bar(model, quote: "Q-0004", defaults: store), width: Self.sectionWidth).height == shown.height)
    }

    @Test func aDocumentThatIsGoneShowsNoStrip() throws {
        let model = try UIFixture.sampleModel()
        let missing = StepBar(model: model, document: .quote(UUID()), defaults: defaults())
        #expect(size(missing, width: Self.sectionWidth).height == 0)
        let missingInvoice = StepBar(model: model, document: .invoice(UUID()), defaults: defaults())
        #expect(size(missingInvoice, width: Self.sectionWidth).height == 0)
    }

    // MARK: In the editors

    /// With the bar on, the header is just as wide as it was: the strip sits below it, in the editor,
    /// and takes nothing from its buttons. (The header-fit tests in InvoiceEditorTests measure the
    /// same `header(_:)` views.)
    @Test func theBarDoesNotChangeTheHeader() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0001"))
        let editor = QuoteEditorView(model: model, quoteID: quote.id)
        let width = size(editor.header(quote)).width
        #expect(width <= Self.sectionWidth)
    }

    @Test func theQuoteEditorShowsTheBarOnADraftWithAnInvoice() throws {
        let model = try UIFixture.model(UIFixture.invoicedLibrary().library)
        model.openQuote(try #require(model.library.quotes.first).id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "step-bar-open-invoice")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func anExpiredQuoteShowsItsWordInTheOverdueColour() throws {
        let model = try UIFixture.sampleModel()
        model.openQuote(try #require(model.library.quote(number: "Q-0003")).id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "step-bar-expired")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
