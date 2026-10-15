import Foundation
import QuotePilotCore
import QuotePilotPDF
import SwiftUI

/// The widths of the line table's columns, shared by its heading and every row so they can't drift.
/// They are the ones plan 2a's 980-pt fix settled on: the item column takes whatever is left.
enum LineColumns {
    static let id: CGFloat = 24
    static let quantity: CGFloat = 48
    static let unit: CGFloat = 72
    static let rate: CGFloat = 92
    static let amount: CGFloat = 88
    /// Move up, move down and remove: three 20-point buttons and the gaps between them.
    static let buttons: CGFloat = 3 * 20 + 2 * 4
    /// How far a line's detail field starts from the left: the ID column and the gap after it.
    static let detailIndent: CGFloat = id + 4
}

/// The line table quotes and invoices share. Each line has its wording, quantity, unit, rate and
/// amount, with buttons to move or remove it. Add Line sits below, then the document's own totals.
struct LinesEditor<Footer: View>: View {
    let model: AppModel
    @Binding var lines: [LineItem]
    /// Quotes show each line's ID; invoices don't.
    let showCodes: Bool
    /// Accepted quotes show what the client decided for each line.
    let showDecision: Bool
    /// Sent invoices show their lines without fields or buttons.
    let editable: Bool
    let onAdd: () -> Void
    let footer: Footer

    init(model: AppModel, lines: Binding<[LineItem]>, showCodes: Bool = true, showDecision: Bool = false,
         editable: Bool = true, onAdd: @escaping () -> Void, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self._lines = lines
        self.showCodes = showCodes
        self.showDecision = showDecision
        self.editable = editable
        self.onAdd = onAdd
        self.footer = footer()
    }

    var body: some View {
        let currency = model.currencyCode
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if showCodes { columnHead("ID", width: LineColumns.id) }
                columnHead("Item", width: nil)
                columnHead("Qty", width: LineColumns.quantity)
                columnHead("Unit", width: LineColumns.unit)
                columnHead("Rate", width: LineColumns.rate)
                columnHead("Amount", width: LineColumns.amount, trailing: true)
                if editable { Spacer().frame(width: LineColumns.buttons) }
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                LineRow(line: lineBinding(line.id), currency: currency, showCode: showCodes,
                        showDecision: showDecision, editable: editable,
                        canMoveUp: index > 0, canMoveDown: index < lines.count - 1,
                        move: { move(line.id, by: $0) }, remove: { remove(line) })
            }
            if lines.isEmpty {
                // A quote's lines are what the client ticks; an invoice's are just what is billed.
                Text(showCodes ? "No lines yet. Add one for each piece of work the client can tick." : "No lines yet.")
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
            }
            HStack(alignment: .top) {
                if editable {
                    Button("Add Line", action: onAdd)
                        .buttonStyle(.win95)
                }
                Spacer()
                footer
            }
            .padding(.top, 4)
        }
        .disabled(!editable)
    }

    private func columnHead(_ title: String, width: CGFloat?, trailing: Bool = false) -> some View {
        Text(title)
            .font(Win95.label)
            .foregroundStyle(Win95.text)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    /// A line found by its identity, so a removed or moved line can never index past the end.
    private func lineBinding(_ id: UUID) -> Binding<LineItem> {
        Binding(
            get: { lines.first { $0.id == id } ?? LineItem(id: id, title: "", rate: .zero) },
            set: { line in
                var edited = lines
                guard let index = edited.firstIndex(where: { $0.id == id }) else { return }
                edited[index] = line
                lines = edited
            })
    }

    private func move(_ id: UUID, by offset: Int) {
        var edited = lines
        guard let index = edited.firstIndex(where: { $0.id == id }), edited.indices.contains(index + offset) else { return }
        edited.swapAt(index, index + offset)
        lines = edited
    }

    /// How the Remove Line question names a line: "line 02, Design", with a long title cut at 60
    /// characters so the message box stays a message box. A document that shows no IDs (an invoice)
    /// names the line by its wording alone, as that is all the person sees.
    static func lineName(_ line: LineItem, showCode: Bool = true) -> String {
        let title = line.title.count > 60 ? String(line.title.prefix(60)) + "…" : line.title
        let code = showCode ? line.code : ""
        switch (code.isEmpty, title.isEmpty) {
        case (false, false): return "line \(code), \(title)"
        case (false, true): return "line \(code)"
        case (true, false): return "\"\(title)\""
        case (true, true): return "this line"
        }
    }

    /// Whether a line has anything in it worth a question before it goes: some wording, a detail or a
    /// price. A line still blank from Add Line just goes.
    static func hasContent(_ line: LineItem) -> Bool {
        let blank = CharacterSet.whitespacesAndNewlines
        return !line.title.trimmingCharacters(in: blank).isEmpty
            || !line.detail.trimmingCharacters(in: blank).isEmpty
            || line.rate != .zero
    }

    /// Removes the line at once when it is empty, and asks first when it isn't.
    func remove(_ line: LineItem) {
        guard Self.hasContent(line) else { return removeNow(line) }
        model.confirm(title: "Remove Line", text: "Remove \(Self.lineName(line, showCode: showCodes))?", confirm: "Remove") {
            removeNow(line)
        }
    }

    private func removeNow(_ line: LineItem) {
        var edited = lines
        edited.removeAll { $0.id == line.id }
        lines = edited
    }
}

/// A document's totals exactly as its PDF prints them.
struct DocumentTotals: View {
    let totals: [DocumentContent.TotalLine]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
            ForEach(Array(totals.enumerated()), id: \.offset) { _, line in
                GridRow {
                    Text(line.label)
                        .font(line.strong ? Win95.label : Win95.body)
                    Text(line.value)
                        .font(line.strong ? Win95.money.bold() : Win95.money)
                }
            }
        }
        .foregroundStyle(Win95.text)
    }
}

struct LineRow: View {
    @Binding var line: LineItem
    let currency: String
    /// Quotes show the line's ID in the first column; invoices don't.
    let showCode: Bool
    let showDecision: Bool
    /// Without this the row shows its text and amounts only, with no buttons.
    let editable: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if showCode {
                    Text(line.code)
                        .font(Win95.money)
                        .foregroundStyle(Win95.text)
                        .frame(width: LineColumns.id, alignment: .leading)
                }
                Win95TextField("Line \(line.code) item", text: $line.title, prompt: "What the work is")
                CommitField(label: "Line \(line.code) quantity", value: line.quantity,
                            format: FieldParser.quantityText, parse: FieldParser.quantity) { line.quantity = $0 }
                    .frame(width: LineColumns.quantity)
                Picker("Line \(line.code) unit", selection: $line.unit) {
                    ForEach(QuotePilotCore.Unit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: LineColumns.unit)
                CommitField(label: "Line \(line.code) rate", value: line.rate,
                            format: { $0.formatted(currencyCode: currency) }, parse: FieldParser.money) { line.rate = $0 }
                    .frame(width: LineColumns.rate)
                Text(line.amount.formatted(currencyCode: currency))
                    .font(Win95.money)
                    .foregroundStyle(Win95.text)
                    .lineLimit(1)
                    .frame(width: LineColumns.amount, alignment: .trailing)
                if editable {
                    SquareButton(PixelGlyph.up, label: "Move line \(line.code) up") { move(-1) }
                        .disabled(!canMoveUp)
                    SquareButton(PixelGlyph.down, label: "Move line \(line.code) down") { move(1) }
                        .disabled(!canMoveDown)
                    SquareButton(PixelGlyph.cross, label: "Remove line \(line.code)", action: remove)
                }
            }
            HStack(spacing: 4) {
                Spacer().frame(width: showCode ? LineColumns.detailIndent : 0)
                Win95TextField("Line \(line.code) detail", text: $line.detail, prompt: "Detail (optional)")
                if showDecision, let decision = line.decision {
                    StatusLabel(decision == .accepted ? .tick : .cross, decision == .accepted ? "Accepted" : "Declined")
                        .frame(width: 110, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// A small square Windows 95 button showing a glyph, for line actions.
struct SquareButton: View {
    let glyph: [String]
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ glyph: [String], label: String, action: @escaping () -> Void) {
        self.glyph = glyph
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PixelGlyph(glyph, color: isEnabled ? Win95.dark : Win95.shadow)
                .frame(width: 7, height: CGFloat(glyph.count))
        }
        .buttonStyle(SquareButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

struct SquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .frame(width: 20, height: 20)
            .background(Win95.face)
            .overlay(Bevel(configuration.isPressed ? .pressed : .raised))
            .contentShape(Rectangle())
    }
}
