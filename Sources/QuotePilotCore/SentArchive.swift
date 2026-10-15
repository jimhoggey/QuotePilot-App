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

    /// Every quote and invoice number in the file names under `root` ("Q-0003 Sample Client.pdf",
    /// "Receipt INV-0009 ….pdf"), as "Q-0003" or "INV-0009". A mailed copy proves its number went to a
    /// client, so it is used whether or not the library says so (a restored backup, an unreadable
    /// library). A number must be a whole one as the app writes them, so "Q-00021" or a long run of
    /// digits in some other file's name isn't mistaken for one. Nothing is read from the files.
    public static func numbers(in root: URL) -> [String] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) else { return [] }
        var found = Set<String>()
        for case let url as URL in files {
            let name = url.lastPathComponent
            var rest = name.startIndex..<name.endIndex
            while let range = name.range(of: numberPattern, options: [.regularExpression, .caseInsensitive], range: rest) {
                let text = name[range].uppercased()
                let prefix = text.hasPrefix("INV-") ? "INV-" : "Q-"
                if let value = Int(text.dropFirst(prefix.count)) {
                    found.insert(prefix + String(format: "%04d", value))
                }
                rest = range.upperBound..<name.endIndex
            }
        }
        return found.sorted()
    }

    /// "Q-" or "INV-", then digits laid out as `Library.nextNumber` writes them (four, padded with
    /// zeros, or five or six without leading zeros), not run into a letter or digit before it or a digit
    /// after.
    private static let numberPattern = "(?<![A-Za-z0-9])(?:Q|INV)-(?:[0-9]{4}|[1-9][0-9]{4,5})(?![0-9])"
}
