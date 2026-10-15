import Foundation

/// A Windows 95 message box: a title, an icon, a sentence and its buttons.
public struct MessageBox: Identifiable {
    public enum Kind: Sendable {
        case info, question, warning
    }

    public struct Choice: Identifiable {
        public let id = UUID()
        public var title: String
        /// Return presses it; it gets the heavy black outline.
        public var isDefault: Bool
        /// Escape presses it.
        public var isCancel: Bool
        public var action: () -> Void

        public init(_ title: String, isDefault: Bool = false, isCancel: Bool = false, action: @escaping () -> Void = {}) {
            self.title = title
            self.isDefault = isDefault
            self.isCancel = isCancel
            self.action = action
        }
    }

    public let id = UUID()
    public var kind: Kind
    public var title: String
    public var text: String
    public var choices: [Choice]

    public init(kind: Kind, title: String, text: String,
                choices: [Choice] = [Choice("OK", isDefault: true, isCancel: true)]) {
        self.kind = kind
        self.title = title
        self.text = text
        self.choices = choices
    }
}
