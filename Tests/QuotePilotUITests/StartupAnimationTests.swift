import AppKit
import SwiftUI
import Testing
@testable import QuotePilotUI

@MainActor
@Suite struct StartupAnimationTests {
    @Test func thePilotIsASquareGridInThePalette() {
        #expect(PilotSprite.rows.count == PilotSprite.gridSize)
        for (index, row) in PilotSprite.rows.enumerated() {
            #expect(row.count == PilotSprite.gridSize, "row \(index) has \(row.count) pixels")
            #expect(row.allSatisfy { $0 == "." || PixelIcon.palette[$0] != nil }, "row \(index) uses a colour outside the palette")
        }
        #expect(PilotSprite.rows.joined().contains { $0 != "." })
    }

    @Test func thePilotRendersBothWays() {
        let sheet = HStack(spacing: 16) {
            PilotSprite(size: 96)
            PilotSprite(size: 64, mirrored: true)
        }
        .padding(16)
        .background(Win95.face)
        let rep = Snapshot.render(sheet, size: CGSize(width: 220, height: 130), name: "pilot-sprite")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// Frames at both window sizes, spread across the five seconds: the switch-on, the wordmark
    /// building, the bar filling, the Pilot in flight and the hand-over starting.
    @Test(arguments: [CGSize(width: 1240, height: 760), CGSize(width: 980, height: 620)])
    func framesRenderAtEveryBeat(size: CGSize) {
        for time in [0.3, 1.0, 2.0, 3.0, 4.0, 4.6] {
            let name = "startup-\(Int(size.width))-\(String(format: "%.1f", time))s"
            let rep = Snapshot.render(StartupAnimation(time: time), size: size, name: name)
            #expect(rep.map(Snapshot.hasContent) == true, "\(name) is blank")
        }
    }

    /// At the end the whole frame is the window grey, so the app underneath takes over cleanly.
    @Test func theLastFrameIsTheHandOver() throws {
        let size = CGSize(width: 1240, height: 760)
        let rep = try #require(Snapshot.render(StartupAnimation(time: StartupAnimationPlayer.duration),
                                               size: size, name: "startup-end"))
        for (x, y) in [(0, 0), (620, 380), (1239, 759), (100, 700), (1100, 50)] {
            let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            let grey = Int((color.redComponent * 255).rounded())
            #expect(grey == 0xC0, "pixel \(x),\(y) is not the window grey")
            #expect(Int((color.greenComponent * 255).rounded()) == grey)
            #expect(Int((color.blueComponent * 255).rounded()) == grey)
        }
    }
}
