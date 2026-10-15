import AppKit
import SwiftUI

/// Makes a right-click on a list row choose that row first, as in Windows, so its context menu opens
/// on a row that shows as selected. SwiftUI's `contextMenu` leaves the selection alone. Put it in the
/// row's background: it watches the window's mouse-downs, passes every one on untouched (the menu
/// still opens, a click still reaches the row) and takes none itself.
struct SelectOnRightClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Watcher { Watcher() }

    /// A row under a message box or dialog is disabled (`isEnabled` is false there), so a click on
    /// it behind the box chooses nothing.
    func updateNSView(_ view: Watcher, context: Context) {
        view.action = action
        view.isActive = context.environment.isEnabled
    }

    static func dismantleNSView(_ view: Watcher, coordinator: ()) { view.stop() }

    /// Which mouse-downs open a context menu: a right-click, or a control-click.
    static func opensMenu(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseDown || (type == .leftMouseDown && modifiers.contains(.control))
    }

    final class Watcher: NSView {
        var action: () -> Void = {}
        var isActive = true
        private var monitor: Any?

        /// Never takes a click: it only listens.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.see(event) }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Only a menu click that lands on the part of this row that shows (a row scrolled half out of
        /// the list doesn't answer for the strip under the header).
        private func see(_ event: NSEvent) {
            guard isActive, event.window === window,
                  SelectOnRightClick.opensMenu(event.type, modifiers: event.modifierFlags),
                  visibleRect.contains(convert(event.locationInWindow, from: nil))
            else { return }
            action()
        }
    }
}
