import SwiftUI

/// The Pilot: the little red plane that guides the tour. A 32×32 grid in the same
/// style as `PixelIcon`, only finer, because it shows at 64–96 points and a 16×16 grid would
/// look like a blob there. One character per pixel, "." transparent, the rest `PixelIcon.palette`.
struct PilotSprite: View {
    let size: CGFloat
    let mirrored: Bool

    /// `mirrored` turns the plane to face left, for pointing at something on its left.
    init(size: CGFloat, mirrored: Bool = false) {
        self.size = size
        self.mirrored = mirrored
    }

    /// A small red propeller plane in side view, flying to the right: a white cheat line along
    /// the fuselage, the tail fin, a low wing, one wheel, the propeller edge-on at the nose, and
    /// the pilot's capped head in the open cockpit (the user's pick of four, 13 Nov 2026).
    static let rows: [String] = [
        "................................",
        "................................",
        "................................",
        "................................",
        "................................",
        ".....kkk.........kkkk...........",
        ".....krrk.......khhhhk..........",
        ".....krrk.......khhhhk..........",
        ".....krrrk......khkssk.......k..",
        ".....krrrk......kffffk.......k..",
        ".....krrrrk.....kffffk.......k..",
        ".....krrrrrkkkkkkkkkkkkkk....k..",
        ".....krrrrrrrrrrrrrrrrrrrk...k..",
        ".....krrrrrrrrrrrrrrrrrrrrk..k..",
        ".kkkkkrrrrrrrrrrrrrrrrrrrrrkkk..",
        "krrrrrrrwwwwwwwwwwwwwwwwwwrkkk..",
        ".kkkkkrrrrrrrrrrrrrrrrrrrrrkkk..",
        ".....krrrrrrrrrrrrrrrrrrrrk..k..",
        ".....kmmmmmmmmmmmmmmmmmmmk...k..",
        ".....kkkkkmmmmmmmmmmmmkkk....k..",
        ".........krrrrrrrrrrrrk......k..",
        "........krrrrrrrrrrrrk.......k..",
        "........kmmmmmmmmmmmk........k..",
        "........kkkkkkkkkkkk............",
        ".............kk.................",
        "............kggk................",
        "............kggk................",
        ".............kk.................",
        "................................",
        "................................",
        "................................",
        "................................",
    ]

    /// The Windows 95 icon colours, plus the pilot's leather cap (h) and skin (f).
    static let palette: [Character: Color] = PixelIcon.palette.merging([
        "h": Color(hex: 0x8B5A2B),
        "f": Color(hex: 0xFFCC99),
    ]) { $1 }

    static let gridSize = 32

    var body: some View {
        Canvas { context, canvasSize in
            let cell = canvasSize.width / CGFloat(Self.gridSize)
            for (y, row) in Self.rows.enumerated() {
                for (x, char) in row.enumerated() {
                    guard let color = Self.palette[char] else { continue }
                    let gx = mirrored ? Self.gridSize - 1 - x : x
                    let rect = CGRect(x: CGFloat(gx) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: size, height: size)
        // The Pilot always comes with words in a speech balloon, so VoiceOver reads those.
        .accessibilityHidden(true)
    }
}
