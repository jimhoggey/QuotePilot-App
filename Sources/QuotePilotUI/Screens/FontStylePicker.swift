import QuotePilotCore
import QuotePilotPDF
import SwiftUI

/// "Style:" under a font's Choose… and Remove: the named styles in the font file, such as Bold or
/// ExtraBold Italic, each with its weight number when the font has a Weight axis ("Bold (700)").
/// A font with only one style has nothing to choose, so the picker isn't shown.
///
/// A native pop-up, like the client picker, so it works from the keyboard and with VoiceOver.
struct FontStylePicker: View {
    /// The chosen font file in Assets, or nil when there's none.
    let fontURL: URL?
    /// What VoiceOver calls the pop-up: "Heading font style".
    let label: String
    /// The brand's chosen style; nil is the font's own default.
    @Binding var style: FontStyle?

    /// The styles to offer for a font file: none without a file, or for a font that isn't one.
    static func options(for url: URL?) -> [FontStyleOption] {
        url.map(FontFile.styles(at:)) ?? []
    }

    /// Which style the pop-up shows: the chosen one, or the font's default when none is chosen or the
    /// font no longer has the one that was.
    static func selection(_ style: FontStyle?, in options: [FontStyleOption]) -> String? {
        if let style, options.contains(where: { $0.id == style.postScriptName }) { return style.postScriptName }
        return options.first(where: \.isDefault)?.id ?? options.first?.id
    }

    /// What the brand keeps when `id` is picked: nothing for the font's default, so a font that is
    /// left alone stays on its default whatever it is.
    static func stored(_ id: String, in options: [FontStyleOption]) -> FontStyle? {
        guard let option = options.first(where: { $0.id == id }), !option.isDefault else { return nil }
        return option.style
    }

    var body: some View {
        let options = Self.options(for: fontURL)
        if options.count > 1 {
            Win95FieldRow("Style:") {
                Picker(label, selection: Binding(
                    get: { Self.selection(style, in: options) ?? "" },
                    set: { style = Self.stored($0, in: options) })) {
                    ForEach(options) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
    }
}
