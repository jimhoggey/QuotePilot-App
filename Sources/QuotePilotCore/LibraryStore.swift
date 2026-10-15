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
        case backupFromNewerVersion(Int)
    }

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
                return .unreadable(reason: "It was saved by a newer version of Quote Pilot (library format \(probe.format)).")
            }
            return .loaded(try Library.makeDecoder().decode(Library.self, from: data))
        } catch {
            return .unreadable(reason: "The library file couldn't be read (\(error.localizedDescription)).")
        }
    }

    /// Writes a temporary file and swaps it in, so a crash can't leave half a library. Refuses to
    /// replace a library file it can't read: that file needs restoring, not overwriting.
    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: libraryURL.path), case .unreadable = load() {
            throw StoreError.wouldOverwriteUnreadableLibrary
        }
        try writeLibrary(library)
    }

    /// Encodes the library and writes it to library.json atomically. Callers decide whether the
    /// existing file may be replaced.
    private func writeLibrary(_ library: Library) throws {
        try Library.makeEncoder().encode(library).write(to: libraryURL, options: .atomic)
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

    /// Backups, newest first.
    public func backups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("library-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Replaces the library with a backup once the backup is known to read and is no newer than this
    /// version. The file being replaced is copied beside it as `library-replaced-<time>.json` first, and
    /// stays on disk until the restored library is written in its place.
    @discardableResult
    public func restore(from backup: URL, now: Date = Date()) throws -> Library {
        let data = try Data(contentsOf: backup)
        let probe = try JSONDecoder().decode(FormatProbe.self, from: data)
        guard probe.format <= Library.currentFormat else {
            throw StoreError.backupFromNewerVersion(probe.format)
        }
        let library = try Library.makeDecoder().decode(Library.self, from: data)
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
