import AppKit
import CoreText
import PDFKit
import QuotePilotCore

public enum DocumentRenderer {
    /// Draws a document as PDF data. Quotes also get the tick-box form.
    public static func render(_ content: DocumentContent, style: PDFStyle) -> Data {
        // Drawn twice: the first time only to count the pages, for the footer's "Page 1 of 2". The
        // footer sits in the bottom margin, so it never moves anything else.
        let pageCount = draw(content, style: style, pageCount: nil).layout.writer.pageIndex + 1
        let (data, layout) = draw(content, style: style, pageCount: pageCount)
        guard content.formQuoteNumber != nil else { return data }
        let withWidgets = addForm(layout.fields, to: data, content: content)
        // PDFKit leaves the catalog without an AcroForm, which other viewers need to fill the form.
        if let standard = AcroFormWriter.addingAcroForm(to: withWidgets) { return standard }
        assertionFailure("Couldn't add an AcroForm to the quote PDF; it will only be fillable in Apple's apps")
        return withWidgets
    }

    /// The document's pages, without the form, and the layout that drew them.
    private static func draw(_ content: DocumentContent, style: PDFStyle, pageCount: Int?) -> (data: Data, layout: Layout) {
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
        layout.pageCount = pageCount
        layout.drawAll()
        writer.finish()
        return (data as Data, layout)
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

    /// The narrowest the Qty, Rate and Amount columns get, each with the space before it. Wider
    /// figures (a total in the millions) widen their column, and the description gives way.
    static let qtyColumn: CGFloat = 58
    static let rateColumn: CGFloat = 72
    static let amountColumn: CGFloat = 78
    /// The space kept between a column's widest figure and the column before it.
    static let columnGap: CGFloat = 14

    init(content: DocumentContent, style: PDFStyle, writer: PageWriter) {
        self.content = content
        self.style = style
        self.writer = writer
        tickX = writer.left
        codeX = writer.left + (content.formQuoteNumber != nil ? 22 : 0)
        descX = codeX + (content.showCodes ? 28 : 0)
        func widest(_ texts: [String], _ font: CTFont) -> CGFloat {
            texts.map { PageWriter.width(of: PageWriter.text($0, font, PDFStyle.ink)) }.max() ?? 0
        }
        let label = style.body(7.5, weight: .medium)
        let qty = max(widest(content.rows.map(\.quantity), style.numbers(9.5)), widest(["Qty"], label))
        let rate = max(widest(content.rows.map(\.rate), style.numbers(9.5)), widest(["Rate"], label))
        let amount = max(widest(content.rows.map(\.amount), style.numbers(9.5, weight: .medium)), widest(["Amount"], label))
        amountRight = writer.right
        rateRight = amountRight - max(Self.amountColumn, ceil(amount) + Self.columnGap)
        qtyRight = rateRight - max(Self.rateColumn, ceil(rate) + Self.columnGap)
        descWidth = qtyRight - max(Self.qtyColumn, ceil(qty) + Self.columnGap) - descX
    }

    /// Where the Qty, Rate and Amount columns end, for tests.
    var columnRights: (qty: CGFloat, rate: CGFloat, amount: CGFloat) { (qtyRight, rateRight, amountRight) }
    /// Where the description column starts and how wide it is, for tests.
    var descriptionColumn: (x: CGFloat, width: CGFloat) { (descX, descWidth) }

    /// How many pages the document has, for the footer; nil while that's still being found out.
    var pageCount: Int?

    func drawAll() {
        writer.onNewPage = { [unowned self] _ in
            self.drawContinuationHeader()
            if self.inTable { self.drawTableHeader() }
        }
        writer.onEndPage = { [unowned self] _ in self.drawFooter() }
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
            // A wide logo is held to the width, a tall one to the height; either way the name starts
            // 12 pt under the logo as drawn.
            let room = Self.logoSize
            let drawn = logo.fitted(in: room)
            if drawn.height > 0 {
                logo.draw(in: writer.pdfRect(x: writer.left, top: leftY, width: room.width, height: room.height),
                          context: writer.context)
                leftY += ceil(drawn.height) + 12
            }
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

    /// The most room a logo gets at the top left.
    static let logoSize = CGSize(width: 180, height: 56)

    /// How wide the right-hand column is: the document's details (number, dates) and the totals
    /// start on the same line, and so does the Accepted by date.
    static let rightColumnWidth: CGFloat = 250
    /// The gap kept between the left-hand blocks and the right-hand column.
    static let columnGutter: CGFloat = 20

    /// Where the right-hand column starts.
    var rightColumnX: CGFloat { writer.right - Self.rightColumnWidth }
    /// How wide a left-hand block can be without reaching the right-hand column.
    private var leftColumnWidth: CGFloat { rightColumnX - Self.columnGutter - writer.left }

    private func drawParties() {
        let top = writer.y
        var leftY = top
        let width = leftColumnWidth
        leftY += writer.draw(label(content.toLabel), x: writer.left, top: leftY, width: width) + 2
        if !content.toName.isEmpty {
            leftY += writer.draw(PageWriter.text(content.toName, style.body(10.5, weight: .semibold), PDFStyle.ink),
                                 x: writer.left, top: leftY, width: width) + 1
        }
        if !content.toDetails.isEmpty {
            leftY += writer.draw(PageWriter.text(content.toDetails, style.body(8.5), PDFStyle.muted),
                                 x: writer.left, top: leftY, width: width)
        }
        let metaX = rightColumnX
        let valueX = metaX + 76
        var rightY = top
        for item in content.meta {
            writer.draw(label(item.label), x: metaX, top: rightY + 1.5, width: 74)
            let used = writer.draw(PageWriter.text(item.value, style.body(9.5), PDFStyle.ink), x: valueX, top: rightY,
                                   width: writer.right - valueX)
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
        let numberFont = style.numbers(9.5)
        if content.showCodes {
            writer.draw(PageWriter.text(row.code, numberFont, PDFStyle.muted), x: codeX, top: top, width: 26)
        }
        writer.draw(title, x: descX, top: top, width: descWidth)
        if !row.detail.isEmpty {
            writer.draw(detail, x: descX, top: top + titleHeight + 2, width: descWidth)
        }
        writer.drawRight(PageWriter.text(row.quantity, numberFont, PDFStyle.ink), right: qtyRight, top: top)
        writer.drawRight(PageWriter.text(row.rate, numberFont, PDFStyle.ink), right: rateRight, top: top)
        writer.drawRight(PageWriter.text(row.amount, style.numbers(9.5, weight: .medium), PDFStyle.ink), right: amountRight, top: top)
        writer.y += rowHeight
        writer.rule(top: writer.y - 1, x: writer.left, width: writer.width, color: PDFStyle.rule)
    }

    /// One line of the totals, measured: its label wraps in the room its amount leaves, and the line
    /// is as tall as the label.
    private struct MeasuredTotal {
        var label: NSAttributedString
        var value: NSAttributedString
        var labelWidth: CGFloat
        var step: CGFloat
        var strong: Bool
    }

    private func measuredTotals() -> [MeasuredTotal] {
        let width = writer.right - rightColumnX
        return content.totals.map { total in
            let font = total.strong ? style.body(10.5, weight: .semibold) : style.body(9.5)
            let figures = total.strong ? style.numbers(10.5, weight: .semibold) : style.numbers(9.5)
            let label = PageWriter.text(total.label, font, PDFStyle.ink)
            let value = PageWriter.text(total.value, figures, PDFStyle.ink)
            let labelWidth = width - ceil(PageWriter.width(of: value)) - Self.columnGap
            let height = max(PageWriter.height(of: label, width: labelWidth), PageWriter.lineHeight(font))
            // 15 and 18 points a line, as always, unless the label wraps.
            let step = max(total.strong ? 18 : 15, height + (total.strong ? 5 : 3))
            return MeasuredTotal(label: label, value: value, labelWidth: labelWidth, step: step, strong: total.strong)
        }
    }

    private func drawTotals() {
        let totals = measuredTotals()
        let needed = totals.reduce(CGFloat(26)) { $0 + $1.step + ($1.strong ? 5 : 0) }
        writer.ensureSpace(needed)
        writer.y += 10
        let x = rightColumnX
        for total in totals {
            if total.strong {
                writer.rule(top: writer.y, x: x, width: writer.right - x, color: PDFStyle.ink, thickness: 1)
                writer.y += 5
            }
            writer.draw(total.label, x: x, top: writer.y, width: total.labelWidth)
            writer.drawRight(total.value, right: writer.right, top: writer.y)
            writer.y += total.step
        }
        writer.y += 16
    }

    private func drawAcceptedBy() {
        guard let number = content.formQuoteNumber else { return }
        writer.ensureSpace(70)
        writer.y += writer.draw(PageWriter.text("Accepted by", style.body(10, weight: .semibold), PDFStyle.ink),
                                x: writer.left, top: writer.y, width: 200) + 8
        let top = writer.y
        // The name across the left-hand column, the date at the start of the right-hand one.
        let nameWidth = leftColumnWidth
        let dateX = rightColumnX
        addField(QuoteFormFields.name(number), .text, x: writer.left, top: top, width: nameWidth, height: 18)
        addField(QuoteFormFields.date(number), .text, x: dateX, top: top, width: 120, height: 18)
        writer.rule(top: top + 18, x: writer.left, width: nameWidth, color: PDFStyle.muted)
        writer.rule(top: top + 18, x: dateX, width: 120, color: PDFStyle.muted)
        writer.draw(label("Name"), x: writer.left, top: top + 21, width: 100)
        writer.draw(label("Date"), x: dateX, top: top + 21, width: 100)
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

    /// Where the footer's rule sits, measured down from the top of the page: in the bottom margin,
    /// clear of the last line of the page.
    static var footerRuleTop: CGFloat { PageWriter.pageSize.height - PageWriter.margin + 12 }

    /// The same on every page of every document: a hairline, the business and the document on the
    /// left, the page number on the right.
    private func drawFooter() {
        let top = Self.footerRuleTop
        writer.rule(top: top, x: writer.left, width: writer.width, color: PDFStyle.rule)
        let font = style.body(7.5)
        let document = "\(content.title) \(content.number)"
        let left = content.fromName.trimmed.isEmpty ? document : "\(content.fromName.trimmed)  ·  \(document)"
        let page = "Page \(writer.pageIndex + 1)" + (pageCount.map { " of \($0)" } ?? "")
        let pageText = PageWriter.text(page, font, PDFStyle.muted)
        let pageWidth = ceil(PageWriter.width(of: pageText))
        writer.draw(PageWriter.text(left, font, PDFStyle.muted), x: writer.left, top: top + 5,
                    width: writer.width - pageWidth - Self.columnGap)
        writer.drawRight(pageText, right: writer.right, top: top + 5)
    }

    private func drawContinuationHeader() {
        writer.draw(PageWriter.text("\(content.title) \(content.number), continued", style.body(8.5), PDFStyle.muted),
                    x: writer.left, top: writer.y, width: writer.width)
        writer.y += 22
    }
}

extension DocumentRenderer {
    /// True when quote PDF data carries its fillable form: the quote's Accept-all box, and an AcroForm
    /// in the file. The AcroForm test searches the whole byte stream for "/AcroForm" rather than parsing
    /// the catalog, which is enough for the bytes `render` writes. When `render` can't add an AcroForm,
    /// it falls back to widgets that other viewers can't fill, and this returns false for those.
    /// Checked before a quote goes into a Mail draft, so a form-less quote is never sent by accident.
    public static func hasForm(_ data: Data, quoteNumber: String) -> Bool {
        guard data.range(of: Data("/AcroForm".utf8)) != nil, let document = PDFDocument(data: data) else { return false }
        let acceptAll = QuoteFormFields.acceptAll(quoteNumber)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if page.annotations.contains(where: { $0.fieldName == acceptAll }) { return true }
        }
        return false
    }
}
