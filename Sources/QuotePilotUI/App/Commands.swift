import AppKit
import SwiftUI

/// The menu bar. A command that can't run is greyed out (Send by Mail…, Save PDF…, Back Up To…, the
/// import and export commands while the library can't be read, Restore Backup… with no backup), not
/// explained in a message box. While a message box, dialog, save panel or open panel is up every
/// command but Close waits (`whenFree`).
public struct QuotePilotCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Quote") { model.whenFree { model.newQuote() } }
                .keyboardShortcut("n")
                .disabled(!model.libraryIsOpen)
            Button("New Invoice") { model.whenFree { model.newInvoice() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!model.libraryIsOpen)
            Button("New Client") { model.whenFree { model.newClient() } }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!model.libraryIsOpen)
            Divider()
            Button("Read Returned Quote…") { model.whenFree { model.choosingFile = .returnedQuote } }
                .keyboardShortcut("o")
                .disabled(!model.libraryIsOpen)
        }
        // Every change saves itself, so there's no Save. Close lives in the same group, so it's put
        // back; it isn't held by whenFree, as closing the window is always allowed. The import and
        // backup items follow it in the same group, which keeps their order under Close.
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Divider()
            Button("Import from Invoice Generator…") { model.whenFree { model.choosingFile = .legacyBackup } }
                .disabled(!model.libraryIsOpen)
            Button("Export Payments for Tax Time…") { model.whenFree { model.dialog = .taxExport } }
                .disabled(!model.libraryIsOpen)
            Divider()
            Button("Back Up To…") { model.whenFree { model.exportBackupCopy() } }
                .disabled(!model.canBackUp)
            // The one command that works while the library can't be read; with no backup it has nothing to offer.
            Button("Restore Backup…") { model.whenFree { model.dialog = .restore } }
                .disabled(!model.canRestoreBackup)
        }
        CommandGroup(replacing: .printItem) {
            Button("Send by Mail…") {
                model.whenFree {
                    if let document = model.sendableDocument { model.send(document) }
                }
            }
            .keyboardShortcut("s")
            .disabled(model.sendableDocument == nil)
            Button("Save PDF…") { model.whenFree { model.exportPDF() } }
                .keyboardShortcut("p")
                .disabled(!model.canExportPDF)
        }
        CommandMenu("Go") {
            ForEach(AppSection.allCases) { section in
                Button(section.title) { model.whenFree { model.go(to: section) } }
                    .keyboardShortcut(KeyEquivalent(section.shortcut))
            }
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") { model.whenFree { model.find() } }
                .keyboardShortcut("f")
        }
    }
}
