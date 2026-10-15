import CoreText
import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// The style a font starts on when it is chosen: the instance nearest Bold for a heading, nearest
/// Regular for the body. `FontFile.closestStyle` is the one rule; these tests give it made-up styles,
/// then fonts that ship with macOS (the repo is public, so none is copied into it).
@Suite struct StartingStyleTests {
    // MARK: Made-up styles

    /// A style as `FontFile.styles` would list it. A variable font's default style sets no axes.
    private func style(_ name: String, _ weight: Int?, italic: Bool = false, isDefault: Bool = false,
                       other: [String: Double] = [:]) -> FontStyleOption {
        var variations = other
        if let weight, !isDefault { variations["wght"] = Double(weight) }
        return FontStyleOption(style: FontStyle(postScriptName: name, variations: variations), name: name,
                               weight: weight, isDefault: isDefault, italic: italic)
    }

    /// Weights 100...900 upright and italic, with SemiBold (600) as the default: like a variable font
    /// whose default is heavy for body text.
    private var archivoLike: [FontStyleOption] {
        let names = [(100, "Thin"), (200, "ExtraLight"), (300, "Light"), (400, "Regular"), (500, "Medium"),
                     (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold"), (900, "Black")]
        return names.map { style($1, $0, isDefault: $0 == 600) }
            + names.map { style($1 + "Italic", $0, italic: true) }
    }

    @Test func aHeadingStartsOnBoldAndABodyOnRegular() {
        let options = archivoLike
        #expect(FontFile.closestStyle(toWeight: 700, in: options)?.name == "Bold")
        #expect(FontFile.closestStyle(toWeight: 400, in: options)?.name == "Regular")
    }

    @Test func theNearestWeightWinsWhenThereIsNoExactOne() {
        let options = [style("Light", 300), style("Book", 360, isDefault: true), style("Semibold", 640),
                       style("Heavy", 900)]
        #expect(FontFile.closestStyle(toWeight: 700, in: options)?.name == "Semibold")
        #expect(FontFile.closestStyle(toWeight: 400, in: options)?.name == "Book")
        // Far from every style, it is still the nearest.
        #expect(FontFile.closestStyle(toWeight: 700, in: [style("Thin", 100, isDefault: true), style("Light", 300)])?.name == "Light")
    }

    @Test func aTieGoesToTheHeavierStyle() {
        let options = [style("Light", 300), style("Book", 400, isDefault: true), style("Heavy", 800)]
        #expect(FontFile.closestStyle(toWeight: 600, in: options)?.name == "Heavy")
    }

    /// An upright font never starts on an italic, whatever the weights; an italic font stays italic.
    @Test func theSlantIsTheOneTheDefaultStyleHas() {
        let upright = [style("Regular", 400, isDefault: true), style("Bold", 700),
                       style("BoldItalic", 700, italic: true), style("Italic", 400, italic: true)]
        #expect(FontFile.closestStyle(toWeight: 700, in: upright)?.name == "Bold")
        #expect(FontFile.closestStyle(toWeight: 400, in: upright)?.name == "Regular")

        // An italic default means the whole choice is among the italics, even with an upright one nearer.
        let slanted = [style("Regular", 400), style("Bold", 700),
                       style("Italic", 400, italic: true, isDefault: true), style("SemiBoldItalic", 600, italic: true)]
        #expect(FontFile.closestStyle(toWeight: 700, in: slanted)?.name == "SemiBoldItalic")
        #expect(FontFile.closestStyle(toWeight: 400, in: slanted)?.name == "Italic")
        #expect(FontFile.closestStyle(toWeight: 700, in: slanted)?.italic == true)
    }

    /// "Bold" and its grade variants all have weight 700: the plain Bold is the one to start on.
    @Test func aTieBetweenAStyleAndItsVariantsGoesToThePlainStyle() {
        let options = [style("Regular", 400, isDefault: true),
                       style("BoldG2", 700, other: ["GRAD": 0.09]), style("BoldG1", 700, other: ["GRAD": 0.04]),
                       style("Bold", 700), style("BoldG4", 700, other: ["GRAD": 0.18])]
        #expect(FontFile.closestStyle(toWeight: 700, in: options)?.name == "Bold")
    }

    @Test func aFontWithNothingToChooseByWeightHasNoStartingStyle() {
        #expect(FontFile.closestStyle(toWeight: 700, in: []) == nil)
        // A static face, and a collection's faces: no Weight axis.
        #expect(FontFile.closestStyle(toWeight: 700, in: [style("Regular", nil, isDefault: true)]) == nil)
        #expect(FontFile.closestStyle(toWeight: 400, in: [style("Regular", nil, isDefault: true), style("Bold", nil)]) == nil)
    }

    // MARK: Fonts that ship with macOS

    private func isPlain(_ option: FontStyleOption) -> Bool {
        Set(option.style.variations.keys).isSubset(of: ["wght"])
    }

    @Test(.enabled(if: SystemFonts.variable != nil))
    func aVariableFontStartsOnItsBoldForAHeadingAndItsRegularForABody() throws {
        let font = try #require(SystemFonts.variable)
        let all = FontFile.styles(at: font.url)
        let defaultStyle = all.first(where: \.isDefault)
        let defaultSlant = try #require(defaultStyle).italic

        for target in [700, 400] {
            let chosen = try #require(FontFile.closestStyle(toWeight: target, in: all), "\(target)")
            let weight = try #require(chosen.weight)
            // About the weight asked for, and no other style of the same slant is nearer to it.
            #expect(abs(weight - target) <= 100, "\(chosen.name) is \(weight) for \(target)")
            #expect(chosen.italic == defaultSlant)
            for other in all where other.italic == defaultSlant {
                if let w = other.weight { #expect(abs(w - target) >= abs(weight - target)) }
            }
            // A plain instance of that weight, if there is one, beats a width or grade variant of it.
            if all.contains(where: { isPlain($0) && $0.weight == weight && $0.italic == defaultSlant }) {
                #expect(isPlain(chosen))
            }
            // And it is what `startingStyle` hands the brand.
            #expect(FontFile.startingStyle(at: font.url, nearWeight: target) == chosen.style)
        }
        let bold = try #require(FontFile.closestStyle(toWeight: 700, in: all))
        let regular = try #require(FontFile.closestStyle(toWeight: 400, in: all))
        #expect(bold.weight! > regular.weight!)
        // The font really can make both.
        #expect(FontFile.font(at: font.url, style: bold.style, size: 12) != nil)
        #expect(FontFile.font(at: font.url, style: regular.style, size: 12) != nil)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: SystemFonts.georgia.path)))
    func aStaticFontHasNoStartingStyle() {
        #expect(FontFile.startingStyle(at: SystemFonts.georgia, nearWeight: 700) == nil)
        #expect(FontFile.startingStyle(at: SystemFonts.georgia, nearWeight: 400) == nil)
    }

    @Test func aFileThatIsNotAFontHasNoStartingStyle() {
        #expect(FontFile.startingStyle(at: URL(fileURLWithPath: "/no/such/font.ttf"), nearWeight: 700) == nil)
    }

    /// Variable fonts that are italic only (their default style is an italic): the pick is italic too.
    static let italicOnly: URL? = ["NewYorkItalic.ttf", "SFNSItalic.ttf", "SFCompactItalic.ttf"]
        .map { URL(fileURLWithPath: "/System/Library/Fonts/\($0)") }
        .first { url in
            let all = FontFile.styles(at: url)
            return all.filter({ $0.weight != nil }).count >= 4 && all.first(where: \.isDefault)?.italic == true
                && all.contains { ($0.weight ?? 0) >= 600 }
        }

    @Test(.enabled(if: StartingStyleTests.italicOnly != nil))
    func anItalicOnlyVariableFontKeepsItalic() throws {
        let url = try #require(StartingStyleTests.italicOnly)
        let all = FontFile.styles(at: url)
        #expect(all.allSatisfy { $0.italic })
        for target in [700, 400] {
            let chosen = try #require(FontFile.closestStyle(toWeight: target, in: all))
            #expect(chosen.italic)
            #expect(abs(chosen.weight! - target) <= 100)
            #expect(chosen.name.contains("Italic"))
            // The font made from that style is slanted too.
            let made = try #require(FontFile.font(at: url, style: FontFile.startingStyle(at: url, nearWeight: target), size: 12))
            #expect(CTFontGetSymbolicTraits(made).contains(.traitItalic))
        }
    }
}
