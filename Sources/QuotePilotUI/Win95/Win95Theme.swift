import SwiftUI

/// The Windows 95 palette and type (spec §15). Views use these names, never raw hex.
public enum Win95 {
    // Faces and bevels
    public static let face = Color(hex: 0xC0C0C0)
    public static let highlight = Color(hex: 0xFFFFFF)
    public static let light = Color(hex: 0xDFDFDF)
    public static let shadow = Color(hex: 0x808080)
    public static let dark = Color(hex: 0x000000)

    // Areas
    public static let titleBar = Color(hex: 0x000080)
    public static let inactiveTitleBar = Color(hex: 0x808080)
    public static let desktop = Color(hex: 0x008080)
    public static let selection = Color(hex: 0x000080)
    public static let field = Color(hex: 0xFFFFFF)
    public static let text = Color(hex: 0x000000)
    public static let tooltip = Color(hex: 0xFFFFE1)
    /// A small grey aside on the window's face, dark enough to read (5.7:1 on `face`).
    public static let note = Color(hex: 0x404040)

    // Meaning, always paired with a word or an icon
    public static let overdue = Color(hex: 0xC00000)
    public static let paid = Color(hex: 0x007000)
    public static let warning = Color(hex: 0xFFFF00)

    // Type
    public static let body = Font.system(size: 13)
    public static let label = Font.system(size: 13, weight: .semibold)
    public static let title = Font.system(size: 13, weight: .bold)
    /// Title bars. 14 pt bold counts as large text, so white stays readable on the grey
    /// inactive bar (3.9:1, above the 3:1 large-text minimum).
    public static let windowTitle = Font.system(size: 14, weight: .bold)
    public static let small = Font.system(size: 11)
    public static let money = Font.system(size: 13).monospacedDigit()
    public static let readout = Font.system(size: 28, design: .monospaced)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
