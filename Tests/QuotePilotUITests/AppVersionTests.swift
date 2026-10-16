import Foundation
import Testing
@testable import QuotePilotUI

@Suite struct AppVersionTests {
    @Test func theVersionComesFromTheInfoPlist() {
        #expect(AppVersion.version(in: ["CFBundleShortVersionString": "1.2.3"]) == "1.2.3")
        #expect(AppVersion.version(in: ["CFBundleShortVersionString": " 1.2.3\n"]) == "1.2.3")
    }

    /// `swift run` and the tests have no Info.plist of their own to read.
    @Test func withoutAnInfoPlistTheVersionIsZero() {
        #expect(AppVersion.version(in: nil) == "0.0.0")
        #expect(AppVersion.version(in: [:]) == "0.0.0")
        #expect(AppVersion.version(in: ["CFBundleShortVersionString": ""]) == "0.0.0")
        #expect(AppVersion.version(in: ["CFBundleShortVersionString": 3]) == "0.0.0")
        #expect(!AppVersion.current.isEmpty)
    }

    /// The Info.plist in the repo is what `build.sh` puts in the app, so it has to be readable as a
    /// version. (It isn't compared with a fixed number: a release bumps it.)
    @Test func theRepoInfoPlistHasAVersionAndTheBundleID() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let version = AppVersion.version(in: info)
        let parts = version.split(separator: ".").map { Int($0) }
        #expect(parts.count == 3 && !parts.contains(nil), "CFBundleShortVersionString is major.minor.patch, not \(version)")
        #expect(version != AppVersion.unbundled)
        let build = try #require(info["CFBundleVersion"] as? String)
        #expect((Int(build) ?? 0) >= 1)
        #expect(info["CFBundleIdentifier"] as? String == "com.fynnprojects.quotepilot")
    }
}
