import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The real window's own title bar gives way to the drawn Windows 95 one. Test windows are never
/// shown, so these check what is set on them and what is drawn, not what the screen shows.
@MainActor
@Suite struct WindowChromeTests {
    /// A window as AppKit makes an ordinary one: a title bar with text, content below it, and (as
    /// SwiftUI's hidden-title-bar windows are) movable by any background.
    func ordinaryWindow(size: CGSize = CGSize(width: 600, height: 400)) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        return window
    }

    func expectSetUp(_ window: NSWindow, title: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(window.titlebarAppearsTransparent, sourceLocation: sourceLocation)
        #expect(window.titleVisibility == .hidden, sourceLocation: sourceLocation)
        #expect(window.titlebarSeparatorStyle == .none, sourceLocation: sourceLocation)
        #expect(window.styleMask.contains(.fullSizeContentView), sourceLocation: sourceLocation)
        #expect(!window.isMovableByWindowBackground, sourceLocation: sourceLocation)
        #expect(window.title == title, sourceLocation: sourceLocation)
        // It is still an ordinary window with its buttons.
        #expect(window.styleMask.isSuperset(of: [.titled, .closable, .miniaturizable, .resizable]),
                sourceLocation: sourceLocation)
    }

    // MARK: The accessor

    @Test func configuringAWindowHidesItsTitleBarAndKeepsItsTitle() {
        let window = ordinaryWindow()
        #expect(!window.titlebarAppearsTransparent)
        #expect(!window.styleMask.contains(.fullSizeContentView))
        WindowAccessor.configure(window, title: "Quote Pilot - Quotes")
        expectSetUp(window, title: "Quote Pilot - Quotes")
    }

    @Test func configuringAgainIsHarmlessAndTakesANewTitle() {
        let window = ordinaryWindow()
        WindowAccessor.configure(window, title: "Quote Pilot - Quotes")
        WindowAccessor.configure(window, title: "Quote Pilot - Quotes")
        expectSetUp(window, title: "Quote Pilot - Quotes")
        WindowAccessor.configure(window, title: "Quote Pilot - Invoices")
        expectSetUp(window, title: "Quote Pilot - Invoices")
    }

    @Test func aStyleSomethingElsePutBackIsPutRight() {
        let window = ordinaryWindow()
        WindowAccessor.configure(window, title: "Quote Pilot")
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = false
        WindowAccessor.configure(window, title: "Quote Pilot")
        expectSetUp(window, title: "Quote Pilot")
    }

    /// Put in the background of a view, it finds the window by itself when the view joins it.
    @Test func theAccessorFindsTheWindowItsViewIsPutIn() {
        let window = ordinaryWindow()
        let host = NSHostingView(rootView: Color.clear.background(WindowAccessor(title: "Found It")))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        expectSetUp(window, title: "Found It")
    }

    @Test func theAccessorIsNotInTheWayOfAClick() {
        let view = WindowAccessor.AccessorView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(view.hitTest(CGPoint(x: 50, y: 50)) == nil)
    }

    // MARK: The root view

    @Test func theRootViewSetsUpItsWindowAndNamesItAfterTheSection() throws {
        let model = try UIFixture.sampleModel()
        let window = ordinaryWindow(size: CGSize(width: 1240, height: 800))
        let host = NSHostingView(rootView: RootView(model: model))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        expectSetUp(window, title: "Quote Pilot - \(model.section.title)")
    }

    @Test func theRootViewKeepsTheWindowTitleWithTheSection() throws {
        let model = try UIFixture.sampleModel()
        let window = ordinaryWindow(size: CGSize(width: 1240, height: 800))
        let host = NSHostingView(rootView: RootView(model: model))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        model.go(to: .invoices)
        host.layoutSubtreeIfNeeded()
        host.rootView = RootView(model: model)
        host.layoutSubtreeIfNeeded()
        expectSetUp(window, title: "Quote Pilot - Invoices")
    }

    @Test func theUnreadableLibraryScreenIsJustCalledQuotePilot() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        let window = ordinaryWindow(size: CGSize(width: 1240, height: 800))
        let host = NSHostingView(rootView: RootView(model: model))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        expectSetUp(window, title: "Quote Pilot")
    }

    // MARK: The drawn bar reaches the top

    /// The root view drawn the way the real window holds it: in a window whose content runs under a
    /// transparent title bar, so the hosting view has the title bar's height as a safe-area inset at
    /// the top. (The off-screen windows of `Snapshot` have none, which is why they never showed this.)
    /// Row 0 of the bitmap is the top edge of the window.
    func renderedUnderATitleBar(_ model: AppModel) throws -> NSBitmapImageRep {
        let size = CGSize(width: 1240, height: 800)
        let window = ordinaryWindow(size: size)
        WindowAccessor.configure(window, title: "Quote Pilot")
        let host = NSHostingView(rootView: RootView(model: model)
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .key)
            .environment(\.displayScale, 1))
        window.contentView = host
        window.setContentSize(size)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // The point of these tests: there is a title-bar inset to push the content down, or to grow
        // a background up through.
        try #require(host.safeAreaInsets.top > 0, "this window has no title bar inset to test against")
        return try #require(Snapshot.capture(host))
    }

    /// Navy by its look rather than its exact numbers: the off-screen bitmap isn't colour managed, so
    /// #000080 reads back as roughly (0, 32, 133), the window's #C0C0C0 as (197, 197, 197) and the
    /// desktop's teal #008080 as roughly (0, 128, 128).
    func isNavy(_ rep: NSBitmapImageRep, y: Int, x: Int = 900) -> Bool {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        return color.redComponent < 0.15 && color.greenComponent < 0.25 && color.blueComponent > 0.35
    }

    /// The navy bar runs from the first row to its 28th, under the window buttons, and what follows is
    /// not navy: the content isn't pushed down by the title bar's inset, and nothing below it (the
    /// toolbar's grey background grows up through that inset) is drawn over it.
    @Test func theDrawnTitleBarFillsTheTopOfTheWindow() throws {
        let rep = try renderedUnderATitleBar(try UIFixture.sampleModel())
        for y in [0, 1, 6, 14, 22, 27] {
            #expect(isNavy(rep, y: y), "row \(y) is not navy")
        }
        for y in [28, 29, 40, 60, 90] {
            #expect(!isNavy(rep, y: y), "row \(y) is navy")
        }
    }

    @Test func theUnreadableLibraryScreenHasTheSameBar() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let rep = try renderedUnderATitleBar(try UIFixture.model(folder: folder))
        for y in [0, 1, 14, 27] {
            #expect(isNavy(rep, y: y), "row \(y) is not navy")
        }
        #expect(!isNavy(rep, y: 29))
    }

    /// With a message box up, the bar is still there.
    @Test func aMessageBoxLeavesTheBarInPlace() throws {
        let model = try UIFixture.model()
        model.confirm(title: "Delete Draft", text: "Delete draft quote Q-0001? Its number won't be used again.",
                      confirm: "Delete") {}
        let rep = try renderedUnderATitleBar(model)
        for y in [0, 14, 27] {
            #expect(isNavy(rep, y: y), "row \(y) is not navy")
        }
    }
}
