import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
import QuotePilotPDF
@testable import QuotePilotUI

/// A variable font that ships with macOS (the repo is public, so none is copied into it). Smaller files
/// first: the model copies the font into the test library's Assets.
enum VariableFixture {
    static let georgia = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Georgia.ttf")

    struct Font {
        var url: URL
        var weights: [FontStyleOption]
        var bold: FontStyleOption { weights.last { ($0.weight ?? 0) <= 700 }! }
        var lightest: FontStyleOption { weights.first! }
    }

    static let variable: Font? = {
        for name in ["NewYork.ttf", "SFNSItalic.ttf", "SFCompact.ttf", "SFNS.ttf"] {
            let url = URL(fileURLWithPath: "/System/Library/Fonts/\(name)")
            let plain = FontFile.styles(at: url)
                .filter { $0.weight != nil && Set($0.style.variations.keys).isSubset(of: ["wght"]) }
                .sorted { $0.weight! < $1.weight! }
            if plain.count >= 4, (plain.last?.weight ?? 0) >= 700 { return Font(url: url, weights: plain) }
        }
        return nil
    }()

    static var available: Bool { variable != nil }

    /// A variable font whose styles are all italic, so its default style is an italic.
    static let italicOnly: URL? = ["NewYorkItalic.ttf", "SFNSItalic.ttf", "SFCompactItalic.ttf"]
        .map { URL(fileURLWithPath: "/System/Library/Fonts/\($0)") }
        .first { url in
            let all = FontFile.styles(at: url)
            return all.filter { $0.weight != nil }.count >= 4 && all.first(where: \.isDefault)?.italic == true
                && all.contains { ($0.weight ?? 0) >= 600 }
        }

    /// Whether the PDF names the instance as an embedded font: by its own name, or (for a font that is
    /// named after its base face) with its Weight spelled out in 16.16 hex, "…wght2BC0000" for 700.
    static func embeds(_ option: FontStyleOption, in pdf: Data) -> Bool {
        let bytes = String(decoding: pdf, as: UTF8.self)
        if bytes.contains(option.style.postScriptName.trimmingCharacters(in: CharacterSet(charactersIn: "."))) { return true }
        guard let weight = option.style.variations["wght"] else { return false }
        return bytes.contains("wght" + String(Int(weight * 65536), radix: 16, uppercase: true))
    }
}

@MainActor
@Suite struct HeadingFontStyleTests {
    // MARK: The picker's choices

    @Test(.enabled(if: VariableFixture.available))
    func theStylePickerOffersTheFontsNamedStylesWithTheirWeights() throws {
        let font = try #require(VariableFixture.variable)
        let options = FontStylePicker.options(for: font.url)
        #expect(options.count > 1)
        for option in options where option.weight != nil {
            #expect(option.label == "\(option.name) (\(option.weight!))")
        }
        let bold = font.bold
        #expect(options.contains { $0.id == bold.id && $0.label == "\(bold.name) (\(bold.weight!))" })
        #expect(bold.label.contains("Bold"))
    }

    @Test(.enabled(if: VariableFixture.available))
    func noChosenStyleShowsTheFontsDefaultAndPickingItStoresNothing() throws {
        let font = try #require(VariableFixture.variable)
        let options = FontStylePicker.options(for: font.url)
        let fontDefault = try #require(options.first { $0.isDefault })
        #expect(options.filter { $0.isDefault }.count == 1)
        #expect(FontStylePicker.selection(nil, in: options) == fontDefault.id)
        #expect(FontStylePicker.stored(fontDefault.id, in: options) == nil)

        // Picking Bold keeps it, and the pop-up then shows it.
        let bold = font.bold
        #expect(FontStylePicker.stored(bold.id, in: options) == bold.style)
        #expect(FontStylePicker.selection(bold.style, in: options) == bold.id)
        // A style the font no longer has shows the default instead.
        #expect(FontStylePicker.selection(FontStyle(postScriptName: "Gone-Bold"), in: options) == fontDefault.id)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: VariableFixture.georgia.path)))
    func aFontWithOneStyleHasNothingToChooseSoNoPicker() {
        // The picker is only shown for more than one style.
        #expect(FontStylePicker.options(for: VariableFixture.georgia).count == 1)
        #expect(FontStylePicker.options(for: nil).isEmpty)
        #expect(FontStylePicker.options(for: URL(fileURLWithPath: "/no/such/font.ttf")).isEmpty)
    }

    // MARK: Saved with the brand, used in the PDF

    @Test(.enabled(if: VariableFixture.available))
    func aChosenStyleIsSavedWithTheBrandAndUsedInThePDF() throws {
        let font = try #require(VariableFixture.variable)
        let model = try UIFixture.sampleModel()
        model.importHeadingFont(from: font.url)
        #expect(model.message == nil)
        #expect(model.library.brand.headingFontFile != nil)
        // A new font starts on its Bold, and the Style picker can put it back on the font's default.
        #expect(model.library.brand.headingFontStyle != nil)
        #expect(model.library.brand.headingFontStyle == FontFile.startingStyle(at: font.url, nearWeight: 700))
        model.brandBinding.wrappedValue.headingFontStyle = nil
        let plain = model.pdf(model.sampleContent())
        #expect(!VariableFixture.embeds(font.bold, in: plain))

        model.brandBinding.wrappedValue.headingFontStyle = font.bold.style
        #expect(model.message == nil)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.headingFontStyle == font.bold.style)
        #expect(model.headingFontURL != nil)
        let bold = model.pdf(model.sampleContent())
        #expect(VariableFixture.embeds(font.bold, in: bold))
        #expect(bold != plain)
    }

    /// A style belongs to the font it was chosen from: a new font, or none, starts on its default.
    @Test(.enabled(if: VariableFixture.available && FileManager.default.fileExists(atPath: VariableFixture.georgia.path)))
    func aStyleIsForgottenWhenTheFontIsReplacedOrRemoved() throws {
        let font = try #require(VariableFixture.variable)
        let model = try UIFixture.sampleModel()
        model.importHeadingFont(from: font.url)
        model.brandBinding.wrappedValue.headingFontStyle = font.bold.style
        #expect(model.library.brand.headingFontStyle == font.bold.style)

        model.importHeadingFont(from: VariableFixture.georgia)
        #expect(model.library.brand.headingFontFile != nil)
        #expect(model.library.brand.headingFontStyle == nil)

        model.importHeadingFont(from: font.url)
        model.brandBinding.wrappedValue.headingFontStyle = font.bold.style
        model.removeHeadingFont()
        #expect(model.library.brand.headingFontFile == nil)
        #expect(model.library.brand.headingFontStyle == nil)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.headingFontStyle == nil)
    }

    @Test(.enabled(if: VariableFixture.available))
    func aVariableFontIsNamedByItsFamilyAndAStaticOneByItsName() throws {
        let font = try #require(VariableFixture.variable)
        let model = try UIFixture.sampleModel()
        #expect(model.headingFontName == nil)
        model.importHeadingFont(from: font.url)
        let name = try #require(model.headingFontName)
        // The family, not the default and the lightest style run together.
        #expect(!name.contains(font.lightest.name))
        #expect(FontFile.displayName(at: font.url) == name)
        if FileManager.default.fileExists(atPath: VariableFixture.georgia.path) {
            model.importHeadingFont(from: VariableFixture.georgia)
            #expect(model.headingFontName == "Georgia")
        }
    }

    // MARK: A new font starts on a sensible style

    /// The style the Style picker shows for a font in Assets whose brand has kept `style`.
    private func shown(_ style: FontStyle?, in url: URL?) -> FontStyleOption? {
        let options = FontStylePicker.options(for: url)
        let id = FontStylePicker.selection(style, in: options)
        return options.first { $0.id == id }
    }

    @Test(.enabled(if: VariableFixture.available))
    func aVariableFontStartsOnBoldAsTheHeadingAndRegularAsTheBody() throws {
        let font = try #require(VariableFixture.variable)
        let model = try UIFixture.sampleModel()
        model.importHeadingFont(from: font.url)
        model.importBodyFont(from: font.url)
        #expect(model.message == nil)

        let heading = try #require(shown(model.library.brand.headingFontStyle, in: model.headingFontURL))
        let body = try #require(shown(model.library.brand.bodyFontStyle, in: model.bodyFontURL))
        #expect(abs(heading.weight! - 700) <= 100, "heading starts on \(heading.label)")
        #expect(abs(body.weight! - 400) <= 100, "body starts on \(body.label)")
        #expect(heading.weight! > body.weight!)
        // Kept with the brand, and shown by the Style picker as the chosen style.
        #expect(model.library.brand.headingFontStyle == heading.style)
        #expect(model.library.brand.bodyFontStyle == body.style)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.headingFontStyle == heading.style)
        #expect(saved.brand.bodyFontStyle == body.style)

        // The body is drawn in it, and the user can still choose another style.
        #expect(VariableFixture.embeds(body, in: model.pdf(model.sampleContent())))
        model.brandBinding.wrappedValue.bodyFontStyle = font.lightest.style
        #expect(model.library.brand.bodyFontStyle == font.lightest.style)
        #expect(model.library.brand.headingFontStyle == heading.style)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: VariableFixture.georgia.path)))
    func aStaticFontStaysOnItsOneStyle() throws {
        let model = try UIFixture.sampleModel()
        model.importHeadingFont(from: VariableFixture.georgia)
        model.importBodyFont(from: VariableFixture.georgia)
        #expect(model.library.brand.headingFontFile != nil)
        #expect(model.library.brand.bodyFontFile != nil)
        #expect(model.library.brand.headingFontStyle == nil)
        #expect(model.library.brand.bodyFontStyle == nil)
    }

    @Test(.enabled(if: VariableFixture.italicOnly != nil))
    func anItalicOnlyVariableFontKeepsItalic() throws {
        let url = try #require(VariableFixture.italicOnly)
        let model = try UIFixture.sampleModel()
        model.importHeadingFont(from: url)
        model.importBodyFont(from: url)
        let heading = try #require(shown(model.library.brand.headingFontStyle, in: model.headingFontURL))
        let body = try #require(shown(model.library.brand.bodyFontStyle, in: model.bodyFontURL))
        #expect(heading.italic && body.italic)
        #expect(abs(heading.weight! - 700) <= 100)
        #expect(abs(body.weight! - 400) <= 100)
    }

    /// The rule applies when a file is chosen, never to a library already holding a font: one with no
    /// style recorded keeps drawing the font's own default, however it is changed or saved.
    @Test(.enabled(if: VariableFixture.available))
    func aLibraryWithNoRecordedStyleKeepsItsLook() throws {
        let font = try #require(VariableFixture.variable)
        let model = try UIFixture.sampleModel()
        model.importHeadingFont(from: font.url)
        model.importBodyFont(from: font.url)
        model.brandBinding.wrappedValue.headingFontStyle = nil
        model.brandBinding.wrappedValue.bodyFontStyle = nil

        model.brandBinding.wrappedValue.businessName = "Another Studio"
        model.brandBinding.wrappedValue.accentHex = "#223344"
        #expect(model.library.brand.businessName == "Another Studio")
        #expect(model.library.brand.headingFontStyle == nil)
        #expect(model.library.brand.bodyFontStyle == nil)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.headingFontStyle == nil)
        #expect(saved.brand.bodyFontStyle == nil)
        #expect(saved.brand.headingFontFile == model.library.brand.headingFontFile)
        #expect(saved.brand.bodyFontFile == model.library.brand.bodyFontFile)
    }

    // MARK: On the Look tab

    @Test(.enabled(if: VariableFixture.available))
    func theLookTabDrawsWithAVariableHeadingFont() throws {
        let font = try #require(VariableFixture.variable)
        let model = try UIFixture.sampleModel()
        model.importHeadingFont(from: font.url)
        model.brandBinding.wrappedValue.headingFontStyle = font.bold.style
        let rep = Snapshot.render(BrandView(model: model, tab: .look).background(Win95.face),
                                  size: CGSize(width: 980, height: 620), name: "brand-look-variable-font")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
