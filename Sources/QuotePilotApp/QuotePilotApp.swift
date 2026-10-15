import AppKit
import QuotePilotCore
import QuotePilotUI
import SwiftUI

@main
struct QuotePilotApp: App {
    @State private var model: AppModel

    init() {
        // QP_LIBRARY_FOLDER points the app at another library, such as the one `qp demo` writes.
        let folder = ProcessInfo.processInfo.environment["QP_LIBRARY_FOLDER"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? LibraryStore.defaultFolder
        _model = State(initialValue: AppModel(store: LibraryStore(folder: folder)))
        // Started with `swift run`, the binary isn't inside an app bundle; make it a normal app anyway.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Quote Pilot", id: "main") {
            RootView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands { QuotePilotCommands(model: model) }
    }
}
