// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Command Line Tools 27.0 install the Swift Testing macro plugin in a folder SwiftPM's build system
// doesn't search. Point the compiler at it when it's there; Xcode users don't need this.
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])]
    : []

let package = Package(
    name: "QuotePilot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuotePilotCore", targets: ["QuotePilotCore"]),
        .library(name: "QuotePilotPDF", targets: ["QuotePilotPDF"]),
        .executable(name: "qp", targets: ["qp"]),
        .executable(name: "QuotePilotApp", targets: ["QuotePilotApp"]),
    ],
    targets: [
        .target(name: "QuotePilotCore"),
        .target(name: "QuotePilotPDF", dependencies: ["QuotePilotCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "qp", dependencies: ["QuotePilotCore", "QuotePilotPDF"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "QuotePilotUI", dependencies: ["QuotePilotCore", "QuotePilotPDF"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "QuotePilotApp", dependencies: ["QuotePilotUI", "QuotePilotCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "QuotePilotCoreTests", dependencies: ["QuotePilotCore"],
                    swiftSettings: testSettings),
        .testTarget(name: "QuotePilotPDFTests", dependencies: ["QuotePilotCore", "QuotePilotPDF"],
                    swiftSettings: testSettings + [.swiftLanguageMode(.v5)]),
        .testTarget(name: "QuotePilotUITests", dependencies: ["QuotePilotUI", "QuotePilotCore", "QuotePilotPDF"],
                    swiftSettings: testSettings + [.swiftLanguageMode(.v5)]),
    ]
)
