import AppKit
import QuotePilotCore
import SwiftUI

/// One quote: the form on the left, its PDF on the right. Text saves as you type; amounts and
/// quantities save when you press Return or leave the field.
struct QuoteEditorView: View {
    let model: AppModel
    let quoteID: UUID

    var body: some View {
        let quote = model.quoteBinding(quoteID)
        let current = quote.wrappedValue
        VStack(spacing: 0) {
            header(current)
            HStack(alignment: .top, spacing: 8) {
                ScrollView {
                    form(quote)
                        .padding(.trailing, 6)
                }
                // The window is at least 980 wide, which leaves 754 beside the section tree. The form
                // takes what it can up to 640 and the preview keeps the rest, never under 220, so at
                // the smallest window the two still fit side by side.
                .frame(minWidth: 500, idealWidth: 600, maxWidth: 640)
                .layoutPriority(1)
                GroupBox("Preview") {
                    LivePDFPreview(model: model, content: model.quoteContent(quoteID))
                }
                .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
        }
        .groupBoxStyle(.win95)
    }

    private func header(_ quote: Quote) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button("All Quotes") { model.openQuoteID = nil }
                .buttonStyle(.win95)
                .help("Back to the list of quotes")
            PixelIconView(.quote, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quote \(quote.number)")
                    .font(Win95.title)
                    .foregroundStyle(Win95.text)
                StatusLabel.cell(quote.status(on: model.today), selected: false)
            }
            Spacer()
            Button("Duplicate") { model.duplicateQuote(quoteID) }
                .buttonStyle(.win95)
            if quote.stage == .draft {
                Button("Delete Draft") { model.deleteDraftQuote(quoteID) }
                    .buttonStyle(.win95)
            }
            Button("Save PDF…") { model.exportPDF() }
                .buttonStyle(.win95)
            Text(model.money(quote.totals.total))
                .font(Win95.readout)
                .foregroundStyle(Win95.text)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .frame(minWidth: 190, alignment: .trailing)
                .win95Sunken()
                .accessibilityLabel("Total \(model.money(quote.totals.total))")
        }
        .padding(8)
        .background(Win95.face)
        .overlay(alignment: .bottom) { EtchedLine() }
    }

    private func form(_ quote: Binding<Quote>) -> some View {
        let current = quote.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            if current.stage != .draft {
                NoteBanner("This quote has been sent. Changes here change Quote Pilot's copy, not the PDF your client already has.")
            }
            GroupBox("Quote") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Client:") { ClientPicker(clients: model.library.clients, selection: quote.clientID) }
                    Win95FieldRow("Title:") {
                        Win95TextField("Title", text: quote.title, prompt: "e.g. Website rebuild, phase 1")
                    }
                    Win95FieldRow("Issued:") { DayPicker(label: "Issued", day: quote.issued) }
                    Win95FieldRow("Valid until:") { DayPicker(label: "Valid until", day: quote.validUntil) }
                    Win95FieldRow("Payment:") {
                        Win95RadioGroup(selection: quote.plan, options: PaymentPlan.allCases.map { ($0, $0.summary) })
                    }
                    if model.library.brand.gstRegistered || current.taxed {
                        Win95FieldRow("GST:") { Toggle("Add GST (10%)", isOn: quote.taxed).toggleStyle(.win95) }
                    }
                }
            }
            GroupBox("Lines") {
                LinesEditor(model: model, quote: quote)
            }
            GroupBox("Work summary") {
                VStack(alignment: .leading, spacing: 4) {
                    Win95TextEditor(text: quote.summary)
                        .frame(height: 90)
                    Text("Lines starting with \"- \" print as dot points.")
                        .font(Win95.small)
                        .foregroundStyle(Win95.text)
                }
            }
            GroupBox("Terms") {
                Win95TextEditor(text: quote.terms)
                    .frame(height: 60)
            }
        }
    }
}

/// The quote's lines, each with its ID, wording, quantity, unit, rate and amount, plus totals.
struct LinesEditor: View {
    let model: AppModel
    @Binding var quote: Quote

    var body: some View {
        let currency = model.currencyCode
        let showDecision = quote.stage == .accepted || quote.stage == .declined
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                columnHead("ID", width: 24)
                columnHead("Item", width: nil)
                columnHead("Qty", width: 48)
                columnHead("Unit", width: 72)
                columnHead("Rate", width: 92)
                columnHead("Amount", width: 88, trailing: true)
                Spacer().frame(width: 3 * 20 + 2 * 4)
            }
            ForEach(Array(quote.lines.enumerated()), id: \.element.id) { index, line in
                LineRow(line: lineBinding(line.id), currency: currency, showDecision: showDecision,
                        canMoveUp: index > 0, canMoveDown: index < quote.lines.count - 1,
                        move: { move(line.id, by: $0) }, remove: { remove(line) })
            }
            if quote.lines.isEmpty {
                Text("No lines yet. Add one for each piece of work the client can tick.")
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
            }
            HStack(alignment: .top) {
                Button("Add Line") { add() }
                    .buttonStyle(.win95)
                Spacer()
                totals(currency)
            }
            .padding(.top, 4)
        }
    }

    private func columnHead(_ title: String, width: CGFloat?, trailing: Bool = false) -> some View {
        Text(title)
            .font(Win95.label)
            .foregroundStyle(Win95.text)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func totals(_ currency: String) -> some View {
        let totals = quote.totals
        return Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
            if quote.taxed {
                GridRow {
                    Text("Subtotal")
                    Text(totals.subtotal.formatted(currencyCode: currency)).font(Win95.money)
                }
                GridRow {
                    Text("GST (10%)")
                    Text(totals.gst.formatted(currencyCode: currency)).font(Win95.money)
                }
            }
            GridRow {
                Text("Total").font(Win95.label)
                Text(totals.total.formatted(currencyCode: currency)).font(Win95.money.bold())
            }
        }
        .font(Win95.body)
        .foregroundStyle(Win95.text)
    }

    /// A line found by its identity, so a removed or moved line can never index past the end.
    private func lineBinding(_ id: UUID) -> Binding<LineItem> {
        Binding(
            get: { quote.lines.first { $0.id == id } ?? LineItem(id: id, title: "", rate: .zero) },
            set: { line in
                var edited = quote
                guard let index = edited.lines.firstIndex(where: { $0.id == id }) else { return }
                edited.lines[index] = line
                quote = edited
            })
    }

    private func add() {
        var edited = quote
        edited.addLine(LineItem(title: "", rate: .zero))
        quote = edited
    }

    private func move(_ id: UUID, by offset: Int) {
        var edited = quote
        guard let index = edited.lines.firstIndex(where: { $0.id == id }),
              edited.lines.indices.contains(index + offset)
        else { return }
        edited.lines.swapAt(index, index + offset)
        quote = edited
    }

    /// How the Remove Line question names a line: "line 02, Design", with a long title cut at 60
    /// characters so the message box stays a message box.
    static func lineName(_ line: LineItem) -> String {
        guard !line.title.isEmpty else { return "line \(line.code)" }
        let title = line.title.count > 60 ? String(line.title.prefix(60)) + "…" : line.title
        return "line \(line.code), \(title)"
    }

    private func remove(_ line: LineItem) {
        model.confirm(title: "Remove Line", text: "Remove \(Self.lineName(line))?", confirm: "Remove") {
            var edited = quote
            edited.lines.removeAll { $0.id == line.id }
            quote = edited
        }
    }
}

struct LineRow: View {
    @Binding var line: LineItem
    let currency: String
    let showDecision: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(line.code)
                    .font(Win95.money)
                    .foregroundStyle(Win95.text)
                    .frame(width: 24, alignment: .leading)
                Win95TextField("Line \(line.code) item", text: $line.title, prompt: "What the work is")
                CommitField(label: "Line \(line.code) quantity", value: line.quantity,
                            format: FieldParser.quantityText, parse: FieldParser.quantity) { line.quantity = $0 }
                    .frame(width: 48)
                Picker("Line \(line.code) unit", selection: $line.unit) {
                    ForEach(QuotePilotCore.Unit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 72)
                CommitField(label: "Line \(line.code) rate", value: line.rate,
                            format: { $0.formatted(currencyCode: currency) }, parse: FieldParser.money) { line.rate = $0 }
                    .frame(width: 92)
                Text(line.amount.formatted(currencyCode: currency))
                    .font(Win95.money)
                    .foregroundStyle(Win95.text)
                    .lineLimit(1)
                    .frame(width: 88, alignment: .trailing)
                SquareButton(PixelGlyph.up, label: "Move line \(line.code) up") { move(-1) }
                    .disabled(!canMoveUp)
                SquareButton(PixelGlyph.down, label: "Move line \(line.code) down") { move(1) }
                    .disabled(!canMoveDown)
                SquareButton(PixelGlyph.cross, label: "Remove line \(line.code)", action: remove)
            }
            HStack(spacing: 4) {
                Spacer().frame(width: 28)
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

/// A number field that saves as you type, but only text `parse` accepts. Each time the text becomes
/// a different valid value it is committed at once, so clicking Save PDF… or another button while
/// the cursor is still in the field uses what is showing. Half-typed text ("1.", "$") is left alone
/// and the text itself is never rewritten while you type. When you press Return or leave the field,
/// text that doesn't parse beeps and the stored value is put back, so it never reaches the library;
/// valid text is tidied to the field's own format ("1500" becomes "$1,500.00").
struct CommitField<Value: Equatable>: View {
    let label: String
    let value: Value
    let format: (Value) -> String
    let parse: (String) -> Value?
    var alignment: TextAlignment = .trailing
    let commit: (Value) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    /// While typing: the value to commit now, or nil when the text is half-typed, nonsense, or no
    /// change from what's stored.
    static func liveCommit(text: String, stored: Value, parse: (String) -> Value?) -> Value? {
        guard let parsed = parse(text), parsed != stored else { return nil }
        return parsed
    }

    /// On Return or leaving: whether to beep, and the text to show from now on (the stored value in
    /// the field's format). Only text that doesn't parse beeps, and not when it is just the stored
    /// value as the field shows it, such as an imported 1.234 that the parser wouldn't take.
    static func onLeave(text: String, stored: Value, format: (Value) -> String,
                        parse: (String) -> Value?) -> (beep: Bool, text: String) {
        let shown = format(stored)
        return (parse(text) == nil && text != shown, shown)
    }

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(Win95.money)
            .foregroundStyle(Win95.text)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onSubmit(apply)
            .onChange(of: text) { _, newText in
                // Only what's typed here: not the text the field is given when it appears or when
                // the stored value changes elsewhere.
                guard focused, let parsed = Self.liveCommit(text: newText, stored: value, parse: parse) else { return }
                commit(parsed)
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { apply() }
            }
            .onChange(of: value) { _, newValue in
                // While you type, the text stays as typed; Return or leaving tidies it.
                if !focused { text = format(newValue) }
            }
            .onChange(of: isEnabled) { _, enabled in
                // A message box disables the window behind it. If it came from a refused edit, the
                // typed text must not stay showing in place of the stored value.
                if !enabled { text = format(value) }
            }
            .onAppear { text = format(value) }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(Win95.field)
            .overlay(Bevel(.sunken))
            .overlay(focused ? FocusRect().padding(3) : nil)
            .accessibilityLabel(label)
    }

    private func apply() {
        // Valid text was committed as it was typed. This only catches an edit that wasn't taken then.
        if let parsed = Self.liveCommit(text: text, stored: value, parse: parse) { commit(parsed) }
        let leaving = Self.onLeave(text: text, stored: value, format: format, parse: parse)
        if leaving.beep { NSSound.beep() }
        // The stored value: what was committed while typing, or the old one if an edit was refused.
        text = leaving.text
    }
}

/// A date field for a `Day`.
struct DayPicker: View {
    let label: String
    @Binding var day: Day

    var body: some View {
        DatePicker(label, selection: Binding(get: { day.date() }, set: { day = Day($0) }), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(maxWidth: 160, alignment: .leading)
    }
}

/// Choose a client, or none. A native pop-up, so it works from the keyboard and with VoiceOver.
struct ClientPicker: View {
    let clients: [Client]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Client", selection: $selection) {
            Text("No client").tag(UUID?.none)
            ForEach(clients.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { client in
                Text(client.name).tag(Optional(client.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 300, alignment: .leading)
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

extension QuotePilotCore.Unit {
    /// The unit as the picker names it.
    var label: String {
        switch self {
        case .hours: return "hours"
        case .days: return "days"
        case .units: return "units"
        }
    }
}
