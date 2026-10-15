import AppKit
import CoreText

/// Draws A4 pages from the top down with Core Text, starting a new page when space runs out.
final class PageWriter {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 46

    let context: CGContext
    private(set) var pageIndex = -1
    /// Distance from the top of the page to where the next thing goes.
    var y: CGFloat = 0
    /// Runs at the top of every page after the first, e.g. to repeat the table header.
    var onNewPage: ((PageWriter) -> Void)?

    init(context: CGContext) {
        self.context = context
    }

    var left: CGFloat { Self.margin }
    var width: CGFloat { Self.pageSize.width - 2 * Self.margin }
    var right: CGFloat { left + width }
    var bottom: CGFloat { Self.pageSize.height - Self.margin }

    func newPage() {
        if pageIndex >= 0 { context.endPDFPage() }
        context.beginPDFPage(nil)
        context.textMatrix = .identity
        pageIndex += 1
        y = Self.margin
        if pageIndex > 0 { onNewPage?(self) }
    }

    func finish() {
        if pageIndex >= 0 { context.endPDFPage() }
        context.closePDF()
    }

    /// Starts a new page unless `height` more points fit on this one.
    func ensureSpace(_ height: CGFloat) {
        if y + height > bottom { newPage() }
    }

    /// A rectangle measured from the top-left of the page, in PDF coordinates (origin bottom-left).
    func pdfRect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: Self.pageSize.height - top - height, width: width, height: height)
    }

    // MARK: Text

    static func text(_ string: String, _ font: CTFont, _ color: CGColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
    }

    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0 else { return 0 }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(size.height)
    }

    static func width(of text: NSAttributedString) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil))
    }

    static func lineHeight(_ font: CTFont) -> CGFloat {
        ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// Wrapped, left-aligned text with its top at `top`. Returns the height it took.
    @discardableResult
    func draw(_ text: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let height = Self.height(of: text, width: width)
        guard height > 0 else { return 0 }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: pdfRect(x: x, top: top, width: width, height: height + 2), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
        return height
    }

    /// One line of text ending at `right`, with its top at `top`.
    func drawRight(_ text: NSAttributedString, right: CGFloat, top: CGFloat) {
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
        context.textPosition = CGPoint(x: right - lineWidth, y: Self.pageSize.height - top - ascent)
        CTLineDraw(line, context)
    }

    func rule(top: CGFloat, x: CGFloat, width: CGFloat, color: CGColor, thickness: CGFloat = 0.75) {
        context.setFillColor(color)
        context.fill(pdfRect(x: x, top: top, width: width, height: thickness))
    }
}
