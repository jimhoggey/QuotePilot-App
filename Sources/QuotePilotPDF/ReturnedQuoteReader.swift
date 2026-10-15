import Foundation
import PDFKit
import QuotePilotCore

public enum ReturnedQuoteError: Error, Equatable {
    case unreadable
    /// No Quote Pilot form fields: the client's app flattened the form, or it's a different PDF.
    case noForm
    case severalQuotes([String])

    public var message: String {
        switch self {
        case .unreadable:
            return "That file isn't a PDF Quote Pilot can open."
        case .noForm:
            return "This PDF has no tick boxes left. The client's app may have flattened it (printing to PDF does this). Tick the lines by hand instead."
        case .severalQuotes(let numbers):
            return "This PDF has tick boxes from more than one quote (\(numbers.joined(separator: ", "))). Tick the lines by hand instead."
        }
    }
}

/// Reads ticks, name and date out of a quote PDF the client sent back.
public enum ReturnedQuoteReader {
    public static func read(contentsOf url: URL) throws -> ReturnedForm {
        guard let data = try? Data(contentsOf: url) else { throw ReturnedQuoteError.unreadable }
        return try read(data)
    }

    public static func read(_ data: Data) throws -> ReturnedForm {
        guard let document = PDFDocument(data: data) else { throw ReturnedQuoteError.unreadable }
        var quotes = Set<String>()
        var acceptAll = false
        var ticked: [String] = []
        var unticked: [String] = []
        var name = ""
        var date = ""

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for widget in page.annotations where widget.type == "Widget" {
                guard let field = widget.fieldName, let parsed = QuoteFormFields.parse(field) else { continue }
                quotes.insert(parsed.quote)
                let isOn = widget.buttonWidgetState == .onState
                switch parsed.part {
                case .all:
                    acceptAll = acceptAll || isOn
                case .line(let code):
                    if isOn { ticked.append(code) } else { unticked.append(code) }
                case .name:
                    name = (widget.widgetStringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                case .date:
                    date = (widget.widgetStringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        guard let quote = quotes.first else { throw ReturnedQuoteError.noForm }
        guard quotes.count == 1 else { throw ReturnedQuoteError.severalQuotes(quotes.sorted()) }
        return ReturnedForm(quoteNumber: quote, acceptAll: acceptAll, ticked: ticked.sorted(),
                            unticked: unticked.sorted(), clientName: name, clientDate: date)
    }

    /// The quote number a Quote Pilot PDF carries in its keywords ("quotepilot", "Q-0007"). That
    /// usually survives when a PDF app flattens the form away, so a flattened quote can still be
    /// matched to its quote for hand-ticking. Nil when the keywords aren't Quote Pilot's.
    public static func quoteNumber(inMetadataOf data: Data) -> String? {
        guard let document = PDFDocument(data: data),
              let value = document.documentAttributes?[PDFDocumentAttribute.keywordsAttribute]
        else { return nil }
        let keywords: [String]
        if let list = value as? [String] {
            keywords = list
        } else if let text = value as? String {
            keywords = text.components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty }
        } else {
            return nil
        }
        guard keywords.contains(where: { $0.caseInsensitiveCompare("quotepilot") == .orderedSame }) else { return nil }
        return keywords.first { $0.uppercased().hasPrefix("Q-") }
    }
}
