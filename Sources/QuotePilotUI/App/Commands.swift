import AppKit
import SwiftUI

/// The menu bar. A command that can't run is greyed out (Send by Mail…, Save PDF…, Back Up To…, the
/// import and export commands while the library can't be read, Restore Backup… with no backup), not
/// explained in a message box. While a message box, dialog, save panel or open panel is up every
/// command but Close waits (`whenFree`).
public struct QuotePilotCommands: Commands {
    let model: AppModel
    /// View → Show Steps: the step bar under a quote's or invoice's header. On unless turned off.
    @AppStorage(StepPreferences.showStepsKey) private var showSteps = true

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
            Divider()
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
        // The File menu's groups keep a fixed order (new, save, import/export, print), so everything
        // that sits above Close is in the first group and Close is alone in the next. Every change
        // saves itself, so there's no Save. Close isn't held by whenFree, as closing the window is
        // always allowed.
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
        }
        // Send by Mail… and Save PDF… moved up with the others, so Print has nothing of ours to hold.
        CommandGroup(replacing: .printItem) {}
        // A checkmark in the View menu. Like the other commands it waits while a message box is up.
        CommandGroup(after: .toolbar) {
            Toggle("Show Steps", isOn: $showSteps)
                .disabled(model.isBusy)
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
