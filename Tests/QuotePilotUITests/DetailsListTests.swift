import AppKit
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

private let october15 = Day(year: 2026, month: 10, day: 15)

struct SampleRow: Identifiable {
    var id: Int
    var name: String
    var total: Money = .zero
    var day: Day = october15
}

/// The colour of the pixel under a point of a snapshot, whatever the snapshot's scale.
private func colour(_ rep: NSBitmapImageRep, _ size: CGSize, x: CGFloat, y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let scale = CGFloat(rep.pixelsWide) / size.width
    let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) ?? .magenta
    return (c.redComponent, c.greenComponent, c.blueComponent)
}

private func isLight(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { c.r > 0.85 && c.g > 0.85 && c.b > 0.85 }
private func isBlack(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { c.r < 0.15 && c.g < 0.15 && c.b < 0.15 }
/// Win95's navy #000080 as the off-screen window draws it (it comes out near #002085).
private func isNavy(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { c.r < 0.1 && c.g < 0.2 && c.b > 0.4 && c.b < 0.6 }

@MainActor
@Suite struct DetailsListTests {
    @Test func flexibleColumnsShareTheRoomAndKeepTheirMinimum() {
        #expect(DetailsLayout.widths([.fixed(100), .flexible(min: 50), .flexible(min: 50)], total: 400) == [100, 150, 150])
        #expect(DetailsLayout.widths([.fixed(300), .flexible(min: 80)], total: 320) == [300, 80])
    }

    @Test func moneySortsByValueNotByText() {
        let rows = [SampleRow(id: 1, name: "a", total: Money(dollars: 900)),
                    SampleRow(id: 2, name: "b", total: Money(dollars: 1000))]
        let column = DetailsColumn<SampleRow>.money("Total") { $0.total }
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: true).map(\.id) == [1, 2])
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: false).map(\.id) == [2, 1])
    }

    @Test func textSortIgnoresCaseAndPutsNumbersInOrder() {
        let rows = ["Q-0010", "q-0009", "Banana", "apple"].enumerated().map { SampleRow(id: $0.offset, name: $0.element) }
        let column = DetailsColumn<SampleRow>.text("Name", width: .flexible(min: 50)) { $0.name }
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: true).map(\.name) == ["apple", "Banana", "q-0009", "Q-0010"])
    }

    @Test func daysSortByDate() {
        let rows = [SampleRow(id: 1, name: "late", day: Day(year: 2026, month: 12, day: 1)),
                    SampleRow(id: 2, name: "early", day: Day(year: 2026, month: 2, day: 9))]
        let column = DetailsColumn<SampleRow>.day("Issued") { $0.day }
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: true).map(\.id) == [2, 1])
    }

    @Test func equalRowsKeepTheirOrder() {
        let rows = (0..<5).map { SampleRow(id: $0, name: "Same") }
        let column = DetailsColumn<SampleRow>.text("Name", width: .flexible(min: 50)) { $0.name }
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: false).map(\.id) == [0, 1, 2, 3, 4])
    }

    @Test func longTextTruncatesInsteadOfWidening() {
        let long = String(repeating: "Very Long Client Name Pty Ltd ", count: 40)
        let columns: [DetailsColumn<SampleRow>] = [
            .text("Client", width: .flexible(min: 120)) { $0.name },
            .money("Total") { $0.total },
        ]
        let widths = DetailsLayout.widths(columns.map(\.width), total: 400)
        #expect(widths == [290, 110])
        let row = DetailsRowView(row: SampleRow(id: 1, name: long, total: Money(dollars: 5)), columns: columns,
                                 widths: widths, selected: false, showsFocus: false)
        let size = NSHostingView(rootView: row).fittingSize
        #expect(size.height == DetailsLayout.rowHeight)
        #expect(size.width <= 400)
    }

    @Test func theListDraws() {
        let rows = [SampleRow(id: 1, name: "Sample Client Pty Ltd", total: Money(dollars: 1935)),
                    SampleRow(id: 2, name: "Example Bakery", total: Money(dollars: 620)),
                    SampleRow(id: 3, name: String(repeating: "A very long client name ", count: 6), total: Money(dollars: 195))]
        let list = DetailsList(rows, id: \.id, columns: [
            .text("Client", width: .flexible(min: 120)) { $0.name },
            .day("Issued") { $0.day },
            .money("Total") { $0.total },
        ], selection: .constant(2), sort: DetailsSort(column: 2, ascending: false), emptyText: "Nothing here.")
        let rep = Snapshot.render(list.padding(8).background(Win95.face), size: CGSize(width: 520, height: 160), name: "details-list")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func columnsGiveWayToAClassicScroller() {
        #expect(DetailsLayout.columnsWidth(total: 500, legacyScroller: 0) == 500)
        #expect(DetailsLayout.columnsWidth(total: 500, legacyScroller: 15) == 485)
        #expect(DetailsLayout.columnsWidth(total: 10, legacyScroller: 15) == 0)
        // The flexible column takes up what the scroller leaves, so header and rows still line up.
        let room = DetailsLayout.columnsWidth(total: 500, legacyScroller: 15)
        #expect(DetailsLayout.widths([.flexible(min: 120), .fixed(100), .fixed(110)], total: room) == [275, 100, 110])
        // The real reading: nothing with floating scrollers, a positive width with classic ones.
        #expect((DetailsLayout.legacyScrollerWidth > 0) == (NSScroller.preferredScrollerStyle == .legacy))
    }

    @Test func aSelectionThatIsGoneIsNotVisible() {
        let rows = [SampleRow(id: 1, name: "a"), SampleRow(id: 2, name: "b")]
        #expect(DetailsLayout.visibleSelection(2, in: rows, id: \.id) == 2)
        #expect(DetailsLayout.visibleSelection(9, in: rows, id: \.id) == nil)
        #expect(DetailsLayout.visibleSelection(nil, in: rows, id: \.id) == nil)
    }

    @Test func theFocusRectangleOnASelectedRowIsWhiteOnNavy() throws {
        let columns: [DetailsColumn<SampleRow>] = [.text("Client", width: .fixed(120)) { $0.name },
                                                    .text("Other", width: .fixed(80)) { $0.name }]
        let size = CGSize(width: 200, height: 20)
        let row = DetailsRowView(row: SampleRow(id: 1, name: "x"), columns: columns, widths: [120, 80],
                                 selected: true, showsFocus: true)
        let rep = try #require(Snapshot.render(row, size: size, name: "details-row-focus"))
        // Dots sit on every other point of the edge, starting at the corner: white on the navy row.
        #expect(isLight(colour(rep, size, x: 2, y: 0)))
        #expect(isLight(colour(rep, size, x: 2, y: 19)))
        #expect(isLight(colour(rep, size, x: 0, y: 2)))
        #expect(isLight(colour(rep, size, x: 199, y: 2)))
        // Between the dots the navy shows through.
        #expect(isNavy(colour(rep, size, x: 1, y: 0)))
        #expect(isNavy(colour(rep, size, x: 3, y: 19)))
        #expect(isNavy(colour(rep, size, x: 0, y: 3)))
    }

    @Test func aFocusedListWithNothingSelectedDrawsTheRectangleAroundItself() throws {
        let rows = [SampleRow(id: 1, name: "Sample Client Pty Ltd")]
        let columns: [DetailsColumn<SampleRow>] = [.text("Client", width: .flexible(min: 120)) { $0.name }]
        let size = CGSize(width: 300, height: 120)

        func render(selection: Int?, focused: Bool, name: String) throws -> NSBitmapImageRep {
            var list = DetailsList(rows, id: \.id, columns: columns, selection: .constant(selection), emptyText: "None")
            list.forcedFocus = focused
            return try #require(Snapshot.render(list.background(Win95.face), size: size, name: name))
        }

        // The rectangle is inset 3 from the edge, so its left edge is dots on x = 3 at every other point.
        let focused = try render(selection: nil, focused: true, name: "details-list-focus")
        #expect(isBlack(colour(focused, size, x: 3, y: 63)))
        #expect(isLight(colour(focused, size, x: 3, y: 62)))
        // A selection that is not among the rows counts as no selection.
        let stale = try render(selection: 99, focused: true, name: "details-list-focus-stale")
        #expect(isBlack(colour(stale, size, x: 3, y: 63)))
        // Without focus, or with the focus on a visible selected row, nothing goes round the list.
        let idle = try render(selection: nil, focused: false, name: "details-list-idle")
        #expect(isLight(colour(idle, size, x: 3, y: 63)))
        let onRow = try render(selection: 1, focused: true, name: "details-list-focus-row")
        #expect(isLight(colour(onRow, size, x: 3, y: 63)))
    }

    /// A row wider than the room it's given starts at the left edge and is cut on the right, as in
    /// Windows 95; it never centres and loses its first column.
    @Test func anOverWideRowIsCutOnTheRight() throws {
        let columns: [DetailsColumn<SampleRow>] = [.text("Client", width: .fixed(120)) { $0.name },
                                                    .text("Other", width: .fixed(300)) { $0.name }]
        let size = CGSize(width: 200, height: 20)
        let row = DetailsRowView(row: SampleRow(id: 1, name: "x"), columns: columns, widths: [120, 300],
                                 selected: true, showsFocus: true)
        let rep = try #require(Snapshot.render(row, size: size, name: "details-row-overwide"))
        // The focus rectangle's left edge (white dots every other point from y = 2) is at x = 0.
        #expect(isLight(colour(rep, size, x: 0, y: 2)))
        #expect(isLight(colour(rep, size, x: 0, y: 4)))
        #expect(isNavy(colour(rep, size, x: 0, y: 3)))
    }

    /// The same for a whole list: header and rows start just inside its border and line up.
    @Test func anOverWideListIsCutOnTheRight() throws {
        let rows = [SampleRow(id: 1, name: "Sample Client Pty Ltd")]
        let columns: [DetailsColumn<SampleRow>] = [.text("Client", width: .fixed(200)) { $0.name },
                                                    .text("Other", width: .fixed(200)) { $0.name }]
        let size = CGSize(width: 240, height: 80)
        var list = DetailsList(rows, id: \.id, columns: columns, selection: .constant(1), emptyText: "None")
        list.forcedFocus = true
        let rep = try #require(Snapshot.render(list.background(Win95.face), size: size, name: "details-list-overwide"))
        // The first header button's white left edge, just inside the list's border.
        #expect(isLight(colour(rep, size, x: 2, y: 10)))
        // The selected row under it: navy, with the focus rectangle's white dots down its left edge.
        #expect(isNavy(colour(rep, size, x: 3, y: 25)))
        #expect(isLight(colour(rep, size, x: 2, y: 24)))
    }

    @Test func anEmptyListSaysSo() {
        let list = DetailsList([SampleRow](), id: \.id, columns: [.text("Client", width: .flexible(min: 120)) { $0.name }],
                               selection: .constant(nil), emptyText: "No quotes yet. Press New Quote to write one.")
        let rep = Snapshot.render(list.padding(8).background(Win95.face), size: CGSize(width: 520, height: 160), name: "details-list-empty")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
