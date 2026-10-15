import Foundation

/// Where a copy of every mailed PDF is kept: `~/Documents/Quote Pilot/<year>/` (spec §2), a record of
/// exactly what each client received.
public enum SentArchive {
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quote Pilot", isDirectory: true)
    }

    /// A file in `root/<year>/` that doesn't exist yet: the name itself, then "… (2).pdf", "… (3).pdf",
    /// so sending a document again never overwrites what went before.
    public static func freshURL(for fileName: String, year: Int, in root: URL) -> URL {
        let folder = root.appendingPathComponent(String(year), isDirectory: true)
        let name = fileName as NSString
        let base = name.deletingPathExtension
        let suffix = name.pathExtension.isEmpty ? "" : "." + name.pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var copy = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(copy))\(suffix)")
            copy += 1
        }
        return candidate
    }
}
