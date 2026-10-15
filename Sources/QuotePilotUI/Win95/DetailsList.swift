import QuotePilotCore
import SwiftUI

/// What a column sorts by: text ignoring case with numbers in order ("Q-0009" before "Q-0010"),
/// whole numbers (money in cents), or days.
public enum SortValue: Comparable {
    case text(String)
    case number(Int)
    case day(Day)

    public static func money(_ amount: Money) -> SortValue { .number(amount.cents) }

    public static func < (a: SortValue, b: SortValue) -> Bool {
        switch (a, b) {
        case (.text(let x), .text(let y)): return x.localizedStandardCompare(y) == .orderedAscending
        case (.number(let x), .number(let y)): return x < y
        case (.day(let x), .day(let y)): return x < y
        default: return a.rank < b.rank
        }
    }

    private var rank: Int {
        switch self {
        case .text: return 0
        case .number: return 1
        case .day: return 2
        }
    }
}

public enum ColumnWidth: Equatable {
    case fixed(CGFloat)
    /// Shares the room the fixed columns leave, never narrower than `min`.
    case flexible(min: CGFloat)
}

public struct DetailsSort: Equatable {
    public var column: Int
    public var ascending: Bool

    public init(column: Int, ascending: Bool = true) {
        self.column = column
        self.ascending = ascending
    }
}

/// One column of a details list: its header, width, alignment, sort value and cell.
public struct DetailsColumn<Row> {
    public var title: String
    public var width: ColumnWidth
    public var alignment: Alignment
    public var sortValue: (Row) -> SortValue
    /// Draws a cell. The flag says whether the row is selected, which means white text on navy.
    public var cell: (Row, Bool) -> AnyView

    public init(_ title: String, width: ColumnWidth, alignment: Alignment = .leading,
                sortValue: @escaping (Row) -> SortValue, cell: @escaping (Row, Bool) -> AnyView) {
        self.title = title
        self.width = width
        self.alignment = alignment
        self.sortValue = sortValue
        self.cell = cell
    }

    /// A plain text column. Monospaced digits keep amounts lined up. Hovering shows the whole text,
    /// for cells cut short.
    public static func text(_ title: String, width: ColumnWidth, alignment: Alignment = .leading,
                            monospaced: Bool = false, sortValue: ((Row) -> SortValue)? = nil,
                            _ text: @escaping (Row) -> String) -> DetailsColumn {
        DetailsColumn(title, width: width, alignment: alignment,
                      sortValue: sortValue ?? { .text(text($0)) },
                      cell: { row, selected in
                          AnyView(Text(text(row))
                              .font(monospaced ? Win95.money : Win95.body)
                              .foregroundStyle(selected ? Win95.highlight : Win95.text)
                              .help(text(row)))
                      })
    }

    /// A right-aligned amount, sorted by value.
    public static func money(_ title: String, width: CGFloat = 110, currencyCode: String = "AUD",
                             _ amount: @escaping (Row) -> Money) -> DetailsColumn {
        .text(title, width: .fixed(width), alignment: .trailing, monospaced: true,
              sortValue: { .money(amount($0)) }, { amount($0).formatted(currencyCode: currencyCode) })
    }

    /// A day such as "15 Oct 2026", sorted by date.
    public static func day(_ title: String, width: CGFloat = 100, _ day: @escaping (Row) -> Day) -> DetailsColumn {
        .text(title, width: .fixed(width), sortValue: { .day(day($0)) }, { day($0).short })
    }
}

public enum DetailsLayout {
    public static let rowHeight: CGFloat = 20
    public static let headerHeight: CGFloat = 20

    /// Fixed columns keep their width; flexible ones share what's left, never below their minimum.
    public static func widths(_ columns: [ColumnWidth], total: CGFloat) -> [CGFloat] {
        var fixed: CGFloat = 0
        var flexibleCount = 0
        for column in columns {
            switch column {
            case .fixed(let width): fixed += width
            case .flexible: flexibleCount += 1
            }
        }
        let share = flexibleCount == 0 ? 0 : max(0, total - fixed) / CGFloat(flexibleCount)
        return columns.map { column in
            switch column {
            case .fixed(let width): return width
            case .flexible(let minimum): return max(minimum, share)
            }
        }
    }

    /// A stable sort: rows that compare equal keep their order.
    public static func sorted<Row>(_ rows: [Row], by value: (Row) -> SortValue, ascending: Bool) -> [Row] {
        rows.enumerated()
            .sorted { a, b in
                let x = value(a.element), y = value(b.element)
                if x < y { return ascending }
                if y < x { return !ascending }
                return a.offset < b.offset
            }
            .map(\.element)
    }
}

/// The Windows 95 "Details view".
public struct DetailsList<Row, ID: Hashable>: View {
    let rows: [Row]
    let id: KeyPath<Row, ID>
    let columns: [DetailsColumn<Row>]
    @Binding var selection: ID?
    let emptyText: String
    let onOpen: ((ID) -> Void)?
    let rowMenu: ((ID) -> AnyView)?
    @State private var sort: DetailsSort?
    @FocusState private var focused: Bool

    public init(_ rows: [Row], id: KeyPath<Row, ID>, columns: [DetailsColumn<Row>], selection: Binding<ID?>,
                sort: DetailsSort? = nil, emptyText: String,
                onOpen: ((ID) -> Void)? = nil, rowMenu: ((ID) -> AnyView)? = nil) {
        self.rows = rows
        self.id = id
        self.columns = columns
        self._selection = selection
        self.emptyText = emptyText
        self.onOpen = onOpen
        self.rowMenu = rowMenu
        self._sort = State(initialValue: sort)
    }

    private var orderedRows: [Row] {
        guard let sort, columns.indices.contains(sort.column) else { return rows }
        return DetailsLayout.sorted(rows, by: columns[sort.column].sortValue, ascending: sort.ascending)
    }

    public var body: some View {
        let ordered = orderedRows
        return GeometryReader { geometry in
            let widths = DetailsLayout.widths(columns.map(\.width), total: geometry.size.width - 4)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    header(widths)
                    if ordered.isEmpty {
                        emptyState
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(ordered, id: id) { row in
                                    rowView(row, widths: widths)
                                }
                            }
                        }
                    }
                }
                .padding(2)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.upArrow) { step(-1, ordered, proxy) }
                .onKeyPress(.downArrow) { step(1, ordered, proxy) }
                .onKeyPress(.return) { openSelection() }
            }
        }
        .background(Win95.field)
        .overlay(Bevel(.sunken))
        .clipped()
    }

    private func header(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { index in
                Button {
                    toggleSort(index)
                } label: {
                    HStack(spacing: 4) {
                        Text(columns[index].title)
                            .font(Win95.body)
                            .foregroundStyle(Win95.text)
                            .lineLimit(1)
                        if let sort, sort.column == index {
                            PixelGlyph(sort.ascending ? PixelGlyph.up : PixelGlyph.down)
                                .frame(width: 7, height: 4)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(width: widths[index], height: DetailsLayout.headerHeight, alignment: columns[index].alignment)
                    .background(Win95.face)
                    .overlay(Bevel(.raised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(headerLabel(index))
            }
            // The empty header to the right of the last column.
            Win95.face
                .frame(height: DetailsLayout.headerHeight)
                .overlay(Bevel(.raised))
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, widths: [CGFloat]) -> some View {
        let rowID = row[keyPath: id]
        let selected = rowID == selection
        let base = DetailsRowView(row: row, columns: columns, widths: widths, selected: selected,
                                  showsFocus: selected && focused)
            .id(rowID)
            .onTapGesture(count: 2) {
                selection = rowID
                onOpen?(rowID)
            }
            .simultaneousGesture(TapGesture().onEnded {
                selection = rowID
                focused = true
            })
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Open") { onOpen?(rowID) }
        if let rowMenu {
            base.contextMenu { rowMenu(rowID) }
        } else {
            base
        }
    }

    private var emptyState: some View {
        Text(emptyText)
            .font(Win95.label)
            .foregroundStyle(Win95.highlight)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Win95.desktop)
    }

    private func toggleSort(_ index: Int) {
        if let current = sort, current.column == index {
            sort = DetailsSort(column: index, ascending: !current.ascending)
        } else {
            sort = DetailsSort(column: index)
        }
    }

    private func headerLabel(_ index: Int) -> String {
        guard let sort, sort.column == index else { return "\(columns[index].title), sort" }
        return "\(columns[index].title), sorted \(sort.ascending ? "ascending" : "descending")"
    }

    private func step(_ delta: Int, _ ordered: [Row], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let ids = ordered.map { $0[keyPath: id] }
        guard !ids.isEmpty else { return .ignored }
        let current = selection.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ids.count - 1) } ?? (delta > 0 ? 0 : ids.count - 1)
        selection = ids[next]
        proxy.scrollTo(ids[next])
        return .handled
    }

    private func openSelection() -> KeyPress.Result {
        guard let selection, let onOpen else { return .ignored }
        onOpen(selection)
        return .handled
    }
}

/// One row: every cell one line high, cut short with "…" rather than wrapping or widening.
struct DetailsRowView<Row>: View {
    let row: Row
    let columns: [DetailsColumn<Row>]
    let widths: [CGFloat]
    let selected: Bool
    let showsFocus: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { index in
                columns[index].cell(row, selected)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .frame(width: widths[index], height: DetailsLayout.rowHeight, alignment: columns[index].alignment)
                    .clipped()
            }
        }
        .background(selected ? Win95.selection : Color.clear)
        .overlay(showsFocus ? FocusRect() : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
