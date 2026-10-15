import Foundation

/// Gives a quote PDF the complete AcroForm that other viewers need.
///
/// PDFKit writes the widgets (the tick boxes and text fields) but no `/AcroForm` entry in the catalog,
/// so Chrome, Edge, pdf.js and Acrobat don't treat the page as a form. (PDFKit only adds one on a
/// re-save, and then lists just the fields that were filled in.) This appends a standard incremental
/// update: a catalog that points at an AcroForm listing every widget, a default appearance, and a
/// standard Helvetica for the widgets to name. The original bytes are left exactly as they were.
enum AcroFormWriter {
    /// The PDF with an AcroForm for all its widgets, or nil if it isn't a PDF this can safely extend:
    /// not a classic cross-reference file, encrypted, no widgets, or already has an AcroForm.
    static func addingAcroForm(to pdf: Data) -> Data? {
        // Read the file as ISO Latin-1, where one byte is one character (and one UTF-16 unit), so
        // NSString offsets are byte offsets.
        guard let text = String(data: pdf, encoding: .isoLatin1) else { return nil }
        let bytes = text as NSString
        guard bytes.length == pdf.count else { return nil }
        let everything = NSRange(location: 0, length: bytes.length)

        // The last cross-reference section: where it starts, and the trailer after it.
        let startxref = try? NSRegularExpression(pattern: #"startxref\s+(\d+)\s+%%EOF\s*$"#)
        guard let found = startxref?.matches(in: text, range: everything).last,
              let previous = Int(bytes.substring(with: found.range(at: 1))),
              previous >= 0, previous + 4 <= bytes.length,
              bytes.substring(with: NSRange(location: previous, length: 4)) == "xref"
        else { return nil }
        let trailerKeyword = bytes.range(of: "trailer", options: .backwards,
                                         range: NSRange(location: 0, length: found.range.location))
        guard trailerKeyword.location != NSNotFound else { return nil }
        let trailerStart = trailerKeyword.location + trailerKeyword.length
        let trailer = bytes.substring(with: NSRange(location: trailerStart, length: found.range.location - trailerStart))
        guard !trailer.contains("/Encrypt"),
              let size = firstInt(#"/Size\s+(\d+)"#, in: trailer), size > 0,
              let root = firstInt(#"/Root\s+(\d+)\s+0\s+R"#, in: trailer)
        else { return nil }
        let info = firstMatch(#"/Info\s+\d+\s+\d+\s+R"#, in: trailer)
        let id = firstMatch(#"/ID\s*\[[^\]]*\]"#, in: trailer)

        // Every object: note the widgets, and keep the catalog's dictionary.
        guard let objectStart = try? NSRegularExpression(pattern: #"(?:\A|[\r\n])(\d+) 0 obj"#),
              let widgetKey = try? NSRegularExpression(pattern: #"/Subtype\s*/Widget\b"#)
        else { return nil }
        var widgets = Set<Int>()
        var catalog: String?
        for match in objectStart.matches(in: text, range: everything) {
            guard let number = Int(bytes.substring(with: match.range(at: 1))) else { continue }
            let bodyStart = match.range.location + match.range.length
            let end = bytes.range(of: "endobj", options: [],
                                  range: NSRange(location: bodyStart, length: bytes.length - bodyStart))
            guard end.location != NSNotFound else { continue }
            let body = NSRange(location: bodyStart, length: end.location - bodyStart)
            if number == root {
                catalog = bytes.substring(with: body).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let widget = widgetKey.firstMatch(in: text, range: body) {
                // A widget is a plain dictionary; ignore the word inside a stream's binary data.
                let stream = bytes.range(of: "stream", options: [], range: body)
                if stream.location == NSNotFound || widget.range.location < stream.location { widgets.insert(number) }
            }
        }
        guard let catalog, catalog.hasPrefix("<<"), catalog.hasSuffix(">>"), catalog.contains("/Catalog"),
              !catalog.contains("/AcroForm"), !widgets.isEmpty
        else { return nil }

        // The update: the catalog again (same number) pointing at the new AcroForm, the AcroForm, and
        // the Helvetica its widgets name.
        let acroForm = size
        let font = size + 1
        let fields = widgets.sorted().map { "\($0) 0 R" }.joined(separator: " ")
        var update = pdf.last == UInt8(ascii: "\n") ? "" : "\n"
        let catalogOffset = pdf.count + update.utf8.count
        update += "\(root) 0 obj\n<< /AcroForm \(acroForm) 0 R" + catalog.dropFirst(2) + "\nendobj\n"
        let acroFormOffset = pdf.count + update.utf8.count
        update += "\(acroForm) 0 obj\n<< /Fields [\(fields)] /NeedAppearances true /DA (/Helv 10 Tf 0 g) "
            + "/DR << /Font << /Helv \(font) 0 R /Helvetica \(font) 0 R >> >> >>\nendobj\n"
        let fontOffset = pdf.count + update.utf8.count
        update += "\(font) 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\n"

        // The cross-reference section: one subsection per run of consecutive object numbers, every
        // entry exactly 20 bytes.
        let entries = [(root, catalogOffset), (acroForm, acroFormOffset), (font, fontOffset)].sorted { $0.0 < $1.0 }
        let xrefOffset = pdf.count + update.utf8.count
        update += "xref\n"
        var index = 0
        while index < entries.count {
            var end = index
            while end + 1 < entries.count, entries[end + 1].0 == entries[end].0 + 1 { end += 1 }
            update += "\(entries[index].0) \(end - index + 1)\n"
            for entry in entries[index...end] { update += String(format: "%010ld 00000 n \n", entry.1) }
            index = end + 1
        }
        update += "trailer\n<< /Size \(size + 2) /Root \(root) 0 R /Prev \(previous)"
        if let info { update += " " + info }
        if let id { update += " " + id }
        update += " >>\nstartxref\n\(xrefOffset)\n%%EOF\n"

        return pdf + Data(update.utf8)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return nil }
        return (text as NSString).substring(with: match.range)
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges > 1
        else { return nil }
        return Int((text as NSString).substring(with: match.range(at: 1)))
    }
}
