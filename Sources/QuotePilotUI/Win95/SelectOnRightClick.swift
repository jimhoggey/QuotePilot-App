import AppKit
import SwiftUI

/// Which row the pointer is over, built from the rows' hover callbacks. Two neighbouring rows can
/// both report in the same moment as the pointer crosses the line between them, in either order, so
/// an exit only clears the row it came from: the row entered last is the one that answers.
struct RowHover<ID: Hashable> {
    private(set) var current: ID?

    mutating func moved(_ id: ID, inside: Bool) {
        if inside {
            current = id
        } else if current == id {
            current = nil
        }
    }

    /// The row a menu click chooses: the one under the pointer, or none (the selection stays as it is).
    var target: ID? { current }
}

/// Holds a `RowHover` for a list without making the list redraw on every pointer move.
final class RowHoverBox<ID: Hashable> {
    var hover = RowHover<ID>()
}

/// Makes a right-click on a list row choose that row first, as in Windows, so its context menu opens
/// on a row that shows as selected. SwiftUI's `contextMenu` leaves the selection alone. One of these
/// goes in the background of the whole list (not one per row, where several could answer the same
/// click): it watches the window's mouse-downs, passes every one on untouched (the menu still opens,
/// a click still reaches the row) and takes none itself. The row to choose is the one the list's
/// hover tracking says is under the pointer.
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

        /// Only a menu click that lands on the part of the list that shows (the header strip above the
        /// rows doesn't count).
        private func see(_ event: NSEvent) {
            guard isActive, event.window === window,
                  SelectOnRightClick.opensMenu(event.type, modifiers: event.modifierFlags),
                  visibleRect.contains(convert(event.locationInWindow, from: nil))
            else { return }
            action()
        }
    }
}
