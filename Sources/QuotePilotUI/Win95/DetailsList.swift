import AppKit
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

    /// The room the columns get: what is inside the list, less the strip a classic always-visible
    /// scroller takes from the rows (0 when scrollers float over the content).
    public static func columnsWidth(total: CGFloat, legacyScroller: CGFloat) -> CGFloat {
        max(0, total - legacyScroller)
    }

    /// How wide a classic scroller is (17 points), whatever the Mac is set to now: what a layout that
    /// must fit either way reserves.
    static var classicScrollerWidth: CGFloat {
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    /// How wide the scroller is right now: 0 unless the Mac is set to always show scroll bars
    /// (or a mouse is attached), which makes them classic scrollers beside the rows.
    static var legacyScrollerWidth: CGFloat {
        guard NSScroller.preferredScrollerStyle == .legacy else { return 0 }
        return classicScrollerWidth
    }

    /// The selection, but only when it is one of these rows (it may have been deleted or filtered out).
    static func visibleSelection<Row, ID: Hashable>(_ selection: ID?, in rows: [Row], id: KeyPath<Row, ID>) -> ID? {
        guard let selection, rows.contains(where: { $0[keyPath: id] == selection }) else { return nil }
        return selection
    }

    /// The rows chosen after a click on `row`, as in Windows: ⇧ takes every row from `anchor` to it,
    /// ⌘ adds or removes it, and a plain click chooses it alone.
    static func chosen<ID: Hashable>(clicking row: ID, in ids: [ID], chosen: Set<ID>, anchor: ID?,
                                     modifiers: NSEvent.ModifierFlags) -> Set<ID> {
        if modifiers.contains(.shift), let anchor, let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: row) {
            return Set(ids[min(from, to)...max(from, to)])
        }
        return modifiers.contains(.command) ? chosen.symmetricDifference([row]) : [row]
    }

    /// Where the selection goes once a click on `row` has made `chosen` the chosen rows: to the row,
    /// except that ⇧-click keeps it on the anchor, and a ⌘-click that takes the row out leaves it on a
    /// row still chosen (the anchor while it is, else the first), or on none when none is left. So the
    /// selection is always a chosen row, and a selection made anywhere else can choose its row.
    static func selection<ID: Hashable>(clicking row: ID, in ids: [ID], chosen: Set<ID>, anchor: ID?,
                                        modifiers: NSEvent.ModifierFlags) -> ID? {
        if modifiers.contains(.shift), let anchor { return anchor }
        if chosen.contains(row) { return row }
        if let anchor, chosen.contains(anchor) { return anchor }
        return ids.first(where: chosen.contains)
    }

    /// The rows a right-click menu acts on: the chosen ones still listed, or the row clicked alone when
    /// it isn't one of them. The menu is built before the click chooses its row, so this says what
    /// the click will make it.
    static func menuRows<ID: Hashable>(_ id: ID, chosen: Set<ID>, listed: [ID]) -> Set<ID> {
        chosen.contains(id) ? chosen.intersection(listed) : [id]
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
    /// The row the keyboard is on, and the anchor for ⇧-click.
    @Binding var selection: ID?
    /// The rows chosen with ⌘- and ⇧-click, on a list that allows several; nil on one that doesn't.
    let chosen: Binding<Set<ID>>?
    let emptyText: String
    let onOpen: ((ID) -> Void)?
    let rowMenu: ((ID) -> AnyView)?
    @State private var sort: DetailsSort?
    @State private var scrollerReserve: CGFloat = DetailsLayout.legacyScrollerWidth
    @State private var rowHover = RowHoverBox<ID>()
    @FocusState private var focused: Bool
    /// Lets a test draw the list as if it had keyboard focus; a real focus needs a key window.
    var forcedFocus: Bool?

    private var isFocused: Bool { forcedFocus ?? focused }

    public init(_ rows: [Row], id: KeyPath<Row, ID>, columns: [DetailsColumn<Row>], selection: Binding<ID?>,
                chosen: Binding<Set<ID>>? = nil, sort: DetailsSort? = nil, emptyText: String,
                onOpen: ((ID) -> Void)? = nil, rowMenu: ((ID) -> AnyView)? = nil) {
        self.rows = rows
        self.id = id
        self.columns = columns
        self._selection = selection
        self.chosen = chosen
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
        let ids = ordered.map { $0[keyPath: id] }
        // With nothing selected (or the selection gone), the dotted focus rectangle goes round the list.
        let listShowsFocus = isFocused && DetailsLayout.visibleSelection(selection, in: ordered, id: id) == nil
        // The empty state has no scroller, so it keeps the whole width.
        let reserve = ordered.isEmpty ? 0 : scrollerReserve
        return GeometryReader { geometry in
            let room = DetailsLayout.columnsWidth(total: geometry.size.width - 4, legacyScroller: reserve)
            let widths = DetailsLayout.widths(columns.map(\.width), total: room)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    header(widths)
                    if ordered.isEmpty {
                        emptyState
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(ordered, id: id) { row in
                                    rowView(row, widths: widths, ids: ids)
                                }
                            }
                        }
                        // One watcher for the whole list: a right-click chooses the row under the pointer.
                        .background {
                            if rowMenu != nil {
                                SelectOnRightClick {
                                    guard let target = rowHover.hover.target else { return }
                                    // On a chosen row the rows stay chosen, so its menu acts on all of them.
                                    if chosen?.wrappedValue.contains(target) == false { chosen?.wrappedValue = [target] }
                                    selection = target
                                    focused = true
                                }
                            }
                        }
                    }
                }
                .padding(2)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.upArrow) { step(-1, ids, proxy) }
                .onKeyPress(.downArrow) { step(1, ids, proxy) }
                .onKeyPress(.return) { openSelection(ordered) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
            scrollerReserve = DetailsLayout.legacyScrollerWidth
        }
        // A selection made elsewhere (an invoice opened from the Dashboard, a new one) chooses its row
        // alone, so the row shown chosen is the one in the preview.
        .onChange(of: selection, initial: true) { _, new in
            if let chosen, let new, !chosen.wrappedValue.contains(new) { chosen.wrappedValue = [new] }
        }
        .background(Win95.field)
        .overlay(Bevel(.sunken))
        .overlay(listShowsFocus ? FocusRect().padding(3) : nil)
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
        // Pinned to the left: columns too wide for the list are cut on the right, never centred.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowView(_ row: Row, widths: [CGFloat], ids: [ID]) -> some View {
        let rowID = row[keyPath: id]
        let selected = chosen?.wrappedValue.contains(rowID) ?? (rowID == selection)
        let base = DetailsRowView(row: row, columns: columns, widths: widths, selected: selected,
                                  showsFocus: rowID == selection && isFocused)
            .id(rowID)
            .onTapGesture(count: 2) {
                click(rowID, in: ids, modifiers: [])
                onOpen?(rowID)
            }
            .simultaneousGesture(TapGesture().onEnded {
                click(rowID, in: ids, modifiers: NSEvent.modifierFlags)
                focused = true
            })
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Open") { onOpen?(rowID) }
        if let rowMenu {
            // A right-click chooses the row first (the list's watcher, from this hover), then its menu opens.
            base
                .onHover { inside in rowHover.hover.moved(rowID, inside: inside) }
                .onDisappear { rowHover.hover.moved(rowID, inside: false) }
                .contextMenu { rowMenu(rowID) }
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

    private func step(_ delta: Int, _ ids: [ID], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !ids.isEmpty else { return .ignored }
        let current = selection.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ids.count - 1) } ?? (delta > 0 ? 0 : ids.count - 1)
        click(ids[next], in: ids, modifiers: [])
        proxy.scrollTo(ids[next])
        return .handled
    }

    /// Selects `rowID`, or on a list that allows several, chooses rows and moves the selection as
    /// `DetailsLayout.chosen` and `DetailsLayout.selection` say.
    private func click(_ rowID: ID, in ids: [ID], modifiers: NSEvent.ModifierFlags) {
        guard let chosen else {
            selection = rowID
            return
        }
        // Rows gone from the list (sent, deleted) are neither chosen nor the anchor any more.
        let anchor = selection.flatMap { ids.contains($0) ? $0 : nil }
        let now = DetailsLayout.chosen(clicking: rowID, in: ids, chosen: chosen.wrappedValue.intersection(ids),
                                       anchor: anchor, modifiers: modifiers)
        chosen.wrappedValue = now
        selection = DetailsLayout.selection(clicking: rowID, in: ids, chosen: now, anchor: anchor, modifiers: modifiers)
    }

    private func openSelection(_ ordered: [Row]) -> KeyPress.Result {
        guard let visible = DetailsLayout.visibleSelection(selection, in: ordered, id: id), let onOpen else { return .ignored }
        onOpen(visible)
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
        // White dots: this rectangle always sits on the navy of the selected row.
        .overlay(showsFocus ? FocusRect(color: Win95.highlight) : nil)
        // Exactly the room offered, pinned to the left: a row too wide is cut on the right (the list
        // clips it) instead of growing and being centred, which would cut its first column too.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
