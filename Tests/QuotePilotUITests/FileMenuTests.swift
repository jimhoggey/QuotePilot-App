import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct FileMenuTests {
    /// A made-up backup in Invoice Generator's format. The logo is a data URL, or "" for none.
    static func backup(logo: String = "") -> Data {
        Data(#"""
        {
          "app": "invoice-quote-maker",
          "settings": { "logo": "\#(logo)", "logoHeight": 56, "accent": "#0B6B66", "paper": "A4" },
          "docs": {
            "a1": { "id": "a1", "type": "quote", "number": "Q-0101", "issued": "2026-10-04", "due": "2026-11-03",
                    "reference": "Shop fit-out", "from": { "name": "Sample Studio", "details": "" },
                    "to": { "name": "Northside Example Cafe", "details": "" },
                    "items": [ { "title": "Design", "detail": "", "qty": 1, "unit": "unit", "rate": 500 } ],
                    "tax": { "mode": "none", "rate": 10, "label": "GST" }, "discount": { "value": 0, "kind": "pct" },
                    "paid": 0, "summary": "", "payment": "", "notes": "" },
            "b2": { "id": "b2", "type": "invoice", "number": "INV-0101", "issued": "2026-10-06", "due": "2026-10-20",
                    "reference": "", "from": { "name": "Sample Studio", "details": "" },
                    "to": { "name": "Northside Example Cafe", "details": "" },
                    "items": [ { "title": "Hosting", "detail": "", "qty": 1, "unit": "unit", "rate": 30 } ],
                    "tax": { "mode": "none", "rate": 10, "label": "GST" }, "discount": { "value": 0, "kind": "pct" },
                    "paid": 10, "summary": "", "payment": "", "notes": "" }
          },
          "currentId": "a1"
        }
        """#.utf8)
    }

    /// A moving clock, so "today" can change under a running model.
    final class Clock {
        var time: Date
        init(_ time: Date) { self.time = time }
    }

    // MARK: Import

    @Test func importingABackupAddsItsDocumentsAndShowsTheReport() throws {
        let model = try UIFixture.sampleModel()
        model.importLegacyBackup(at: try UIFixture.file("invoices-backup.json", Self.backup()))
        #expect(model.library.quote(number: "Q-0101") != nil)
        #expect(model.library.invoices.contains { $0.number == "INV-0101" })
        guard case .importReport(let report) = model.dialog else {
            Issue.record("Expected the import report")
            return
        }
        #expect(report.addedQuotes == ["Q-0101"])
        #expect(report.notes.contains { $0.contains("Record it as a payment") })
        #expect(model.message == nil)
    }

    @Test func aFileThatIsntABackupChangesNothing() throws {
        let model = try UIFixture.sampleModel()
        let before = model.library.quotes.count
        model.importLegacyBackup(at: try UIFixture.file("notes.json", Data(#"{"hello":1}"#.utf8)))
        #expect(model.library.quotes.count == before)
        #expect(model.message?.text == LegacyImportError.notABackup.message)
        #expect(model.dialog == nil)
    }

    @Test func aFileThatCantBeReadChangesNothing() throws {
        let model = try UIFixture.sampleModel()
        let before = model.library.quotes.count
        model.importLegacyBackup(at: UIFixture.makeFolder().appendingPathComponent("missing.json"))
        #expect(model.library.quotes.count == before)
        #expect(model.message?.text == LegacyImportError.notABackup.message)
    }

    private func dataURL(_ data: Data) -> String { "data:image/png;base64," + data.base64EncodedString() }

    @Test func theOldLogoBecomesTheBrandLogoWhenThereIsNone() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.library.brand.logoFile == nil)
        model.importLegacyBackup(at: try UIFixture.file("b.json", Self.backup(logo: dataURL(UIFixture.pngData()))))
        let name = try #require(model.library.brand.logoFile)
        #expect(name.hasPrefix("logo-") && name.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: model.store.assetsFolder.appendingPathComponent(name).path))
        guard case .importReport(let report) = model.dialog else {
            Issue.record("Expected the import report")
            return
        }
        #expect(!report.notes.contains { $0.contains("logo") })
    }

    @Test func aLogoAlreadyThereIsKept() throws {
        var library = try SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date())
        library.brand.logoFile = "logo-OLD.png"
        let model = try UIFixture.model(library)
        model.importLegacyBackup(at: try UIFixture.file("b.json", Self.backup(logo: dataURL(UIFixture.pngData()))))
        #expect(model.library.brand.logoFile == "logo-OLD.png")
        let copied = (try? FileManager.default.contentsOfDirectory(atPath: model.store.assetsFolder.path)) ?? []
        #expect(copied.isEmpty)
    }

    @Test func anOldLogoThatIsntAnImageIsSaidSoInTheReport() throws {
        let model = try UIFixture.sampleModel()
        let junk = "data:image/png;base64," + Data("not a picture".utf8).base64EncodedString()
        model.importLegacyBackup(at: try UIFixture.file("b.json", Self.backup(logo: junk)))
        #expect(model.library.brand.logoFile == nil)
        guard case .importReport(let report) = model.dialog else {
            Issue.record("Expected the import report")
            return
        }
        #expect(report.notes.contains { $0.contains("logo couldn't be read") })
        // The documents came in all the same.
        #expect(model.library.quote(number: "Q-0101") != nil)
    }

    /// The logo can't be saved (here: a file sits where the Assets folder should be). That is said
    /// once, as a note in the import report: no message box over it, since the report is the one place
    /// the import says what is left to do.
    @Test func aLogoThatCantBeSavedIsSaidInTheReportAndInNoBox() throws {
        let model = try UIFixture.sampleModel()
        #expect(FileManager.default.createFile(atPath: model.store.assetsFolder.path, contents: Data()))
        model.importLegacyBackup(at: try UIFixture.file("b.json", Self.backup(logo: dataURL(UIFixture.pngData()))))
        #expect(model.message == nil)
        #expect(model.library.brand.logoFile == nil)
        guard case .importReport(let report) = model.dialog else {
            Issue.record("Expected the import report")
            return
        }
        #expect(report.notes.contains { $0.contains("logo") && $0.contains("Brand page") })
        // The documents came in all the same.
        #expect(model.library.quote(number: "Q-0101") != nil)
        #expect(report.addedQuotes == ["Q-0101"])
    }

    @Test func theImportMenuItemOpensTheJSONPicker() throws {
        let model = try UIFixture.sampleModel()
        model.choosingFile = .legacyBackup
        #expect(FileChoice.legacyBackup.contentTypes == [.json])
        // SwiftUI may close the panel (clearing the choice) before it reports the file.
        model.choosingFile = nil
        model.fileChosen(.success(try UIFixture.file("b.json", Self.backup())))
        #expect(model.library.quote(number: "Q-0101") != nil)
        guard case .importReport = model.dialog else {
            Issue.record("Expected the import report")
            return
        }
        #expect(model.choosingFile == nil)
    }

    // MARK: Tax time

    @Test func theTaxExportSavesACSVForTheChosenYear() throws {
        let model = try UIFixture.sampleModel()
        let year = FinancialYear(containing: UIFixture.today)
        #expect(model.taxYears.first == year)
        model.dialog = .taxExport
        model.exportPayments(for: year)
        let export = try #require(model.pendingExport)
        #expect(export.contentType == .commaSeparatedText)
        #expect(export.fileName == "Payments FY 2026-27.csv")
        let csv = String(decoding: export.data, as: UTF8.self)
        #expect(csv.hasPrefix("Date,Client,Invoice,Amount,Method,Note"))
        #expect(csv.contains("INV-0001"))
        #expect(model.dialog == nil)
    }

    @Test func theTaxYearsAreThoseWithPaymentsPlusThisOneNewestFirst() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.taxYears == [FinancialYear(startYear: 2026)])
        let invoice = try #require(model.library.invoices.first { $0.number == "INV-0003" })
        model.change("test") {
            try $0.recordPayment(Payment(date: Day(year: 2025, month: 8, day: 1), amount: Money(dollars: 10)), toInvoice: invoice.id)
        }
        #expect(model.taxYears == [FinancialYear(startYear: 2026), FinancialYear(startYear: 2025)])
        // A year with no payments in it isn't offered.
        #expect(!model.taxYears.contains(FinancialYear(startYear: 2024)))
    }

    // MARK: Back Up To…

    @Test func backUpToSavesTheLibraryFile() throws {
        let model = try UIFixture.sampleModel()
        model.exportBackupCopy()
        let export = try #require(model.pendingExport)
        #expect(export.contentType == .json)
        #expect(export.fileName == "Quote Pilot backup 2026-10-15.json")
        #expect(export.data == (try Data(contentsOf: model.store.libraryURL)))
    }

    /// The menu item reads `canBackUp`: with no saved library file it is greyed out, and the first
    /// save turns it on.
    @Test func backUpToIsGreyedOutUntilThereIsASavedLibrary() throws {
        let model = try UIFixture.model()
        #expect(!model.canBackUp)
        var beeps = 0
        model.beep = { beeps += 1 }
        model.exportBackupCopy()
        #expect(model.pendingExport == nil)
        #expect(model.message == nil)
        #expect(beeps == 1)

        model.newClient()
        #expect(model.canBackUp)
        model.exportBackupCopy()
        #expect(model.pendingExport != nil)
        #expect(beeps == 1)

        // An existing library file counts from the start.
        #expect(try UIFixture.sampleModel().canBackUp)
    }

    /// The menu items read `libraryIsOpen` (Read Returned Quote…, Import from Invoice Generator…,
    /// Export Payments for Tax Time…, and the New commands) and `canRestoreBackup` (Restore Backup…):
    /// on the unreadable-library screen only restoring is on offer, and only when there is a backup.
    @Test func theFileMenuOffersOnlyRestoreWhileTheLibraryCantBeRead() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.libraryIsOpen)
        #expect(model.canRestoreBackup, "a library that loaded makes today's backup")

        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let unreadable = try UIFixture.model(folder: folder)
        #expect(unreadable.loadState != .ready)
        #expect(!unreadable.libraryIsOpen)
        // No backup yet: Restore Backup… is greyed out too.
        #expect(!unreadable.canRestoreBackup)

        // With a backup beside it, Restore Backup… is the one command that works.
        try FileManager.default.createDirectory(at: unreadable.store.backupsFolder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: unreadable.store.backupsFolder.appendingPathComponent("library-2026-10-01.json"))
        #expect(!unreadable.libraryIsOpen)
        #expect(unreadable.canRestoreBackup)

        // Restoring opens the library again.
        let good = try UIFixture.sampleModel()
        let backup = try #require(good.store.backups().first)
        try FileManager.default.copyItem(at: backup, to: unreadable.store.backupsFolder.appendingPathComponent("library-2026-10-02.json"))
        unreadable.restore(from: unreadable.store.backupsFolder.appendingPathComponent("library-2026-10-02.json"))
        #expect(unreadable.libraryIsOpen)
    }

    /// Restore Backup… has nothing to offer on a new library, and is on once the first save has made a backup.
    @Test func restoreBackupIsGreyedOutUntilThereIsABackup() throws {
        let model = try UIFixture.model()
        #expect(model.libraryIsOpen)
        #expect(model.store.backups().isEmpty)
        #expect(!model.canRestoreBackup)
        model.newClient()
        #expect(model.canRestoreBackup)
    }

    @Test func aDamagedLibraryIsNotOfferedAsABackup() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        #expect(!model.canBackUp)
    }

    // MARK: Restore Backup…

    @Test func restoringAChosenBackupAsksNothingAndSaysSoInTheStatusBar() throws {
        let model = try UIFixture.sampleModel()
        let backup = try #require(model.store.backups().first)
        model.newQuote()
        #expect(model.library.quotes.count == 5)
        model.dialog = .restore
        model.restore(from: backup)
        #expect(model.library.quotes.count == 4)
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.statusNote?.text == "Restored the 15 Oct 2026 backup")
        #expect(StatusBarText.items(model.dashboard, lastSaved: model.lastSaved, note: model.statusNote,
                                    currencyCode: "AUD")[3] == "Restored the 15 Oct 2026 backup")
        #expect(model.library.activity.first?.message == "Restored the backup library-2026-10-15.json")
        // The editor that was open belongs to the library that was replaced.
        #expect(model.openQuoteID == nil)
        // The library it replaced is kept beside it.
        let folder = model.store.libraryURL.deletingLastPathComponent()
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("library-replaced-") }
        #expect(kept.count == 1)
    }

    // MARK: Numbers are never reused, even across a restore

    /// A made-up mailed PDF in the sent folder's year folder.
    private func mailedFile(_ name: String, in model: AppModel) throws {
        let folder = model.sentFolder.appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: folder.appendingPathComponent(name))
    }

    /// The backup is older than the numbers issued since: restoring it must not hand them out again.
    @Test func restoringABackupNeverBringsBackANumberIssuedSince() throws {
        let model = try UIFixture.sampleModel()
        let backup = try #require(model.store.backups().first)
        #expect(model.library.nextNumber(.quote) == "Q-0005")
        #expect(model.library.nextNumber(.invoice) == "INV-0004")
        model.newQuote()
        model.newInvoice()
        #expect(model.library.quote(number: "Q-0005") != nil)
        #expect(model.library.invoices.contains { $0.number == "INV-0004" })

        model.restore(from: backup)
        // The quote and invoice are gone with the replaced library, but their numbers stay used.
        #expect(model.library.quote(number: "Q-0005") == nil)
        #expect(model.library.usedNumbers.contains("Q-0005"))
        #expect(model.library.usedNumbers.contains("INV-0004"))
        model.newQuote()
        model.newInvoice()
        #expect(model.library.quote(number: "Q-0006") != nil)
        #expect(model.library.invoices.contains { $0.number == "INV-0005" })
        // And it was saved, in the same change as the Activity entry.
        guard case .loaded(let onDisk) = model.store.load() else {
            Issue.record("Expected the saved library")
            return
        }
        #expect(onDisk.usedNumbers.contains("Q-0005") && onDisk.usedNumbers.contains("INV-0004"))
    }

    /// A number in a mailed PDF's file name was sent to a client, so it is used whatever the library says.
    @Test func restoringNeverReusesANumberFoundInTheSentFolder() throws {
        let model = try UIFixture.sampleModel()
        try mailedFile("Q-0007 Sample Client Pty Ltd.pdf", in: model)
        try mailedFile("INV-0009 Sample Client Pty Ltd.pdf", in: model)
        try mailedFile("Receipt INV-0010 Sample Client Pty Ltd.pdf", in: model)
        try mailedFile("notes.txt", in: model)
        model.restore(from: try #require(model.store.backups().first))
        #expect(model.library.nextNumber(.quote) == "Q-0008")
        #expect(model.library.nextNumber(.invoice) == "INV-0011")
        model.newQuote()
        #expect(model.library.quote(number: "Q-0008") != nil)
    }

    /// The library being replaced couldn't be read, so its used numbers are lost: the sent folder is
    /// what is left to go on.
    @Test func restoringOverAnUnreadableLibraryStillSkipsSentNumbers() throws {
        let folder = UIFixture.makeFolder()
        let store = LibraryStore(folder: folder)
        try store.save(SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date()))
        try FileManager.default.createDirectory(at: store.backupsFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: store.libraryURL,
                                         to: store.backupsFolder.appendingPathComponent("library-2026-10-01.json"))
        try Data("not a library".utf8).write(to: store.libraryURL)
        let model = AppModel(store: store, now: { UIFixture.today.date() }, mail: FakeMail(), sentFolder: UIFixture.makeFolder())
        #expect(model.loadState != .ready)
        try mailedFile("Q-0012 Sample Client Pty Ltd.pdf", in: model)
        try mailedFile("INV-0020 Sample Client Pty Ltd.pdf", in: model)

        model.restoreLatestBackup()
        #expect(model.loadState == .ready)
        #expect(model.library.nextNumber(.quote) == "Q-0013")
        #expect(model.library.nextNumber(.invoice) == "INV-0021")
    }

    @Test func aBackupThatCantBeRestoredKeepsTheDialogAndShowsItsBox() throws {
        let model = try UIFixture.sampleModel()
        model.newQuote()
        let saved = try Data(contentsOf: model.store.libraryURL)
        let junk = try UIFixture.file("library-2026-10-01.json", Data("not a library".utf8))
        model.dialog = .restore
        model.restore(from: junk)
        // Nothing changed: the library, the file and the open editor are as they were.
        #expect(model.library.quotes.count == 5)
        #expect(try Data(contentsOf: model.store.libraryURL) == saved)
        #expect(model.openQuoteID != nil)
        #expect(model.message?.title == "Couldn't restore the backup")
        #expect(model.statusNote == nil)
        // Still up, so another backup can be chosen.
        #expect(model.dialog == .restore)
    }

    /// Plan 2a's guard: when the restore worked but today's backup then failed, that box stays up,
    /// with a sentence saying the restore itself worked.
    @Test func aFailedActivityNoteKeepsItsBoxAndSaysTheRestoreWorked() throws {
        let clock = Clock(UIFixture.today.date())
        let store = LibraryStore(folder: UIFixture.makeFolder())
        try store.save(SampleLibrary.make(today: UIFixture.today, now: clock.time))
        let model = AppModel(store: store, now: { clock.time }, mail: FakeMail(), sentFolder: UIFixture.makeFolder())
        let backup = try UIFixture.file("library-2026-10-01.json", try Data(contentsOf: store.libraryURL))
        model.newQuote()
        // Tomorrow, with the Backups folder blocked by a file: the first save of the day can't back up.
        clock.time = clock.time.addingTimeInterval(24 * 60 * 60)
        try FileManager.default.removeItem(at: store.backupsFolder)
        #expect(FileManager.default.createFile(atPath: store.backupsFolder.path, contents: Data()))

        model.dialog = .restore
        model.restore(from: backup)
        #expect(model.library.quotes.count == 4)
        #expect(model.dialog == nil)
        #expect(model.message?.title == "Couldn't make today's backup")
        #expect(model.message?.text.hasSuffix(" The backup itself was restored.") == true)
        #expect(model.statusNote == nil)
    }

    @Test func restoringTheLatestBackupUsesTheSamePath() throws {
        let model = try UIFixture.sampleModel()
        model.newQuote()
        model.restoreLatestBackup()
        #expect(model.library.quotes.count == 4)
        #expect(model.message == nil)
        #expect(model.statusNote?.text == "Restored the 15 Oct 2026 backup")
    }

    // MARK: One save panel

    @Test func theSavePanelHandlesPDFsSpreadsheetsAndBackups() {
        #expect(ExportFile.readableContentTypes == [.pdf, .commaSeparatedText, .json])
        #expect(FileExport(data: Data(), fileName: "Q-0001.pdf").contentType == .pdf)
    }

    @Test func aFailedSaveNamesWhatWasBeingSaved() throws {
        let model = try UIFixture.sampleModel()
        let failure = Result<URL, Error>.failure(CocoaError(.fileWriteOutOfSpace))
        model.exportPayments(for: FinancialYear(containing: UIFixture.today))
        // SwiftUI may clear the pending export before it reports; the title still names the file.
        model.pendingExport = nil
        model.finishExport(failure)
        #expect(model.message?.title == "Couldn't save the CSV")
        model.message = nil

        model.exportBackupCopy()
        model.finishExport(failure)
        #expect(model.message?.title == "Couldn't save the backup")
        model.message = nil

        model.section = .quotes
        model.openQuote(try #require(model.library.quotes.first).id)
        model.exportPDF()
        model.finishExport(failure)
        #expect(model.message?.title == "Couldn't save the PDF")
    }

    // MARK: Drawing

    @Test func theFileDialogsDraw() throws {
        let model = try UIFixture.sampleModel()
        var report = ImportReport()
        report.addedQuotes = ["Q-0101"]
        report.addedInvoices = ["INV-0101"]
        report.notes = ["INV-0101: the old tool showed $10.00 already paid. Record it as a payment with the date it arrived."]
        model.dialog = .importReport(report)
        #expect(Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "import-report")
            .map(Snapshot.hasContent) == true)
        model.dialog = .taxExport
        #expect(Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "tax-export")
            .map(Snapshot.hasContent) == true)
        model.dialog = .restore
        #expect(Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "restore")
            .map(Snapshot.hasContent) == true)
    }

    /// After a restore the status bar's last cell says which backup came back, in the room it has.
    @Test func theStatusBarSaysWhichBackupCameBack() throws {
        let model = try UIFixture.sampleModel()
        model.newQuote()
        model.restore(from: try #require(model.store.backups().first))
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "restored")
        #expect(rep.map(Snapshot.hasContent) == true)
        #expect(StatusBarText.items(model.dashboard, lastSaved: model.lastSaved, note: model.statusNote,
                                    currencyCode: "AUD")[3] == "Restored the 15 Oct 2026 backup")
    }

    // MARK: Greyed-out menu items

    /// Send by Mail… reads `sendableDocument` and Save PDF… reads `canExportPDF`; each is greyed out
    /// when there is nothing to send or save.
    @Test func sendAndSavePDFAreGreyedOutWithNothingToSendOrSave() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.section == .dashboard)
        #expect(model.sendableDocument == nil)
        #expect(!model.canExportPDF)

        model.section = .quotes
        #expect(model.sendableDocument == nil)
        #expect(!model.canExportPDF)
        let quote = try #require(model.library.quote(number: "Q-0002"))
        model.selectedQuoteID = quote.id
        #expect(model.sendableDocument != nil)
        #expect(model.canExportPDF)

        model.section = .invoices
        #expect(model.sendableDocument == nil)
        #expect(!model.canExportPDF)
        model.selectedInvoiceID = try #require(model.library.invoices.first).id
        #expect(model.sendableDocument != nil)
        #expect(model.canExportPDF)

        model.section = .brand
        #expect(model.sendableDocument == nil)
        #expect(!model.canExportPDF)
    }

    /// A void invoice no longer counts, so there is nothing to mail for it: ⌘S, the toolbar's Send and
    /// the menu item are greyed out, whether it is selected in the list or open in the editor.
    @Test func nothingCanBeSentForAVoidInvoice() throws {
        let model = try UIFixture.sampleModel()
        let care = try #require(model.library.invoices.first { $0.number == "INV-0002" })
        model.section = .invoices
        model.selectedInvoiceID = care.id
        #expect(model.sendableDocument == .invoice(care.id))

        model.change("test") { try $0.voidInvoice(care.id) }
        #expect(model.library.invoice(care.id)?.stage == .void)
        #expect(model.sendableDocument == nil)
        model.openInvoice(care.id)
        #expect(model.sendableDocument == nil)
        // It can still be saved as a PDF: that is a record, not a send.
        #expect(model.canExportPDF)

        // Other invoices are unaffected.
        model.openInvoiceID = nil
        model.selectedInvoiceID = try #require(model.library.invoices.first { $0.number == "INV-0003" }).id
        #expect(model.sendableDocument != nil)
    }

    @Test func savingAPDFWithNothingToSaveBeepsInsteadOfExplaining() throws {
        let model = try UIFixture.sampleModel()
        var beeps = 0
        model.beep = { beeps += 1 }
        model.exportPDF()
        #expect(model.pendingExport == nil)
        #expect(model.message == nil)
        #expect(beeps == 1)
    }
}
