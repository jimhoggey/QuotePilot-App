import AppKit
import SwiftUI

/// The navy title bar across the top of the window and of every message box. It turns grey when
/// the window isn't the active one, as in Windows 95.
public struct TitleBar: View {
    let title: String
    let icon: PixelIcon?
    let height: CGFloat
    let leadingInset: CGFloat
    @Environment(\.controlActiveState) private var activeState

    public init(_ title: String, icon: PixelIcon? = nil, height: CGFloat = 22, leadingInset: CGFloat = 0) {
        self.title = title
        self.icon = icon
        self.height = height
        self.leadingInset = leadingInset
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let icon {
                // Most icons have black or navy pixels that vanish on the bar, so each sits on a
                // small grey square.
                PixelIconView(icon)
                    .padding(1)
                    .background(Win95.face)
            }
            Text(title)
                .font(Win95.windowTitle)
                .foregroundStyle(Win95.highlight)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4 + leadingInset)
        .padding(.trailing, 4)
        .frame(height: height)
        .background(activeState == .inactive ? Win95.inactiveTitleBar : Win95.titleBar)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Lets the drawn title bar move the window, and a double-click zoom it, like a real title bar.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// One sunken panel of the status bar.
public struct StatusPanel: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Win95.body)
            .foregroundStyle(Win95.text)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .overlay(Bevel(.sunken))
    }
}

/// The two-tone line Windows 95 draws between toolbars and panels.
public struct EtchedLine: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Win95.shadow.frame(height: 1)
            Win95.highlight.frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A note in a pale yellow box, or a warning in bright yellow, with its icon.
public struct NoteBanner: View {
    let text: String
    let warning: Bool

    public init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            PixelIconView(warning ? .warning : .info)
            Text(text)
                .font(Win95.body)
                .foregroundStyle(Win95.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(warning ? Win95.warning : Win95.tooltip)
        .overlay(Rectangle().strokeBorder(Win95.dark, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// A Windows 95 message box: navy title, a 32-point icon, the sentence, and bevelled buttons.
/// Return presses the default button and Escape the cancel one.
struct MessageBoxView: View {
    let box: MessageBox
    let respond: (MessageBox.Choice) -> Void

    private var icon: PixelIcon {
        switch box.kind {
        case .info: return .info
        case .question: return .question
        case .warning: return .warning
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(box.title)
                .padding(2)
            HStack(alignment: .top, spacing: 14) {
                PixelIconView(icon, size: 32)
                Text(box.text)
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380, alignment: .leading)
            }
            .padding(16)
            HStack(spacing: 8) {
                ForEach(box.choices) { choice in
                    Button(choice.title) { respond(choice) }
                        .buttonStyle(Win95ButtonStyle(isDefault: choice.isDefault))
                        .keyboardShortcut(shortcut(for: choice))
                }
            }
            .padding(.bottom, 14)
            // When one button is both default and cancel (a lone OK), Escape still needs a home.
            if let cancel = box.choices.first(where: { $0.isCancel && $0.isDefault }) {
                Button("") { respond(cancel) }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        // The title bar and button row stretch to whatever width they're offered, so without a
        // ceiling the box would span the whole window. 460 fits the 380-point sentence column.
        .frame(minWidth: 320, maxWidth: 460)
        .background(Win95.face)
        .overlay(Bevel(.raised))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(box.title)
        .accessibilityAddTraits(.isModal)
    }

    private func shortcut(for choice: MessageBox.Choice) -> KeyboardShortcut? {
        if choice.isDefault { return .defaultAction }
        if choice.isCancel { return .cancelAction }
        return nil
    }
}
