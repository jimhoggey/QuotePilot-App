import AppKit
import QuotePilotCore
import QuotePilotUI
import SwiftUI

@main
struct QuotePilotApp: App {
    @State private var model: AppModel

    init() {
        // build.sh runs the binary with `--make-iconset <folder>` to draw the Dock icon, then quits.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--make-iconset"), arguments.indices.contains(flag + 1) {
            do {
                try AppIcon.writeIconset(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Couldn't draw the icon: \(error)\n".utf8))
                exit(1)
            }
        }
        // QP_LIBRARY_FOLDER points the app at another library, such as the one `qp demo` writes; its
        // mailed copies then go in a Sent folder beside it rather than ~/Documents.
        let folders = AppFolders(environment: ProcessInfo.processInfo.environment)
        _model = State(initialValue: AppModel(store: LibraryStore(folder: folders.library), sentFolder: folders.sent))
        // Started with `swift run`, the binary isn't inside an app bundle; make it a normal app anyway.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Quote Pilot", id: "main") {
            RootView(model: model)
                // Once the window is up: the automatic check for updates (and, after an update, the
                // note saying how it went). The tests build RootView without this, so they never
                // reach the network.
                .task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands { QuotePilotCommands(model: model) }
    }
}
