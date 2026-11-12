import SwiftUI

/// The Pilot: the paper-plane helper that guides the first-run tour. A 32×32 grid in the same
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

    /// The plane flies to the right: nose at the right, tail at the left. The lit top wing is
    /// white, the keel below the fold is grey, dithered towards the tail. The aviator goggles sit
    /// across the fold at the front like a face, the scarf is knotted behind them and streams
    /// back through the tail notch with a forked tip, and a smirk sits on the keel. The keel is
    /// left solid around the smirk so it isn't lost in the dither.
    static let rows: [String] = [
        "................................",
        "..kk............................",
        "...kkk..........................",
        "...kswkk........................",
        "....kswskkk.....................",
        ".....kswswskk...................",
        "......kswswswkk.................",
        "......kwswswwwwkkk..............",
        ".......kwswswwwwwwkk............",
        "........kwswwwwwwwwwkk..........",
        ".........kwswwwwwwwwwwkkk.......",
        "..kkk....kswwwkkkkkwwwkkkkk.....",
        ".krrmkk...kkkkoooookwkoooookk...",
        "krrmkrrkkkrrrkowccokkkowccokgkk.",
        "krmkrrrrrrrmrkocktokokocktokkk..",
        ".kkkrrrrmmmrrkottmokkkottmok....",
        "..krrrmmkkkkkkoooookskoooook....",
        ".krmmkkk......kkkkkssskkkkk.....",
        "krmkk.........kgssssssgk........",
        "kmk..........kkssssksgk.........",
        "kk...........kskkkkskk..........",
        "............ksgsgsgk............",
        "............kgsgskk.............",
        "...........kgsggk...............",
        "...........ksggk................",
        "..........ksgkk.................",
        "..........kgk...................",
        ".........kgk....................",
        ".........kk.....................",
        "........k.......................",
        "................................",
        "................................",
    ]

    static let gridSize = 32

    /// Draws the sprite into a canvas that is drawing other things too, such as the start-up
    /// animation: `cell` points per grid pixel, the top-left corner at `origin`.
    static func draw(in context: inout GraphicsContext, origin: CGPoint, cell: CGFloat, mirrored: Bool = false) {
        for (y, row) in rows.enumerated() {
            for (x, char) in row.enumerated() {
                guard let color = PixelIcon.palette[char] else { continue }
                let gx = mirrored ? gridSize - 1 - x : x
                let rect = CGRect(x: origin.x + CGFloat(gx) * cell, y: origin.y + CGFloat(y) * cell,
                                  width: cell, height: cell)
                context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
            }
        }
    }

    var body: some View {
        Canvas { context, canvasSize in
            Self.draw(in: &context, origin: .zero, cell: canvasSize.width / CGFloat(Self.gridSize), mirrored: mirrored)
        }
        .frame(width: size, height: size)
        // The Pilot always comes with words in a speech balloon, so VoiceOver reads those.
        .accessibilityHidden(true)
    }
}
