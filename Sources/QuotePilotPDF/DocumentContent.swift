import Foundation
import QuotePilotCore

/// Everything a document's pages show, already worded and formatted.
public struct DocumentContent: Equatable {
    public struct Meta: Equatable {
        public var label: String
        public var value: String
    }

    public struct Row: Equatable {
        public var code: String
        public var title: String
        public var detail: String
        public var quantity: String
        public var rate: String
        public var amount: String
    }

    public struct TotalLine: Equatable {
        public var label: String
        public var value: String
        public var strong: Bool
    }

    public struct Section: Equatable {
        public var heading: String
        /// Lines starting with "- " print as dot points.
        public var text: String
    }

    public var title: String
    public var number: String
    public var fromName: String
    public var fromDetails: String
    public var toLabel: String
    public var toName: String
    public var toDetails: String
    public var meta: [Meta]
    public var amountLabel: String
    public var amount: String
    public var amountNote: String
    /// Quotes show each line's ID.
    public var showCodes: Bool
    public var rows: [Row]
    public var totals: [TotalLine]
    public var sections: [Section]
    /// Quotes only: draw the tick-box form for this quote number.
    public var formQuoteNumber: String?
    public var fileName: String
}

extension DocumentContent {
    public static func quote(_ quote: Quote, client: Client?, brand: Brand) -> DocumentContent {
        let currency = brand.currencyCode
        let totals = quote.totals
        var totalLines: [TotalLine] = []
        if quote.taxed {
            totalLines.append(TotalLine(label: "Subtotal", value: totals.subtotal.formatted(currencyCode: currency), strong: false))
            totalLines.append(TotalLine(label: "GST (10%)", value: totals.gst.formatted(currencyCode: currency), strong: false))
        }
        totalLines.append(TotalLine(label: "Total (\(currency))", value: totals.total.formatted(currencyCode: currency), strong: true))

        var meta = [Meta(label: "Quote no.", value: quote.number),
                    Meta(label: "Issued", value: quote.issued.long),
                    Meta(label: "Valid until", value: quote.validUntil.long)]
        if !quote.title.trimmed.isEmpty { meta.append(Meta(label: "Reference", value: quote.title)) }

        var sections: [Section] = []
        if !quote.summary.trimmed.isEmpty { sections.append(Section(heading: "Work summary", text: quote.summary)) }
        sections.append(Section(heading: "Payment plan",
                                text: "\(quote.plan.summary). You're only invoiced for the lines you accept."))
        if !quote.terms.trimmed.isEmpty { sections.append(Section(heading: "Terms", text: quote.terms)) }

        return DocumentContent(
            title: "Quote", number: quote.number,
            fromName: brand.businessName, fromDetails: fromDetails(brand, taxed: quote.taxed),
            toLabel: "Prepared for", toName: client?.name ?? "", toDetails: clientDetails(client),
            meta: meta,
            amountLabel: "Quote total (\(currency))",
            amount: totals.total.formatted(currencyCode: currency),
            amountNote: "Valid until \(quote.validUntil.long)",
            showCodes: true,
            rows: quote.lines.map { row($0, currency) },
            totals: totalLines,
            sections: sections,
            formQuoteNumber: quote.number,
            fileName: fileName(quote.number, client))
    }

    public static func invoice(_ invoice: Invoice, client: Client?, brand: Brand, quoteNumber: String?) -> DocumentContent {
        let currency = brand.currencyCode
        func money(_ amount: Money) -> String { amount.formatted(currencyCode: currency) }
        let lineTotals = invoice.lineTotals

        var totals: [TotalLine] = []
        if invoice.taxed {
            totals.append(TotalLine(label: "Subtotal", value: money(lineTotals.subtotal), strong: false))
            totals.append(TotalLine(label: "GST (10%)", value: money(lineTotals.gst), strong: false))
        }
        switch invoice.kind {
        case .deposit:
            totals.append(TotalLine(label: "Accepted total", value: money(lineTotals.total), strong: false))
            totals.append(TotalLine(label: "Deposit (\(invoice.depositPercent ?? 50)%)", value: money(invoice.amount), strong: true))
        case .final where !invoice.deductions.isEmpty:
            totals.append(TotalLine(label: "Accepted total", value: money(lineTotals.total), strong: false))
            for deduction in invoice.deductions {
                totals.append(TotalLine(label: "\(deduction.label), \(deduction.invoiceNumber)",
                                        value: "−" + money(deduction.amount), strong: false))
            }
            totals.append(TotalLine(label: "Balance (\(currency))", value: money(invoice.amount), strong: true))
        default:
            totals.append(TotalLine(label: "Total (\(currency))", value: money(invoice.amount), strong: true))
        }
        if invoice.paid > .zero {
            totals.append(TotalLine(label: "Paid", value: "−" + money(invoice.paid), strong: false))
            totals.append(TotalLine(label: "Amount due (\(currency))", value: money(invoice.owing), strong: true))
        }

        var meta = [Meta(label: "Invoice no.", value: invoice.number),
                    Meta(label: "Issued", value: invoice.issued.long),
                    Meta(label: "Due", value: invoice.due.long)]
        if let quoteNumber { meta.append(Meta(label: "Quote", value: quoteNumber)) }
        if !invoice.title.trimmed.isEmpty { meta.append(Meta(label: "Reference", value: invoice.title)) }

        var sections: [Section] = []
        if !brand.paymentDetails.trimmed.isEmpty { sections.append(Section(heading: "Payment details", text: brand.paymentDetails)) }
        if !invoice.terms.trimmed.isEmpty { sections.append(Section(heading: "Terms", text: invoice.terms)) }

        let paidUp = invoice.paid > .zero && invoice.owing <= .zero
        return DocumentContent(
            title: invoice.taxed ? "Tax invoice" : "Invoice", number: invoice.number,
            fromName: brand.businessName, fromDetails: fromDetails(brand, taxed: invoice.taxed),
            toLabel: "Billed to", toName: client?.name ?? "", toDetails: clientDetails(client),
            meta: meta,
            amountLabel: paidUp ? "Paid in full" : "Amount due (\(currency))",
            amount: money(paidUp ? invoice.amount : invoice.owing),
            amountNote: paidUp ? "Thank you" : "Due \(invoice.due.long)",
            showCodes: false,
            rows: invoice.lines.map { row($0, currency) },
            totals: totals,
            sections: sections,
            formQuoteNumber: nil,
            fileName: fileName(invoice.number, client))
    }

    public static func receipt(_ invoice: Invoice, client: Client?, brand: Brand) -> DocumentContent {
        let currency = brand.currencyCode
        func money(_ amount: Money) -> String { amount.formatted(currencyCode: currency) }

        var totals = [TotalLine(label: "Invoice total", value: money(invoice.amount), strong: false)]
        for payment in invoice.payments.sorted(by: { $0.date < $1.date }) {
            totals.append(TotalLine(label: "Paid \(payment.date.short), \(payment.method.label.lowercased())",
                                    value: money(payment.amount), strong: false))
        }
        let owing = max(invoice.owing, .zero)
        totals.append(TotalLine(label: owing > .zero ? "Still owing (\(currency))" : "Balance (\(currency))",
                                value: money(owing), strong: true))

        var meta = [Meta(label: "Receipt for", value: invoice.number)]
        if let latest = invoice.payments.map(\.date).max() { meta.append(Meta(label: "Date", value: latest.long)) }
        meta.append(Meta(label: "Invoice issued", value: invoice.issued.long))

        return DocumentContent(
            title: "Receipt", number: invoice.number,
            fromName: brand.businessName, fromDetails: fromDetails(brand, taxed: invoice.taxed),
            toLabel: "Received from", toName: client?.name ?? "", toDetails: clientDetails(client),
            meta: meta,
            amountLabel: "Total paid (\(currency))",
            amount: money(invoice.paid),
            amountNote: owing > .zero ? "\(money(owing)) still owing" : "Paid in full. Thank you.",
            showCodes: false,
            rows: invoice.lines.map { row($0, currency) },
            totals: totals,
            sections: [],
            formQuoteNumber: nil,
            fileName: fileName("Receipt \(invoice.number)", client))
    }

    static func row(_ line: LineItem, _ currency: String) -> Row {
        Row(code: line.code, title: line.title, detail: line.detail,
            quantity: line.unit.describe(line.quantity),
            rate: line.rate.formatted(currencyCode: currency),
            amount: line.amount.formatted(currencyCode: currency))
    }

    static func fromDetails(_ brand: Brand, taxed: Bool) -> String {
        var parts = [brand.details.trimmed].filter { !$0.isEmpty }
        if taxed && !brand.abn.trimmed.isEmpty { parts.append("ABN \(brand.abn.trimmed)") }
        return parts.joined(separator: "\n")
    }

    static func clientDetails(_ client: Client?) -> String {
        guard let client else { return "" }
        return [client.contactName, client.address, client.email]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// "Q-0001 Sample Client Pty Ltd.pdf", with characters Finder dislikes swapped for dashes.
    static func fileName(_ prefix: String, _ client: Client?) -> String {
        let name = [prefix, client?.name.trimmed ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".pdf"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
