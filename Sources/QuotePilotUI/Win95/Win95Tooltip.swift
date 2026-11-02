import SwiftUI

/// A Windows 95 tooltip: a pale yellow note with a question mark, saying what a control does.
struct Win95Tooltip: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("?").font(Win95.label)
            Text(text).font(Win95.small).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Win95.text)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(width: 260, alignment: .leading)
        .background(Win95.tooltip)
        .overlay(Rectangle().strokeBorder(Win95.dark, lineWidth: 1))
    }
}

extension View {
    /// Explains this control in a `Win95Tooltip` just below it, half a second into a hover: quicker
    /// and plainer than macOS's own tooltip. VoiceOver reads it as the hint. The row it's in needs a
    /// `zIndex` above what's drawn under it, so the note isn't covered.
    func explained(_ text: String) -> some View { modifier(Explained(text: text)) }
}

private struct Explained: ViewModifier {
    let text: String
    @State private var hovering = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .task(id: hovering) {
                shown = false
                guard hovering else { return }
                try? await Task.sleep(for: .milliseconds(500))
                shown = !Task.isCancelled
            }
            .overlay(alignment: .bottomLeading) {
                if shown {
                    Win95Tooltip(text: text)
                        .alignmentGuide(.bottom) { $0[.top] - 4 }
                        .allowsHitTesting(false)
                }
            }
            .accessibilityHint(text)
    }
}
