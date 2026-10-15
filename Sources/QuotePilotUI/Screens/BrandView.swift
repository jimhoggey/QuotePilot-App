import AppKit
import QuotePilotCore
import QuotePilotPDF
import SwiftUI

/// Brand: everything documents carry about the business, on four tabs, beside a sample quote that
/// redraws as you change things.
struct BrandView: View {
    enum Tab: Hashable {
        case business, look, documents, emails
    }

    let model: AppModel
    @State private var tab: Tab

    init(model: AppModel, tab: Tab = .business) {
        self.model = model
        self._tab = State(initialValue: tab)
    }

    var body: some View {
        let brand = model.brandBinding
        HStack(alignment: .top, spacing: 8) {
            PropertyTabs(selection: $tab, tabs: [(.business, "Business"), (.look, "Look"),
                                                 (.documents, "Documents"), (.emails, "Emails")]) {
                ScrollView {
                    Group {
                        switch tab {
                        case .business: BusinessTab(brand: brand)
                        case .look: LookTab(model: model, brand: brand)
                        case .documents: DocumentsTab(brand: brand)
                        case .emails: EmailsTab(brand: brand)
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
            .frame(minWidth: 460, idealWidth: 520, maxWidth: 600)
            GroupBox("Sample quote") {
                LivePDFPreview(model: model, content: model.sampleContent())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .groupBoxStyle(.win95)
    }
}

struct BusinessTab: View {
    @Binding var brand: Brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Business") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Name:") { Win95TextField("Business name", text: $brand.businessName) }
                    Win95FieldRow("Details:") { Win95TextEditor(text: $brand.details).frame(height: 70) }
                    Text("Address, email, phone and website, one per line. They print under your name.")
                        .font(Win95.small)
                    Win95FieldRow("ABN:") { Win95TextField("ABN", text: $brand.abn) }
                }
            }
            GroupBox("Payment details") {
                VStack(alignment: .leading, spacing: 4) {
                    Win95TextEditor(text: $brand.paymentDetails)
                        .frame(height: 54)
                    Text("Bank, BSB and account, or PayID. Printed on invoices.")
                        .font(Win95.small)
                }
            }
            GroupBox("GST") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Registered for GST", isOn: $brand.gstRegistered)
                        .toggleStyle(.win95)
                    Text("Off: no GST anywhere. On: new quotes add 10% GST, and invoices say Tax invoice and show your ABN.")
                        .font(Win95.small)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(Win95.text)
    }
}

/// The Brand screen's pickers don't have importers of their own: Choose… asks the model's one open
/// panel (`FileChoice.logo`, `.headingFont`), which RootView shows and `fileChosen` answers.
struct LookTab: View {
    let model: AppModel
    @Binding var brand: Brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Logo") {
                HStack(alignment: .center, spacing: 10) {
                    LogoWell(url: model.logoURL)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(brand.logoFile == nil ? "No logo yet." : "Shown at the top of every document.")
                            .font(Win95.body)
                        HStack(spacing: 6) {
                            Button("Choose…") { model.choosingFile = .logo }
                                .buttonStyle(.win95)
                            Button("Remove") { model.removeLogo() }
                                .buttonStyle(.win95)
                                .disabled(brand.logoFile == nil)
                        }
                        Text("PNG, JPG or PDF. A PDF logo stays sharp at any size.")
                            .font(Win95.small)
                    }
                }
            }
            GroupBox("Hourly rate") {
                HourlyRateField(rate: $brand.hourlyRate, currencyCode: brand.currencyCode)
            }
            GroupBox("Heading font") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.headingFontName ?? "The system font (no heading font chosen).")
                        .font(Win95.body)
                    HStack(spacing: 6) {
                        Button("Choose…") { model.choosingFile = .headingFont }
                            .buttonStyle(.win95)
                        Button("Remove") { model.removeHeadingFont() }
                            .buttonStyle(.win95)
                            .disabled(brand.headingFontFile == nil)
                    }
                    Text("A TTF or OTF file, used for document titles and headings.")
                        .font(Win95.small)
                }
            }
            GroupBox("Accent colour") {
                AccentPicker(hex: $brand.accentHex)
            }
        }
        .foregroundStyle(Win95.text)
    }
}

/// The one hourly rate Quote Pilot remembers, as a single money field. Blank (or $0) means no rate; a
/// rate is from $0 up to the same limit as a line's. Text that isn't an amount is refused with a beep.
struct HourlyRateField: View {
    @Binding var rate: Money?
    let currencyCode: String

    /// What the field shows for a rate: nothing while there is none.
    static func text(_ rate: Money, currencyCode: String) -> String {
        rate == .zero ? "" : rate.formatted(currencyCode: currencyCode)
    }

    /// What the brand keeps for an amount typed in the field: $0 is no rate at all.
    static func stored(_ typed: Money) -> Money? {
        typed == .zero ? nil : typed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Win95FieldRow("Rate:") {
                CommitField(label: "Hourly rate", value: rate ?? .zero,
                            format: { Self.text($0, currencyCode: currencyCode) }, parse: FieldParser.hourlyRate,
                            alignment: .leading, prompt: "e.g. $90.00") { rate = Self.stored($0) }
                    .frame(width: 100)
            }
            Text("With a rate here, new lines start in hours at this rate. You can still change any line.")
                .font(Win95.small)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The logo in a sunken well, or "No logo".
struct LogoWell: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text("No logo")
                    .font(Win95.small)
                    .foregroundStyle(Win95.text)
            }
        }
        .padding(4)
        .frame(width: 96, height: 64)
        .win95Sunken()
    }
}

/// The documents' accent colour: a hex field, its swatch, and a few ready-made choices.
struct AccentPicker: View {
    @Binding var hex: String
    /// Document colours, not window colours: these go on the client's PDFs.
    private static let presets = ["#0B6B66", "#1F2A44", "#7A1F2B", "#2E6B30", "#5B3F8C", "#B85C00"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Swatch(hex: hex)
                    .frame(width: 28, height: 22)
                CommitField(label: "Accent colour", value: hex, format: { $0 }, parse: FieldParser.hex,
                            alignment: .leading) { hex = $0 }
                    .frame(width: 100)
                Text("Six hex digits, like #0B6B66.")
                    .font(Win95.small)
            }
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button { hex = preset } label: {
                        Swatch(hex: preset)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(preset)")
                    .help(preset)
                }
            }
        }
    }
}

struct Swatch: View {
    let hex: String

    var body: some View {
        Rectangle()
            .fill(PDFStyle.color(hex: hex).map { Color(cgColor: $0) } ?? Win95.field)
            .overlay(Bevel(.sunken))
            .accessibilityHidden(true)
    }
}

struct DocumentsTab: View {
    @Binding var brand: Brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Quotes") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Valid for:") {
                        HStack(spacing: 6) {
                            CommitField(label: "Quotes are valid for, in days", value: brand.quoteValidDays,
                                        format: { String($0) }, parse: FieldParser.days) { brand.quoteValidDays = $0 }
                                .frame(width: 60)
                            Text("days")
                        }
                    }
                    Text("Terms printed on quotes:")
                    Win95TextEditor(text: $brand.quoteTerms)
                        .frame(height: 60)
                }
            }
            GroupBox("Invoices") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Payment due:") {
                        HStack(spacing: 6) {
                            CommitField(label: "Payment is due after, in days", value: brand.paymentDueDays,
                                        format: { String($0) }, parse: FieldParser.days) { brand.paymentDueDays = $0 }
                                .frame(width: 60)
                            Text("days")
                        }
                    }
                    Text("Terms printed on invoices:")
                    Win95TextEditor(text: $brand.invoiceTerms)
                        .frame(height: 60)
                }
            }
            GroupBox("Currency") {
                Text("Australian dollars (\(brand.currencyCode))")
            }
        }
        .font(Win95.body)
        .foregroundStyle(Win95.text)
    }
}

struct EmailsTab: View {
    @Binding var brand: Brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NoteBanner("Quote Pilot fills in {client}, {contact}, {number}, {amount}, {due} and {business}. Send by Mail opens a draft with the PDF attached, and you always press Send yourself.")
            template("Quote email", $brand.emails.quote)
            template("Invoice email", $brand.emails.invoice)
            template("Receipt email", $brand.emails.receipt)
        }
    }

    private func template(_ title: String, _ template: Binding<EmailTemplate>) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                Win95FieldRow("Subject:", labelWidth: 64) {
                    Win95TextField("\(title) subject", text: template.subject)
                }
                Win95TextEditor(text: template.body)
                    .frame(height: 110)
            }
        }
    }
}
