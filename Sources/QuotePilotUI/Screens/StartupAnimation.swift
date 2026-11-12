import SwiftUI

/// Plays the five-second start-up screen once, after "Take the Tour", then calls `onFinish` so
/// the tour's first speech balloon can appear. A click anywhere or Escape skips straight to the
/// end, and with Reduce Motion on nothing plays at all: the window grey shows and `onFinish`
/// follows at once.
struct StartupAnimationPlayer: View {
    let onFinish: () -> Void

    static let duration = 5.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started: Date?
    @State private var finished = false

    var body: some View {
        ZStack {
            if reduceMotion {
                Win95.face
            } else {
                TimelineView(.animation) { timeline in
                    let elapsed = started.map { timeline.date.timeIntervalSince($0) } ?? 0
                    StartupAnimation(time: min(elapsed, Self.duration))
                        .onChange(of: elapsed >= Self.duration) { _, done in
                            if done { finish() }
                        }
                }
            }
            // Escape needs a button to land on; this one is never seen.
            Button("") { finish() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear {
            started = Date()
            if reduceMotion { finish() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quote Pilot tour starting")
    }

    /// `onFinish` fires once, whether the clock ran out or the user skipped.
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// One frame of the start-up screen at `time` (0…5 s). A pure function of time, so frames are
/// deterministic and testable; `StartupAnimationPlayer` supplies the clock. Everything is drawn
/// on a 310×190 virtual pixel grid scaled up to the window with antialiasing off, so it stays
/// crisp and chunky at 1240×760 (4×) and 980×620 (about 3.2×).
///
/// Beats: 0.0–0.4 the picture switches on like a CRT; 0.4–2.0 the wordmark builds pixel by
/// pixel with a yellow sparkle on the newest blocks; 2.0–3.8 the progress bar fills and the
/// tagline arrives a word at a time; 3.4–4.5 the Pilot swoops in from the left and parks beside
/// the title; 4.55–5.0 the scene dissolves to the window grey through a Bayer dither.
struct StartupAnimation: View {
    let time: Double

    static let layout = CGSize(width: 310, height: 190)

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            let scale = min(size.width / Self.layout.width, size.height / Self.layout.height)
            context.scaleBy(x: scale, y: scale)
            var scene = StartupScene(context: context,
                                     viewport: CGSize(width: size.width / scale, height: size.height / scale),
                                     time: time)
            scene.draw()
        }
    }
}

/// Draws one frame in virtual pixels. The viewport is at least 310×190; the layout box sits
/// centred in it and the sky and ground fill whatever is left over, so no window size gets bars.
private struct StartupScene {
    var context: GraphicsContext
    let viewport: CGSize
    let time: Double

    var ox: Double { ((viewport.width - StartupAnimation.layout.width) / 2).rounded(.down) }
    var oy: Double { ((viewport.height - StartupAnimation.layout.height) / 2).rounded(.down) }

    // The icon palette, plus a few in-between blues the 16 colours can't make for the sky.
    static func pal(_ c: Character) -> Color { PixelIcon.palette[c]! }
    static let skyBands: [Color] = [
        Color(hex: 0x000080), Color(hex: 0x0000A0), Color(hex: 0x0000FF), Color(hex: 0x2060FF),
        Color(hex: 0x4090FF), Color(hex: 0x80C0FF), Color(hex: 0xC0E0FF),
    ]

    mutating func put(_ x: Double, _ y: Double, _ w: Double = 1, _ h: Double = 1, _ color: Color) {
        context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color),
                     style: FillStyle(antialiased: false))
    }

    /// A stable pseudo-random number in 0..<1 for a grid cell, so every frame agrees.
    static func hash(_ i: Int, _ j: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: i) &* 73_856_093 ^ UInt32(truncatingIfNeeded: j) &* 19_349_663
        h = (h ^ (h >> 13)) &* 2_654_435_761
        h ^= h >> 16
        return Double(h & 0xFFFF) / 65536
    }

    static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    mutating func draw() {
        drawSky()
        drawSun()
        drawClouds()
        drawGround()
        drawWordmark()
        drawTagline()
        drawProgressBar()
        drawPilot()
        drawSwitchOn()
        drawHandover()
    }

    // MARK: Sky and scenery

    var horizon: Double { viewport.height - 22 }

    mutating func drawSky() {
        let bands = Self.skyBands
        let bandHeight = horizon / Double(bands.count)
        var y = 0.0
        while y < horizon {
            let band = min(Int(y / bandHeight), bands.count - 1)
            let within = y - Double(band) * bandHeight
            put(0, y, viewport.width, 1, bands[band])
            // The last two rows of each band dither into the next one: a row of the base colour,
            // then every other cell in the next colour.
            if band < bands.count - 1, within >= bandHeight - 2 {
                var x = Double(Int(y) % 2)
                while x < viewport.width {
                    put(x, y, 1, 1, bands[band + 1])
                    x += 2
                }
            }
            y += 1
        }
    }

    mutating func drawSun() {
        let cx = ox + 38.0, cy = oy + 30.0, r = 11.0
        for dy in stride(from: -r - 1, through: r + 1, by: 1) {
            for dx in stride(from: -r - 1, through: r + 1, by: 1) {
                let d2 = dx * dx + dy * dy
                if d2 <= r * r {
                    // A brighter core, dithered out to plain yellow.
                    let core = d2 <= (r - 5) * (r - 5) || (d2 <= (r - 2) * (r - 2) && (Int(dx) + Int(dy)) % 2 == 0)
                    put(cx + dx, cy + dy, 1, 1, core ? Color(hex: 0xFFFF80) : Self.pal("y"))
                } else if d2 <= (r + 1.5) * (r + 1.5), (Int(dx) + Int(dy)) % 2 == 0 {
                    put(cx + dx, cy + dy, 1, 1, Self.pal("y"))
                }
            }
        }
    }

    static let cloudBig = [
        "..........wwwwww............",
        "......wwwwwwwwwwww..........",
        "....wwwwwwwwwwwwwwwww.......",
        "..wwwwwwwwwwwwwwwwwwwwww....",
        ".wwwwwwwwwwwwwwwwwwwwwwwww..",
        "wwwwwwwwwwwwwwwwwwwwwwwwwwww",
        ".wsssswwwwwwwwwssswwwwwwwww.",
        "..sssssssssssssssssssssss...",
        "....sssssssssssssssssss.....",
    ]
    static let cloudSmall = [
        ".....wwwww......",
        "..wwwwwwwwwww...",
        ".wwwwwwwwwwwwww.",
        "wwwwwwwwwwwwwwww",
        ".ssswwwwwsssswws",
        "..ssssssssssss..",
    ]

    mutating func drawClouds() {
        // (shape, start x, y, speed in virtual px/s, cell size). Slow ones read as far away. They
        // keep out of the title's band (y 46–84) so nothing peeks over a letter.
        let clouds: [([String], Double, Double, Double, Double)] = [
            (Self.cloudBig, 200, 14, 9, 1.0),
            (Self.cloudSmall, 120, 30, 6, 1.0),
            (Self.cloudBig, 30, 118, 14, 1.5),
            (Self.cloudSmall, 250, 136, 11, 1.0),
            (Self.cloudSmall, 20, 92, 5, 1.0),
            (Self.cloudBig, 300, 150, 7, 1.0),
        ]
        for (shape, startX, y, speed, cell) in clouds {
            let width = Double(shape[0].count) * cell
            let span = viewport.width + width
            var x = (startX - speed * time).truncatingRemainder(dividingBy: span)
            if x < -width { x += span }
            drawRows(shape, at: CGPoint(x: x.rounded(), y: oy + y), cell: cell)
        }
    }

    mutating func drawRows(_ rows: [String], at origin: CGPoint, cell: Double) {
        for (j, row) in rows.enumerated() {
            for (i, char) in row.enumerated() {
                guard let color = PixelIcon.palette[char] else { continue }
                put(origin.x + Double(i) * cell, origin.y + Double(j) * cell, cell, cell, color)
            }
        }
    }

    mutating func drawGround() {
        let top = horizon
        // A dithered horizon, then flat green with a few darker tufts.
        var x = 0.0
        while x < viewport.width {
            put(x, top, 1, 1, Int(x) % 2 == 0 ? Self.pal("G") : Self.skyBands.last!)
            put(x, top + 1, 1, 1, Int(x) % 2 == 1 ? Self.pal("G") : Self.pal("l"))
            x += 1
        }
        put(0, top + 2, viewport.width, viewport.height - top - 2, Self.pal("G"))
        var i = 0
        while Double(i) * 7 < viewport.width {
            let x = Double(i) * 7 + (Self.hash(i, 1) * 5).rounded(.down)
            let y = top + 5 + (Self.hash(i, 2) * 14).rounded(.down)
            put(x, y, 2, 1, Color(hex: 0x006000))
            i += 1
        }
    }

    // MARK: The wordmark and tagline

    /// A 5×7 bitmap face with just the letters the screen needs; "." is a 2-wide full stop.
    static let font: [Character: [String]] = [
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        ".": ["..", "..", "..", "..", "..", "##", "##"],
        " ": ["..", "..", "..", "..", "..", "..", ".."],
    ]

    /// The lit cells of `text` in font pixels, plus the text's width in font pixels.
    static func cells(_ text: String) -> (cells: [(x: Int, y: Int)], width: Int) {
        var out: [(x: Int, y: Int)] = []
        var x = 0
        for char in text {
            guard let glyph = font[char] else { continue }
            for (j, row) in glyph.enumerated() {
                for (i, px) in row.enumerated() where px == "#" {
                    out.append((x: x + i, y: j))
                }
            }
            x += glyph[0].count + 1
        }
        return (out, max(x - 1, 0))
    }

    static let wordmark = cells("QUOTE PILOT")
    static let block = 3.0
    var wordmarkOrigin: CGPoint {
        CGPoint(x: ox + ((StartupAnimation.layout.width - Double(Self.wordmark.width) * Self.block) / 2).rounded(.down),
                y: oy + 46)
    }

    /// When each block of the wordmark appears: a left-to-right sweep with some scatter.
    static func appearance(_ cell: (x: Int, y: Int)) -> Double {
        let sweep = Double(cell.x) / Double(max(wordmark.width, 1))
        return 0.4 + 1.6 * (0.6 * sweep + 0.4 * hash(cell.x, cell.y))
    }

    mutating func drawWordmark() {
        let origin = wordmarkOrigin, b = Self.block
        let shown = Self.wordmark.cells.filter { Self.appearance($0) <= time }
        guard !shown.isEmpty else { return }
        // Navy drop shadow, then the black outline, then the faces: the outline squares overlap
        // one pixel beyond each block, and the faces cover the joins, so the union gets a single
        // 1-px outline.
        for c in shown {
            put(origin.x + Double(c.x) * b + 1, origin.y + Double(c.y) * b + 1, b + 2, b + 2, Self.pal("n"))
        }
        for c in shown {
            put(origin.x + Double(c.x) * b - 1, origin.y + Double(c.y) * b - 1, b + 2, b + 2, Self.pal("k"))
        }
        for c in shown {
            let age = time - Self.appearance(c)
            let color: Color = age < 0.10 ? Self.pal("y") : age < 0.18 ? Color(hex: 0xFFFF80) : Self.pal("w")
            put(origin.x + Double(c.x) * b, origin.y + Double(c.y) * b, b, b, color)
        }
        // A sparkle cross on the very newest block.
        if let newest = shown.max(by: { Self.appearance($0) < Self.appearance($1) }),
           time - Self.appearance(newest) < 0.08 {
            let cx = origin.x + Double(newest.x) * b + 1, cy = origin.y + Double(newest.y) * b + 1
            for d in [-3.0, -2, 2, 3] {
                put(cx + d, cy, 1, 1, Self.pal("w"))
                put(cx, cy + d, 1, 1, Self.pal("w"))
            }
        }
    }

    var progress: Double { min(max((time - 2.0) / 1.8, 0), 1) }

    mutating func drawTagline() {
        let words: [(String, Double, Color)] = [("QUOTES.", 0.3, Self.pal("w")), ("INVOICES.", 0.65, Self.pal("w")),
                                                ("PAID.", 1.0, Self.pal("y"))]
        let full = Self.cells("QUOTES. INVOICES. PAID.")
        let startX = ox + ((StartupAnimation.layout.width - Double(full.width)) / 2).rounded(.down)
        let y = oy + 77
        var x = startX
        for (word, at, color) in words {
            let shape = Self.cells(word)
            if progress >= at {
                for c in shape.cells {
                    put(x + Double(c.x) + 1, y + Double(c.y) + 1, 1, 1, Self.pal("k"))
                }
                for c in shape.cells {
                    put(x + Double(c.x), y + Double(c.y), 1, 1, color)
                }
            }
            x += Double(shape.width) + 3  // a space
        }
    }

    // MARK: The progress bar

    mutating func drawProgressBar() {
        guard time >= 1.9 else { return }
        let w = 170.0, h = 14.0
        let x = ox + ((StartupAnimation.layout.width - w) / 2).rounded(.down), y = oy + 98
        // A sunken Windows 95 tray.
        put(x, y, w, h, Self.pal("g"))
        put(x + 1, y + 1, w - 1, h - 1, Self.pal("w"))
        put(x + 1, y + 1, w - 2, h - 2, Self.pal("k"))
        put(x + 2, y + 2, w - 3, h - 3, Self.pal("s"))
        put(x + 2, y + 2, w - 4, h - 4, Self.pal("w"))
        // Chunky navy blocks, 8 wide with a 1-px gap.
        let blocks = Int(((w - 6) + 1) / 9)
        let lit = Int((progress * Double(blocks)).rounded())
        for i in 0..<lit {
            put(x + 3 + Double(i) * 9, y + 3, 8, h - 6, Self.pal("n"))
        }
    }

    // MARK: The Pilot

    /// The Pilot's top-left corner at flight fraction `f` (0 off-screen left, 1 parked beside the
    /// title): a swoop under the progress bar that overshoots to the right and curls back up
    /// into the parking spot, so the plane ends facing the title.
    func flightPoint(_ f: Double) -> CGPoint {
        let e = Self.smooth(f)
        let p0 = CGPoint(x: -36, y: oy + 122), c1 = CGPoint(x: ox + 150, y: oy + 150)
        let c2 = CGPoint(x: ox + 334, y: oy + 124), p3 = CGPoint(x: ox + 258, y: oy + 38)
        let u = 1 - e
        let x = u * u * u * p0.x + 3 * u * u * e * c1.x + 3 * u * e * e * c2.x + e * e * e * p3.x
        let y = u * u * u * p0.y + 3 * u * u * e * c1.y + 3 * u * e * e * c2.y + e * e * e * p3.y
        return CGPoint(x: x, y: y)
    }

    mutating func drawPilot() {
        let f = min(max((time - 3.4) / 1.1, 0), 1)
        guard f > 0 else { return }
        var p = flightPoint(f)
        // Facing: right while heading right, flipped once the curl turns back towards the title.
        let ahead = flightPoint(min(f + 0.02, 1))
        let mirrored = f >= 0.98 || ahead.x < p.x
        if f >= 1 {
            // Parked: a gentle hover.
            p.y += (sin((time - 4.5) * 5) * 1.5).rounded()
        }
        // A dotted flight path behind the plane, fading with distance.
        var k = 1
        while k <= 9 {
            let back = f - Double(k) * 0.045
            if back <= 0 { break }
            let q = flightPoint(back)
            let shade: Color = k < 4 ? Self.pal("w") : k < 7 ? Self.pal("s") : Self.pal("g")
            put(q.x.rounded() + 15, q.y.rounded() + 17, 3, 1, shade)
            k += 1
        }
        let origin = CGPoint(x: p.x.rounded(), y: p.y.rounded())
        PilotSprite.draw(in: &context, origin: origin, cell: 1, mirrored: mirrored)
    }

    // MARK: Switch-on and handover

    /// The first 0.4 s open like an old monitor: a bright line that grows into the picture.
    mutating func drawSwitchOn() {
        guard time < 0.4 else { return }
        let open = Self.smooth(time / 0.4)
        let half = viewport.height / 2 * open
        let top = (viewport.height / 2 - half).rounded(.down)
        let bottom = (viewport.height / 2 + half).rounded(.up)
        put(0, 0, viewport.width, top, Self.pal("k"))
        put(0, bottom, viewport.width, viewport.height - bottom, Self.pal("k"))
        if time < 0.2 {
            put(0, top - 1, viewport.width, 1, Self.pal("w"))
            put(0, bottom, viewport.width, 1, Self.pal("w"))
        }
    }

    /// From 4.55 s the window grey takes over through a 4×4 Bayer dither. The cells are 4 px so
    /// a frame is a few thousand fills at most: smooth matters more than fine here.
    mutating func drawHandover() {
        let d = (time - 4.55) / 0.45
        guard d > 0 else { return }
        if d >= 1 {
            put(0, 0, viewport.width, viewport.height, Win95.face)
            return
        }
        let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        let cell = 4.0
        var j = 0
        while Double(j) * cell < viewport.height {
            var i = 0
            while Double(i) * cell < viewport.width {
                if bayer[j % 4][i % 4] / 16 < d {
                    put(Double(i) * cell, Double(j) * cell, cell, cell, Win95.face)
                }
                i += 1
            }
            j += 1
        }
    }
}
