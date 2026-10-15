import SwiftUI

/// The menu bar. Each command checks for itself whether it applies, and says so in a message box
/// when it doesn't. While a message box is up every command waits (`whenFree`).
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
