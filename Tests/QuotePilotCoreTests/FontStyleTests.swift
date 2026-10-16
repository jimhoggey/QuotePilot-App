import Foundation
import Testing
@testable import QuotePilotCore

/// The brand's heading-font and body-font styles (a variable font's Bold, say) are saved beside the
/// font's file name.
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

    /// A library saved before the body font existed has neither of its fields; it loads with the
    /// standard Mac font, and a body font and style that are there round-trip beside the heading's.
    @Test func aBrandWithoutABodyFontLoadsWithNone() throws {
        let old = try Library.makeDecoder().decode(
            Brand.self, from: Data(#"{"businessName":"Sample Studio","headingFontFile":"heading-font-1A2B3C4D.ttf","headingFontStyle":{"postScriptName":"ArchivoItalic-Bold","variations":{"wght":700}}}"#.utf8))
        #expect(old.bodyFontFile == nil)
        #expect(old.bodyFontStyle == nil)
        #expect(old.headingFontStyle == FontStyle(postScriptName: "ArchivoItalic-Bold", variations: ["wght": 700]))

        var brand = Brand()
        #expect(brand.bodyFontFile == nil)
        #expect(brand.bodyFontStyle == nil)
        brand.headingFontFile = "heading-font-1A2B3C4D.ttf"
        brand.bodyFontFile = "body-font-5E6F7A8B.ttf"
        brand.bodyFontStyle = FontStyle(postScriptName: "Archivo-Regular", variations: ["wght": 400, "wdth": 100])
        let loaded = try Library.makeDecoder().decode(Brand.self, from: try Library.makeEncoder().encode(brand))
        #expect(loaded.bodyFontFile == "body-font-5E6F7A8B.ttf")
        #expect(loaded.bodyFontStyle == FontStyle(postScriptName: "Archivo-Regular", variations: ["wght": 400, "wdth": 100]))
        #expect(loaded.headingFontStyle == nil)
        #expect(loaded == brand)
        // With none set, nothing is written, so the file is as it was before the fields existed.
        let plain = String(decoding: try Library.makeEncoder().encode(Brand()), as: UTF8.self)
        #expect(!plain.contains("bodyFont"))

        let library = try Library.makeDecoder().decode(
            Library.self, from: Data(#"{"format":1,"brand":{"businessName":"Sample Studio","quoteValidDays":20}}"#.utf8))
        #expect(library.brand.bodyFontFile == nil)
        #expect(library.brand.bodyFontStyle == nil)
        #expect(library.brand.quoteValidDays == 20)

        // A body style that can't be read is the font's default, not a library that won't open.
        let broken = try Library.makeDecoder().decode(
            Brand.self, from: Data(#"{"bodyFontFile":"body-font-5E6F7A8B.ttf","bodyFontStyle":7}"#.utf8))
        #expect(broken.bodyFontFile == "body-font-5E6F7A8B.ttf")
        #expect(broken.bodyFontStyle == nil)
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
