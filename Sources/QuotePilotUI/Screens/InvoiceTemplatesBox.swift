import QuotePilotCore
import SwiftUI

/// Brand → Documents' invoice templates: choose one to change its title and lines, or start a new
/// one. New Invoice in the toolbar offers them once there are any. The lines are a compact table
/// (item, quantity, unit, rate), as the tab shares the window with the sample preview.
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
                    let template = InvoiceTemplate(lines: [blankLine])
                    templates.append(template)
                    chosenID = template.id
                }
                Button("Delete Template") { templates.removeAll { $0.id == shownID } }
                    .disabled(shownID == nil)
            }
            .buttonStyle(.win95)
            if let id = shownID {
                TemplateForm(template: binding(id), currency: model.currencyCode, blankLine: blankLine)
            }
            Text(templates.isEmpty
                 ? "A template starts an invoice with its title and lines filled in, such as \"Billing for meeting time\" with an hour of meeting time."
                 : "New Invoice in the toolbar offers your templates. Each invoice still gets its own client and dates.")
                .font(Win95.small)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blankLine: LineItem { .blank(hourlyRate: model.library.brand.hourlyRate) }

    private func binding(_ id: UUID) -> Binding<InvoiceTemplate> {
        Binding(get: { templates.first { $0.id == id } ?? InvoiceTemplate() },
                set: { new in
                    guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
                    templates[index] = new
                })
    }
}

/// One template's title and lines.
private struct TemplateForm: View {
    @Binding var template: InvoiceTemplate
    let currency: String
    let blankLine: LineItem

    var body: some View {
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
            ForEach($template.lines) { $line in
                HStack(spacing: 4) {
                    Win95TextField("Template line item", text: $line.title, prompt: "What the work is")
                    CommitField(label: "Template line quantity", value: line.quantity,
                                format: FieldParser.quantityText, parse: FieldParser.quantity) { line.quantity = $0 }
                        .frame(width: LineColumns.quantity)
                    Picker("Template line unit", selection: $line.unit) {
                        ForEach(QuotePilotCore.Unit.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: LineColumns.unit)
                    CommitField(label: "Template line rate", value: line.rate,
                                format: { $0.formatted(currencyCode: currency) }, parse: FieldParser.money) { line.rate = $0 }
                        .frame(width: LineColumns.rate)
                    SquareButton(PixelGlyph.cross, label: "Remove line") { template.lines.removeAll { $0.id == line.id } }
                }
            }
            Button("Add Line") { template.lines.append(blankLine) }
                .buttonStyle(.win95)
        }
    }

    private func head(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(Win95.small)
            .foregroundStyle(Win95.text)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
