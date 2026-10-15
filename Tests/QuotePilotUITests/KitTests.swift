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
}

/// One of everything in the kit, for the screenshot.
struct KitSampler: View {
    // The macOS 27 SDK turns `@State` into a macro, and Command Line Tools don't ship the plugin
    // that expands it ("plugin for module 'SwiftUIMacros' not found"). Holding the `State` values
    // directly is what the attribute expands to anyway, and needs no macro.
    private let name = State(initialValue: "Sample Client Pty Ltd")
    private let notes = State(initialValue: "Prefers email.\nPays on time.")
    private let gst = State(initialValue: false)
    private let copy = State(initialValue: true)
    private let plan = State(initialValue: "5050")

    private func swatch(_ kind: BevelKind, _ caption: String) -> some View {
        VStack(spacing: 3) {
            Bevel(kind).frame(width: 44, height: 28)
            Text(caption).font(Win95.small).foregroundStyle(Win95.text)
        }
    }

    private func toolbarLabel(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 20))
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
                        Win95FieldRow("Name:") { Win95TextField("Name", text: name.projectedValue) }
                        Win95FieldRow("Notes:") { Win95TextEditor(text: notes.projectedValue).frame(height: 54) }
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
                        Toggle("Registered for GST", isOn: gst.projectedValue).toggleStyle(.win95)
                        Toggle("Send me a copy", isOn: copy.projectedValue).toggleStyle(.win95)
                        Win95RadioGroup(selection: plan.projectedValue,
                                        options: [("5050", "50/50"), ("full", "Full amount")])
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
                        Button {} label: { toolbarLabel("doc.text", "Quotes") }
                            .buttonStyle(Win95ToolbarButtonStyle())
                        Button {} label: { toolbarLabel("tray", "Archive") }
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
