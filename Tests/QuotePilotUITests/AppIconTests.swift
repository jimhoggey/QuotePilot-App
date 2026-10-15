import AppKit
import Foundation
import Testing
@testable import QuotePilotUI

@MainActor
@Suite struct AppIconTests {
    @Test func theIconsetHasEverySizeMacOSAsksFor() throws {
        let folder = UIFixture.makeFolder().appendingPathComponent("AppIcon.iconset")
        try AppIcon.writeIconset(to: folder)
        let expected = ["icon_16x16.png": 16, "icon_16x16@2x.png": 32, "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
                        "icon_128x128.png": 128, "icon_128x128@2x.png": 256, "icon_256x256.png": 256,
                        "icon_256x256@2x.png": 512, "icon_512x512.png": 512, "icon_512x512@2x.png": 1024]
        for (name, pixels) in expected {
            let image = try #require(NSBitmapImageRep(data: try Data(contentsOf: folder.appendingPathComponent(name))), "\(name)")
            #expect(image.pixelsWide == pixels, "\(name)")
            #expect(image.pixelsHigh == pixels, "\(name)")
        }
    }
}
