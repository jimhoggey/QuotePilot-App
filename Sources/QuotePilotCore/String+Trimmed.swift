import Foundation

extension String {
    /// The text without leading or trailing spaces and line breaks.
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
