import Foundation
@testable import QuotePilotUI

/// The updater's two remembered values, kept in memory.
final class MemoryUpdateSettings: UpdateSettings {
    var lastUpdateCheck: Date?
    var updateExpectedVersion: String?
}

/// Stands in for GitHub: answers every request with `reply` and keeps the requests, so a test can see
/// what was asked and how often. No test reaches the real network.
final class FetchScript: @unchecked Sendable {
    enum Failure: Error { case offline }

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    var reply: Result<(Data, Int), Error>

    init(_ reply: Result<(Data, Int), Error>) {
        self.reply = reply
    }

    /// A reply with a status of 200.
    convenience init(json: String) {
        self.init(.success((Data(json.utf8), 200)))
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func answer(_ request: URLRequest) -> Result<(Data, Int), Error> {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return reply
    }

    var fetch: UpdateChecker.Fetch {
        { [self] request in
            let (data, status) = try answer(request).get()
            return (data, status)
        }
    }
}

/// Stands in for the download and the helper: records what it was asked and does nothing to the disk.
final class FakeInstaller: UpdateInstalling {
    struct HandOver: Equatable {
        var appPath: String
        var from: String
        var to: String
    }

    enum Failure: Error, LocalizedError {
        case broken
        var errorDescription: String? { "The fake installer broke." }
    }

    var stageResult: Result<StagedUpdate, Error> = .success(StagedUpdate(
        workFolder: URL(fileURLWithPath: "/nonexistent/QuotePilotUpdate-fake"),
        app: URL(fileURLWithPath: "/nonexistent/QuotePilotUpdate-fake/unzipped/Quote Pilot.app")))
    var handOverError: Error?
    var onHandOver: () -> Void = {}
    private(set) var staged: [ReleaseInfo] = []
    private(set) var handOvers: [HandOver] = []

    func stage(_ release: ReleaseInfo, runningVersion: String, log: UpdateLog) async throws -> StagedUpdate {
        staged.append(release)
        return try stageResult.get()
    }

    func handOver(_ staged: StagedUpdate, replacing appPath: String, from oldVersion: String,
                  to newVersion: String, log: UpdateLog) throws {
        onHandOver()
        if let handOverError { throw handOverError }
        handOvers.append(HandOver(appPath: appPath, from: oldVersion, to: newVersion))
    }
}

enum UpdateFixture {
    static let downloadBase = "https://github.com/jimhoggey/QuotePilot-App/releases/download"

    /// What GitHub's "latest release" reply looks like, with made-up notes. `assets` are file names.
    static func releaseJSON(tag: String = "v1.1.0",
                            assets: [String] = ["QuotePilot-mac.zip.sha256", "QuotePilot-mac.zip"],
                            downloadBase: String = downloadBase) -> String {
        let files = assets.map { name in
            #"{ "name": "\#(name)", "size": 4096, "browser_download_url": "\#(downloadBase)/\#(tag)/\#(name)" }"#
        }.joined(separator: ",\n")
        return #"""
        {
          "url": "https://api.github.com/repos/jimhoggey/QuotePilot-App/releases/1",
          "html_url": "https://github.com/jimhoggey/QuotePilot-App/releases/tag/\#(tag)",
          "tag_name": "\#(tag)",
          "name": "Quote Pilot \#(tag)",
          "draft": false,
          "prerelease": false,
          "assets": [\#(files)],
          "body": "What's Changed\n* Something new"
        }
        """#
    }

    /// Services that only touch memory and a temporary log: the settings are in memory, `fetch` is the
    /// script, the installer is a fake that does nothing, "quitting" does nothing, and the app claims
    /// to be a real one in Applications.
    static func services(version: String = "1.0.0", bundlePath: String = "/Applications/Quote Pilot.app",
                         script: FetchScript = FetchScript(.failure(FetchScript.Failure.offline)),
                         settings: MemoryUpdateSettings = MemoryUpdateSettings(),
                         installer: any UpdateInstalling = FakeInstaller(),
                         folderIsWritable: @escaping (String) -> Bool = { _ in true },
                         quit: @escaping () -> Void = {},
                         logFolder: URL = UIFixture.makeFolder()) -> UpdateServices {
        UpdateServices(version: version, bundlePath: bundlePath, settings: settings,
                       log: UpdateLog(url: logFolder.appendingPathComponent("update.log")), fetch: script.fetch,
                       installer: installer, folderIsWritable: folderIsWritable, quit: quit)
    }

    static func release(_ version: String = "1.1.0") -> ReleaseInfo {
        ReleaseInfo(version: version, tag: "v\(version)",
                    pageURL: URL(string: "https://github.com/jimhoggey/QuotePilot-App/releases/tag/v\(version)")!,
                    downloadURL: URL(string: "\(downloadBase)/v\(version)/QuotePilot-mac.zip")!)
    }

    /// Services for a test that has nothing to do with updates: any request fails as if offline.
    static func offline() -> UpdateServices {
        services(script: FetchScript(.failure(FetchScript.Failure.offline)))
    }
}
