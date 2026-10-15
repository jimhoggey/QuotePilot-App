import QuotePilotCore
import SwiftUI

/// One invoice, laid out like the quote editor. Drafts can be edited; sent and void invoices are
/// records, shown read-only with a note saying why.
struct InvoiceEditorView: View {
    let model: AppModel
    let invoiceID: UUID

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

    private func header(_ invoice: Invoice) -> some View {
        let status = invoice.status(on: model.today)
        let showOwing = invoice.stage == .sent
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
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
                Spacer()
                Text(showOwing ? "Owing" : "Amount")
                    .font(Win95.label)
                    .foregroundStyle(Win95.text)
                Text(model.money(showOwing ? invoice.owing : invoice.amount))
                    .font(Win95.readout)
                    .foregroundStyle(status.isAlert ? Win95.overdue : Win95.text)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .frame(minWidth: 190, alignment: .trailing)
                    .win95Sunken()
            }
            .padding(8)
            HStack(spacing: 6) {
                if invoice.stage != .void {
                    Button("Send by Mail…") { model.send(.invoice(invoiceID)) }
                        .buttonStyle(.win95Default)
                        .help("Open a Mail draft with this invoice attached (⌘S)")
                }
                if invoice.stage == .sent, invoice.payments.isEmpty {
                    Button("Void…") { model.voidInvoice(invoiceID) }
                        .help("Cancel this invoice; its number stays used")
                }
                if invoice.stage == .draft {
                    Button("Delete Draft") { model.deleteDraftInvoice(invoiceID) }
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

    private func form(_ invoice: Binding<Invoice>) -> some View {
        let current = invoice.wrappedValue
        let editable = current.stage == .draft
        let quote = current.quoteID.flatMap { model.library.quote($0) }
        return VStack(alignment: .leading, spacing: 10) {
            switch current.stage {
            case .sent:
                NoteBanner("This invoice has been sent, so it can't be changed. If something's wrong, void it and draft a new one.")
            case .void:
                NoteBanner("This invoice is void. It no longer counts as owed, and its number stays used.", warning: true)
            case .draft:
                EmptyView()
            }
            if let quote {
                HStack(spacing: 8) {
                    NoteBanner("Drafted from quote \(quote.number), as its \(current.kind.columnLabel.lowercased()) invoice.")
                    Button("Open Quote") { model.openQuote(quote.id) }
                        .buttonStyle(.win95)
                }
            }
            GroupBox("Invoice") {
                VStack(alignment: .leading, spacing: 6) {
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
                        Win95FieldRow("GST:") { Toggle("Add GST (10%)", isOn: invoice.taxed).toggleStyle(.win95) }
                    }
                }
            }
            .disabled(!editable)
            GroupBox("Lines") {
                LinesEditor(model: model, lines: invoice.lines, showCodes: false, editable: editable,
                            onAdd: {
                                var edited = invoice.wrappedValue
                                edited.lines.append(LineItem(title: "", rate: .zero))
                                invoice.wrappedValue = edited
                            }) {
                    DocumentTotals(totals: model.invoiceContent(invoiceID)?.totals ?? [])
                }
            }
            GroupBox("Terms") {
                Win95TextEditor("Terms", text: invoice.terms)
                    .frame(height: 60)
            }
            .disabled(!editable)
        }
    }
}
