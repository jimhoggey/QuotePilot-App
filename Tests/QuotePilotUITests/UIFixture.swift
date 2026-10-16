import AppKit
import Foundation
import PDFKit
import QuotePilotCore
import QuotePilotPDF
@testable import QuotePilotUI

/// Stands in for Mail: records each draft, and can pretend Mail isn't available.
final class FakeMail: MailComposer {
    struct Draft: Equatable {
        var to: String
        var subject: String
        var body: String
        var attachment: URL
    }

    var available = true
    var drafts: [Draft] = []
    var setAside: [(message: String, attachment: URL)] = []

    func compose(to: String, subject: String, body: String, attachment: URL) -> Bool {
        guard available else { return false }
        drafts.append(Draft(to: to, subject: subject, body: body, attachment: attachment))
        return true
    }

    func setAside(message: String, attachment: URL) {
        setAside.append((message, attachment))
    }
}

/// Made-up data for the UI tests. Never real clients: this repo is public.
enum UIFixture {
    static let today = Day(year: 2026, month: 10, day: 15)

    /// A new temporary folder. Tests never touch the real library.
    static func makeFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotePilotUITests-\(UUID().uuidString)", isDirectory: true)
    }

    /// An accepted 50/50 quote (Design $600, Build $1,200) with its deposit invoice drafted, so its
    /// prices are locked.
    static func invoicedLibrary() throws -> (library: Library, quoteID: UUID) {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example")
        library.addClient(client)
        var quote = library.newQuote(on: today, clientID: client.id)
        quote.addLine(LineItem(title: "Design", rate: Money(dollars: 600)))
        quote.addLine(LineItem(title: "Build", rate: Money(dollars: 1200)))
        try library.update(quote)
        try library.markSent(quote: quote.id)
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: []), forQuote: quote.id)
        try library.draftNextInvoice(forQuote: quote.id, on: today)
        return (library, quote.id)
    }

    /// A model on its own temporary folder, starting from `library` when one is given. Mail is a fake
    /// and mailed PDFs go to a temporary folder.
    @MainActor
    static func model(_ library: Library? = nil, folder: URL = makeFolder(), mail: FakeMail = FakeMail()) throws -> AppModel {
        let store = LibraryStore(folder: folder)
        if let library { try store.save(library) }
        let model = AppModel(store: store, now: { today.date() }, mail: mail, sentFolder: makeFolder())
        // Nothing in a test reaches GitHub, the real settings or the real log.
        model.updates = UpdateFixture.offline()
        return model
    }

    /// A model holding the made-up sample business, on its own temporary folder.
    @MainActor
    static func sampleModel(mail: FakeMail = FakeMail()) throws -> AppModel {
        try model(SampleLibrary.make(today: today, now: today.date()), mail: mail)
    }

    /// A real 2×2 PNG.
    static func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// A tiny made-up SVG logo, 200 x 80: a magenta rectangle and a blue circle.
    static func svgData() -> Data {
        Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="80" viewBox="0 0 200 80">
          <rect x="4" y="4" width="120" height="72" fill="#C2185B"/>
          <circle cx="160" cy="40" r="30" fill="#1F6FEB"/>
        </svg>
        """.utf8)
    }

    /// Writes `data` to a file called `name` in a new temporary folder.
    static func file(_ name: String, _ data: Data) throws -> URL {
        let folder = makeFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// Fills a quote PDF's form the way a client's PDF app would, then saves it.
    static func fill(_ data: Data, ticking codes: [String] = [], acceptAll: Bool = false,
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

    /// Redraws page 1 into a new PDF, the way printing to PDF does: the form is gone. Keeps Quote
    /// Pilot's keywords when asked, as most PDF apps do.
    static func flattened(_ data: Data, keepingKeywords: Bool) -> Data {
        let document = PDFDocument(data: data)!
        let page = document.page(at: 0)!
        let keywords = document.documentAttributes?[PDFDocumentAttribute.keywordsAttribute]
        let info: [CFString: Any]? = keepingKeywords ? [kCGPDFContextKeywords: keywords as Any] : nil
        let flat = NSMutableData()
        var box = page.bounds(for: .mediaBox)
        let context = CGContext(consumer: CGDataConsumer(data: flat as CFMutableData)!, mediaBox: &box,
                                info as CFDictionary?)!
        context.beginPDFPage(nil)
        page.draw(with: .mediaBox, to: context)
        context.endPDFPage()
        context.closePDF()
        return flat as Data
    }
}
