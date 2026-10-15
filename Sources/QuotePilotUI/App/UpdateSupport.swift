import Foundation

// What the updater needs from outside: the two values it remembers, the log it writes, and the one
// bundle of those (`UpdateServices`) the app model holds. Tests swap the bundle for fakes, so they
// never use the network, the real settings or the real log.

/// The two things the updater remembers between launches.
protocol UpdateSettings: AnyObject {
    /// When the last check that reached GitHub happened.
    var lastUpdateCheck: Date? { get set }
    /// The version an install is expected to leave running, until the next launch has looked.
    var updateExpectedVersion: String? { get set }
}

/// The real settings: two keys in the app's UserDefaults.
final class UserDefaultsUpdateSettings: UpdateSettings {
    static let lastCheckKey = "lastUpdateCheck"
    static let expectedVersionKey = "updateExpectedVersion"

    private let defaults: UserDefaults

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Self.lastCheckKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastCheckKey) }
    }

    var updateExpectedVersion: String? {
        get { defaults.string(forKey: Self.expectedVersionKey) }
        set { defaults.set(newValue, forKey: Self.expectedVersionKey) }
    }
}

/// `~/Library/Logs/Quote Pilot/update.log`: one line per step of every check and update. The helper
/// that swaps the app in writes to the same file after Quote Pilot has quit.
struct UpdateLog {
    var url: URL
    var now: () -> Date = Date.init

    static var standardURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Quote Pilot/update.log")
    }

    /// What the status bar tells the user to look at when an update didn't finish.
    static let displayPath = "~/Library/Logs/Quote Pilot/update.log"

    /// "2026-10-16 14:03:22", the same shape the helper's own lines have.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Adds one line. A log that can't be written to is not worth stopping an update for.
    func append(_ message: String) {
        let text = message.replacingOccurrences(of: "\n", with: " ")
        let line = "\(Self.stamp(now()))  \(text)\n"
        do {
            let files = FileManager.default
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !files.fileExists(atPath: url.path) { files.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {}
    }
}

/// How the app model reaches GitHub, the settings and the log, and what it knows about itself.
struct UpdateServices {
    /// The running app's version.
    var version: String
    /// Where the running app is: `Bundle.main.bundlePath`.
    var bundlePath: String
    var settings: any UpdateSettings
    var log: UpdateLog
    var fetch: UpdateChecker.Fetch

    /// Whether this is an app bundle. Under `swift run` and in the tests it isn't, and nothing checks
    /// for updates on its own there.
    var isBundledApp: Bool { bundlePath.hasSuffix(".app") }

    static var live: UpdateServices {
        UpdateServices(version: AppVersion.current, bundlePath: Bundle.main.bundlePath,
                       settings: UserDefaultsUpdateSettings(), log: UpdateLog(url: UpdateLog.standardURL),
                       fetch: UpdateChecker.live)
    }
}
