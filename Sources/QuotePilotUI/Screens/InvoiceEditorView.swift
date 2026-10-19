import QuotePilotCore
import SwiftUI

/// One invoice, laid out like the quote editor. Drafts can be edited; sent and void invoices are
/// records, shown read-only with a note saying why.
struct InvoiceEditorView: View {
    let model: AppModel
    let invoiceID: UUID
    /// Where View → Show Steps is kept. Tests give it their own, so none touches the real one.
    var stepDefaults: UserDefaults = .standard

    var body: some View {
        let invoice = model.invoiceBinding(invoiceID)
        VStack(spacing: 0) {
            header(invoice.wrappedValue)
            // Same widths as plan 2a's QuoteEditorView after its 980-pt fix (form 500…640 with
            // layoutPriority(1), preview at least 220), so the editor fits the minimum window.
            HStack(alignment: .top, spacing: 8) {
                ScrollView {
                    form(invoice)
                        .padding(.trailing, 6)
                }
                .frame(minWidth: 500, idealWidth: 620, maxWidth: 640)
                .layoutPriority(1)
                GroupBox("Preview") {
                    LivePDFPreview(model: model, content: model.invoiceContent(invoiceID))
                }
                .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
        }
        .groupBoxStyle(.win95)
    }

    /// What this invoice allows. The model works it out from the library; an invoice that has just gone
    /// from the library is a draft with nothing deducting it, which shows nothing to act on.
    private func rulesFor(_ invoice: Invoice) -> InvoiceRules {
        model.invoiceRules(invoice.id) ?? InvoiceRules(invoice: invoice, finalDeducting: nil)
    }

    /// Whether Send by Mail… has the heavy outline: only while sending is the next step (a draft). A
    /// sent invoice's outlined button is Record Payment, so the screen never has two.
    static func sendIsDefault(_ invoice: Invoice) -> Bool { invoice.stage == .draft }

    /// Two rows, like the quote's: the name, status and amount above, with the step bar in the space
    /// between them; the actions below, on the same left edge as All Invoices. 8 pt above the first
    /// row, between the rows and below the actions. (Not private: a test measures it at the smallest
    /// window.)
    func header(_ invoice: Invoice) -> some View {
        let rules = rulesFor(invoice)
        return VStack(spacing: 0) {
            titleRow(invoice)
            HStack(spacing: 6) {
                if invoice.stage != .void {
                    Button("Send by Mail…") { model.send(.invoice(invoiceID)) }
                        .buttonStyle(Win95ButtonStyle(isDefault: Self.sendIsDefault(invoice)))
                        .disabled(invoice.clientID == nil)
                        .help(invoice.clientID == nil ? "Choose a client first" : "Open a Mail draft with this invoice attached (⌘S)")
                }
                // Greyed, not hidden, for a deposit the final invoice deducts: the note on the form says why.
                if invoice.stage == .sent, invoice.payments.isEmpty {
                    Button("Void…") { model.voidInvoice(invoiceID) }
                        .disabled(!rules.canVoid)
                        .help(rules.deductedHelp ?? "Cancel this invoice; its number stays used")
                }
                if invoice.stage == .draft {
                    Button("Delete Draft") { model.deleteDraftInvoice(invoiceID) }
                        .disabled(!rules.canDelete)
                        .help(rules.deductedHelp ?? "Delete this draft; its number won't be used again")
                }
                if invoice.kind == .standalone {
                    Button("Duplicate") { model.duplicateInvoice(invoiceID) }
                        .help("A new draft with the same lines, for repeat work")
                }
                // No Save PDF… here: the toolbar's Save PDF, right above, is the one control for it.
                Spacer()
            }
            .buttonStyle(.win95)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            // Under the padding, not over it, so the 8 pt below the buttons is as clear as the 8 pt
            // above the first row and between the rows.
            EtchedLine()
        }
        .background(Win95.face)
    }

    /// The header's first row. The step bar sits between the title block and the amount, where the
    /// spacer was; with View → Show Steps off it is that spacer. (Not private: a test measures it.)
    func titleRow(_ invoice: Invoice) -> some View {
        HStack(alignment: .owingRow, spacing: 10) {
            Button("All Invoices") { model.openInvoiceID = nil }
                .buttonStyle(.win95)
                .help("Back to the list of invoices")
            PixelIconView(.invoice, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Invoice \(invoice.number)")
                    .font(Win95.title)
                    .foregroundStyle(Win95.text)
                HStack(spacing: 8) {
                    StatusLabel.cell(invoice.status(on: model.today), selected: false)
                    Text(invoice.kind.columnLabel)
                        .font(Win95.body)
                        .foregroundStyle(Win95.text)
                }
            }
            StepBar(model: model, document: .invoice(invoiceID), defaults: stepDefaults)
            readouts(invoice)
        }
        .padding(8)
    }

    /// The readouts at the right of the first row, in a two-row grid: the invoice's figure, and under
    /// it, smaller, what's left on the whole job. The labels share one column, right-aligned, each
    /// centred on its box; the boxes share the other, so they are one width (the wider of the two)
    /// with their edges lined up. The first row is centred on the header's `.owingRow`, so the title
    /// and the step bar stay level with it and the job's row hangs below. (Not private: a test
    /// measures it.)
    func readouts(_ invoice: Invoice) -> some View {
        let status = invoice.status(on: model.today)
        let showOwing = invoice.stage == .sent
        let figure = model.money(showOwing ? invoice.owing : invoice.amount)
        // A deposit is only part of the job, so its readout says it's this invoice's, and the line
        // under it says what's left on the whole job.
        let label = showOwing ? (invoice.kind == .deposit ? "Owing on this invoice" : "Owing") : "Amount"
        let leftToPay = model.leftToPayOnJob(invoice.id).map { model.money($0) }
        return Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                readoutLabel(label, font: Win95.label)
                Text(figure)
                    .font(Win95.readout)
                    .foregroundStyle(status.isAlert ? Win95.overdue : Win95.text)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .frame(minWidth: 190, maxWidth: .infinity, alignment: .trailing)
                    .win95Sunken()
                    .alignmentGuide(.owingRow) { $0[VerticalAlignment.center] }
                    .accessibilityLabel("\(label) \(figure)")
            }
            if let leftToPay {
                GridRow {
                    readoutLabel(Self.jobReadoutLabel, font: Win95.label.weight(.bold))
                    Text(leftToPay)
                        .font(Win95.smallReadout)
                        .foregroundStyle(Win95.text)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .win95Sunken()
                        .accessibilityLabel("\(Self.jobReadoutLabel) \(leftToPay)")
                }
            }
        }
        // As wide as the grid needs and no wider, so the step bar has the rest of the row.
        .fixedSize()
    }

    private func readoutLabel(_ text: String, font: Font) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(Win95.text)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }

    static let jobReadoutLabel = "Left to pay on this job"

    private func form(_ invoice: Binding<Invoice>) -> some View {
        let current = invoice.wrappedValue
        let rules = rulesFor(current)
        let quote = current.quoteID.flatMap { model.library.quote($0) }
        return VStack(alignment: .leading, spacing: 10) {
            // Why the rest of the screen is locked, in a sentence that fits this invoice's state.
            if let note = rules.note {
                NoteBanner(note.text, warning: note.warning)
            }
            if let quote {
                QuoteSourceBanner(model: model, invoice: current, quote: quote,
                                  text: model.depositNote(invoiceID)
                                    ?? "Drafted from quote \(quote.number), as its \(current.kind.columnLabel.lowercased()) invoice.",
                                  defaults: stepDefaults)
            }
            // Payments are what you do with a sent invoice, so the box sits first, where it shows
            // without scrolling; the invoice's own boxes are the record below it.
            if current.stage != .draft {
                PaymentsBox(model: model, invoice: current)
            }
            GroupBox("Invoice") {
                VStack(alignment: .leading, spacing: 6) {
                    DocumentNumberRow(model: model, number: current.number, kind: .invoice,
                                      editable: rules.canRenumber,
                                      help: rules.canRenumber
                                        ? "Type a number no other invoice has, then press Return"
                                        : rules.deductedHelp ?? "Only a draft's number can be changed") {
                        model.renumberInvoice(invoiceID, to: $0)
                    }
                    Win95FieldRow("Client:") {
                        ClientPicker(clients: model.library.clients, selection: invoice.clientID)
                            .disabled(quote != nil)
                    }
                    Win95FieldRow("Title:") {
                        Win95TextField("Title", text: invoice.title, prompt: "e.g. Website care, October")
                    }
                    Win95FieldRow("Issued:") { DayPicker(label: "Issued", day: invoice.issued) }
                    Win95FieldRow("Due:") { DayPicker(label: "Due", day: invoice.due) }
                    if model.library.brand.gstRegistered || current.taxed {
                        Win95FieldRow("GST:") {
                            Toggle("Add GST (10%)", isOn: invoice.taxed)
                                .toggleStyle(.win95)
                                .disabled(!rules.canEditAmounts)
                        }
                    }
                }
            }
            .disabled(!rules.canEditDetails)
            GroupBox("Lines") {
                LinesEditor(model: model, lines: invoice.lines, showCodes: false, editable: rules.canEditAmounts,
                            onAdd: {
                                var edited = invoice.wrappedValue
                                edited.lines.append(.blank(hourlyRate: model.library.brand.hourlyRate))
                                invoice.wrappedValue = edited
                            }) {
                    DocumentTotals(totals: model.invoiceContent(invoiceID)?.totals ?? [])
                }
            }
            GroupBox("Terms") {
                Win95TextEditor("Terms", text: invoice.terms)
                    .frame(height: 60)
            }
            .disabled(!rules.canEditAmounts)
        }
    }
}

/// An invoice's line about the quote it came from, with the button that opens that quote. The button
/// is "Open Q-0001", as the step bar's is. One control per action (see `StepBar`): while the step bar
/// shows its own Open Q-0001 (a paid deposit's next step), the banner leaves its button out.
struct QuoteSourceBanner: View {
    let model: AppModel
    let invoice: Invoice
    let quote: Quote
    let text: String
    @AppStorage private var showSteps: Bool

    init(model: AppModel, invoice: Invoice, quote: Quote, text: String, defaults: UserDefaults = .standard) {
        self.model = model
        self.invoice = invoice
        self.quote = quote
        self.text = text
        _showSteps = AppStorage(wrappedValue: true, StepPreferences.showStepsKey, store: defaults)
    }

    /// The button's label, the same as the step bar's.
    static func openTitle(_ quote: Quote) -> String { "Open \(quote.number)" }

    /// Whether the banner has its own Open button: only while the step bar isn't offering it.
    static func showsOpenButton(_ invoice: Invoice, quote: Quote, in library: Library, today: Day,
                                stepsShown: Bool) -> Bool {
        let next = NextStep.forInvoice(invoice, in: library, today: today)
        return !StepBar.offersOpen(quote.id, next: next, stepsShown: stepsShown)
    }

    var body: some View {
        HStack(spacing: 8) {
            NoteBanner(text)
            if Self.showsOpenButton(invoice, quote: quote, in: model.library, today: model.today,
                                    stepsShown: showSteps) {
                Button(Self.openTitle(quote)) { model.openQuote(quote.id) }
                    .buttonStyle(.win95)
                    .help("Open quote \(quote.number)")
            }
        }
    }
}

extension VerticalAlignment {
    /// The invoice header's first row lines up on the middle of the Owing readout's row; everything
    /// else in it uses its own centre, as with `.center`.
    enum OwingRow: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }

    static let owingRow = VerticalAlignment(OwingRow.self)
}
