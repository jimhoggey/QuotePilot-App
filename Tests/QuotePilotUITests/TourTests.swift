import Foundation
import QuotePilotCore
import SwiftUI
import Testing
@testable import QuotePilotUI

@MainActor
@Suite struct TourTests {
    /// The sample library with Take the Tour pressed on the Invoices screen.
    func touring() throws -> AppModel {
        let model = try UIFixture.sampleModel()
        model.go(to: .invoices)
        model.takeTour()
        return model
    }

    func libraryJSON(_ model: AppModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(model.library)
    }

    @Test func theStartUpPlaysThenStep1OnTheDashboard() throws {
        let model = try touring()
        #expect(model.section == .dashboard)
        #expect(model.tourIsStarting && model.tour == nil)
        model.startupFinished()
        #expect(!model.tourIsStarting)
        #expect(model.tour?.count == "1 of 5")
        model.startupFinished()
        #expect(model.tour?.count == "1 of 5", "a second finish changes nothing")
    }

    /// Next clicks each step's section for them, then moves on; the library is untouched throughout.
    @Test func nextWalksAllFiveStepsAndChangesNothing() throws {
        let model = try touring()
        let before = try libraryJSON(model)
        model.startupFinished()
        var seen: [String] = []
        var presses = 0
        while let tour = model.tour, presses < 20 {
            seen.append("\(tour.count) \(model.section.title)")
            model.tourNext()
            presses += 1
        }
        #expect(seen == ["1 of 5 Dashboard", "2 of 5 Dashboard", "2 of 5 Quotes", "3 of 5 Quotes",
                         "4 of 5 Quotes", "4 of 5 Invoices", "5 of 5 Invoices", "5 of 5 Brand"])
        #expect(model.tour == nil)
        #expect(try libraryJSON(model) == before)
    }

    /// Away from its section a step asks for the click; clicking the tree shows the step itself.
    @Test func aStepAsksForItsSectionFirst() throws {
        let model = try touring()
        model.startupFinished()
        model.tourNext()
        let tour = try #require(model.tour)
        let prompt = tour.shown(in: model.section)
        #expect(prompt.text == "Click Quotes on the left.")
        #expect(prompt.target == .section(.quotes) && prompt.placement == .beside)
        model.go(to: .quotes)
        #expect(tour.shown(in: model.section).target == .newQuote)
        #expect(tour.nextTitle(in: model.section) == "Next >")
    }

    @Test func theLastStepFinishes() {
        var tour: Tour? = Tour()
        while tour?.isLast == false { tour = tour?.advanced() }
        #expect(tour?.nextTitle(in: .brand) == "Finish")
        #expect(tour?.nextTitle(in: .dashboard) == "Next >")
        #expect(tour?.advanced() == nil)
    }

    @Test func endTourStopsItAnywhere() throws {
        let model = try touring()
        model.endTour()
        #expect(!model.tourIsStarting && model.tour == nil)
        model.startupFinished()
        #expect(model.tour == nil, "a late end of the animation doesn't bring it back")
    }

    /// The Pilot and balloon stay inside the window whatever they point at.
    @Test func thePairStaysInTheWindow() {
        let window = CGSize(width: 980, height: 620)
        let half = Tour.pairWidth / 2
        let beside = Tour.pairCenter(around: CGRect(x: 56, y: 147, width: 54, height: 22), placement: .beside, in: window)
        #expect(beside.center.x == 110 + Tour.margin + half && beside.center.y == 158 && beside.pilotLeads)
        let corner = Tour.pairCenter(around: CGRect(x: 900, y: 600, width: 60, height: 20), placement: .below, in: window)
        #expect(corner.center.x == 980 - Tour.margin - half)
        #expect(corner.center.y == 620 - Tour.margin - Tour.balloonHeight / 2)
        let nothing = Tour.pairCenter(around: nil, placement: .below, in: window)
        #expect(nothing.center == CGPoint(x: 490, y: 310) && !nothing.pilotLeads)
    }

    /// Each step in place, at the largest and smallest window, for people to look at (QP_SNAPSHOTS).
    @Test func everyStepDraws() throws {
        let model = try touring()
        model.startupFinished()
        for size in [CGSize(width: 1240, height: 760), CGSize(width: 980, height: 620)] {
            model.endTour()
            model.takeTour()
            model.startupFinished()
            while let tour = model.tour {
                if model.section == tour.step.section {
                    let name = "tour-\(tour.index + 1)-\(Int(size.width))"
                    let rep = Snapshot.render(RootView(model: model), size: size, name: name)
                    #expect(rep.map(Snapshot.hasContent) == true, "\(name)")
                }
                model.tourNext()
            }
        }
        // The prompt to click a section, too.
        model.takeTour()
        model.startupFinished()
        model.tourNext()
        _ = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 760), name: "tour-prompt")
    }

    /// With the library unreadable there's nothing to tour: no welcome, no button, no tour.
    @Test func anUnreadableLibraryOffersNoTour() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        #expect(!model.libraryIsOpen)
        let settings = MemoryUpdateSettings()
        settings.lastSeenVersion = nil
        model.updates = UpdateFixture.services(version: "1.6.1", settings: settings)
        model.showWhatsNewOnce(justUpdated: false)
        #expect(model.message == nil)
        model.showWhatsNew()
        #expect(model.message?.choices.map(\.title) == ["OK"])
        model.message = nil
        model.takeTour()
        #expect(!model.tourIsStarting && model.tour == nil)
    }

    @Test func helpOffersTheTour() throws {
        let model = try touring()
        model.endTour()
        model.go(to: .clients)
        model.takeTour()
        #expect(model.section == .dashboard && model.tourIsStarting)
    }
}
