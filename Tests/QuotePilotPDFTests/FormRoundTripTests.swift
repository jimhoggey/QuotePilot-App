import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

@Suite struct FormRoundTripTests {
    func quotePDF(extraLines: Int = 0) -> Data {
        DocumentRenderer.render(.quote(Sample.quote(extraLines: extraLines), client: Sample.client, brand: Sample.brand),
                                style: PDFStyle())
    }

    /// Fills the form the way a client's PDF app would, then saves.
    func fill(_ data: Data, ticking codes: [String] = [], acceptAll: Bool = false,
              name: String = "", date: String = "") -> Data {
        let document = PDFDocument(data: data)!
        for index in 0..<document.pageCount {
            for widget in document.page(at: index)!.annotations {
                switch widget.fieldName.flatMap({ QuoteFormFields.parse($0) })?.part {
                case .line(let code)? where codes.contains(code): widget.buttonWidgetState = .onState
                case .all? where acceptAll: widget.buttonWidgetState = .onState
                case .name?: widget.widgetStringValue = name
                case .date?: widget.widgetStringValue = date
                default: break
                }
            }
        }
        return document.dataRepresentation()!
    }

    @Test func anUntouchedQuoteReadsAsNothingTicked() throws {
        let form = try ReturnedQuoteReader.read(quotePDF())
        #expect(form == ReturnedForm(quoteNumber: "Q-0001", acceptAll: false, ticked: [], unticked: ["01", "02", "03"]))
    }

    @Test func ticksNameAndDateSurviveTheRoundTrip() throws {
        let form = try ReturnedQuoteReader.read(fill(quotePDF(), ticking: ["01", "03"], name: "Sam Example", date: "16/10/2026"))
        #expect(form.ticked == ["01", "03"])
        #expect(form.unticked == ["02"])
        #expect(form.clientName == "Sam Example")
        #expect(form.clientDate == "16/10/2026")
        let proposal = Sample.quote().proposal(from: form, today: Sample.today)
        #expect(proposal.accepted == ["01", "03"])
        #expect(proposal.declined == ["02"])
        #expect(proposal.problems == [])
    }

    @Test func acceptAllOnItsOwnAcceptsEverything() throws {
        let form = try ReturnedQuoteReader.read(fill(quotePDF(), acceptAll: true))
        #expect(form.acceptAll)
        #expect(Sample.quote().proposal(from: form, today: Sample.today).accepted == ["01", "02", "03"])
    }

    /// A draft whose last line was moved to the top without renumbering, so it still carries "03".
    @Test func aDraftIsRenderedWithTheLineIDsSendingWillFreeze() throws {
        var draft = Sample.quote()
        draft.lines.insert(draft.lines.removeLast(), at: 0)
        #expect(draft.lineCodes == ["03", "01", "02"])

        // What sending freezes, on a library holding that same quote.
        var library = Library()
        library.quotes.append(draft)
        try library.markSent(quote: draft.id)
        let frozen = try #require(library.quote(draft.id))
        #expect(frozen.lines.map(\.title) == ["Extra screens", "Discovery", "Build"])
        #expect(frozen.lineCodes == ["01", "02", "03"])

        let content = DocumentContent.quote(draft, client: Sample.client, brand: Sample.brand)
        #expect(content.rows.map { "\($0.code) \($0.title)" } == frozen.lines.map { "\($0.code) \($0.title)" })

        let data = DocumentRenderer.render(content, style: PDFStyle())
        let form = try ReturnedQuoteReader.read(data)
        #expect(form.ticked == [])
        #expect(form.unticked == frozen.lineCodes)

        // Down the page, each tick box sits on the row of the title that carries its ID.
        let page = try #require(PDFDocument(data: data)?.page(at: 0))
        let boxes = page.annotations
            .compactMap { widget -> (code: String, bounds: CGRect)? in
                guard case .line(let code)? = widget.fieldName.flatMap({ QuoteFormFields.parse($0) })?.part else { return nil }
                return (code, widget.bounds)
            }
            .sorted { $0.bounds.minY > $1.bounds.minY }
        #expect(boxes.map(\.code) == frozen.lineCodes)
        for (box, line) in zip(boxes, frozen.lines) {
            let row = CGRect(x: 0, y: box.bounds.minY - 1, width: page.bounds(for: .mediaBox).width,
                             height: box.bounds.height + 2)
            let text = page.selection(for: row)?.string ?? ""
            #expect(text.contains(line.title), "\(line.title) isn't on the row of tick box \(box.code): \(text)")
            #expect(text.hasPrefix(box.code), "tick box \(box.code) isn't beside its ID: \(text)")
        }
    }

    @Test func aFlattenedPDFHasNoForm() {
        // Drawing the page into a new PDF drops the form, the way printing to PDF does.
        let document = PDFDocument(data: quotePDF())!
        let flat = NSMutableData()
        var box = CGRect(origin: .zero, size: PageWriter.pageSize)
        let context = CGContext(consumer: CGDataConsumer(data: flat as CFMutableData)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        document.page(at: 0)!.draw(with: .mediaBox, to: context)
        context.endPDFPage()
        context.closePDF()
        #expect(throws: ReturnedQuoteError.noForm) { try ReturnedQuoteReader.read(flat as Data) }
    }

    @Test func somethingThatIsntAPDFIsUnreadable() {
        #expect(throws: ReturnedQuoteError.unreadable) { try ReturnedQuoteReader.read(Data("hello".utf8)) }
    }

    @Test func aFileOnDiskIsReadTheSameWay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("returned-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Q-0001 Sample Client Pty Ltd.pdf")
        try fill(quotePDF(), ticking: ["02"], name: "Sam Example").write(to: file)
        let form = try ReturnedQuoteReader.read(contentsOf: file)
        #expect(form.ticked == ["02"])
        #expect(form.clientName == "Sam Example")
        #expect(throws: ReturnedQuoteError.unreadable) {
            try ReturnedQuoteReader.read(contentsOf: folder.appendingPathComponent("missing.pdf"))
        }
    }

    @Test func tickBoxesFromTwoQuotesAreRefused() throws {
        var second = Sample.quote()
        second.number = "Q-0002"
        let other = DocumentRenderer.render(.quote(second, client: Sample.client, brand: Sample.brand), style: PDFStyle())
        let combined = PDFDocument(data: quotePDF())!
        combined.insert(PDFDocument(data: other)!.page(at: 0)!, at: combined.pageCount)
        let merged = try #require(combined.dataRepresentation())
        #expect(throws: ReturnedQuoteError.severalQuotes(["Q-0001", "Q-0002"])) { try ReturnedQuoteReader.read(merged) }
    }

    @Test func everyErrorSaysWhatToDoNext() {
        #expect(ReturnedQuoteError.unreadable.message.contains("isn't a PDF"))
        #expect(ReturnedQuoteError.noForm.message.contains("Tick the lines by hand"))
        #expect(ReturnedQuoteError.severalQuotes(["Q-0001", "Q-0002"]).message.contains("Q-0001, Q-0002"))
    }

    @Test func fieldNamesRoundTrip() {
        #expect(QuoteFormFields.line("Q-0007", "03") == "quotepilot_Q-0007_line_03")
        #expect(QuoteFormFields.parse("quotepilot_Q-0007_line_03")! == ("Q-0007", .line("03")))
        #expect(QuoteFormFields.parse("quotepilot_Q-0007_all")! == ("Q-0007", .all))
        #expect(QuoteFormFields.parse("quotepilot_Q-0007_name")! == ("Q-0007", .name))
        #expect(QuoteFormFields.parse("Check Box 1") == nil)
        // The old dotted form is no longer ours.
        #expect(QuoteFormFields.parse("quotepilot.Q-0007.all") == nil)
    }

    @Test func longQuoteKeepsEachTickBoxWithItsLine() throws {
        let document = PDFDocument(data: quotePDF(extraLines: 40))!
        #expect(document.pageCount >= 3)
        var pageOfLine: [String: Int] = [:]
        for index in 0..<document.pageCount {
            let page = document.page(at: index)!
            for widget in page.annotations {
                guard case .line(let code)? = widget.fieldName.flatMap({ QuoteFormFields.parse($0) })?.part else { continue }
                #expect(pageOfLine[code] == nil, "line \(code) has two tick boxes")
                pageOfLine[code] = index
                #expect(page.bounds(for: .mediaBox).contains(widget.bounds))
            }
        }
        let quote = Sample.quote(extraLines: 40)
        #expect(pageOfLine.count == quote.lines.count)
        for line in quote.lines {
            let page = try #require(pageOfLine[line.code])
            #expect(document.page(at: page)!.string?.contains(line.title) == true,
                    "\(line.title) isn't on page \(page + 1) with its tick box")
        }
    }
}
