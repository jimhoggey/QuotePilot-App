import Foundation

/// One named style of a font file, as the Style picker offers it: an instance of a variable font
/// (Bold, ExtraBold Italic, …) or one face of a font collection. The brand keeps it beside the font's
/// file name so a document draws the same style every time.
///
/// It is saved as the style's PostScript name (what the PDF names the font, and what identifies the
/// style in the file) together with the axis values that make it, so the style can still be found,
/// or rebuilt on the file's default, when the name alone doesn't pick one out.
public struct FontStyle: Codable, Hashable, Sendable {
    /// The style's PostScript name, like "ArchivoItalic-Bold".
    public var postScriptName: String
    /// The variable-font axis values that make this style, by four-letter axis tag: ["wght": 700].
    /// Only the axes that differ from the font's defaults are listed, as Core Text lists them; empty
    /// for a static face and for a variable font's default style.
    public var variations: [String: Double]

    public init(postScriptName: String, variations: [String: Double] = [:]) {
        self.postScriptName = postScriptName
        self.variations = variations
    }

    enum CodingKeys: String, CodingKey {
        case postScriptName, variations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postScriptName = try c.decode(String.self, forKey: .postScriptName)
        variations = try c.value(.variations, or: [:])
    }
}
