import CoreText
import Foundation
import QuotePilotCore

/// One named style a font file offers: an instance of a variable font ("Bold", "ExtraBold Italic") or
/// one face of a font collection. The Brand screen lists them in its Style picker.
public struct FontStyleOption: Identifiable, Hashable, Sendable {
    /// What the brand keeps when this is the chosen style.
    public var style: FontStyle
    /// The style as the file names it: "Bold Italic".
    public var name: String
    /// The Weight axis value of a variable font (700), or nil when the file has no Weight axis.
    public var weight: Int?
    /// Whether this is the font's own default style: the one with every axis at its default value,
    /// or a collection's first face. It is what a document uses when no style is chosen.
    public var isDefault: Bool
    /// Whether the style is slanted (an Italic or Oblique style).
    public var italic: Bool = false

    public var id: String { style.postScriptName }

    /// The picker's label: "Bold Italic (700)", or just "Regular" for a font without a Weight axis.
    public var label: String {
        guard let weight else { return name }
        return "\(name) (\(weight))"
    }
}

/// Reads the styles out of a font file (TTF, OTF or a collection) and builds fonts from them.
///
/// Core Text lists a variable font's named instances as one font descriptor each, and a collection's
/// faces the same way. `FontStyle` picks one of those out, and the document draws with the font made
/// from that descriptor, so the PDF holds exactly that instance.
public enum FontFile {
    /// The file's styles, in the file's order. Empty when the file isn't a font.
    public static func styles(at url: URL) -> [FontStyleOption] {
        let descriptors = descriptors(at: url)
        guard let first = descriptors.first else { return [] }
        let axes = axes(of: first)
        let weightAxis = axes.first { $0.tag == "wght" }
        let defaultIndex = descriptors.firstIndex { atDefaults(variations(of: $0), axes) } ?? 0
        return descriptors.enumerated().map { index, descriptor in
            let explicit = variations(of: descriptor)
            var weight: Int?
            if let weightAxis { weight = Int((explicit["wght"] ?? weightAxis.defaultValue).rounded()) }
            return FontStyleOption(style: FontStyle(postScriptName: name(of: descriptor), variations: explicit),
                                   name: styleName(of: descriptor), weight: weight, isDefault: index == defaultIndex,
                                   italic: isItalic(descriptor))
        }
    }

    /// The style a font starts on when it is chosen for a document: of `options`, the one whose Weight
    /// axis value is nearest `weight` (700 is Bold, 400 Regular), among the styles slanted the way the
    /// font's default style is, so an Italic font stays Italic and an upright one stays upright.
    ///
    /// A tie goes to the style with fewer other axes set (Bold rather than "Bold G2", a grade variant),
    /// then to the heavier one. Nil when the font has no Weight axis: a static face, or a collection,
    /// has no weight to match and keeps its default.
    public static func closestStyle(toWeight weight: Int, in options: [FontStyleOption]) -> FontStyleOption? {
        guard let reference = options.first(where: \.isDefault) ?? options.first else { return nil }
        /// Smaller is better: how far from `weight`, how many other axes are set, how light.
        func rank(_ option: FontStyleOption) -> [Int] {
            let own = option.weight ?? 0
            return [abs(own - weight), option.style.variations.keys.filter { $0 != "wght" }.count, -own]
        }
        return options
            .filter { $0.weight != nil && $0.italic == reference.italic }
            .min { rank($0).lexicographicallyPrecedes(rank($1)) }
    }

    /// The style to keep when the font file at `url` is chosen for a document, as `closestStyle` picks it
    /// for `weight`. Nil for a font with nothing to choose by weight, which stays on its default.
    public static func startingStyle(at url: URL, nearWeight weight: Int) -> FontStyle? {
        closestStyle(toWeight: weight, in: styles(at: url))?.style
    }

    /// The font's name as people know it, or nil when the file isn't a font: "Georgia" for a font of
    /// one face, and for one with several styles the family ("Archivo"), since the Style picker says
    /// which style. (A variable font's own display name runs its default and chosen styles together.)
    public static func displayName(at url: URL) -> String? {
        let all = descriptors(at: url)
        guard let first = all.first else { return nil }
        let attribute = all.count > 1 ? kCTFontFamilyNameAttribute : kCTFontDisplayNameAttribute
        return CTFontDescriptorCopyAttribute(first, attribute) as? String
    }

    /// The font for `style` from the file at `url`; the file's own default style when `style` is nil or
    /// the file has no such style any more. Nil when the file isn't a font.
    ///
    ///
    /// `weight` asks for a heavier cut of the same style, on the scale `NSFont.Weight` uses (medium is
    /// 0.23, semibold 0.3): the file's own face of the same slant nearest that much heavier, never one
    /// lighter than the style itself. Body text asks for these where it is emphasised. A file with no
    /// heavier face gives the style itself, never a faked bold.
    public static func font(at url: URL, style: FontStyle?, size: CGFloat, weight: CGFloat = 0) -> CTFont? {
        let all = descriptors(at: url)
        guard !all.isEmpty else { return nil }
        var chosen = style.flatMap { descriptor(for: $0, in: all) } ?? defaultDescriptor(in: all)
        if weight > 0 { chosen = heavier(than: chosen, by: weight, in: all) }
        return CTFontCreateWithFontDescriptor(chosen, size, nil)
    }

    // MARK: Finding a style

    /// The file's default style: the first with every axis at its default value. A collection has no
    /// axes, so that is its first face.
    private static func defaultDescriptor(in all: [CTFontDescriptor]) -> CTFontDescriptor {
        let axes = axes(of: all[0])
        return all.first { atDefaults(variations(of: $0), axes) } ?? all[0]
    }

    private static func atDefaults(_ explicit: [String: Double], _ axes: [Axis]) -> Bool {
        axes.allSatisfy { abs((explicit[$0.tag] ?? $0.defaultValue) - $0.defaultValue) < 0.001 }
    }

    /// The descriptor `style` names: by PostScript name, and among several of that name by axis
    /// values. When the file has no style of that name, its default with the saved axis values put on.
    private static func descriptor(for style: FontStyle, in all: [CTFontDescriptor]) -> CTFontDescriptor? {
        let named = all.filter { name(of: $0) == style.postScriptName }
        if named.count == 1 { return named[0] }
        if let exact = named.first(where: { variations(of: $0) == style.variations }) { return exact }
        if let any = named.first { return any }
        guard !style.variations.isEmpty else { return nil }
        let known = Set(axes(of: all[0]).map(\.tag))
        var rebuilt = defaultDescriptor(in: all)
        for (tag, value) in style.variations where known.contains(tag) {
            rebuilt = CTFontDescriptorCreateCopyWithVariation(rebuilt, axisIdentifier(tag), value)
        }
        return rebuilt
    }

    /// The face of the same slant (and, in a variable font, the same width and other axes) as `base`
    /// that is heavier than it and nearest to `base`'s weight plus `weight`; `base` itself when the
    /// file has none.
    private static func heavier(than base: CTFontDescriptor, by weight: CGFloat, in all: [CTFontDescriptor]) -> CTFontDescriptor {
        func apartFromWeight(_ descriptor: CTFontDescriptor) -> [String: Double] {
            variations(of: descriptor).filter { $0.key != "wght" }
        }
        let baseWeight = weightTrait(of: base)
        let target = baseWeight + Double(weight)
        let italic = isItalic(base)
        let others = apartFromWeight(base)
        let candidates = all.filter {
            isItalic($0) == italic && apartFromWeight($0) == others && weightTrait(of: $0) > baseWeight + 0.001
        }
        return candidates.min { abs(weightTrait(of: $0) - target) < abs(weightTrait(of: $1) - target) } ?? base
    }

    // MARK: What Core Text says about a descriptor

    private static func name(of descriptor: CTFontDescriptor) -> String {
        CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? ""
    }

    private static func styleName(of descriptor: CTFontDescriptor) -> String {
        CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? name(of: descriptor)
    }

    private static func traits(of descriptor: CTFontDescriptor) -> [String: Any] {
        CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any] ?? [:]
    }

    /// How heavy the face is on Core Text's scale: 0 regular, 0.4 bold, below 0 lighter.
    private static func weightTrait(of descriptor: CTFontDescriptor) -> Double {
        (traits(of: descriptor)[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? 0
    }

    private static func isItalic(_ descriptor: CTFontDescriptor) -> Bool {
        let symbolic = (traits(of: descriptor)[kCTFontSymbolicTrait as String] as? NSNumber)?.uint32Value ?? 0
        return symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0
    }

    /// The axis values a descriptor sets, by axis tag. A variable font's default style sets none.
    private static func variations(of descriptor: CTFontDescriptor) -> [String: Double] {
        guard let raw = CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAttribute) as? [NSNumber: NSNumber]
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.map { (tag(axisIdentifier: $0.key.intValue), $0.value.doubleValue) })
    }

    private struct Axis {
        var tag: String
        var defaultValue: Double
    }

    private static func axes(of descriptor: CTFontDescriptor) -> [Axis] {
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        guard let list = CTFontCopyVariationAxes(font) as? [[String: Any]] else { return [] }
        return list.compactMap { axis in
            guard let id = (axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue,
                  let value = (axis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)?.doubleValue
            else { return nil }
            return Axis(tag: tag(axisIdentifier: id), defaultValue: value)
        }
    }

    /// An axis identifier is its four-letter tag read as a number: "wght" is 0x77676874.
    private static func tag(axisIdentifier id: Int) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((id >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func axisIdentifier(_ tag: String) -> NSNumber {
        NSNumber(value: tag.utf8.prefix(4).reduce(0) { ($0 << 8) | Int($1) })
    }

    // MARK: Reading the file once

    private static let cacheLock = NSLock()
    private static var cache: [String: (stamp: Date?, descriptors: [CTFontDescriptor])] = [:]

    /// The file's font descriptors. A document asks for the font once for every piece of text, so the
    /// file is read once and remembered until it changes.
    private static func descriptors(at url: URL) -> [CTFontDescriptor] {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let hit = cache[url.path], hit.stamp == stamp { return hit.descriptors }
        let read = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        if cache.count >= 16 { cache.removeAll() }
        cache[url.path] = (stamp, read)
        return read
    }
}
