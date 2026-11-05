import QuotePilotCore
import SwiftUI

/// Brand → Documents' invoice templates: choose one to change its title and lines, or start a new
/// one. New Invoice in the toolbar offers those with a title. The lines are a compact table (item,
/// quantity, unit, rate), as the tab shares the window with the sample preview.
struct InvoiceTemplatesBox: View {
    let model: AppModel
    @Binding var templates: [InvoiceTemplate]
    @State private var chosenID: UUID?

    /// The template being changed: the one chosen, or the first.
    private var shownID: UUID? {
        templates.contains { $0.id == chosenID } ? chosenID : templates.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !templates.isEmpty {
                    Picker("Template", selection: Binding(get: { shownID }, set: { chosenID = $0 })) {
                        ForEach(templates) { Text($0.shownTitle).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }
                Button("New Template") {
                    let template = InvoiceTemplate(lines: [.blank(hourlyRate: model.library.brand.hourlyRate)])
                    templates.append(template)
                    chosenID = template.id
                }
                Button("Delete Template") { if let id = shownID { delete(id) } }
                    .disabled(shownID == nil)
            }
            .buttonStyle(.win95)
            if let id = shownID {
                TemplateForm(model: model, template: binding(id))
            }
            Text(templates.isEmpty
                 ? "A template starts an invoice with its title and lines filled in, such as \"Billing for meeting time\" with an hour of meeting time."
                 : "Once it has a title, New Invoice in the toolbar offers it. Each invoice still gets its own client and dates.")
                .font(Win95.small)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Removes the template at once when it's empty, and asks first when it isn't.
    private func delete(_ id: UUID) {
        guard let template = templates.first(where: { $0.id == id }) else { return }
        let removeIt = { templates.removeAll { $0.id == id } }
        guard template.hasContent else { return removeIt() }
        model.confirm(title: "Delete Template", text: "Delete the template \(template.shownTitle)? Invoices made from it stay as they are.",
                      confirm: "Delete", action: removeIt)
    }

    private func binding(_ id: UUID) -> Binding<InvoiceTemplate> {
        Binding(get: { templates.first { $0.id == id } ?? InvoiceTemplate() },
                set: { new in
                    guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
                    templates[index] = new
                })
    }
}

extension InvoiceTemplate {
    /// Whether deleting it would lose anything: a title, or a line with something in it.
    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lines.contains(where: \.hasContent)
    }
}

/// One template's title and lines, edited as the invoice editor edits lines: found by identity, the
/// hourly rate filled in for a line put in hours, and a line with something in it removed only after asking.
private struct TemplateForm: View {
    let model: AppModel
    @Binding var template: InvoiceTemplate

    var body: some View {
        let currency = model.currencyCode
        VStack(alignment: .leading, spacing: 4) {
            Win95FieldRow("Title:") {
                Win95TextField("Template title", text: $template.title, prompt: "e.g. Billing for meeting time")
            }
            HStack(spacing: 4) {
                head("Item", width: nil)
                head("Qty", width: LineColumns.quantity)
                head("Unit", width: LineColumns.unit)
                head("Rate", width: LineColumns.rate)
                Spacer().frame(width: 20)
            }
            ForEach(template.lines) { line in
                let id = line.id
                let edited = lineBinding(id)
                HStack(spacing: 4) {
                    Win95TextField("Template line item", text: edited.title, prompt: "What the work is")
                    CommitField(label: "Template line quantity", value: line.quantity,
                                format: FieldParser.quantityText, parse: FieldParser.quantity) { edited.wrappedValue.quantity = $0 }
                        .frame(width: LineColumns.quantity)
                    Picker("Template line unit", selection: edited.unit) {
                        ForEach(QuotePilotCore.Unit.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: LineColumns.unit)
                    CommitField(label: "Template line rate", value: line.rate,
                                format: { $0.formatted(currencyCode: currency) }, parse: FieldParser.money) { edited.wrappedValue.rate = $0 }
                        .frame(width: LineColumns.rate)
                    SquareButton(PixelGlyph.cross, label: "Remove line") { remove(id) }
                }
            }
            Button("Add Line") { template.lines.append(.blank(hourlyRate: model.library.brand.hourlyRate)) }
                .buttonStyle(.win95)
        }
    }

    private func lineBinding(_ id: UUID) -> Binding<LineItem> {
        Binding(get: { template.lines.first { $0.id == id } ?? LineItem(id: id, title: "", rate: .zero) },
                set: { line in
                    guard let edited = template.lines.replacing(line, id: id, hourlyRate: model.library.brand.hourlyRate,
                                                                editable: true) else { return }
                    template.lines = edited
                })
    }

    private func remove(_ id: UUID) {
        guard let line = template.lines.first(where: { $0.id == id }) else { return }
        let removeIt = { template.lines.removeAll { $0.id == id } }
        guard line.hasContent else { return removeIt() }
        model.confirm(title: "Remove Line", text: "Remove \(line.removalName(showCode: false))?", confirm: "Remove", action: removeIt)
    }

    private func head(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(Win95.small)
            .foregroundStyle(Win95.text)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
