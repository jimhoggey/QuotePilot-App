import AppKit
import SwiftUI

/// The menu bar. Each command checks for itself whether it applies, and says so in a message box
/// when it doesn't. While a message box, dialog, save panel or open panel is up every command but
/// Close waits (`whenFree`).
public struct QuotePilotCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Quote") { model.whenFree { model.newQuote() } }
                .keyboardShortcut("n")
            Button("New Client") { model.whenFree { model.newClient() } }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Read Returned Quote…") { model.whenFree { model.choosingFile = .returnedQuote } }
                .keyboardShortcut("o")
        }
        // Every change saves itself, so there's no Save. Close lives in the same group, so it's put
        // back; it isn't held by whenFree, as closing the window is always allowed.
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
        }
        CommandGroup(replacing: .printItem) {
            Button("Send by Mail…") {
                model.whenFree {
                    if let document = model.sendableDocument {
                        model.send(document)
                    } else {
                        model.show(title: "Send by Mail", text: "Open a quote or select an invoice first.")
                    }
                }
            }
            .keyboardShortcut("s")
            Button("Save PDF…") { model.whenFree { model.exportPDF() } }
                .keyboardShortcut("p")
        }
        CommandMenu("Go") {
            ForEach(AppSection.allCases) { section in
                Button(section.title) { model.whenFree { model.go(to: section) } }
                    .keyboardShortcut(KeyEquivalent(section.shortcut))
            }
        }
    }
}
