import Foundation
import Testing
@testable import QuotePilotCore

/// The brand's heading-font style (a variable font's Bold, say) is saved beside the font's file name.
@Suite struct FontStyleTests {
    /// A library saved before the style existed has no such field; it loads with no style, which is the
    /// font's own default, and a style that is there round-trips.
    @Test func aBrandWithoutAHeadingFontStyleLoadsWithNone() throws {
        let old = try Library.makeDecoder().decode(
            Brand.self, from: Data(#"{"businessName":"Sample Studio","headingFontFile":"heading-font-1A2B3C4D.ttf"}"#.utf8))
        #expect(old.headingFontFile == "heading-font-1A2B3C4D.ttf")
        #expect(old.headingFontStyle == nil)

        var brand = Brand()
        #expect(brand.headingFontStyle == nil)
        brand.headingFontFile = "heading-font-1A2B3C4D.ttf"
        brand.headingFontStyle = FontStyle(postScriptName: "ArchivoItalic-Bold", variations: ["wght": 700])
        let saved = try Library.makeEncoder().encode(brand)
        let loaded = try Library.makeDecoder().decode(Brand.self, from: saved)
        #expect(loaded.headingFontStyle == FontStyle(postScriptName: "ArchivoItalic-Bold", variations: ["wght": 700]))
        #expect(loaded == brand)
        // With none set, nothing is written, so the file is as it was before the field existed.
        #expect(!String(decoding: try Library.makeEncoder().encode(Brand()), as: UTF8.self).contains("headingFontStyle"))

        let library = try Library.makeDecoder().decode(
            Library.self, from: Data(#"{"format":1,"brand":{"businessName":"Sample Studio","quoteValidDays":20}}"#.utf8))
        #expect(library.brand.headingFontStyle == nil)
        #expect(library.brand.quoteValidDays == 20)
    }

    /// A style saved without its axis values still reads, and a style that can't be read at all is the
    /// font's default rather than a library that won't open.
    @Test func aStyleThatIsOddlySavedStillLoads() throws {
        let decoder = Library.makeDecoder()
        let bare = try decoder.decode(
            Brand.self, from: Data(#"{"headingFontStyle":{"postScriptName":"Georgia-Bold"}}"#.utf8))
        #expect(bare.headingFontStyle == FontStyle(postScriptName: "Georgia-Bold"))

        let broken = try decoder.decode(Brand.self, from: Data(#"{"businessName":"Sample Studio","headingFontStyle":"Bold"}"#.utf8))
        #expect(broken.headingFontStyle == nil)
        #expect(broken.businessName == "Sample Studio")
    }
}
