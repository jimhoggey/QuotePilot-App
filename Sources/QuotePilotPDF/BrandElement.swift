import CoreGraphics

/// A part of the brand that documents show. While one is being edited on the Brand screen, its
/// sample quote highlights where it lands (`DocumentRenderer.render(_:style:highlight:)`). Real
/// documents never carry a highlight.
public enum BrandElement: String, CaseIterable, Sendable {
    case businessName, details, abn, logo
    case headingFont, bodyFont, accentColour
    case hourlyRate, quoteValidDays, quoteTerms
    case paymentDetails, paymentDueDays, invoiceTerms
    case emails

    /// The highlight: a soft yellow, see-through so the text stays easy to read.
    public static let highlightColor = CGColor(srgbRed: 0xFF / 255, green: 0xF3 / 255, blue: 0xA0 / 255, alpha: 0.6)
}
