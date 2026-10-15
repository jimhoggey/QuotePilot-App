import AppKit
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
        let rep = Snapshot.render(KitSampler(), size: CGSize(width: 640, height: 420), name: "kit")
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
