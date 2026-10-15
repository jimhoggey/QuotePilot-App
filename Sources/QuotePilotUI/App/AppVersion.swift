import Foundation

/// The version of the running app. `Resources/Info.plist` is the one place it is written
/// (`CFBundleShortVersionString`); `build.sh` copies that file into the app, and this reads it back.
public enum AppVersion {
    /// What a build that isn't an app bundle reports (`swift run`, the tests): older than every release.
    public static let unbundled = "0.0.0"

    /// "1.0.0" for the running app, or `unbundled` when there is no Info.plist to read.
    public static var current: String { version(in: Bundle.main.infoDictionary) }

    /// The version in an Info.plist's contents. Tests pass their own.
    static func version(in info: [String: Any]?) -> String {
        guard let text = info?["CFBundleShortVersionString"] as? String else { return unbundled }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unbundled : trimmed
    }
}
