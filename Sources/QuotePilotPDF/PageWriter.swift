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
    /// Runs as each page is finished, e.g. to draw its footer.
    var onEndPage: ((PageWriter) -> Void)?
    /// Runs as each page starts, the first one too, before anything is drawn on it: what it draws
    /// lies behind the page's text.
    var onBeginPage: ((PageWriter) -> Void)?

    init(context: CGContext) {
        self.context = context
    }

    var left: CGFloat { Self.margin }
    var width: CGFloat { Self.pageSize.width - 2 * Self.margin }
    var right: CGFloat { left + width }
    var bottom: CGFloat { Self.pageSize.height - Self.margin }

    func newPage() {
        endPage()
        context.beginPDFPage(nil)
        context.textMatrix = .identity
        pageIndex += 1
        y = Self.margin
        onBeginPage?(self)
        if pageIndex > 0 { onNewPage?(self) }
        contentTop = y
    }

    /// Where this page's own content starts, under any repeated header.
    private var contentTop: CGFloat = 0
    /// True when nothing has been drawn on this page yet but its repeated header.
    var isAtTopOfPage: Bool { y <= contentTop + 0.5 }

    func finish() {
        endPage()
        context.closePDF()
    }

    private func endPage() {
        guard pageIndex >= 0 else { return }
        onEndPage?(self)
        context.endPDFPage()
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

    /// `text` set to wrap between words, breaking inside a word only when it's wider than the line.
    static func wrapping(_ text: NSAttributedString) -> NSAttributedString {
        let wrapped = NSMutableAttributedString(attributedString: text)
        var mode = CTLineBreakMode.byWordWrapping
        let paragraph = withUnsafeBytes(of: &mode) { bytes in
            CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: bytes.count,
                                                            value: bytes.baseAddress!)], 1)
        }
        wrapped.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: paragraph,
                             range: NSRange(location: 0, length: wrapped.length))
        return wrapped
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

    /// Where each line of wrapped text drawn at `x`, `top` lies: from the top of its tallest glyphs to
    /// its descent, as wide as its words, measured from the top-left of the page.
    static func lineFrames(of text: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat) -> [CGRect] {
        let height = Self.height(of: text, width: width)
        guard height > 0 else { return [] }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let frameHeight = height + 2
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: frameHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        return zip(lines, origins).map { line, origin in
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            let baseline = top + (frameHeight - origin.y)
            return CGRect(x: x + origin.x, y: baseline - ascent, width: lineWidth, height: ascent + descent)
        }
    }

    /// One line of wrapped text, laid out as `draw` would set it, for text that may continue on the
    /// next page. Distances are from the top of the whole text.
    struct Line {
        let line: CTLine
        /// Where the line's room starts and ends, and its baseline.
        let top: CGFloat
        let bottom: CGFloat
        let baseline: CGFloat
        /// Its words: in from the left, how wide, and how far they reach above and below the baseline.
        let x: CGFloat
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
    }

    /// `text` wrapped to `width`, line by line.
    static func lines(of text: NSAttributedString, width: CGFloat) -> [Line] {
        let height = Self.height(of: text, width: width)
        guard height > 0 else { return [] }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let frameHeight = height + 2
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: frameHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let ctLines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = [CGPoint](repeating: .zero, count: ctLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let measured = zip(ctLines, origins).map { line, origin -> (CTLine, CGPoint, CGFloat, CGFloat, CGFloat) in
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            return (line, origin, width, ascent, descent)
        }
        return measured.enumerated().map { index, item in
            let (line, origin, lineWidth, ascent, descent) = item
            let baseline = frameHeight - origin.y
            let top = index == 0 ? 0 : baseline - ascent
            let bottom: CGFloat
            if index + 1 < measured.count {
                let next = measured[index + 1]
                bottom = (frameHeight - next.1.y) - next.3
            } else {
                bottom = max(height, baseline + descent)
            }
            return Line(line: line, top: top, bottom: bottom, baseline: baseline, x: origin.x, width: lineWidth,
                        ascent: ascent, descent: descent)
        }
    }

    /// Draws one laid-out line, with the top of its text block at `textTop`.
    func draw(_ line: Line, x: CGFloat, textTop: CGFloat) {
        context.textPosition = CGPoint(x: x + line.x, y: Self.pageSize.height - (textTop + line.baseline))
        CTLineDraw(line.line, context)
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

    /// One line of text ending at `right`, with its top at `top`. It is set flush right in a frame,
    /// the way `draw` sets text, so a figure sits on the same baseline as the words beside it.
    func drawRight(_ text: NSAttributedString, right: CGFloat, top: CGFloat) {
        guard text.length > 0 else { return }
        let aligned = NSMutableAttributedString(attributedString: text)
        var alignment = CTTextAlignment.right
        let paragraph = withUnsafeBytes(of: &alignment) { bytes in
            CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .alignment, valueSize: bytes.count,
                                                            value: bytes.baseAddress!)], 1)
        }
        aligned.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: paragraph,
                             range: NSRange(location: 0, length: aligned.length))
        // Room to spare, so the line never wraps; flush right puts its end at `right` all the same.
        let width = ceil(Self.width(of: text)) + 8
        draw(aligned, x: right - width, top: top, width: width)
    }

    func rule(top: CGFloat, x: CGFloat, width: CGFloat, color: CGColor, thickness: CGFloat = 0.75) {
        context.setFillColor(color)
        context.fill(pdfRect(x: x, top: top, width: width, height: thickness))
    }
}
