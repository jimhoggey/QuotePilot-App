import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The "Getting started" box on the Dashboard of a new library, and the Dashboard's list order.
@MainActor
@Suite struct GettingStartedTests {
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

    // MARK: Which steps are done

    @Test func anEmptyLibraryHasNothingDone() {
        let steps = GettingStarted(library: Library())
        #expect(steps.isDone(.business) == false)
        #expect(steps.isDone(.client) == false)
        #expect(steps.isDone(.quote) == false)
        #expect(steps.isShowing)
        #expect(steps.first == .business)
    }

    @Test func aBusinessNameMakesTheFirstStepDone() {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        let steps = GettingStarted(library: library)
        #expect(steps.isDone(.business))
        #expect(steps.isDone(.client) == false)
        #expect(steps.isDone(.quote) == false)
        #expect(steps.first == .client)
    }

    @Test func aBlankBusinessNameIsNotAName() {
        var library = Library()
        library.brand.businessName = "   "
        #expect(GettingStarted(library: library).isDone(.business) == false)
    }

    @Test func aClientMakesTheSecondStepDone() {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        library.addClient(Client(name: "Sample Client Pty Ltd"))
        let steps = GettingStarted(library: library)
        #expect(steps.isDone(.business))
        #expect(steps.isDone(.client))
        #expect(steps.isDone(.quote) == false)
        #expect(steps.first == .quote)
    }

    @Test func aClientCountsEvenBeforeTheBusinessIsFilledIn() {
        var library = Library()
        library.addClient(Client(name: "Sample Client Pty Ltd"))
        let steps = GettingStarted(library: library)
        #expect(steps.isDone(.client))
        // The first step still not done is the one that gets the default button.
        #expect(steps.first == .business)
    }

    @Test func theBoxHidesOnceAQuoteExists() {
        var library = Library()
        library.newQuote(on: UIFixture.today)
        let steps = GettingStarted(library: library)
        #expect(steps.isDone(.quote))
        #expect(steps.isShowing == false)
        #expect(steps.first == .business)
    }

    @Test func theSampleBusinessNeedsNoHelp() throws {
        let model = try UIFixture.sampleModel()
        #expect(GettingStarted(library: model.library).isShowing == false)
    }

    // MARK: The buttons

    @Test func theButtonsGoWhereTheyPromise() throws {
        let model = try UIFixture.model()
        GettingStarted.perform(.business, in: model)
        #expect(model.section == .brand)

        GettingStarted.perform(.client, in: model)
        #expect(model.section == .clients)
        #expect(model.library.clients.count == 1)
        #expect(model.selectedClientID == model.library.clients.first?.id)

        GettingStarted.perform(.quote, in: model)
        #expect(model.section == .quotes)
        #expect(model.library.quotes.count == 1)
        #expect(model.openQuoteID == model.library.quotes.first?.id)
        // A quote exists now, so the box is gone.
        #expect(GettingStarted(library: model.library).isShowing == false)
    }

    // MARK: The box on screen

    @Test func theBoxShowsOnANewLibraryAndOnlyThen() throws {
        let fresh = try UIFixture.model()
        let box = size(GettingStartedBox(model: fresh, defaults: defaults()).groupBoxStyle(.win95), width: 778)
        #expect(box.height > 80, "the box is \(box.height) high")

        let sample = try UIFixture.sampleModel()
        let none = size(GettingStartedBox(model: sample, defaults: defaults()).groupBoxStyle(.win95), width: 778)
        #expect(none.height == 0)
    }

    @Test func hideTakesTheBoxAwayAndShowingItAgainBringsItBack() throws {
        let model = try UIFixture.model()
        let store = defaults()
        let shown = size(GettingStartedBox(model: model, defaults: store).groupBoxStyle(.win95), width: 778)
        store.set(true, forKey: StepPreferences.hideGettingStartedKey)
        let hidden = size(GettingStartedBox(model: model, defaults: store).groupBoxStyle(.win95), width: 778)
        #expect(shown.height > 0)
        #expect(hidden.height == 0)
        store.removeObject(forKey: StepPreferences.hideGettingStartedKey)
        #expect(size(GettingStartedBox(model: model, defaults: store).groupBoxStyle(.win95), width: 778).height == shown.height)
    }

    @Test func theSwitchesAreSavedUnderTheirOwnNames() {
        #expect(StepPreferences.showStepsKey == "showSteps")
        #expect(StepPreferences.hideGettingStartedKey == "hideGettingStarted")
        #expect(StepPreferences.showGettingStartedKey == "showGettingStarted")
    }

    // MARK: Help → Show Getting Started

    @Test func theRuleShowsANewLibraryUntilHidden() {
        #expect(GettingStarted.isVisible(hasQuotes: false, hidden: false, shownFromHelp: false))
        #expect(GettingStarted.isVisible(hasQuotes: false, hidden: true, shownFromHelp: false) == false)
    }

    @Test func theRuleHidesTheBoxOnceThereAreQuotes() {
        #expect(GettingStarted.isVisible(hasQuotes: true, hidden: false, shownFromHelp: false) == false)
    }

    @Test func theHelpMenuShowsTheBoxEvenWithQuotes() {
        #expect(GettingStarted.isVisible(hasQuotes: true, hidden: false, shownFromHelp: true))
        #expect(GettingStarted.isVisible(hasQuotes: true, hidden: true, shownFromHelp: true))
    }

    @Test func showGettingStartedSetsTheFlagsAndGoesToTheDashboard() throws {
        let model = try UIFixture.sampleModel()
        let store = defaults()
        store.set(true, forKey: StepPreferences.hideGettingStartedKey)
        model.go(to: .clients)

        GettingStarted.showAgain(in: model, defaults: store)
        #expect(store.bool(forKey: StepPreferences.hideGettingStartedKey) == false)
        #expect(store.bool(forKey: StepPreferences.showGettingStartedKey))
        #expect(model.section == .dashboard)
    }

    @Test func showGettingStartedWaitsWhileAMessageIsShowing() throws {
        let model = try UIFixture.sampleModel()
        let store = defaults()
        var beeps = 0
        model.beep = { beeps += 1 }
        model.go(to: .clients)
        model.show(title: "Careful", text: "Read this first.")

        GettingStarted.showAgain(in: model, defaults: store)
        #expect(beeps == 1)
        #expect(store.bool(forKey: StepPreferences.showGettingStartedKey) == false)
        #expect(model.section == .clients)
    }

    /// The user's report: Hide, then no way back once there are quotes. The Help menu brings the box
    /// back with its three steps ticked as usual, and Hide takes it away again.
    @Test func theBoxComesBackWithQuotesAndHideTakesItAwayAgain() throws {
        let model = try UIFixture.sampleModel()
        let store = defaults()
        GettingStarted.hide(in: store)
        func height() -> CGFloat {
            size(GettingStartedBox(model: model, defaults: store).groupBoxStyle(.win95), width: 778).height
        }
        #expect(height() == 0)

        GettingStarted.showAgain(in: model, defaults: store)
        #expect(height() > 80, "the box is \(height()) high")
        // The steps keep their ticks: the sample library has a quote.
        #expect(GettingStarted(library: model.library).isDone(.quote))

        GettingStarted.hide(in: store)
        #expect(store.bool(forKey: StepPreferences.hideGettingStartedKey))
        #expect(store.bool(forKey: StepPreferences.showGettingStartedKey) == false)
        #expect(height() == 0)
    }

    @Test func theSentenceUnderTheBoxDropsTheStepBarWhenItIsOff() {
        let on = GettingStarted.footnote(stepsShown: true)
        let off = GettingStarted.footnote(stepsShown: false)
        #expect(on == "After that: send the quote, read the client's ticked reply, invoice, and record payments. Each quote shows its next step.")
        #expect(off == "After that: send the quote, read the client's ticked reply, invoice, and record payments.")
    }

    /// The box has to fit the width beside the section tree at the smallest window (778) whole: every
    /// title, sentence and button in it, with nothing cut.
    @Test func theBoxFitsTheSmallestWindowsWidth() throws {
        let model = try UIFixture.model()
        let box = size(GettingStartedBox(model: model, defaults: defaults()).groupBoxStyle(.win95))
        // The Dashboard pads its content by 8 either side.
        #expect(box.width <= 778 - 16, "the box needs \(box.width) pt of \(778 - 16)")
    }

    // MARK: The Dashboard

    @Test func theEmptyDashboardKeepsEveryListUsableInTheSmallestWindow() throws {
        let model = try UIFixture.model()
        // The window is 980 x 620. Its section area is that less the title bar (28), toolbar (66),
        // status bar (26) and the 4-pt padding round the tree and the section (8): 492 high, 778 wide.
        let area = CGSize(width: 778, height: 620 - 28 - 66 - 26 - 8)
        let needed = size(DashboardView(model: model), width: area.width)
        #expect(needed.height <= area.height, "the Dashboard needs \(needed.height) of \(area.height)")
        // And the lists get a usable height of their own, not whatever is left over.
        #expect(DashboardView.listMinHeight >= 80)
    }

    @Test func theListsFollowTheOrderTheWorkHappens() {
        #expect(DashboardView.listTitles == ["Quotes waiting on a reply", "Still to invoice", "Waiting to be paid"])
        #expect(DashboardView.listTitles.allSatisfy { $0.first?.isNumber == false })
    }
}
