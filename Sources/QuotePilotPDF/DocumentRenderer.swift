import AppKit
import CoreText
import PDFKit
import QuotePilotCore

public enum DocumentRenderer {
    /// Draws a document as PDF data. Quotes also get the tick-box form.
    ///
    /// `highlight` is for the Brand screen's sample only: a soft yellow behind wherever that part of
    /// the brand lands, while it's being edited. Real documents never pass one.
    public static func render(_ content: DocumentContent, style: PDFStyle, highlight: BrandElement? = nil) -> Data {
        // Drawn twice: the first time to count the pages, for the footer's "Page 1 of 2", and to
        // find where the highlighted element lands, so the second can draw the highlight behind it.
        // The footer sits in the bottom margin, so it never moves anything else.
        let first = draw(content, style: style, pageCount: nil, highlights: [:]).layout
        let highlights = highlight.map { first.frames(of: $0) } ?? [:]
        let (data, layout) = draw(content, style: style, pageCount: first.writer.pageIndex + 1, highlights: highlights)
        guard content.formQuoteNumber != nil else { return data }
        let withWidgets = addForm(layout.fields, to: data, content: content)
        // PDFKit leaves the catalog without an AcroForm, which other viewers need to fill the form.
        if let standard = AcroFormWriter.addingAcroForm(to: withWidgets) { return standard }
        assertionFailure("Couldn't add an AcroForm to the quote PDF; it will only be fillable in Apple's apps")
        return withWidgets
    }

    /// The document's pages, without the form, and the layout that drew them.
    private static func draw(_ content: DocumentContent, style: PDFStyle, pageCount: Int?,
                             highlights: [Int: [CGRect]]) -> (data: Data, layout: Layout) {
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
        layout.highlights = highlights
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

    /// Rectangles to highlight behind the page's text, by page, measured from the top left.
    var highlights: [Int: [CGRect]] = [:]
    /// Where each part of the brand was drawn: by page, rectangles measured from the top left.
    private var elementFrames: [BrandElement: [Int: [CGRect]]] = [:]

    /// Where `element` was drawn, by page; empty when the document doesn't show it.
    func frames(of element: BrandElement) -> [Int: [CGRect]] { elementFrames[element] ?? [:] }

    private func mark(_ element: BrandElement?, _ rect: CGRect) {
        guard let element, !rect.isNull, rect.width > 0, rect.height > 0 else { return }
        elementFrames[element, default: [:]][writer.pageIndex, default: []].append(rect)
    }

    private func mark(_ element: BrandElement?, lines: [CGRect]) {
        mark(element, lines.reduce(CGRect.null) { $0.union($1) })
    }

    /// The highlight, a little larger than what it marks, with soft corners.
    private func drawHighlights() {
        guard let rects = highlights[writer.pageIndex] else { return }
        writer.context.saveGState()
        writer.context.setFillColor(BrandElement.highlightColor)
        // One path, filled once, so where two boxes overlap the yellow isn't any darker.
        for rect in rects {
            let box = writer.pdfRect(x: rect.minX - 3, top: rect.minY - 2, width: rect.width + 6, height: rect.height + 4)
            writer.context.addPath(CGPath(roundedRect: box, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
        }
        writer.context.fillPath(using: .winding)
        writer.context.restoreGState()
    }

    func drawAll() {
        writer.onBeginPage = { [unowned self] _ in self.drawHighlights() }
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
                mark(.logo, CGRect(x: writer.left, y: leftY, width: drawn.width, height: drawn.height))
                leftY += ceil(drawn.height) + 12
            }
        }
        if !content.fromName.isEmpty {
            let name = PageWriter.text(content.fromName, style.body(13, weight: .semibold), PDFStyle.ink)
            mark(.businessName, lines: PageWriter.lineFrames(of: name, x: writer.left, top: leftY, width: 300))
            leftY += writer.draw(name, x: writer.left, top: leftY, width: 300) + 3
        }
        if !content.fromDetails.isEmpty {
            let details = PageWriter.text(content.fromDetails, style.body(8.5), PDFStyle.muted)
            var lines = PageWriter.lineFrames(of: details, x: writer.left, top: leftY, width: 300)
            // The ABN is the last line, when there is one (`DocumentContent.fromDetails`).
            if content.fromDetails.components(separatedBy: "\n").last?.hasPrefix("ABN ") == true, let abn = lines.popLast() {
                mark(.abn, abn)
            }
            mark(.details, lines: lines)
            leftY += writer.draw(details, x: writer.left, top: leftY, width: 300)
        }
        let titleFont = style.heading(26)
        let title = PageWriter.text(content.title, titleFont, PDFStyle.ink)
        writer.drawRight(title, right: writer.right, top: top)
        let titleWidth = PageWriter.width(of: title)
        mark(.headingFont, CGRect(x: writer.right - titleWidth, y: top, width: titleWidth, height: PageWriter.lineHeight(titleFont)))
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
        var client: [CGRect] = []
        if !content.toName.isEmpty {
            let name = PageWriter.text(content.toName, style.body(10.5, weight: .semibold), PDFStyle.ink)
            client += PageWriter.lineFrames(of: name, x: writer.left, top: leftY, width: width)
            leftY += writer.draw(name, x: writer.left, top: leftY, width: width) + 1
        }
        if !content.toDetails.isEmpty {
            let details = PageWriter.text(content.toDetails, style.body(8.5), PDFStyle.muted)
            client += PageWriter.lineFrames(of: details, x: writer.left, top: leftY, width: width)
            leftY += writer.draw(details, x: writer.left, top: leftY, width: width)
        }
        mark(.bodyFont, lines: client)
        let metaX = rightColumnX
        let valueX = metaX + 76
        var rightY = top
        for item in content.meta {
            writer.draw(label(item.label), x: metaX, top: rightY + 1.5, width: 74)
            let value = PageWriter.text(item.value, style.body(9.5), PDFStyle.ink)
            let lines = PageWriter.lineFrames(of: value, x: valueX, top: rightY, width: writer.right - valueX)
            mark(item.source, lines: lines + [CGRect(x: metaX, y: rightY + 1.5, width: 1, height: 9)])
            let used = writer.draw(value, x: valueX, top: rightY, width: writer.right - valueX)
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
        let amountFrame = PageWriter.lineFrames(of: amount, x: writer.left, top: writer.y, width: writer.width)
        mark(.headingFont, lines: amountFrame)
        mark(.accentColour, lines: amountFrame)
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

    /// How tall the column labels and their rule are.
    private static let tableHeaderHeight: CGFloat = 17

    private func drawTable() {
        // The column labels never end a page: they go over with the first line if it won't fit.
        writer.ensureSpace(Self.tableHeaderHeight + (content.rows.first.map(rowHeight) ?? 0))
        drawTableHeader()
        inTable = true
        for row in content.rows { drawRow(row) }
        inTable = false
    }

    private func rowTexts(_ row: DocumentContent.Row) -> (title: NSAttributedString, detail: NSAttributedString) {
        // Pasted wording wraps between words here too, as in the sections.
        (PageWriter.wrapping(PageWriter.text(Self.printable(row.title), style.body(9.5, weight: .medium), PDFStyle.ink)),
         PageWriter.wrapping(PageWriter.text(Self.printable(row.detail), style.body(8.5), PDFStyle.muted)))
    }

    private func rowHeight(_ row: DocumentContent.Row) -> CGFloat {
        let (title, detail) = rowTexts(row)
        let detailHeight = row.detail.isEmpty ? 0 : PageWriter.height(of: detail, width: descWidth) + 2
        return max(PageWriter.height(of: title, width: descWidth) + detailHeight, 14) + 14
    }

    private func drawRow(_ row: DocumentContent.Row) {
        let (title, detail) = rowTexts(row)
        let titleHeight = PageWriter.height(of: title, width: descWidth)
        let rowHeight = rowHeight(row)
        writer.ensureSpace(rowHeight)

        let top = writer.y + 7
        if let number = content.formQuoteNumber {
            addField(QuoteFormFields.line(number, row.code), .checkbox, x: tickX, top: top, width: 12, height: 12)
        }
        let numberFont = style.numbers(9.5)
        if content.showCodes {
            writer.draw(PageWriter.text(row.code, numberFont, PDFStyle.muted), x: codeX, top: top, width: 26)
        }
        var words = PageWriter.lineFrames(of: title, x: descX, top: top, width: descWidth)
        writer.draw(title, x: descX, top: top, width: descWidth)
        if !row.detail.isEmpty {
            words += PageWriter.lineFrames(of: detail, x: descX, top: top + titleHeight + 2, width: descWidth)
            writer.draw(detail, x: descX, top: top + titleHeight + 2, width: descWidth)
        }
        mark(.bodyFont, lines: words)
        writer.drawRight(PageWriter.text(row.quantity, numberFont, PDFStyle.ink), right: qtyRight, top: top)
        let rate = PageWriter.text(row.rate, numberFont, PDFStyle.ink)
        let rateWidth = PageWriter.width(of: rate)
        mark(row.rateSource, CGRect(x: rateRight - rateWidth, y: top, width: rateWidth, height: PageWriter.lineHeight(numberFont)))
        writer.drawRight(rate, right: rateRight, top: top)
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

    /// One paragraph of a section: its text, and whether it's a dot point.
    struct Paragraph: Equatable {
        var text: String
        var isBullet: Bool
    }

    /// What starts a dot point: a dash of any length, a bullet or an asterisk, with or without a
    /// space after it.
    static let bulletMarkers: Set<Character> = ["-", "–", "—", "•", "*"]

    /// A section's paragraphs, one per line of its text; nil for a blank line. A marker alone on its
    /// line (as a two-column web page pastes its dot points) is dropped, not printed.
    static func paragraphs(_ text: String) -> [Paragraph?] {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        return unified.components(separatedBy: "\n").compactMap { paragraph -> Paragraph?? in
            let line = printable(paragraph).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return .some(nil) }
            guard let first = line.first, bulletMarkers.contains(first) else { return Paragraph(text: line, isBullet: false) }
            let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return Paragraph??.none }
            return Paragraph(text: rest, isBullet: true)
        }
    }

    /// Text as it should wrap: spaces that forbid a line break (pasted from web pages as
    /// non-breaking spaces) become plain spaces, and invisible break points and soft hyphens go,
    /// so lines break between words and never inside one.
    static func printable(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x00AD, 0x200B, 0x2060, 0xFEFF:
                continue
            default:
                scalars.append(scalar.properties.generalCategory == .spaceSeparator ? " " : scalar)
            }
        }
        return String(scalars)
    }

    private static let bulletIndent: CGFloat = 12

    private func paragraphText(_ paragraph: Paragraph) -> NSAttributedString {
        PageWriter.wrapping(PageWriter.text(paragraph.text, style.body(9), PDFStyle.ink))
    }

    private func paragraphLines(_ paragraph: Paragraph) -> [PageWriter.Line] {
        PageWriter.lines(of: paragraphText(paragraph), width: writer.width - (paragraph.isBullet ? Self.bulletIndent : 0))
    }

    /// The height of a paragraph's first two lines (all of it when shorter): the least of it that
    /// starts on a page.
    private func openingHeight(_ paragraph: Paragraph) -> CGFloat {
        let lines = paragraphLines(paragraph)
        return lines.prefix(2).last?.bottom ?? 0
    }

    private func drawSections() {
        for section in content.sections {
            let heading = PageWriter.text(section.heading, style.body(10, weight: .semibold), PDFStyle.ink)
            let headingHeight = PageWriter.height(of: heading, width: writer.width)
            let parts = Self.paragraphs(section.text)
            // A heading never ends a page: it goes over with the start of its first paragraph.
            let first = parts.lazy.compactMap { $0 }.first.map(openingHeight) ?? 0
            writer.ensureSpace(6 + headingHeight + 4 + first)
            writer.y += 6
            mark(section.source, lines: PageWriter.lineFrames(of: heading, x: writer.left, top: writer.y, width: writer.width))
            writer.draw(heading, x: writer.left, top: writer.y, width: writer.width)
            writer.y += headingHeight + 4
            for part in parts {
                guard let paragraph = part else {
                    writer.y += 5
                    continue
                }
                drawParagraph(paragraph, source: section.source)
                writer.y += 2
            }
            writer.y += 10
        }
    }

    /// A paragraph, line by line, so a long one carries on at the top of the next page with its
    /// wrapping and indent. It never leaves its first line alone at the foot of a page, nor its last
    /// line alone at the top of the next.
    private func drawParagraph(_ paragraph: Paragraph, source: BrandElement?) {
        let lines = paragraphLines(paragraph)
        let indent: CGFloat = paragraph.isBullet ? Self.bulletIndent : 0
        let x = writer.left + indent
        var start = 0
        while start < lines.count {
            let offset = lines[start].top
            let pageTop = writer.y
            // How many of the remaining lines fit on this page.
            var count = 0
            while start + count < lines.count, pageTop + lines[start + count].bottom - offset <= writer.bottom { count += 1 }
            let remaining = lines.count - start
            let atTopOfPage = writer.isAtTopOfPage
            if count < remaining {
                if remaining - count == 1 && count > 1 { count -= 1 }            // no lone last line over the page
                if count == 1 && start == 0 && !atTopOfPage { count = 0 }        // no lone first line at the foot
            }
            if count == 0 {
                if atTopOfPage { count = 1 } else { writer.newPage(); continue }
            }
            if start == 0 && paragraph.isBullet {
                writer.draw(PageWriter.text("•", style.body(9), style.accent), x: writer.left + 2, top: writer.y, width: 10)
            }
            var frames: [CGRect] = []
            for line in lines[start..<(start + count)] {
                writer.draw(line, x: x, textTop: pageTop - offset)
                frames.append(CGRect(x: x + line.x, y: pageTop - offset + line.baseline - line.ascent,
                                     width: line.width, height: line.ascent + line.descent))
            }
            // A dot point's highlight takes in its dot.
            let dot = start == 0 && paragraph.isBullet ? [CGRect(x: writer.left + 2, y: pageTop, width: 1, height: 1)] : []
            mark(source, lines: frames + dot)
            mark(.bodyFont, lines: frames)
            writer.y = pageTop + lines[start + count - 1].bottom - offset
            start += count
            if start < lines.count { writer.newPage() }
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
