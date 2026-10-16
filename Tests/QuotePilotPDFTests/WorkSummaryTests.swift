import AppKit
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// The work summary (and every section) as pasted from elsewhere: lines break between words, any
/// common dot-point marker makes a dot point, and long text carries on over the page intact.
@Suite struct WorkSummaryTests {
    /// The user's report: a summary pasted from a two-column web page, its markers on lines of their own.
    static let pasted = """
    INCLUDED NOT
    INCLUDED
    –
    –
    –
    Private web address with HTTPS
    Password screen in front of the app
    100 Point Check-Up and Recommendations/Quote sheets, wording and columns as confirmed by you
    Automatic calculation of accepted options, savings, GST and total
    """

    static func pdf(summary: String, extraLines: Int = 0) -> PDFDocument {
        var quote = Sample.quote(extraLines: extraLines)
        quote.summary = summary
        return Sample.pdf(.quote(quote, client: Sample.client, brand: Sample.brand))
    }

    /// The printed lines of the text between the "Work summary" heading and the next heading, page
    /// by page, as PDFKit reads them.
    static func summaryLines(_ document: PDFDocument) -> [String] {
        var lines: [String] = []
        var inSummary = false
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let all = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() else { continue }
            for line in all {
                let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text == "Work summary" { inSummary = true; continue }
                if text == "Payment plan" { inSummary = false }
                // The repeated header at the top of a later page isn't the summary's.
                if text.hasSuffix(", continued") { continue }
                if inSummary, line.bounds(for: page).minY > PageWriter.margin, !text.isEmpty { lines.append(text) }
            }
        }
        return lines
    }

    // MARK: Breaking lines between words

    /// Non-breaking spaces, invisible break points and soft hyphens, as web pages paste them, would
    /// make Core Text break inside words ("colum / ns"). Every printed line ends on a whole word.
    @Test func linesBreakBetweenWordsEvenWithPastedSpaces() throws {
        let sentence = "The quote covers columns, totals, GST and every screen as confirmed by you before the work starts"
        let words = Set(sentence.split(separator: " ").map(String.init))
        // Joined by non-breaking spaces, with a soft hyphen and a zero-width space inside words.
        let pasted = String(repeating: sentence + " ", count: 4)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "columns", with: "colum\u{00AD}ns")
            .replacingOccurrences(of: "GST", with: "G\u{200B}ST")
        let lines = Self.summaryLines(Self.pdf(summary: pasted))
        #expect(lines.count >= 4, "\(lines)")
        for line in lines {
            for word in line.split(separator: " ") {
                #expect(words.contains(String(word)), "\"\(word)\" is a broken word, in: \(line)")
            }
        }
    }

    @Test func pastedSpacesAndBreakPointsAreCleanedUp() {
        #expect(Layout.printable("GST\u{00A0}and\u{202F}total") == "GST and total")
        #expect(Layout.printable("colum\u{00AD}ns") == "columns")
        #expect(Layout.printable("G\u{200B}ST\u{2060}\u{FEFF}") == "GST")
        #expect(Layout.printable("tab\tstays") == "tab\tstays")
    }

    /// A single word wider than the column still breaks, rather than running off the page.
    @Test func aWordWiderThanTheColumnStillBreaks() throws {
        let word = String(repeating: "Supercalifragilistic", count: 8)
        let document = Self.pdf(summary: word)
        let page = try #require(document.page(at: 0))
        let found = try #require(LayoutTests.bounds(of: "Supercalifragilistic", in: document).first)
        #expect(found.maxX <= PageWriter.pageSize.width - PageWriter.margin + 1)
        #expect(Self.summaryLines(document).count >= 2)
        _ = page
    }

    // MARK: Dot points

    @Test func everyCommonMarkerMakesADotPoint() {
        let text = "Intro\n- dash\n-tight dash\n– en dash\n—em dash\n• bullet\n•tight bullet\n* star\n*tight star"
        let parts = Layout.paragraphs(text).compactMap { $0 }
        #expect(parts.map(\.text) == ["Intro", "dash", "tight dash", "en dash", "em dash", "bullet", "tight bullet",
                                      "star", "tight star"])
        #expect(parts.map(\.isBullet) == [false] + Array(repeating: true, count: 8))
    }

    /// A marker alone on its line prints nothing, not a lone dash; blank lines still space paragraphs.
    @Test func aMarkerAloneOnItsLineIsDropped() {
        let parts = Layout.paragraphs("First\n–\n—\n-\n•\n*\n\nSecond")
        #expect(parts == [Layout.Paragraph(text: "First", isBullet: false), nil,
                          Layout.Paragraph(text: "Second", isBullet: false)])
    }

    @Test func thePastedSummaryPrintsWithoutLoneDashes() throws {
        let document = Self.pdf(summary: Self.pasted)
        let lines = Self.summaryLines(document)
        #expect(lines.allSatisfy { !["–", "—", "-", "•", "*"].contains($0) }, "\(lines)")
        #expect(lines.contains("INCLUDED NOT"))
        #expect(lines.contains { $0.contains("100 Point Check-Up and Recommendations/Quote sheets, wording and columns as confirmed by you") })
        #expect(lines.contains { $0.contains("Automatic calculation of accepted options, savings, GST and total") })
        #expect(!Sample.text(document).contains("–"))
    }

    // MARK: Width and pages

    /// The summary uses the full width between the margins, not a narrow column.
    @Test func theSummaryUsesTheFullWidth() throws {
        let long = "This line of the work summary is long enough to need nearly the whole width of the page between its margins, and then some more."
        let document = Self.pdf(summary: long)
        let start = try #require(LayoutTests.bounds(of: "This line of the work summary", in: document).first)
        #expect(abs(start.minX - PageWriter.margin) < 1)
        // Its first line reaches most of the way to the right margin before it wraps.
        let page = try #require(document.page(at: 0))
        let firstLine = try #require(page.selection(for: start)?.selectionsByLine().first?.bounds(for: page))
        let lineSelection = try #require(page.selection(from: CGPoint(x: PageWriter.margin, y: start.midY),
                                                        to: CGPoint(x: PageWriter.pageSize.width, y: start.midY)))
        _ = firstLine
        #expect(lineSelection.bounds(for: page).maxX > PageWriter.pageSize.width - PageWriter.margin - 80)
    }

    /// A summary too long for the page carries on over the next, still wrapped between words and
    /// still with its dot points, and nothing runs into the footer.
    @Test func aLongSummaryCarriesOnOverThePage() throws {
        let item = "A dot point long enough to wrap onto a second line of the page, so the summary takes plenty of room on it"
        let words = Set(item.split(separator: " ").map(String.init)).union(["Item"])
        let summary = (1...40).map { "– Item \($0): \(item)" }.joined(separator: "\n")
            + "\n" + String(repeating: item + ". ", count: 30)
        let document = Self.pdf(summary: summary, extraLines: 6)
        #expect(document.pageCount >= 3)
        let lines = Self.summaryLines(document)
        for line in lines {
            for word in line.split(separator: " ") {
                // The dot points' own dots are drawn, so they read as "•".
                let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: ".:0123456789•"))
                #expect(bare.isEmpty || words.contains(bare), "\"\(word)\" in: \(line)")
            }
        }
        for number in [1, 20, 40] { #expect(lines.contains { $0.contains("Item \(number):") }, "Item \(number)") }
        // Dot points on every page the summary reaches past the first, and nothing in the bottom margin
        // but the footer.
        var pagesWithDots = 0
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            if (page.string ?? "").contains("•") { pagesWithDots += 1 }
            let footer = try #require(LayoutTests.bounds(of: "Page \(index + 1) of", in: document, page: index).first)
            let low = page.selection(for: CGRect(x: 0, y: footer.maxY + 1, width: PageWriter.pageSize.width,
                                                 height: PageWriter.margin - footer.maxY - 1))?.string ?? ""
            #expect(low.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "page \(index + 1): \(low)")
        }
        #expect(pagesWithDots >= 2)
        // The long last paragraph is split across pages rather than overflowing.
        // Every one of the 70 copies of the sentence is printed: 40 dot points and 30 in the paragraph.
        #expect(Sample.text(document).components(separatedBy: "plenty").count - 1 == 70)
    }
}
