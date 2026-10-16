import AppKit
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

@Suite struct SVGLogoTests {
    /// A made-up logo: a magenta rectangle and a blue circle, 200 x 80. Magenta appears nowhere else
    /// on a document, so finding it on a page means the logo was drawn.
    static let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="80" viewBox="0 0 200 80">
      <rect x="4" y="4" width="120" height="72" fill="#C2185B"/>
      <circle cx="160" cy="40" r="30" fill="#1F6FEB"/>
    </svg>
    """

    /// Writes `text` to a new temporary file called `name`.
    private func file(_ name: String, _ text: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SVGLogoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// The made-up logo as a PDF file, ready for `Logo(url:)`.
    private func logoPDF() throws -> URL {
        let data = try #require(SVGLogo.pdfData(from: try file("logo.svg", Self.svg)))
        let url = try file("logo.pdf", "")
        try data.write(to: url)
        return url
    }

    @Test func anSVGBecomesAOnePageVectorPDFAtItsOwnSize() throws {
        let data = try #require(SVGLogo.pdfData(from: try file("logo.svg", Self.svg)))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 200, height: 80))
        // Vector all the way: nothing in it is a bitmap.
        let raw = String(decoding: data, as: UTF8.self)
        #expect(!raw.contains("/Subtype /Image") && !raw.contains("/Subtype/Image"))
    }

    @Test func theConvertedLogoLoadsAsAVectorLogo() throws {
        let logo = try #require(Logo(url: try logoPDF()))
        guard case .vector = logo else {
            Issue.record("A converted SVG should be a PDF (vector) logo")
            return
        }
        #expect(logo.size == CGSize(width: 200, height: 80))
    }

    /// The page takes the SVG's size from its width and height, or its viewBox, or what it draws.
    @Test func thePageSizeComesFromTheSVG() throws {
        func size(_ svg: String) throws -> CGSize? {
            guard let data = SVGLogo.pdfData(from: try file("logo.svg", svg)) else { return nil }
            return PDFDocument(data: data)?.page(at: 0)?.bounds(for: .mediaBox).size
        }
        let shapes = ##"<rect x="4" y="4" width="120" height="72" fill="#C2185B"/>"##
        let ns = #"xmlns="http://www.w3.org/2000/svg""#
        #expect(try size("<svg \(ns) width=\"50\" height=\"20\">\(shapes)</svg>") == CGSize(width: 50, height: 20))
        #expect(try size("<svg \(ns) viewBox=\"0 0 200 80\">\(shapes)</svg>") == CGSize(width: 200, height: 80))
        // No size at all: the size of what it draws.
        #expect(try size("<svg \(ns)>\(shapes)</svg>") == CGSize(width: 120, height: 72))
        // Nothing to measure either: the default size.
        #expect(try size("<svg \(ns)></svg>") == SVGLogo.defaultSize)
    }

    @Test func aHugeSVGIsShrunkToAPageThatFitsAndKeepsItsShape() throws {
        let huge = #"<svg xmlns="http://www.w3.org/2000/svg" width="100000" height="50000"><rect width="10" height="10"/></svg>"#
        let data = try #require(SVGLogo.pdfData(from: try file("logo.svg", huge)))
        let size = try #require(PDFDocument(data: data)?.page(at: 0)?.bounds(for: .mediaBox).size)
        #expect(abs(size.width - SVGLogo.largestSide) < 0.01)
        #expect(abs(size.height - SVGLogo.largestSide / 2) < 0.01)
    }

    @Test func aFileThatIsNotAnSVGIsRefused() throws {
        #expect(SVGLogo.pdfData(from: try file("a.svg", "this is not a picture")) == nil)
        #expect(SVGLogo.pdfData(from: try file("b.svg", "")) == nil)
        #expect(SVGLogo.pdfData(from: try file("c.svg", #"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect"#)) == nil)
        #expect(SVGLogo.pdfData(from: try file("d.svg", "<html><body>hello</body></html>")) == nil)
        #expect(SVGLogo.pdfData(from: URL(fileURLWithPath: "/nonexistent/logo.svg")) == nil)
    }

    @Test func onlyFilesNamedSVGAreTreatedAsSVG() {
        #expect(SVGLogo.isSVG(URL(fileURLWithPath: "/tmp/logo.svg")))
        #expect(SVGLogo.isSVG(URL(fileURLWithPath: "/tmp/LOGO.SVG")))
        #expect(!SVGLogo.isSVG(URL(fileURLWithPath: "/tmp/logo.png")))
        #expect(!SVGLogo.isSVG(URL(fileURLWithPath: "/tmp/svg")))
        #expect(SVGLogo.looksLikeSVG(Data(Self.svg.utf8)))
        #expect(SVGLogo.looksLikeSVG(Data("<?xml version=\"1.0\"?>\n<!-- made up -->\n<svg></svg>".utf8)))
        #expect(!SVGLogo.looksLikeSVG(Data("not a picture".utf8)))
    }

    // MARK: On a quote

    /// Page 1 of a document drawn at one pixel per point, on white: RGBA bytes, top row first.
    private func pixels(_ document: PDFDocument) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let page = try #require(document.page(at: 0))
        let box = page.bounds(for: .mediaBox)
        let width = Int(box.width), height = Int(box.height)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            page.draw(with: .mediaBox, to: context)
        }
        return (bytes, width, height)
    }

    /// Where the page has a magenta pixel (the logo's rectangle), as (x, top-down y).
    private func magenta(in document: PDFDocument) throws -> [(x: Int, y: Int)] {
        let (bytes, width, height) = try pixels(document)
        var found: [(x: Int, y: Int)] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                if r > g + 100, r > b + 50, b > g + 30 { found.append((x, y)) }
            }
        }
        return found
    }

    @Test func anSVGLogoIsDrawnOnAQuote() throws {
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        let plain = Sample.pdf(content)
        #expect(try magenta(in: plain).isEmpty)

        let style = PDFStyle(logo: Logo(url: try logoPDF()))
        let data = DocumentRenderer.render(content, style: style)
        let branded = try #require(PDFDocument(data: data))
        #expect(data.count > DocumentRenderer.render(content, style: PDFStyle()).count)
        #expect(branded.pageCount == 1)

        // The 200 x 80 logo is drawn to fit 180 x 44 at the top left, so its rectangle (120 x 72 of
        // it) is about 66 x 40 points up there.
        let hits = try magenta(in: branded)
        #expect(hits.count > 1_500)
        let size = try #require(branded.page(at: 0)?.bounds(for: .mediaBox).size)
        #expect(hits.allSatisfy { $0.y < 150 && CGFloat($0.x) < size.width / 2 })
        // The rest of the page is as it was: the same words, and still a quote with its form.
        let text = Sample.text(branded)
        #expect(text.contains("Q-0001") && text.contains("Sample Studio") && text.contains("Accept all"))
        #expect((0..<branded.pageCount).flatMap { branded.page(at: $0)!.annotations }.contains { $0.fieldName != nil })
        // And the logo is still vector: the quote has no bitmap in it.
        #expect(!String(decoding: data, as: UTF8.self).contains("/Subtype /Image"))
    }
}
