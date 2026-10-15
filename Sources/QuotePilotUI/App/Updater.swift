import Foundation

// The update check, as pure logic: what to ask GitHub, how to read the answer, which version is newer
// and when to ask again. The network, the settings file and the log are passed in (`UpdateServices`),
// so the tests never touch any of them.

/// Where Quote Pilot's releases live, and what to expect in them.
enum UpdateSource {
    static let owner = "jimhoggey"
    static let repository = "QuotePilot-App"
    /// The one file of a release that holds the app: `ditto -c -k --keepParent` of "Quote Pilot.app".
    static let assetName = "QuotePilot-mac.zip"
    /// What the app inside the zip is called.
    static let appName = "Quote Pilot.app"
    /// The bundle identifier the downloaded app must have (`Resources/Info.plist`).
    static let bundleID = "com.fynnprojects.quotepilot"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!

    /// Whether `url` is a download from this repository's releases. The address comes out of GitHub's
    /// reply, so the app only follows it when it points back at the project's own release files.
    static func isReleaseDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && url.path.hasPrefix("/\(owner)/\(repository)/releases/download/")
    }
}

/// A version such as 1.10.0, compared part by part as numbers, so 1.10.0 is newer than 1.9.0. A
/// leading "v" is allowed (a tag reads "v1.2.0"), and missing parts count as zero (1.0 equals 1.0.0).
/// Anything else, such as "1.2.0-beta" or "latest", is not a version at all.
struct VersionNumber: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, first == "v" || first == "V" { text.removeFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...6).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ ("0"..."9").contains($0) }), let number = Int(piece) else {
                return nil
            }
            parts.append(number)
        }
        self.parts = parts
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    private var withoutTrailingZeros: [Int] {
        var kept = parts
        while kept.last == 0 { kept.removeLast() }
        return kept
    }

    static func == (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        lhs.withoutTrailingZeros == rhs.withoutTrailingZeros
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

/// A published release that is newer than the running app and has the app attached.
public struct ReleaseInfo: Equatable, Sendable {
    /// "1.1.0": the tag without its "v".
    public let version: String
    /// "v1.1.0", as tagged.
    public let tag: String
    /// The release's page on GitHub.
    public let pageURL: URL
    /// `QuotePilot-mac.zip`.
    public let downloadURL: URL

    /// The release in GitHub's "latest release" reply, or nil when the reply isn't one Quote Pilot can
    /// use: not JSON, a tag that isn't a version, or no `QuotePilot-mac.zip` attached.
    static func parse(_ data: Data) -> ReleaseInfo? {
        struct Reply: Decodable {
            struct Asset: Decodable {
                var name: String
                var browserDownloadUrl: String
            }
            var tagName: String
            var htmlUrl: String
            var assets: [Asset]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let reply = try? decoder.decode(Reply.self, from: data),
              let version = VersionNumber(reply.tagName),
              let page = URL(string: reply.htmlUrl),
              let asset = reply.assets?.first(where: { $0.name == UpdateSource.assetName }),
              let download = URL(string: asset.browserDownloadUrl), UpdateSource.isReleaseDownload(download)
        else { return nil }
        let tag = reply.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReleaseInfo(version: version.description, tag: tag, pageURL: page, downloadURL: download)
    }
}

enum UpdateError: LocalizedError {
    case githubReplied(Int)

    var errorDescription: String? {
        switch self {
        case .githubReplied(let status):
            return "GitHub answered with an error (\(status))."
        }
    }
}

/// Asks GitHub for the latest release and says whether it is newer than the running version.
struct UpdateChecker {
    typealias Fetch = @Sendable (URLRequest) async throws -> (data: Data, status: Int)

    var currentVersion: String
    var fetch: Fetch

    /// The whole request. It carries the app's version in the User-Agent, which GitHub asks every
    /// client to name itself with, and nothing about the user or their work.
    static func request(version: String) -> URLRequest {
        var request = URLRequest(url: UpdateSource.latestReleaseURL, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QuotePilot/\(version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        return request
    }

    /// The release in `data` when it is newer than `currentVersion`. Anything that can't be read, or
    /// can't be compared, counts as no update.
    static func newerRelease(in data: Data, than currentVersion: String) -> ReleaseInfo? {
        guard let current = VersionNumber(currentVersion),
              let release = ReleaseInfo.parse(data),
              let latest = VersionNumber(release.version), latest > current
        else { return nil }
        return release
    }

    /// The newer release, or nil when this is the newest. Throws when GitHub can't be reached or
    /// refuses; no release published yet (a 404) is not an error.
    func check() async throws -> ReleaseInfo? {
        let reply = try await fetch(Self.request(version: currentVersion))
        switch reply.status {
        case 200: return Self.newerRelease(in: reply.data, than: currentVersion)
        case 404: return nil
        default: throw UpdateError.githubReplied(reply.status)
        }
    }

    /// The real thing: no cookies, no cache, nothing kept between checks.
    static let live: Fetch = { request in
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// When to ask GitHub: at launch, and then not again for 24 hours.
enum UpdateThrottle {
    static let interval: TimeInterval = 24 * 60 * 60

    /// Whether the last check is old enough. A last check that lies in the future (the clock was set
    /// back) doesn't hold the next one off.
    static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}
