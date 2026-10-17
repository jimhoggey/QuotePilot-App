import Foundation

/// Where the library lives and how it's kept safe.
public struct LibraryStore: Sendable {
    public enum LoadResult: Sendable {
        case loaded(Library)
        /// No library yet: start with an empty one.
        case fresh(Library)
        /// The file is there but can't be used. It is left exactly as it is.
        case unreadable(reason: String)
    }

    public enum StoreError: Error, Equatable, Sendable {
        case wouldOverwriteUnreadableLibrary
        /// The library as it stands encodes to JSON that this version can't read back.
        case wouldWriteUnreadableLibrary
        case backupFromNewerVersion(Int)
        /// The backup holds numbers past the library's limits (`Library.problems()`), so restoring it
        /// would only bring back a library the app can't open.
        case backupHasProblems([String])
    }

    /// How an unreadable reason starts when the file came from a newer Quote Pilot. Restoring a backup
    /// then would roll the library back, so the unreadable screen leads with Quit instead.
    public static let newerVersionReason = "It was saved by a newer version of Quote Pilot"

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// `~/Library/Application Support/Quote Pilot`
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quote Pilot", isDirectory: true)
    }

    public var libraryURL: URL { folder.appendingPathComponent("library.json") }
    public var backupsFolder: URL { folder.appendingPathComponent("Backups", isDirectory: true) }
    /// The brand's logo and font files.
    public var assetsFolder: URL { folder.appendingPathComponent("Assets", isDirectory: true) }

    private struct FormatProbe: Decodable {
        var format: Int
    }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return .fresh(Library()) }
        do {
            let data = try Data(contentsOf: libraryURL)
            let probe = try JSONDecoder().decode(FormatProbe.self, from: data)
            guard probe.format <= Library.currentFormat else {
                return .unreadable(reason: "\(LibraryStore.newerVersionReason) (library format \(probe.format)).")
            }
            let library = try Library.makeDecoder().decode(Library.self, from: data)
            // Numbers past the limits would trap when added up, before any screen could explain.
            let problems = library.problems()
            guard problems.isEmpty else {
                return .unreadable(reason: Library.describe(problems, opening: "It holds numbers Quote Pilot can't work with."))
            }
            return .loaded(library)
        } catch {
            return .unreadable(reason: "The library file couldn't be read (\(error.localizedDescription)).")
        }
    }

    /// Writes a temporary file and swaps it in, so a crash can't leave half a library. Refuses to
    /// replace a library file it can't read (that file needs restoring, not overwriting), and refuses
    /// to write one the next launch couldn't read.
    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: libraryURL.path), case .unreadable = load() {
            throw StoreError.wouldOverwriteUnreadableLibrary
        }
        try writeLibrary(library)
    }

    /// The only place library.json is written: encodes the library, reads the result back the way the
    /// next launch will, and only then replaces the file atomically. Callers decide whether the
    /// existing file may be replaced. A library with numbers past the limits would load as
    /// unreadable, so it isn't written either.
    private func writeLibrary(_ library: Library) throws {
        guard library.problems().isEmpty else { throw StoreError.wouldWriteUnreadableLibrary }
        let data = try Library.makeEncoder().encode(library)
        do {
            _ = try Library.makeDecoder().decode(Library.self, from: data)
        } catch {
            throw StoreError.wouldWriteUnreadableLibrary
        }
        try data.write(to: libraryURL, options: .atomic)
    }

    /// Copies the library into Backups/ at most once a day, keeping the newest 30. Makes no backup
    /// unless the library file reads, so a damaged or newer file never becomes the newest backup.
    @discardableResult
    public func backUpIfDue(today: Day) throws -> URL? {
        guard case .loaded = load() else { return nil }
        try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let target = backupsFolder.appendingPathComponent("library-\(today.iso).json")
        guard !FileManager.default.fileExists(atPath: target.path) else { return nil }
        try FileManager.default.copyItem(at: libraryURL, to: target)
        for old in backups().dropFirst(30) {
            try FileManager.default.removeItem(at: old)
        }
        return target
    }

    /// What a backup made just before File → Start Fresh has after its day, so the restore list can
    /// say so: "library-2026-10-15-before-start-fresh-143005.json".
    public static let startFreshTag = "-before-start-fresh-"

    /// Copies the library into Backups/ now, whether or not today's backup is made, before File →
    /// Start Fresh empties it. Nil when there's no library file yet, so nothing to keep. Only a
    /// library that reads is copied: anything else throws, and Start Fresh doesn't go ahead.
    @discardableResult
    public func backUpBeforeStartingFresh(now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return nil }
        guard case .loaded = load() else { throw StoreError.wouldOverwriteUnreadableLibrary }
        try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_AU_POSIX")
        time.dateFormat = "HHmmss"
        let target = backupsFolder.appendingPathComponent(
            "library-\(Day(now).iso)\(Self.startFreshTag)\(time.string(from: now)).json")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: libraryURL, to: target)
        return target
    }

    /// Backups, newest first.
    public func backups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("library-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Replaces the library with a backup once the backup is known to read, is no newer than this
    /// version and holds no numbers past the limits. The file being replaced is copied beside it as `library-replaced-<time>.json` first, and
    /// stays on disk until the restored library is written in its place.
    @discardableResult
    public func restore(from backup: URL, now: Date = Date()) throws -> Library {
        let data = try Data(contentsOf: backup)
        let probe = try JSONDecoder().decode(FormatProbe.self, from: data)
        guard probe.format <= Library.currentFormat else {
            throw StoreError.backupFromNewerVersion(probe.format)
        }
        let library = try Library.makeDecoder().decode(Library.self, from: data)
        let problems = library.problems()
        guard problems.isEmpty else { throw StoreError.backupHasProblems(problems) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            try FileManager.default.copyItem(at: libraryURL,
                                             to: folder.appendingPathComponent("library-replaced-\(stamp).json"))
        }
        try writeLibrary(library)
        return library
    }

    /// "File → Back up to…": a copy wherever the user picks.
    public func exportCopy(to destination: URL) throws {
        try Data(contentsOf: libraryURL).write(to: destination, options: .atomic)
    }
}
