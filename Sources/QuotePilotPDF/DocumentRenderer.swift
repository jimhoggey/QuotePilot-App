import AppKit
import CoreText
import PDFKit
import QuotePilotCore

public enum DocumentRenderer {
    /// Draws a document as PDF data. Quotes also get the tick-box form.
    public static func render(_ content: DocumentContent, style: PDFStyle) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: PageWriter.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "\(content.title) \(content.number)",
            kCGPDFContextCreator: "Quote Pilot",
            kCGPDFContextAuthor: content.fromName,
            kCGPDFContextKeywords: ["quotepilot", content.number],
        ]
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)!
        let writer = PageWriter(context: context)
        let layout = Layout(content: content, style: style, writer: writer)
        layout.drawAll()
        writer.finish()
        guard content.formQuoteNumber != nil else { return data as Data }
        let withWidgets = addForm(layout.fields, to: data as Data, content: content)
        // PDFKit leaves the catalog without an AcroForm, which other viewers need to fill the form.
        if let standard = AcroFormWriter.addingAcroForm(to: withWidgets) { return standard }
        assertionFailure("Couldn't add an AcroForm to the quote PDF; it will only be fillable in Apple's apps")
        return withWidgets
    }

    /// Adds the form widgets PDFKit-side, where the drawing recorded them.
    static func addForm(_ fields: [PlacedField], to data: Data, content: DocumentContent) -> Data {
        guard let document = PDFDocument(data: data) else { return data }
        let ink = NSColor(cgColor: PDFStyle.ink) ?? .black
        // A standard font, so each widget's default appearance names something every PDF viewer has.
        // The system font's name (".AppleSystemUIFont") only Apple's apps can resolve.
        let fieldFont = NSFont(name: "Helvetica", size: 10) ?? NSFont.systemFont(ofSize: 10)
        for field in fields {
            guard let page = document.page(at: field.page) else { continue }
            let widget = PDFAnnotation(bounds: field.rect, forType: .widget, withProperties: nil)
            switch field.kind {
            case .checkbox:
                widget.widgetFieldType = .button
                widget.widgetControlType = .checkBoxControl
                widget.buttonWidgetState = .offState
                widget.font = fieldFont
                widget.backgroundColor = .white
                let border = PDFBorder()
                border.lineWidth = 1
                widget.border = border
                widget.color = ink
            case .text:
                widget.widgetFieldType = .text
                widget.backgroundColor = NSColor(white: 0.96, alpha: 1)
                widget.font = fieldFont
                widget.fontColor = ink
            }
            // Named after the field type is set: setting the type resets the name, and PDFKit then
            // falls back to "button0", "text0", … which would hide which quote and line a box is for.
            widget.fieldName = field.name
            page.addAnnotation(widget)
        }
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "\(content.title) \(content.number)",
            PDFDocumentAttribute.creatorAttribute: "Quote Pilot",
            PDFDocumentAttribute.authorAttribute: content.fromName,
            PDFDocumentAttribute.keywordsAttribute: ["quotepilot", content.number],
        ]
        return document.dataRepresentation() ?? data
    }
}

/// A form field the layout placed; PDFKit adds the real widget afterwards.
struct PlacedField: Equatable {
    enum Kind { case checkbox, text }
    var name: String
    var kind: Kind
    var page: Int
    var rect: CGRect
}

/// Lays out one document: header, parties, amount, line table, totals, form, sections.
final class Layout {
    let content: DocumentContent
    let style: PDFStyle
    let writer: PageWriter
    private(set) var fields: [PlacedField] = []
    private var inTable = false

    // Line-table columns, measured from the left of the page.
    private let tickX: CGFloat
    private let codeX: CGFloat
    private let descX: CGFloat
    private let descWidth: CGFloat
    private let qtyRight: CGFloat
    private let rateRight: CGFloat
    private let amountRight: CGFloat

    init(content: DocumentContent, style: PDFStyle, writer: PageWriter) {
        self.content = content
        self.style = style
        self.writer = writer
        tickX = writer.left
        codeX = writer.left + (content.formQuoteNumber != nil ? 22 : 0)
        descX = codeX + (content.showCodes ? 28 : 0)
        amountRight = writer.right
        rateRight = amountRight - 78
        qtyRight = rateRight - 72
        descWidth = qtyRight - 58 - descX
    }

    func drawAll() {
        writer.onNewPage = { [unowned self] _ in
            self.drawContinuationHeader()
            if self.inTable { self.drawTableHeader() }
        }
        writer.newPage()
        drawHeader()
        drawParties()
        drawAmount()
        drawAcceptAll()
        drawTable()
        drawTotals()
        drawAcceptedBy()
        drawSections()
    }

    private func label(_ text: String) -> NSAttributedString {
        PageWriter.text(text, style.body(7.5, weight: .medium), PDFStyle.muted)
    }

    private func addField(_ name: String, _ kind: PlacedField.Kind, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) {
        fields.append(PlacedField(name: name, kind: kind, page: writer.pageIndex,
                                  rect: writer.pdfRect(x: x, top: top, width: width, height: height)))
    }

    private func drawHeader() {
        let top = writer.y
        var leftY = top
        if let logo = style.logo {
            logo.draw(in: writer.pdfRect(x: writer.left, top: leftY, width: 180, height: 44), context: writer.context)
            leftY += 44 + 12
        }
        if !content.fromName.isEmpty {
            leftY += writer.draw(PageWriter.text(content.fromName, style.body(13, weight: .semibold), PDFStyle.ink),
                                 x: writer.left, top: leftY, width: 300) + 3
        }
        if !content.fromDetails.isEmpty {
            leftY += writer.draw(PageWriter.text(content.fromDetails, style.body(8.5), PDFStyle.muted),
                                 x: writer.left, top: leftY, width: 300)
        }
        let titleFont = style.heading(26)
        writer.drawRight(PageWriter.text(content.title, titleFont, PDFStyle.ink), right: writer.right, top: top)
        writer.y = max(leftY, top + PageWriter.lineHeight(titleFont)) + 28
    }

    private func drawParties() {
        let top = writer.y
        var leftY = top
        leftY += writer.draw(label(content.toLabel), x: writer.left, top: leftY, width: 240) + 2
        if !content.toName.isEmpty {
            leftY += writer.draw(PageWriter.text(content.toName, style.body(10.5, weight: .semibold), PDFStyle.ink),
                                 x: writer.left, top: leftY, width: 240) + 1
        }
        if !content.toDetails.isEmpty {
            leftY += writer.draw(PageWriter.text(content.toDetails, style.body(8.5), PDFStyle.muted),
                                 x: writer.left, top: leftY, width: 240)
        }
        let metaX = writer.right - 230
        var rightY = top
        for item in content.meta {
            writer.draw(label(item.label), x: metaX, top: rightY + 1.5, width: 74)
            let used = writer.draw(PageWriter.text(item.value, style.body(9.5), PDFStyle.ink), x: metaX + 76, top: rightY, width: 154)
            rightY += max(used, 12) + 3
        }
        writer.y = max(leftY, rightY) + 22
    }

    private func drawAmount() {
        writer.rule(top: writer.y, x: writer.left, width: writer.width, color: PDFStyle.rule)
        writer.y += 14
        writer.y += writer.draw(label(content.amountLabel), x: writer.left, top: writer.y, width: writer.width) + 2
        let amountFont = style.heading(30)
        let amount = PageWriter.text(content.amount, amountFont, style.accent)
        writer.draw(amount, x: writer.left, top: writer.y, width: writer.width)
        let noteFont = style.body(9.5)
        let noteX = writer.left + PageWriter.width(of: amount) + 14
        writer.draw(PageWriter.text(content.amountNote, noteFont, PDFStyle.muted), x: noteX,
                    top: writer.y + CTFontGetAscent(amountFont) - CTFontGetAscent(noteFont),
                    width: writer.right - noteX)
        writer.y += PageWriter.lineHeight(amountFont) + 20
    }

    private func drawAcceptAll() {
        guard let number = content.formQuoteNumber else { return }
        writer.ensureSpace(60)
        addField(QuoteFormFields.acceptAll(number), .checkbox, x: writer.left, top: writer.y, width: 12, height: 12)
        writer.draw(PageWriter.text("Accept all", style.body(10, weight: .semibold), PDFStyle.ink),
                    x: writer.left + 20, top: writer.y - 0.5, width: 200)
        writer.y += 16
        let instruction = "Tick the lines you'd like to go ahead with, or Accept all. Add your name and the date at the bottom, then save this PDF and send it back."
        writer.y += writer.draw(PageWriter.text(instruction, style.body(8.5), PDFStyle.muted),
                                x: writer.left + 20, top: writer.y, width: writer.width - 20) + 14
    }

    private func drawTableHeader() {
        let top = writer.y
        if content.showCodes { writer.draw(label("ID"), x: codeX, top: top, width: 26) }
        writer.draw(label("Description"), x: descX, top: top, width: descWidth)
        writer.drawRight(label("Qty"), right: qtyRight, top: top)
        writer.drawRight(label("Rate"), right: rateRight, top: top)
        writer.drawRight(label("Amount"), right: amountRight, top: top)
        writer.y += 13
        writer.rule(top: writer.y, x: writer.left, width: writer.width, color: PDFStyle.ink, thickness: 1)
        writer.y += 4
    }

    private func drawTable() {
        writer.ensureSpace(60)
        drawTableHeader()
        inTable = true
        for row in content.rows { drawRow(row) }
        inTable = false
    }

    private func drawRow(_ row: DocumentContent.Row) {
        let title = PageWriter.text(row.title, style.body(9.5, weight: .medium), PDFStyle.ink)
        let detail = PageWriter.text(row.detail, style.body(8.5), PDFStyle.muted)
        let titleHeight = PageWriter.height(of: title, width: descWidth)
        let detailHeight = row.detail.isEmpty ? 0 : PageWriter.height(of: detail, width: descWidth) + 2
        let rowHeight = max(titleHeight + detailHeight, 14) + 14
        writer.ensureSpace(rowHeight)

        let top = writer.y + 7
        if let number = content.formQuoteNumber {
            addField(QuoteFormFields.line(number, row.code), .checkbox, x: tickX, top: top, width: 12, height: 12)
        }
        let numberFont = style.body(9.5)
        if content.showCodes {
            writer.draw(PageWriter.text(row.code, numberFont, PDFStyle.muted), x: codeX, top: top, width: 26)
        }
        writer.draw(title, x: descX, top: top, width: descWidth)
        if !row.detail.isEmpty {
            writer.draw(detail, x: descX, top: top + titleHeight + 2, width: descWidth)
        }
        writer.drawRight(PageWriter.text(row.quantity, numberFont, PDFStyle.ink), right: qtyRight, top: top)
        writer.drawRight(PageWriter.text(row.rate, numberFont, PDFStyle.ink), right: rateRight, top: top)
        writer.drawRight(PageWriter.text(row.amount, style.body(9.5, weight: .medium), PDFStyle.ink), right: amountRight, top: top)
        writer.y += rowHeight
        writer.rule(top: writer.y - 1, x: writer.left, width: writer.width, color: PDFStyle.rule)
    }

    private func drawTotals() {
        let needed = content.totals.reduce(CGFloat(26)) { $0 + ($1.strong ? 23 : 15) }
        writer.ensureSpace(needed)
        writer.y += 10
        let x = writer.right - 250
        for total in content.totals {
            let font = total.strong ? style.body(10.5, weight: .semibold) : style.body(9.5)
            if total.strong {
                writer.rule(top: writer.y, x: x, width: 250, color: PDFStyle.ink, thickness: 1)
                writer.y += 5
            }
            writer.draw(PageWriter.text(total.label, font, PDFStyle.ink), x: x, top: writer.y, width: 170)
            writer.drawRight(PageWriter.text(total.value, font, PDFStyle.ink), right: writer.right, top: writer.y)
            writer.y += total.strong ? 18 : 15
        }
        writer.y += 16
    }

    private func drawAcceptedBy() {
        guard let number = content.formQuoteNumber else { return }
        writer.ensureSpace(70)
        writer.y += writer.draw(PageWriter.text("Accepted by", style.body(10, weight: .semibold), PDFStyle.ink),
                                x: writer.left, top: writer.y, width: 200) + 8
        let top = writer.y
        addField(QuoteFormFields.name(number), .text, x: writer.left, top: top, width: 240, height: 18)
        addField(QuoteFormFields.date(number), .text, x: writer.left + 260, top: top, width: 120, height: 18)
        writer.rule(top: top + 18, x: writer.left, width: 240, color: PDFStyle.muted)
        writer.rule(top: top + 18, x: writer.left + 260, width: 120, color: PDFStyle.muted)
        writer.draw(label("Name"), x: writer.left, top: top + 21, width: 100)
        writer.draw(label("Date"), x: writer.left + 260, top: top + 21, width: 100)
        writer.y = top + 43
    }

    private func drawSections() {
        for section in content.sections {
            writer.ensureSpace(40)
            writer.y += 6
            writer.y += writer.draw(PageWriter.text(section.heading, style.body(10, weight: .semibold), PDFStyle.ink),
                                    x: writer.left, top: writer.y, width: writer.width) + 4
            for paragraph in section.text.components(separatedBy: "\n") {
                let line = paragraph.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    writer.y += 5
                    continue
                }
                let isBullet = line.hasPrefix("- ") || line.hasPrefix("• ")
                let text = PageWriter.text(isBullet ? String(line.dropFirst(2)) : line, style.body(9), PDFStyle.ink)
                let indent: CGFloat = isBullet ? 12 : 0
                let height = PageWriter.height(of: text, width: writer.width - indent)
                writer.ensureSpace(height)
                if isBullet {
                    writer.draw(PageWriter.text("•", style.body(9), style.accent), x: writer.left + 2, top: writer.y, width: 10)
                }
                writer.draw(text, x: writer.left + indent, top: writer.y, width: writer.width - indent)
                writer.y += height + 2
            }
            writer.y += 10
        }
    }

    private func drawContinuationHeader() {
        writer.draw(PageWriter.text("\(content.title) \(content.number), continued", style.body(8.5), PDFStyle.muted),
                    x: writer.left, top: writer.y, width: writer.width)
        writer.y += 22
    }
}
