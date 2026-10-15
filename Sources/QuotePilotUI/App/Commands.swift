import SwiftUI

/// The menu bar. Each command checks for itself whether it applies, and says so in a message box
/// when it doesn't.
public struct QuotePilotCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Quote") { model.newQuote() }
                .keyboardShortcut("n")
            Button("New Client") { model.newClient() }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        // Every change saves itself, so there's no Save.
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .printItem) {
            Button("Save PDF…") { model.exportPDF() }
                .keyboardShortcut("p")
        }
        CommandMenu("Go") {
            ForEach(AppSection.allCases) { section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(section.shortcut))
            }
        }
    }
}
