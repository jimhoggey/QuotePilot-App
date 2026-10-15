import SwiftUI

/// The menu bar. Each command checks for itself whether it applies, and says so in a message box
/// when it doesn't. While a message box or dialog is up every command waits (`whenFree`).
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
        }
        // Every change saves itself, so there's no Save.
        CommandGroup(replacing: .saveItem) {}
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
