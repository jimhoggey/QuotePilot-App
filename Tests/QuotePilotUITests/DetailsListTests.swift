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

    @Test func anEmptyListSaysSo() {
        let list = DetailsList([SampleRow](), id: \.id, columns: [.text("Client", width: .flexible(min: 120)) { $0.name }],
                               selection: .constant(nil), emptyText: "No quotes yet. Press New Quote to write one.")
        let rep = Snapshot.render(list.padding(8).background(Win95.face), size: CGSize(width: 520, height: 160), name: "details-list-empty")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
