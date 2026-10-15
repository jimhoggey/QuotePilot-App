import SwiftUI

// MARK: Buttons

public struct Win95ButtonStyle: ButtonStyle {
    /// The default button gets the heavy black outline, as in Windows 95.
    public var isDefault: Bool

    public init(isDefault: Bool = false) {
        self.isDefault = isDefault
    }

    public func makeBody(configuration: Configuration) -> some View {
        Win95ButtonBody(configuration: configuration, isDefault: isDefault)
    }
}

struct Win95ButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isDefault: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Win95.body)
            .foregroundStyle(isEnabled ? Win95.text : Win95.shadow)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(minWidth: 75, minHeight: 23)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .background(Win95.face)
            .overlay(Bevel(configuration.isPressed ? .pressed : .raised))
            .padding(isDefault ? 1 : 0)
            .overlay(isDefault ? Rectangle().strokeBorder(Win95.dark, lineWidth: 1) : nil)
            .contentShape(Rectangle())
    }
}

public extension ButtonStyle where Self == Win95ButtonStyle {
    static var win95: Win95ButtonStyle { Win95ButtonStyle() }
    static var win95Default: Win95ButtonStyle { Win95ButtonStyle(isDefault: true) }
}

/// The square toolbar button: an icon above a short label.
public struct Win95ToolbarButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Win95ToolbarButtonBody(configuration: configuration)
    }
}

struct Win95ToolbarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Win95.small)
            .foregroundStyle(isEnabled ? Win95.text : Win95.shadow)
            .opacity(isEnabled ? 1 : 0.6)
            .frame(width: 80, height: 58)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .background(Win95.face)
            .overlay(Bevel(configuration.isPressed ? .pressed : .raised))
            .contentShape(Rectangle())
    }
}

// MARK: Text

/// A sunken white text field with the dotted focus rectangle.
public struct Win95TextField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    public init(_ label: String, text: Binding<String>, prompt: String = "") {
        self.label = label
        self._text = text
        self.prompt = prompt
    }

    public var body: some View {
        TextField(label, text: $text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(Win95.body)
            .foregroundStyle(Win95.text)
            .focused($focused)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(Win95.field)
            .overlay(Bevel(.sunken))
            .overlay(focused ? FocusRect().padding(3) : nil)
            .accessibilityLabel(label)
    }
}

/// A sunken multi-line editor.
public struct Win95TextEditor: View {
    @Binding var text: String

    public init(text: Binding<String>) {
        self._text = text
    }

    public var body: some View {
        TextEditor(text: $text)
            .font(Win95.body)
            .foregroundStyle(Win95.text)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Win95.field)
            .overlay(Bevel(.sunken))
            // A text editor reports no baseline of its own, which left a row's label floating
            // above the first line. The first line of 13 pt text sits about 16 pt down: 4 of
            // padding plus the line's ascent.
            .alignmentGuide(.firstTextBaseline) { $0[.top] + 16 }
    }
}

/// "Label:" on the left, the control on the right, as in Windows 95 dialogs.
public struct Win95FieldRow<Content: View>: View {
    let label: String
    let labelWidth: CGFloat
    let content: Content

    public init(_ label: String, labelWidth: CGFloat = 96, @ViewBuilder content: () -> Content) {
        self.label = label
        self.labelWidth = labelWidth
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(Win95.body)
                .foregroundStyle(Win95.text)
                .frame(width: labelWidth, alignment: .leading)
            content
        }
    }
}

// MARK: Group box

/// An etched frame with its title set into the top edge.
public struct Win95GroupBoxStyle: GroupBoxStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Bevel(.etched).padding(.top, 7))
            .overlay(alignment: .topLeading) {
                configuration.label
                    .font(Win95.label)
                    .foregroundStyle(Win95.text)
                    .padding(.horizontal, 3)
                    .background(Win95.face)
                    .padding(.leading, 8)
            }
    }
}

public extension GroupBoxStyle where Self == Win95GroupBoxStyle {
    static var win95: Win95GroupBoxStyle { Win95GroupBoxStyle() }
}

// MARK: Checkbox and radio

/// A sunken white square with a black tick.
public struct Win95CheckboxStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Win95.field
                    if configuration.isOn { PixelGlyph(PixelGlyph.tick).frame(width: 7, height: 7) }
                }
                .frame(width: 13, height: 13)
                .overlay(Bevel(.sunken))
                configuration.label
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

public extension ToggleStyle where Self == Win95CheckboxStyle {
    static var win95: Win95CheckboxStyle { Win95CheckboxStyle() }
}

/// A small glyph for controls (a tick, an arrow, a cross), drawn from rows where "k" is a pixel.
/// Give it a frame of one point per pixel (7×7 for the tick) so every pixel lands whole.
public struct PixelGlyph: View {
    public static let tick = ["......k", ".....kk", "k...kkk", "kk.kkk.", "kkkkk..", ".kkk...", "..k...."]
    public static let up = ["...k...", "..kkk..", ".kkkkk.", "kkkkkkk"]
    public static let down = ["kkkkkkk", ".kkkkk.", "..kkk..", "...k..."]
    public static let cross = ["kk...kk", ".kk.kk.", "..kkk..", ".kk.kk.", "kk...kk"]

    let rows: [String]
    let color: Color

    public init(_ rows: [String], color: Color = Win95.dark) {
        self.rows = rows
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            let columns = rows.map(\.count).max() ?? 1
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(max(rows.count, 1)))
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() where char == "k" {
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Round option buttons, one choice per row.
public struct Win95RadioGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    public init(selection: Binding<Value>, options: [(Value, String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.0
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Win95.field)
                            Circle().strokeBorder(Win95.shadow, lineWidth: 1)
                            if selection == option.0 {
                                Circle().fill(Win95.dark).frame(width: 5, height: 5)
                            }
                        }
                        .frame(width: 13, height: 13)
                        Text(option.1)
                            .font(Win95.body)
                            .foregroundStyle(Win95.text)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }
    }
}

// MARK: Progress

/// The chunky segmented Windows 95 progress bar.
public struct Win95Progress: View {
    let fraction: Double

    public init(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
    }

    public var body: some View {
        GeometryReader { geometry in
            let block: CGFloat = 8, gap: CGFloat = 2
            let count = max(0, Int((geometry.size.width - 4 + gap) / (block + gap)))
            let filled = Int((Double(count) * fraction).rounded())
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    Rectangle()
                        .fill(index < filled ? Win95.selection : Color.clear)
                        .frame(width: block)
                }
            }
            .padding(2)
        }
        .frame(height: 16)
        .background(Win95.field)
        .overlay(Bevel(.sunken))
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}
