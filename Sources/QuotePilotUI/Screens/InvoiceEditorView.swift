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

    /// Two rows, like the quote's: the name, status and amount above, with the step bar in the space
    /// between them; the actions below. (Not private: a test measures it at the smallest window.)
    func header(_ invoice: Invoice) -> some View {
        let rules = rulesFor(invoice)
        return VStack(spacing: 0) {
            titleRow(invoice)
            HStack(spacing: 6) {
                if invoice.stage != .void {
                    Button("Send by Mail…") { model.send(.invoice(invoiceID)) }
                        .buttonStyle(.win95Default)
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

    /// The header's first row. The step bar sits between the title block and the amount, where the
    /// spacer was; with View → Show Steps off it is that spacer. (Not private: a test measures it.)
    func titleRow(_ invoice: Invoice) -> some View {
        let status = invoice.status(on: model.today)
        let showOwing = invoice.stage == .sent
        let figure = model.money(showOwing ? invoice.owing : invoice.amount)
        return HStack(alignment: .center, spacing: 10) {
            Button("All Invoices") { model.openInvoiceID = nil }
                .buttonStyle(.win95)
                .help("Back to the list of invoices")
            PixelIconView(.invoice, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Invoice \(invoice.number)")
                    .font(Win95.title)
                    .foregroundStyle(Win95.text)
                HStack(spacing: 8) {
                    StatusLabel.cell(status, selected: false)
                    Text(invoice.kind.columnLabel)
                        .font(Win95.body)
                        .foregroundStyle(Win95.text)
                }
            }
            StepBar(model: model, document: .invoice(invoiceID), defaults: stepDefaults)
            Text(showOwing ? "Owing" : "Amount")
                .font(Win95.label)
                .foregroundStyle(Win95.text)
                .accessibilityHidden(true)
            Text(figure)
                .font(Win95.readout)
                .foregroundStyle(status.isAlert ? Win95.overdue : Win95.text)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .frame(minWidth: 190, alignment: .trailing)
                .win95Sunken()
                .accessibilityLabel("\(showOwing ? "Owing" : "Amount") \(figure)")
        }
        .padding(8)
    }

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
                HStack(spacing: 8) {
                    NoteBanner("Drafted from quote \(quote.number), as its \(current.kind.columnLabel.lowercased()) invoice.")
                    Button("Open Quote") { model.openQuote(quote.id) }
                        .buttonStyle(.win95)
                }
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
