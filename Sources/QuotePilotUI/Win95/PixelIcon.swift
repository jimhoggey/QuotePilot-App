import QuotePilotCore
import SwiftUI

/// The app's icons, drawn from 16×16 grids (spec §15). Each character is one pixel; "." is
/// transparent and the rest are the Windows 95 icon colours in `palette`.
public enum PixelIcon: String, CaseIterable, Sendable {
    case quote, invoice, receipt, client, dashboard, activity, brand
    case mail, pdf, payment, warning, info, question, folder, tick, cross

    /// The Windows 95 16-colour icon palette.
    static let palette: [Character: Color] = [
        "k": Color(hex: 0x000000), "w": Color(hex: 0xFFFFFF), "s": Color(hex: 0xC0C0C0),
        "g": Color(hex: 0x808080), "n": Color(hex: 0x000080), "b": Color(hex: 0x0000FF),
        "t": Color(hex: 0x008080), "c": Color(hex: 0x00FFFF), "y": Color(hex: 0xFFFF00),
        "o": Color(hex: 0x808000), "m": Color(hex: 0x800000), "r": Color(hex: 0xFF0000),
        "G": Color(hex: 0x008000), "l": Color(hex: 0x00FF00), "p": Color(hex: 0x800080),
    ]

    public var grid: [String] {
        switch self {
        case .quote:
            // A page with a green tick.
            return ["..kkkkkkkkk.....",
                    "..kwwwwwwwkk....",
                    "..kwwwwwwwkwk...",
                    "..kwwwwwwwkkkk..",
                    "..kwwwwwwwwwwk..",
                    "..kwgggggggwwk..",
                    "..kwwwwwwwwwwk..",
                    "..kwgggggwwwwk..",
                    "..kwwwwwwwwGwk..",
                    "..kwwwwwwwGGwk..",
                    "..kwGwwwwGGwwk..",
                    "..kwGGwwGGwwwk..",
                    "..kwwGGGGwwwwk..",
                    "..kwwwGGwwwwwk..",
                    "..kwwwwwwwwwwk..",
                    "..kkkkkkkkkkkk.."]
        case .invoice:
            // A page with a dollar sign.
            return ["..kkkkkkkkk.....",
                    "..kwwwwwwwkk....",
                    "..kwwwwwwwkwk...",
                    "..kwwwwwwwkkkk..",
                    "..kwwwwwwwwwwk..",
                    "..kwwwwwGwwwwk..",
                    "..kwwwwGGGGwwk..",
                    "..kwwwGwGwwwwk..",
                    "..kwwwwGGGwwwk..",
                    "..kwwwwwGwGwwk..",
                    "..kwwwGGGGwwwk..",
                    "..kwwwwwGwwwwk..",
                    "..kwwwwwwwwwwk..",
                    "..kwggggggggwk..",
                    "..kwwwwwwwwwwk..",
                    "..kkkkkkkkkkkk.."]
        case .receipt:
            // A till slip with a torn bottom edge.
            return ["...kkkkkkkkkk...",
                    "...kwwwwwwwwk...",
                    "...kwggggggwk...",
                    "...kwwwwwwwwk...",
                    "...kwggggwwwk...",
                    "...kwwwwwwwwk...",
                    "...kwggwwggwk...",
                    "...kwwwwwwwwk...",
                    "...kwggwwggwk...",
                    "...kwwwwwwwwk...",
                    "...kwwwkkkkwk...",
                    "...kwwwwwwwwk...",
                    "...kwwwwGGGwk...",
                    "...kwwwwwwwwk...",
                    "...kwkwkwkwkk...",
                    "....k.k.k.k....."]
        case .client:
            // Head and shoulders.
            return ["................",
                    "......kkkk......",
                    ".....kyyyyk.....",
                    "....kyyyyyyk....",
                    "....kykyykyk....",
                    "....kyyyyyyk....",
                    "....kyykkyyk....",
                    ".....kyyyyk.....",
                    "......kkkk......",
                    "....kknnnnkk....",
                    "...knnnnnnnnk...",
                    "..knnnnnnnnnnk..",
                    "..knnnnnnnnnnk..",
                    "..knnnnnnnnnnk..",
                    "..knnnnnnnnnnk..",
                    "..kkkkkkkkkkkk.."]
        case .dashboard:
            // A bar chart.
            return ["................",
                    ".k..............",
                    ".k..............",
                    ".k......bb......",
                    ".k......bb......",
                    ".k......bb......",
                    ".k...GG.bb......",
                    ".k...GG.bb.tt...",
                    ".k...GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".kkkkkkkkkkkkkk.",
                    "................"]
        case .activity:
            // A clipboard with a list.
            return ["......kkkk......",
                    "..oooksssskooo..",
                    "..ookkkkkkkkoo..",
                    "..okwwwwwwwwko..",
                    "..okwkwggggwko..",
                    "..okwwwwwwwwko..",
                    "..okwkwggggwko..",
                    "..okwwwwwwwwko..",
                    "..okwkwgggwwko..",
                    "..okwwwwwwwwko..",
                    "..okwkwggggwko..",
                    "..okwwwwwwwwko..",
                    "..okwkwggwwwko..",
                    "..okwwwwwwwwko..",
                    "..okkkkkkkkkko..",
                    "..oooooooooooo.."]
        case .brand:
            // A paint palette.
            return ["................",
                    "................",
                    ".....kkkkkk.....",
                    "...kkooooookk...",
                    "..koorroobbook..",
                    ".kooorroobboook.",
                    "koooooooooollook",
                    "koo..oooooollook",
                    "koo..ooooooooook",
                    "kooooooyyooooook",
                    ".koooooyyoooook.",
                    "..kooooooooook..",
                    "...kkooooookk...",
                    ".....kkkkkk.....",
                    "................",
                    "................"]
        case .mail:
            // An envelope.
            return ["................",
                    "................",
                    "................",
                    "kkkkkkkkkkkkkkkk",
                    "kkwwwwwwwwwwwwkk",
                    "kwkwwwwwwwwwwkwk",
                    "kwwkwwwwwwwwkwwk",
                    "kwwwkwwwwwwkwwwk",
                    "kwwwwkwwwwkwwwwk",
                    "kwwwwwkwwkwwwwwk",
                    "kwwwwwwkkwwwwwwk",
                    "kwwwwwwwwwwwwwwk",
                    "kwwwwwwwwwwwwwwk",
                    "kkkkkkkkkkkkkkkk",
                    "................",
                    "................"]
        case .pdf:
            // A printer with a page coming out.
            return ["................",
                    "....kkkkkkkk....",
                    "....kwwwwwwk....",
                    "....kwggggwk....",
                    "....kwwwwwwk....",
                    "..kkkkkkkkkkkk..",
                    ".kssssssssssssk.",
                    ".kssssssssssGsk.",
                    ".kssssssssssssk.",
                    ".kggggggggggggk.",
                    ".kkkkkkkkkkkkkk.",
                    "...kwwwwwwwwk...",
                    "...kwggggggwk...",
                    "...kwwwwwwwwk...",
                    "...kkkkkkkkkk...",
                    "................"]
        case .payment:
            // A gold coin with a dollar sign.
            return ["................",
                    ".....kkkkkk.....",
                    "...kkyyyyyykk...",
                    "..kyyyyyyyyyyk..",
                    ".kyyyyykyyyyyyk.",
                    ".kyyyykkkkyyyyk.",
                    ".kyyykykyyyyyyk.",
                    ".kyyyykkkyyyyyk.",
                    ".kyyyyykykyyyyk.",
                    ".kyyykkkkyyyyyk.",
                    ".kyyyyykyyyyyyk.",
                    ".kyyyyyyyyyyyyk.",
                    "..kyyyyyyyyyyk..",
                    "...kkyyyyyykk...",
                    ".....kkkkkk.....",
                    "................"]
        case .warning:
            // A yellow triangle with an exclamation mark.
            return [".......kk.......",
                    "......kyyk......",
                    "......kyyk......",
                    ".....kyyyyk.....",
                    ".....kykkyk.....",
                    "....kyykkyyk....",
                    "....kyykkyyk....",
                    "...kyyykkyyyk...",
                    "...kyyykkyyyk...",
                    "..kyyyykkyyyyk..",
                    "..kyyyyyyyyyyk..",
                    ".kyyyyykkyyyyyk.",
                    ".kyyyyykkyyyyyk.",
                    "kyyyyyyyyyyyyyyk",
                    "kkkkkkkkkkkkkkkk",
                    "................"]
        case .info:
            // A blue circle with a white "i".
            return [".....kkkkkk.....",
                    "...kkbbbbbbkk...",
                    "..kbbbbwwbbbbk..",
                    ".kbbbbbwwbbbbbk.",
                    ".kbbbbbbbbbbbbk.",
                    "kbbbbbwwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    ".kbbbbbwwbbbbbk.",
                    ".kbbbbwwwwbbbbk.",
                    "..kbbbbbbbbbbk..",
                    "...kkbbbbbbkk...",
                    ".....kkkkkk.....",
                    "................"]
        case .question:
            // A blue circle with a white question mark.
            return [".....kkkkkk.....",
                    "...kkbbbbbbkk...",
                    "..kbbbbbbbbbbk..",
                    ".kbbbbwwwwbbbbk.",
                    ".kbbbwwbbwwbbbk.",
                    "kbbbbbbbbwwbbbbk",
                    "kbbbbbbbwwbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbbbbbbbbbk",
                    ".kbbbbbwwbbbbbk.",
                    ".kbbbbbwwbbbbbk.",
                    "..kbbbbbbbbbbk..",
                    "...kkbbbbbbkk...",
                    ".....kkkkkk.....",
                    "................"]
        case .folder:
            // A yellow folder.
            return ["................",
                    "................",
                    ".kkkkk..........",
                    "kyyyyyk.........",
                    "kyyyyyykkkkkkkk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "koooooooooooook.",
                    "kkkkkkkkkkkkkkk.",
                    "................",
                    "................"]
        case .tick:
            // A green tick.
            return ["................",
                    "................",
                    "................",
                    "............GG..",
                    "...........GGG..",
                    "..........GGG...",
                    ".........GGG....",
                    "..GG....GGG.....",
                    "..GGG..GGG......",
                    "...GGGGGG.......",
                    "....GGGG........",
                    ".....GG.........",
                    "................",
                    "................",
                    "................",
                    "................"]
        case .cross:
            // A red cross.
            return ["................",
                    "................",
                    "................",
                    "...rr......rr...",
                    "...rrr....rrr...",
                    "....rrr..rrr....",
                    ".....rrrrrr.....",
                    "......rrrr......",
                    ".....rrrrrr.....",
                    "....rrr..rrr....",
                    "...rrr....rrr...",
                    "...rr......rr...",
                    "................",
                    "................",
                    "................",
                    "................"]
        }
    }
}

/// Draws a pixel icon. At 16 points each grid pixel is one point; at 32, two. Icons always sit
/// beside a word, so VoiceOver skips them.
public struct PixelIconView: View {
    let icon: PixelIcon
    let size: CGFloat

    public init(_ icon: PixelIcon, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let cell = canvasSize.width / 16
            for (y, row) in icon.grid.enumerated() {
                for (x, char) in row.enumerated() {
                    guard let color = PixelIcon.palette[char] else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(color), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A status as Windows 95 lists show it: a small icon and a word, never colour alone.
public struct StatusLabel: View {
    let icon: PixelIcon
    let text: String
    let color: Color

    public init(_ icon: PixelIcon, _ text: String, color: Color = Win95.text) {
        self.icon = icon
        self.text = text
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            PixelIconView(icon)
            Text(text)
                .font(Win95.body)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension QuoteStatus {
    var icon: PixelIcon {
        switch self {
        case .draft: return .quote
        case .sent: return .mail
        case .expired: return .warning
        case .declined: return .cross
        case .accepted: return .tick
        }
    }
}

extension InvoiceStatus {
    var icon: PixelIcon {
        switch self {
        case .draft: return .invoice
        case .sent: return .mail
        case .partPaid: return .payment
        case .paid: return .tick
        case .void: return .cross
        case .overdue: return .warning
        }
    }

    /// The short form lists use: "Overdue 5 d".
    var listLabel: String {
        if case .overdue(let days) = self { return "Overdue \(days) d" }
        return label
    }

    var isAlert: Bool {
        if case .overdue = self { return true }
        return false
    }
}
