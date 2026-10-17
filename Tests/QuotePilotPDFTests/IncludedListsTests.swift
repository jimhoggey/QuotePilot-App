import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// A quote's optional Included and Not included lists: a table before Accepted by, only when either
/// has items, with a column only for a list that has them.
@Suite struct IncludedListsTests {
    static func pdf(included: [String], notIncluded: [String], extraLines: Int = 0) -> PDFDocument {
        var quote = Sample.quote(extraLines: extraLines)
        quote.included = included
        quote.notIncluded = notIncluded
        return Sample.pdf(.quote(quote, client: Sample.client, brand: Sample.brand))
    }

    @Test func noListsNoTable() {
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        #expect(content.sections.allSatisfy { $0.lists == nil })
        let text = Sample.text(Self.pdf(included: [], notIncluded: ["  "]))
        #expect(!text.contains("Not included"))
    }

    /// Only Not included has items: it prints alone, at the left margin, with no empty Included column.
    @Test func onlyNotIncludedPrintsAlone() throws {
        let document = Self.pdf(included: [], notIncluded: ["Printing and signage"])
        let text = Sample.text(document)
        #expect(text.contains("Not included"))
        #expect(!text.contains("Included"))
        #expect(text.contains("Printing and signage"))
        let item = try #require(LayoutTests.bounds(of: "Printing and signage", in: document).first)
        #expect(abs(item.minX - PageWriter.margin) < 1)
    }

    /// Only Included has items: no empty Not included heading, and the list runs the full width.
    @Test func onlyIncludedPrintsAloneAtFullWidth() throws {
        let long = "Design, build and testing of the home page, the about page and the contact page, with copy edits"
        let document = Self.pdf(included: [long], notIncluded: [])
        let text = Sample.text(document)
        #expect(text.contains("Included"))
        #expect(!text.contains("Not included"))
        let start = try #require(LayoutTests.bounds(of: "Design, build", in: document).first)
        #expect(abs(start.minX - PageWriter.margin) < 1)
        // Wider than half the page: a two-column table would have wrapped it there.
        let lines = LayoutTests.bounds(of: "contact page", in: document)
        let end = try #require(lines.first)
        #expect(end.maxX > PageWriter.pageSize.width / 2)
    }

    /// The client sees the table before signing: it prints before Accepted by, with the Name and
    /// Date fields still under Accepted by.
    @Test func theTableComesBeforeAcceptedBy() throws {
        let document = Self.pdf(included: ["Home page design"], notIncluded: ["Printing and signage"])
        let text = Sample.text(document)
        let heading = try #require(text.range(of: "Included"))
        let accepted = try #require(text.range(of: "Accepted by"))
        #expect(heading.lowerBound < accepted.lowerBound)
        let item = try #require(LayoutTests.bounds(of: "Home page design", in: document).first)
        let acceptedBy = try #require(LayoutTests.bounds(of: "Accepted by", in: document).first)
        #expect(item.minY > acceptedBy.maxY, "PDF space: the table sits above Accepted by")
        let annotations = try #require(document.page(at: 0)).annotations
        let name = try #require(annotations.first { $0.fieldName == QuoteFormFields.name("Q-0001") })
        let date = try #require(annotations.first { $0.fieldName == QuoteFormFields.date("Q-0001") })
        #expect(abs(name.bounds.minY - date.bounds.minY) < 0.5, "Name and Date share a line")
        for field in [name, date] {
            #expect(field.bounds.maxY < acceptedBy.minY + 1, "\(field.fieldName ?? "") sits under Accepted by")
        }
    }

    /// Side by side: the first items share a line, Included on the left, Not included on the right.
    @Test func theListsSitSideBySideBeforeAcceptedBy() throws {
        let document = Self.pdf(included: ["Home page design"], notIncluded: ["Printing and signage"])
        let left = try #require(LayoutTests.bounds(of: "Home page design", in: document).first)
        let right = try #require(LayoutTests.bounds(of: "Printing and signage", in: document).first)
        #expect(abs(left.midY - right.midY) < 1)
        #expect(abs(left.minX - PageWriter.margin) < 1)
        #expect(right.minX > PageWriter.pageSize.width / 2)
        // Before the payment plan.
        let text = Sample.text(document)
        let table = try #require(text.range(of: "Home page design"))
        let plan = try #require(text.range(of: "Payment plan"))
        #expect(table.lowerBound < plan.lowerBound)
    }

    /// A long table carries on over the page, with its headings again at the top, and every item prints.
    @Test func aLongTableSplitsAcrossPages() throws {
        let included = (1...60).map { "Included item \($0)" }
        let notIncluded = (1...45).map { "Left out item \($0)" }
        let document = Self.pdf(included: included, notIncluded: notIncluded, extraLines: 4)
        #expect(document.pageCount >= 2)
        let text = Sample.text(document)
        for item in included + notIncluded { #expect(text.contains(item + "\n") || text.hasSuffix(item) || text.contains(item + " "), "\(item)") }
        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        let first = try #require(pages.firstIndex { $0.contains("Included item 1\n") || $0.contains("Included item 1 ") })
        let end = try #require(pages.firstIndex { $0.contains("Included item 60") })
        #expect(end > first)
        #expect(pages[end].contains("Not included"), "the headings repeat on the next page")
        // Nothing runs into the footer.
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            let footer = try #require(LayoutTests.bounds(of: "Page \(index + 1) of", in: document, page: index).first)
            let low = page.selection(for: CGRect(x: 0, y: footer.maxY + 1, width: PageWriter.pageSize.width,
                                                 height: PageWriter.margin - footer.maxY - 1))?.string ?? ""
            #expect(low.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "page \(index + 1): \(low)")
        }
    }
}
