import SwiftUI

enum Find {
    /// True when every word of `query` appears somewhere in `fields`, ignoring case and accents.
    /// An empty query matches everything.
    static func matches(_ query: String, _ fields: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = fields.joined(separator: " ")
        return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// "Find:" and a sunken field above a list. ⌘F (a new `request` number) puts the cursor in it.
struct FindField: View {
    @Binding var text: String
    let request: Int
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("Find:")
                .font(Win95.body)
                .foregroundStyle(Win95.text)
            TextField("Find", text: $text, prompt: Text("Number, client, title…"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(Win95.body)
                .foregroundStyle(Win95.text)
                .focused($focused)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .background(Win95.field)
                .overlay(Bevel(.sunken))
                .overlay(focused ? FocusRect().padding(3) : nil)
                .frame(maxWidth: 260)
                .accessibilityLabel("Find")
            if !text.isEmpty {
                Button("Clear") { text = "" }
                    .buttonStyle(.win95)
            }
        }
        .onChange(of: request) { _, _ in focused = true }
    }
}
