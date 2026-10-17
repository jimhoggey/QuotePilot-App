import AppKit
import QuotePilotCore
import SwiftUI

/// One quote: the form on the left, its PDF on the right. Text saves as you type; amounts and
/// quantities save when you press Return or leave the field.
struct QuoteEditorView: View {
    let model: AppModel
    let quoteID: UUID
    /// Where View → Show Steps is kept. Tests give it their own, so none touches the real one.
    var stepDefaults: UserDefaults = .standard

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

    /// Two rows: the quote's name, status and total above, with the step bar in the space between
    /// them; the actions below, where a long set of buttons has the whole width to itself. (Not
    /// private: a test measures it at the smallest window.)
    func header(_ quote: Quote) -> some View {
        VStack(spacing: 0) {
            titleRow(quote)
            HStack(spacing: 6) {
                Button("Send by Mail…") { model.send(.quote(quoteID)) }
                    .buttonStyle(.win95Default)
                    .disabled(quote.clientID == nil)
                    .help(quote.clientID == nil ? "Choose a client first" : "Open a Mail draft with this quote attached (⌘S)")
                if quote.stage != .draft, model.library.invoices(forQuote: quoteID).isEmpty {
                    Button("Record Acceptance…") { model.startHandTicking(quoteID) }
                        .help("Tick the lines the client accepted, when they couldn't fill in the PDF")
                }
                if model.library.nextInvoiceKind(forQuote: quoteID) != nil {
                    Button("Draft Invoice Now") { model.draftInvoiceNow(forQuote: quoteID) }
                        .help("Draft the next invoice the payment plan calls for")
                }
                // Not tied to Draft Invoice Now: once that has drafted the final there's nothing left to
                // draft, but the job still isn't marked complete.
                if model.canCompleteJob(quoteID) {
                    Button("Job Complete") { model.completeJob(quoteID) }
                        .help("Record the job as done, and open its final invoice (drafting it first if it isn't there yet)")
                }
                Button("Duplicate") { model.duplicateQuote(quoteID) }
                if quote.stage == .draft {
                    Button("Delete Draft") { model.deleteDraftQuote(quoteID) }
                }
                Button("Save PDF…") { model.exportPDF() }
                Spacer()
            }
            .buttonStyle(.win95)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Win95.face)
        .overlay(alignment: .bottom) { EtchedLine() }
    }

    /// The header's first row. The step bar sits between the title block and the total, where the
    /// spacer was; with View → Show Steps off it is that spacer. (Not private: a test measures it.)
    func titleRow(_ quote: Quote) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button("All Quotes") { model.openQuoteID = nil }
                .buttonStyle(.win95)
                .help("Back to the list of quotes")
            PixelIconView(.quote, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quote \(quote.number)")
                    .font(Win95.title)
                    .foregroundStyle(Win95.text)
                HStack(spacing: 8) {
                    StatusLabel.cell(quote.status(on: model.today), selected: false)
                    if let done = quote.completedOn {
                        Text("Job completed \(done.short)")
                            .font(Win95.body)
                            .foregroundStyle(Win95.text)
                    }
                }
            }
            StepBar(model: model, document: .quote(quoteID), defaults: stepDefaults)
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
    }

    private func form(_ quote: Binding<Quote>) -> some View {
        let current = quote.wrappedValue
        // Core refuses a new client, plan, GST setting or line change once the quote has invoices, so
        // those controls are greyed out and a banner says why, instead of an error box per attempt.
        let locked = model.billingLocked(forQuote: quoteID)
        return VStack(alignment: .leading, spacing: 10) {
            // One banner: the lock says more than the sent note does, so a sent quote that has
            // invoices shows only the lock.
            if locked {
                NoteBanner(AppModel.billingLockedNote)
            } else if current.stage != .draft {
                NoteBanner("This quote has been sent. Changes here change Quote Pilot's copy, not the PDF your client already has.")
            }
            GroupBox("Quote") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Client:") {
                        ClientPicker(clients: model.library.clients, selection: quote.clientID)
                            .disabled(locked)
                    }
                    Win95FieldRow("Title:") {
                        Win95TextField("Title", text: quote.title, prompt: "e.g. Website rebuild, phase 1")
                    }
                    Win95FieldRow("Issued:") { DayPicker(label: "Issued", day: quote.issued) }
                    Win95FieldRow("Valid until:") { DayPicker(label: "Valid until", day: quote.validUntil) }
                    Win95FieldRow("Payment:") {
                        Win95RadioGroup(selection: quote.plan, options: PaymentPlan.allCases.map { ($0, $0.summary) })
                            .disabled(locked)
                    }
                    if model.library.brand.gstRegistered || current.taxed {
                        Win95FieldRow("GST:") {
                            Toggle("Add GST (10%)", isOn: quote.taxed)
                                .toggleStyle(.win95)
                                .disabled(locked)
                        }
                    }
                }
            }
            GroupBox("Lines") {
                LinesEditor(model: model, lines: quote.lines,
                            showDecision: current.stage == .accepted || current.stage == .declined,
                            editable: !locked,
                            onAdd: {
                                var edited = quote.wrappedValue
                                edited.addLine(.blank(hourlyRate: model.library.brand.hourlyRate))
                                quote.wrappedValue = edited
                            }) {
                    DocumentTotals(totals: model.quoteContent(quoteID)?.totals ?? [])
                }
            }
            GroupBox("Work summary") {
                VStack(alignment: .leading, spacing: 4) {
                    Win95TextEditor(text: quote.summary)
                        .frame(height: 90)
                    Text("Lines starting with a dash, • or * print as dot points.")
                        .font(Win95.small)
                        .foregroundStyle(Win95.text)
                }
            }
            GroupBox("Included / Not included") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        ListBox(label: "Included:", items: quote.included)
                        ListBox(label: "Not included:", items: quote.notIncluded)
                    }
                    Text("Optional. One item per line. The quote prints them side by side when either box has items.")
                        .font(Win95.small)
                        .foregroundStyle(Win95.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            GroupBox("Terms") {
                Win95TextEditor(text: quote.terms)
                    .frame(height: 60)
            }
        }
    }
}

/// A number field that saves as you type, but only text `parse` accepts. Each time the text becomes
/// a different valid value it is committed at once, so clicking Save PDF… or another button while
/// the cursor is still in the field uses what is showing. Half-typed text ("1.", "$") is left alone
/// and the text itself is never rewritten while you type. When you press Return or leave the field,
/// text that doesn't parse beeps and the stored value is put back, so it never reaches the library;
/// valid text is tidied to the field's own format ("1500" becomes "$1,500.00"). Disabled, it is grey
/// with grey text, like `Win95TextField`.
struct CommitField<Value: Equatable>: View {
    let label: String
    let value: Value
    let format: (Value) -> String
    let parse: (String) -> Value?
    var alignment: TextAlignment = .trailing
    /// What an empty field says, grey; the label (which VoiceOver reads) when nil.
    var prompt: String?
    let commit: (Value) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.textEditEnded) private var editEnded
    @Environment(\.textFocusChanged) private var focusChanged

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

    /// When the stored value changes: whether the field's text is replaced by it. Not while you type,
    /// when the text is the value you just typed (committed as it was typed, so it parses to it); but
    /// yes when it is a different value, because something else changed it, such as the unit picker
    /// filling in the hourly rate while the cursor was still in the rate field. Left as it was, leaving
    /// the field would commit that old text and undo the change.
    static func refreshesText(text: String, focused: Bool, newValue: Value, parse: (String) -> Value?) -> Bool {
        !focused || parse(text) != newValue
    }

    var body: some View {
        TextField(prompt ?? label, text: $text)
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(Win95.money)
            .foregroundStyle(isEnabled ? Win95.text : Win95.shadow)
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
                focusChanged(isFocused)
                if !isFocused { apply() }
            }
            .onChange(of: value) { _, newValue in
                // While you type, the text stays as typed; Return or leaving tidies it.
                if Self.refreshesText(text: text, focused: focused, newValue: newValue, parse: parse) {
                    text = format(newValue)
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                // A message box disables the window behind it. If it came from a refused edit, the
                // typed text must not stay showing in place of the stored value.
                if !enabled { text = format(value) }
            }
            .onAppear { text = format(value) }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(isEnabled ? Win95.field : Win95.face)
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
        editEnded()
    }
}

/// One of a quote's Included / Not included boxes: one item per line. What's typed is saved as you
/// type, as items with any dot-point marker stripped (`Quote.listItems`). The text itself is left
/// alone while you type, so a new empty line stays; when you leave the box it is tidied to the items.
struct ListBox: View {
    let label: String
    @Binding var items: [String]
    @State private var text = ""
    @Environment(\.textEditEnded) private var editEnded

    /// The box's text for `items`.
    static func text(_ items: [String]) -> String { items.joined(separator: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Win95.body)
                .foregroundStyle(Win95.text)
            Win95TextEditor(label, text: $text)
                .frame(height: 80)
                .environment(\.textEditEnded) {
                    text = Self.text(items)
                    editEnded()
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { text = Self.text(items) }
        .onChange(of: text) { _, newText in
            let parsed = Quote.listItems(from: newText)
            if parsed != items { items = parsed }
        }
        .onChange(of: items) { _, newItems in
            // Changed elsewhere, not by typing here: show it.
            if Quote.listItems(from: text) != newItems { text = Self.text(newItems) }
        }
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
