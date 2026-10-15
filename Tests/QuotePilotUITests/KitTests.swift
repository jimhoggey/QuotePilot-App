import AppKit
import QuotePilotCore
import SwiftUI
import Testing
@testable import QuotePilotUI

@MainActor
@Suite struct KitTests {
    @Test func paletteMatchesTheSpec() {
        func hex(_ color: Color) -> String {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                          Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
        }
        #expect(hex(Win95.face) == "#C0C0C0")
        #expect(hex(Win95.highlight) == "#FFFFFF")
        #expect(hex(Win95.light) == "#DFDFDF")
        #expect(hex(Win95.shadow) == "#808080")
        #expect(hex(Win95.dark) == "#000000")
        #expect(hex(Win95.titleBar) == "#000080")
        #expect(hex(Win95.inactiveTitleBar) == "#808080")
        #expect(hex(Win95.desktop) == "#008080")
        #expect(hex(Win95.selection) == "#000080")
        #expect(hex(Win95.field) == "#FFFFFF")
        #expect(hex(Win95.text) == "#000000")
        #expect(hex(Win95.tooltip) == "#FFFFE1")
        #expect(hex(Win95.overdue) == "#C00000")
        #expect(hex(Win95.paid) == "#007000")
        #expect(hex(Win95.warning) == "#FFFF00")
    }

    @Test func theKitDraws() {
        let rep = Snapshot.render(KitSampler(), size: CGSize(width: 640, height: 560), name: "kit")
        #expect(rep != nil)
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// A dashboard fraction of paid / total is 0 / 0 when nothing is owed yet. That must draw an
    /// empty bar, not trap on converting NaN to a block count.
    @Test func progressClampsEveryFraction() {
        #expect(Win95Progress(fraction: 0.25).fraction == 0.25)
        #expect(Win95Progress(fraction: -0.5).fraction == 0)
        #expect(Win95Progress(fraction: 1.5).fraction == 1)
        #expect(Win95Progress(fraction: .nan).fraction == 0)
        #expect(Win95Progress(fraction: .infinity).fraction == 0)
        #expect(Win95Progress(fraction: -.infinity).fraction == 0)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func progressDrawsWithAFractionThatIsNotANumber(_ fraction: Double) {
        let bar = Win95Progress(fraction: fraction).padding(4).background(Win95.face)
        let rep = Snapshot.render(bar, size: CGSize(width: 200, height: 24), name: "progress-odd-fraction")
        #expect(rep != nil)
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    // MARK: Fields that can't be edited look it

    /// A rendered picture and the pixels-per-point it was drawn at, so a point can be read back.
    struct Picture {
        let rep: NSBitmapImageRep
        let scale: Int

        /// 0 (black) to 255 (white): the average of the pixel's channels, at a point of the view.
        func level(x: Int, y: Int) -> Int {
            guard let color = rep.colorAt(x: x * scale, y: y * scale)?.usingColorSpace(.sRGB) else { return -1 }
            return Int(((color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255).rounded())
        }

        /// The darkest pixel in a block of points: black text and ticks, grey ones, or none.
        func darkest(x: ClosedRange<Int>, y: ClosedRange<Int>) -> Int {
            var lowest = 255
            for px in x.lowerBound * scale...(x.upperBound * scale + scale - 1) {
                for py in y.lowerBound * scale...(y.upperBound * scale + scale - 1) {
                    guard let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { continue }
                    let level = Int(((color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255).rounded())
                    lowest = min(lowest, level)
                }
            }
            return lowest
        }
    }

    /// `view` padded 10 points on the window's grey, drawn at exactly `size` plus the padding.
    func picture<V: View>(_ view: V, size: CGSize, name: String) throws -> Picture {
        let framed = view.padding(10).background(Win95.face)
        let total = CGSize(width: size.width + 20, height: size.height + 20)
        let rep = try #require(Snapshot.render(framed, size: total, name: name))
        return Picture(rep: rep, scale: max(1, rep.pixelsWide / Int(total.width)))
    }

    static let white = 255

    /// What a field's fill should be: white to type in, or the grey of the window around it (the
    /// padding's corner) when it is locked. The window's grey is never white, or this would pass for
    /// the wrong reason.
    func fill(_ shot: Picture, enabled: Bool) -> Int {
        let window = shot.level(x: 2, y: 2)
        #expect(window < Self.white, "the window's grey is \(window)")
        return enabled ? Self.white : window
    }

    @Test(arguments: [true, false])
    func aTextFieldGoesGreyWhenItIsDisabled(_ enabled: Bool) throws {
        let field = Win95TextField("Title", text: .constant("Hosting and support"))
            .frame(width: 220, height: 24)
            .disabled(!enabled)
        let shot = try picture(field, size: CGSize(width: 220, height: 24), name: "kit-disabled-text-field-\(enabled)")
        // A point inside the field, right of the words: white to type in, or the window's grey.
        #expect(shot.level(x: 10 + 210, y: 10 + 12) == fill(shot, enabled: enabled))
        // The words themselves, inside the bevel: black, or grey when the field is locked.
        let darkest = shot.darkest(x: 15...150, y: 14...28)
        #expect(enabled ? darkest < 60 : darkest > 100, "the darkest pixel of the words is \(darkest)")
    }

    /// An empty field's hint ("Detail (optional)") invites typing, so a locked one leaves it out.
    @Test(arguments: [true, false])
    func aLockedEmptyFieldShowsNoHint(_ enabled: Bool) throws {
        let field = Win95TextField("Detail", text: .constant(""), prompt: "Detail (optional)")
            .frame(width: 220, height: 24)
            .disabled(!enabled)
        let shot = try picture(field, size: CGSize(width: 220, height: 24), name: "kit-disabled-hint-\(enabled)")
        let ground = fill(shot, enabled: enabled)
        let darkest = shot.darkest(x: 15...150, y: 14...28)
        if enabled {
            #expect(darkest < ground - 40, "the hint should be showing: the darkest pixel is \(darkest) on \(ground)")
        } else {
            #expect(darkest == ground, "nothing but the fill should be showing: the darkest pixel is \(darkest) on \(ground)")
        }
    }

    @Test(arguments: [true, false])
    func aNumberFieldGoesGreyWhenItIsDisabled(_ enabled: Bool) throws {
        let field = CommitField(label: "Rate", value: Money(dollars: 60), format: { $0.formatted(currencyCode: "AUD") },
                                parse: FieldParser.money) { _ in }
            .frame(width: 92, height: 24)
            .disabled(!enabled)
        let shot = try picture(field, size: CGSize(width: 92, height: 24), name: "kit-disabled-number-field-\(enabled)")
        // The top-left corner, inside the bevel and left of the right-aligned figure.
        #expect(shot.level(x: 10 + 6, y: 10 + 12) == fill(shot, enabled: enabled))
        let darkest = shot.darkest(x: 40...95, y: 14...28)
        #expect(enabled ? darkest < 60 : darkest > 100, "the darkest pixel of the figure is \(darkest)")
    }

    @Test(arguments: [true, false])
    func aTextEditorGoesGreyWhenItIsDisabled(_ enabled: Bool) throws {
        let editor = Win95TextEditor("Terms", text: .constant("Please pay within 14 days."))
            .frame(width: 220, height: 60)
            .disabled(!enabled)
        let shot = try picture(editor, size: CGSize(width: 220, height: 60), name: "kit-disabled-text-editor-\(enabled)")
        #expect(shot.level(x: 10 + 200, y: 10 + 50) == fill(shot, enabled: enabled))
        let darkest = shot.darkest(x: 15...200, y: 14...30)
        #expect(enabled ? darkest < 60 : darkest > 100, "the darkest pixel of the words is \(darkest)")
    }

    @Test(arguments: [true, false])
    func aCheckboxGoesGreyWhenItIsDisabled(_ enabled: Bool) throws {
        func shot(on: Bool) throws -> Picture {
            let box = Toggle("Add GST (10%)", isOn: .constant(on))
                .toggleStyle(.win95)
                .frame(width: 160, height: 30, alignment: .leading)
                .disabled(!enabled)
            return try picture(box, size: CGSize(width: 160, height: 30), name: "kit-disabled-checkbox-\(enabled)-\(on)")
        }
        // The middle of the 13-point box: white or grey when it is off, and the tick when it is on.
        let off = try shot(on: false)
        #expect(off.level(x: 10 + 6, y: 10 + 15) == fill(off, enabled: enabled))
        let tick = try shot(on: true).level(x: 10 + 6, y: 10 + 15)
        #expect(enabled ? tick < 60 : (100...160).contains(tick), "the tick's level is \(tick)")
        // And its words.
        let darkest = off.darkest(x: 30...120, y: 18...32)
        #expect(enabled ? darkest < 60 : darkest > 100, "the darkest pixel of the words is \(darkest)")
    }
}

/// One of everything in the kit, for the screenshot.
struct KitSampler: View {
    @State private var name = "Sample Client Pty Ltd"
    @State private var notes = "Prefers email.\nPays on time."
    @State private var gst = false
    @State private var copy = true
    @State private var plan = "5050"

    private func swatch(_ kind: BevelKind, _ caption: String) -> some View {
        VStack(spacing: 3) {
            Bevel(kind).frame(width: 44, height: 28)
            Text(caption).font(Win95.small).foregroundStyle(Win95.text)
        }
    }

    /// The toolbar's icon above a short label. Chrome uses pixel glyphs, never SF Symbols.
    private func toolbarLabel(_ glyph: [String], _ title: String) -> some View {
        VStack(spacing: 8) {
            // 14 x 14 pt is two points per glyph pixel, so every pixel still lands whole.
            PixelGlyph(glyph).frame(width: 14, height: 14)
            Text(title)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Buttons") {
                    HStack {
                        Button("OK") {}.buttonStyle(.win95Default)
                        Button("Cancel") {}.buttonStyle(.win95)
                        Button("Disabled") {}.buttonStyle(.win95).disabled(true)
                    }
                }
                GroupBox("Client") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95FieldRow("Name:") { Win95TextField("Name", text: $name) }
                        Win95FieldRow("Notes:") { Win95TextEditor("Notes", text: $notes).frame(height: 54) }
                    }
                }
                GroupBox("Progress") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95Progress(fraction: 0.5)
                        Win95Progress(fraction: 1)
                    }
                }
                GroupBox("Locked") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95TextField("Locked name", text: $name)
                        Win95TextEditor("Locked notes", text: $notes).frame(height: 40)
                        Toggle("Registered for GST", isOn: $copy).toggleStyle(.win95)
                        Win95RadioGroup(selection: $plan, options: [("5050", "50/50"), ("full", "Full amount")],
                                        axis: .horizontal)
                    }
                    .disabled(true)
                }
                GroupBox("Glyphs and focus") {
                    HStack(spacing: 16) {
                        PixelGlyph(PixelGlyph.tick).frame(width: 7, height: 7)
                        PixelGlyph(PixelGlyph.up).frame(width: 7, height: 4)
                        PixelGlyph(PixelGlyph.down).frame(width: 7, height: 4)
                        PixelGlyph(PixelGlyph.cross).frame(width: 7, height: 5)
                        FocusRect().frame(width: 70, height: 22)
                    }
                    .padding(.vertical, 4)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Options") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Registered for GST", isOn: $gst).toggleStyle(.win95)
                        Toggle("Send me a copy", isOn: $copy).toggleStyle(.win95)
                        Win95RadioGroup(selection: $plan, options: [("5050", "50/50"), ("full", "Full amount")])
                    }
                }
                GroupBox("Wells") {
                    Text("$1,080.00").font(Win95.readout).padding(6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .win95Sunken()
                }
                GroupBox("Bevels") {
                    HStack(spacing: 8) {
                        swatch(.raised, "raised")
                        swatch(.sunken, "sunken")
                        swatch(.pressed, "pressed")
                        swatch(.etched, "etched")
                    }
                }
                GroupBox("Toolbar") {
                    HStack(spacing: 6) {
                        Button {} label: { toolbarLabel(PixelGlyph.tick, "Quotes") }
                            .buttonStyle(Win95ToolbarButtonStyle())
                        Button {} label: { toolbarLabel(PixelGlyph.cross, "Archive") }
                            .buttonStyle(Win95ToolbarButtonStyle()).disabled(true)
                    }
                }
            }
        }
        .groupBoxStyle(.win95)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Win95.face)
    }
}
