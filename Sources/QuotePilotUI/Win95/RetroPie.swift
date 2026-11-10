import Foundation
import SwiftUI

/// A two-slice pie as Windows 95's drive Properties draws one: a tilted disc with a rim, filled flat
/// in blue and magenta, the rim a shade darker, every edge a one-pixel black line and nothing smoothed.
///
/// The first slice starts at three o'clock and runs clockwise, towards you, so a small one shows its
/// rim. With no share the disc is grey: there's nothing to divide yet.
struct PiePixels: Equatable {
    enum Slice: Equatable { case first, rest, empty }

    enum Paint: Equatable {
        case outline, top(Slice), rim(Slice)

        var topSlice: Slice? { if case .top(let slice) = self { slice } else { nil } }
        var rimSlice: Slice? { if case .rim(let slice) = self { slice } else { nil } }
    }

    let width: Int
    let height: Int
    /// `height` rows of `width` pixels; nil is see-through.
    let rows: [[Paint?]]

    /// `share` is the first slice's part of the disc, 0 to 1; nil for an empty grey disc. The disc's
    /// face is `width` by `faceHeight` and the rim `depth` pixels deep below it.
    init(share: Double?, width: Int, faceHeight: Int, depth: Int) {
        self.width = width
        height = faceHeight + depth
        let cx = Double(width) / 2, cy = Double(faceHeight) / 2
        // A quarter pixel inside the picture's edge, so the outermost pixel centres at the top, bottom
        // and sides still land on the disc.
        let rx = cx - 0.25, ry = cy - 0.25

        func slice(_ angle: Double) -> Slice {
            guard let share else { return .empty }
            return angle / (2 * .pi) < share ? .first : .rest
        }
        func fill(_ x: Int, _ y: Int) -> Paint? {
            let nx = (Double(x) + 0.5 - cx) / rx
            guard abs(nx) <= 1 else { return nil }
            let dy = Double(y) + 0.5 - cy
            let halfFace = ry * (1 - nx * nx).squareRoot()
            if abs(dy) <= halfFace {
                // On the face, the angle as on the round disc before it was tilted, so each slice keeps
                // its share of the area.
                let angle = atan2(dy / ry, nx)
                return .top(slice(angle < 0 ? angle + 2 * .pi : angle))
            }
            // The rim shows below the face's front edge; along it, the angle comes from across alone.
            guard dy > halfFace, dy <= halfFace + Double(depth) else { return nil }
            return .rim(slice(acos(nx)))
        }

        let fills = (0..<height).map { y in (0..<width).map { x in fill(x, y) } }
        func at(_ x: Int, _ y: Int) -> Paint? {
            fills.indices.contains(y) && fills[y].indices.contains(x) ? fills[y][x] : nil
        }
        rows = fills.indices.map { y in
            fills[y].indices.map { x -> Paint? in
                guard let paint = at(x, y) else { return nil }
                let around = [at(x - 1, y), at(x + 1, y), at(x, y - 1), at(x, y + 1)]
                // The disc's edge, and the face's front edge where the rim starts.
                if around.contains(where: { $0 == nil }) { return .outline }
                if paint.topSlice != nil, around.contains(where: { $0?.rimSlice != nil }) { return .outline }
                // Where one slice meets the other: the face's radii and the rim's upright line.
                let next = [at(x + 1, y), at(x, y + 1)]
                if let mine = paint.topSlice, next.contains(where: { $0?.topSlice.map { $0 != mine } == true }) {
                    return .outline
                }
                if let mine = paint.rimSlice, next.contains(where: { $0?.rimSlice.map { $0 != mine } == true }) {
                    return .outline
                }
                return paint
            }
        }
    }
}

/// The pie on screen, one point to a pixel.
struct RetroPie: View {
    /// The disc's face, width by height, and how deep its rim is, in pixels.
    struct Size {
        var width: Int, faceHeight: Int, depth: Int

        /// A deep rim, so it reads as a solid disc.
        static let large = Size(width: 140, faceHeight: 60, depth: 16)
        /// For a narrow window, where the large one would crowd the figures beside it.
        static let compact = Size(width: 112, faceHeight: 48, depth: 12)
    }

    /// The first slice's part, 0 to 1; nil for an empty grey disc.
    let share: Double?
    var size = Size.large
    /// Windows 95's drive pie colours, which the legend's swatches use too.
    static let firstColor = Color(hex: 0x0000FF)
    static let restColor = Color(hex: 0xFF00FF)

    static func color(_ paint: PiePixels.Paint) -> Color {
        switch paint {
        case .outline: Win95.dark
        case .top(.first): firstColor
        case .rim(.first): Color(hex: 0x000080)
        case .top(.rest): restColor
        case .rim(.rest): Color(hex: 0x800080)
        case .top(.empty): Win95.face
        case .rim(.empty): Win95.shadow
        }
    }

    var body: some View {
        let pixels = PiePixels(share: share, width: size.width, faceHeight: size.faceHeight, depth: size.depth)
        Canvas { context, _ in
            // One rectangle for each run of a colour along a row.
            for (y, row) in pixels.rows.enumerated() {
                var x = 0
                while x < row.count {
                    guard let paint = row[x] else { x += 1; continue }
                    var end = x + 1
                    while end < row.count, row[end] == paint { end += 1 }
                    context.fill(Path(CGRect(x: x, y: y, width: end - x, height: 1)), with: .color(Self.color(paint)),
                                 style: FillStyle(antialiased: false))
                    x = end
                }
            }
        }
        .frame(width: CGFloat(pixels.width), height: CGFloat(pixels.height))
    }
}
