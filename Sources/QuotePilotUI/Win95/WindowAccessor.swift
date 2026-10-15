import AppKit
import SwiftUI

/// Reaches the NSWindow that holds the view and sets it up to show the drawn Windows 95 title bar
/// (`TitleBar`) instead of the system's: the system title bar turns transparent and loses its text,
/// and the content runs underneath it, so the drawn bar starts at the very top with the window
/// buttons sitting over its left end. Put it in the background of the root view.
///
/// Asking the window directly, rather than relying on `.windowStyle(.hiddenTitleBar)` alone, gives the
/// same result on macOS 14 and on the newer systems whose title-bar area otherwise draws over, or
/// pushes the content below, the top of the window.
///
/// The window's title is still set (from the model), though it isn't drawn: Mission Control, the
/// Window menu and VoiceOver read it.
struct WindowAccessor: NSViewRepresentable {
    let title: String

    /// Everything the window needs. Safe to call again and again: it only sets what isn't already so.
    @MainActor
    static func configure(_ window: NSWindow, title: String) {
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
        // SwiftUI's hidden-title-bar window can be dragged by any background; here only the drawn bar
        // (`WindowDragArea`) moves it, so a drag in a list or a field never does.
        if window.isMovableByWindowBackground { window.isMovableByWindowBackground = false }
        if window.title != title { window.title = title }
    }

    final class AccessorView: NSView {
        var title = ""

        /// The window shows up here, before it is on screen. Once more on the next turn of the run
        /// loop, in case SwiftUI sets its own window style after it has put the content in.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            WindowAccessor.configure(window, title: title)
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                WindowAccessor.configure(window, title: self.title)
            }
        }

        /// Never takes a click: it is only there to find the window.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.title = title
        return view
    }

    /// Runs whenever the root view does, so a changed title follows the model and any setting the
    /// system put back in the meantime is put right again.
    func updateNSView(_ view: AccessorView, context: Context) {
        view.title = title
        if let window = view.window { WindowAccessor.configure(window, title: title) }
    }
}
