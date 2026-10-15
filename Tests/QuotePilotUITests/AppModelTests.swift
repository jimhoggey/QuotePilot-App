import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct AppModelTests {
    @Test func aFreshLibraryStartsEmptyAndWritesNothingUntilTheFirstChange() throws {
        let model = try UIFixture.model()
        #expect(model.loadState == .ready)
        #expect(model.library.quotes.isEmpty)
        #expect(model.lastSaved == nil)
        #expect(!FileManager.default.fileExists(atPath: model.store.libraryURL.path))
        // No backups either, so there's nothing to ask about.
        #expect(model.message == nil)
    }

    // MARK: A missing library with backups

    /// A folder whose library.json has gone (moved or deleted) but whose Backups/ still holds one.
    func folderWithOnlyABackup() throws -> (folder: URL, quoteID: UUID) {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let folder = UIFixture.makeFolder()
        let store = LibraryStore(folder: folder)
        try store.save(library)
        try store.backUpIfDue(today: UIFixture.today)
        try FileManager.default.removeItem(at: store.libraryURL)
        return (folder, quoteID)
    }

    @Test func aMissingLibraryWithABackupAsksToRestoreIt() throws {
        let (folder, quoteID) = try folderWithOnlyABackup()
        let model = try UIFixture.model(folder: folder)
        let box = try #require(model.message)
        #expect(box.kind == .question)
        #expect(box.title == "Library Missing")
        #expect(box.text == "Quote Pilot can't find your library file, but there's a backup from 15 Oct 2026. Restore it?")
        #expect(box.choices.map(\.title) == ["Restore", "Start Empty"])
        #expect(box.choices.first(where: \.isDefault)?.title == "Restore")
        #expect(box.choices.first(where: \.isCancel)?.title == "Start Empty")
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "library-missing")
        #expect(rep.map(Snapshot.hasContent) == true)

        model.respond(box.choices[0])
        #expect(model.loadState == .ready)
        #expect(model.library.quote(quoteID) != nil)
        #expect(FileManager.default.fileExists(atPath: model.store.libraryURL.path))
        // No box: the status bar says it, and Activity keeps the entry.
        #expect(model.message == nil)
        #expect(model.statusNote?.text == "Restored the 15 Oct 2026 backup")
        #expect(model.library.activity.first?.message == "Restored the backup library-2026-10-15.json")
    }

    @Test func startingEmptyLeavesTheBackupAlone() throws {
        let (folder, _) = try folderWithOnlyABackup()
        let model = try UIFixture.model(folder: folder)
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first { $0.title == "Start Empty" }))
        #expect(model.message == nil)
        #expect(model.loadState == .ready)
        #expect(model.library.quotes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: model.store.libraryURL.path))
        #expect(model.store.backups().map(\.lastPathComponent) == ["library-2026-10-15.json"])
    }

    @Test func aBackupIsNamedByItsDay() {
        #expect(AppModel.backupLabel(URL(fileURLWithPath: "/backups/library-2026-10-15.json")) == "15 Oct 2026")
        #expect(AppModel.backupLabel(URL(fileURLWithPath: "/backups/library-old.json")) == "library-old")
    }

    // MARK: Unreadable libraries

    @Test func aLibraryWithAnAbsurdAmountOpensTheUnreadableScreen() throws {
        var (library, _) = try UIFixture.invoicedLibrary()
        library.quotes[0].lines[0].rate = Money(dollars: 20_000_000)
        let folder = UIFixture.makeFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Library.makeEncoder().encode(library).write(to: folder.appendingPathComponent("library.json"))
        let model = try UIFixture.model(folder: folder)
        guard case .unreadable(let reason) = model.loadState else {
            Issue.record("An absurd amount should load as unreadable")
            return
        }
        #expect(reason.contains("Q-0001 line 01 has a rate of $20,000,000.00"))
        #expect(!model.loadState.isFromNewerVersion)
        #expect(model.store.backups().isEmpty)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "unreadable-absurd")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func aLibraryFromANewerVersionSaysSo() throws {
        let newer = try UIFixture.file("library.json", Data(#"{"format": 99}"#.utf8)).deletingLastPathComponent()
        #expect(try UIFixture.model(folder: newer).loadState.isFromNewerVersion)
        let damaged = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        #expect(try !UIFixture.model(folder: damaged).loadState.isFromNewerVersion)
        #expect(!AppModel.LoadState.ready.isFromNewerVersion)
    }

    @Test func aChangeIsSavedBeforeTheAppKeepsIt() throws {
        let model = try UIFixture.model()
        model.newQuote()
        #expect(model.library.quotes.map(\.number) == ["Q-0001"])
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("The new quote wasn't saved")
            return
        }
        #expect(saved.quotes.map(\.number) == ["Q-0001"])
        #expect(model.lastSaved != nil)
        #expect(model.section == .quotes)
        #expect(model.openQuoteID == saved.quotes[0].id)
    }

    @Test func aRefusedChangeKeepsTheStoredValue() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        let before = try Data(contentsOf: model.store.libraryURL)
        var edited = try #require(model.library.quote(quoteID))
        edited.lines[0].rate = Money(dollars: 999)
        model.updateQuote(edited)
        #expect(model.library.quote(quoteID)?.lines[0].rate == Money(dollars: 600))
        #expect(try Data(contentsOf: model.store.libraryURL) == before)
        #expect(model.message?.text == LibraryError.alreadyInvoiced.message)
    }

    @Test func anUnreadableLibraryIsNeverSaved() throws {
        let garbage = Data("not a library".utf8)
        let folder = try UIFixture.file("library.json", garbage).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        guard case .unreadable = model.loadState else {
            Issue.record("A damaged file should load as unreadable")
            return
        }
        model.newQuote()
        model.newClient()
        #expect(try Data(contentsOf: model.store.libraryURL) == garbage)
        #expect(model.library.quotes.isEmpty)
        #expect(model.message != nil)
    }

    @Test func aFailedSaveOpensNothing() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        #expect(model.loadState == .ready)
        // The file is damaged after the app has loaded it, so the next save is refused.
        let damaged = Data("damaged".utf8)
        try damaged.write(to: model.store.libraryURL)

        model.newQuote()
        #expect(model.openQuoteID == nil)
        #expect(model.selectedQuoteID == nil)
        #expect(model.section == .dashboard)
        #expect(model.library.quotes.map(\.id) == [quoteID])
        #expect(model.message?.text == LibraryStore.StoreError.wouldOverwriteUnreadableLibrary.message)
        #expect(try Data(contentsOf: model.store.libraryURL) == damaged)
    }

    @Test func aFailedSaveOpensNoDuplicate() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        try Data("damaged".utf8).write(to: model.store.libraryURL)

        model.duplicateQuote(quoteID)
        #expect(model.openQuoteID == nil)
        #expect(model.selectedQuoteID == nil)
        #expect(model.section == .dashboard)
        #expect(model.library.quotes.map(\.id) == [quoteID])
        #expect(model.message?.text == LibraryStore.StoreError.wouldOverwriteUnreadableLibrary.message)
    }

    @Test func restoringTheLatestBackupRecovers() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let folder = UIFixture.makeFolder()
        let store = LibraryStore(folder: folder)
        try store.save(library)
        try store.backUpIfDue(today: UIFixture.today)
        try Data("damaged".utf8).write(to: store.libraryURL)

        let model = try UIFixture.model(folder: folder)
        guard case .unreadable = model.loadState else {
            Issue.record("A damaged file should load as unreadable")
            return
        }
        model.restoreLatestBackup()
        #expect(model.loadState == .ready)
        #expect(model.library.quote(quoteID) != nil)
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("library-replaced-") }
        #expect(kept.count == 1)
        #expect(model.library.activity.first?.message.hasPrefix("Restored the backup") == true)
        #expect(model.message == nil)
        #expect(model.statusNote?.text == "Restored the 15 Oct 2026 backup")
    }

    @Test func anExistingLibraryIsBackedUpOnLaunch() throws {
        let (library, _) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        #expect(model.store.backups().count == 1)
    }

    @Test func aNonImageLogoIsRefused() throws {
        let model = try UIFixture.model(Library())
        let fake = try UIFixture.file("logo.png", Data("this is not a picture".utf8))
        model.importLogo(from: fake)
        #expect(model.library.brand.logoFile == nil)
        #expect(model.message?.title == "Not an Image")
        let copied = (try? FileManager.default.contentsOfDirectory(atPath: model.store.assetsFolder.path)) ?? []
        #expect(copied.isEmpty)
    }

    @Test func aRealLogoIsCopiedIntoAssets() throws {
        let model = try UIFixture.model(Library())
        model.importLogo(from: try UIFixture.file("logo.png", UIFixture.pngData()))
        let name = try #require(model.library.brand.logoFile)
        #expect(name.hasPrefix("logo-") && name.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: model.store.assetsFolder.appendingPathComponent(name).path))
        #expect(model.logoURL?.lastPathComponent == name)
    }

    @Test func aNonFontIsRefused() throws {
        let model = try UIFixture.model(Library())
        model.importHeadingFont(from: try UIFixture.file("heading.ttf", Data("not a font".utf8)))
        #expect(model.library.brand.headingFontFile == nil)
        #expect(model.message?.title == "Not a Font")
    }

    @Test func deletingADraftAsksFirstWithCancelAsTheDefault() throws {
        let model = try UIFixture.model()
        model.newQuote()
        let id = try #require(model.openQuoteID)
        model.deleteDraftQuote(id)
        #expect(model.library.quote(id) != nil)
        let box = try #require(model.message)
        #expect(box.choices.first(where: \.isDefault)?.title == "Cancel")
        model.respond(try #require(box.choices.first { $0.title == "Delete" }))
        #expect(model.library.quote(id) == nil)
        #expect(model.openQuoteID == nil)
        #expect(model.message == nil)
    }

    @Test func savePDFNeedsAQuoteOrAnInvoice() throws {
        let model = try UIFixture.model()
        var beeps = 0
        model.beep = { beeps += 1 }
        #expect(!model.canExportPDF)
        // The menu item is greyed out then; called anyway, it beeps and explains nothing.
        model.exportPDF()
        #expect(model.pendingExport == nil)
        #expect(model.message == nil)
        #expect(beeps == 1)
        model.newQuote()
        #expect(model.canExportPDF)
        model.exportPDF()
        let export = try #require(model.pendingExport)
        #expect(export.fileName == "Q-0001.pdf")
        #expect(export.data.starts(with: Data("%PDF".utf8)))
    }

    @Test func theSampleQuoteUsesTheBrand() throws {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        let model = try UIFixture.model(library)
        let content = model.sampleContent()
        #expect(content.fromName == "Sample Studio")
        #expect(model.pdf(content).starts(with: Data("%PDF".utf8)))
    }

    @Test func commandsWaitWhileAMessageIsShowing() throws {
        let model = try UIFixture.model()
        var beeps = 0
        model.beep = { beeps += 1 }
        var ran = 0

        model.whenFree { ran += 1 }
        #expect(ran == 1)
        #expect(beeps == 0)

        model.show(title: "Careful", text: "Read this first.")
        model.whenFree { ran += 1 }
        #expect(ran == 1)
        #expect(beeps == 1)
        #expect(model.message?.title == "Careful")

        model.respond(try #require(model.message?.choices.first))
        model.whenFree { ran += 1 }
        #expect(ran == 2)
        #expect(beeps == 1)
    }

    /// The save panel is modal too: a menu command behind it would change what it's saving.
    @Test func commandsWaitWhileTheSavePanelIsOpen() throws {
        let model = try UIFixture.model()
        var beeps = 0
        model.beep = { beeps += 1 }
        var ran = 0

        model.pendingExport = FileExport(data: Data("%PDF".utf8), fileName: "Q-0001.pdf")
        model.whenFree { ran += 1 }
        #expect(ran == 0)
        #expect(beeps == 1)

        model.finishExport(.failure(CocoaError(.userCancelled)))
        model.whenFree { ran += 1 }
        #expect(ran == 1)
        #expect(beeps == 1)
    }

    /// The open panel is modal too, like the save panel.
    @Test func commandsWaitWhileTheOpenPanelIsUp() throws {
        let model = try UIFixture.model()
        var beeps = 0
        model.beep = { beeps += 1 }
        var ran = 0

        model.choosingFile = .returnedQuote
        model.whenFree { ran += 1 }
        #expect(ran == 0)
        #expect(beeps == 1)

        model.choosingFile = nil
        model.whenFree { ran += 1 }
        #expect(ran == 1)
        #expect(beeps == 1)
    }

    /// The toolbar, the section tree and the section behind a modal state are disabled by `isBusy`,
    /// and `whenFree` waits on the same four conditions, so a click can't do what a menu command can't.
    @Test func theWindowIsBusyWhileAnyModalStateIsUp() throws {
        let model = try UIFixture.model()
        #expect(!model.isBusy)

        model.show(title: "Careful", text: "Read this first.")
        #expect(model.isBusy)
        model.message = nil
        #expect(!model.isBusy)

        model.dialog = .taxExport
        #expect(model.isBusy)
        model.dialog = nil
        #expect(!model.isBusy)

        model.pendingExport = FileExport(data: Data("%PDF".utf8), fileName: "Q-0001.pdf")
        #expect(model.isBusy)
        model.finishExport(.failure(CocoaError(.userCancelled)))
        #expect(!model.isBusy)

        model.choosingFile = .returnedQuote
        #expect(model.isBusy)
        model.choosingFile = nil
        #expect(!model.isBusy)

        // `whenFree` is the same test.
        var beeps = 0
        model.beep = { beeps += 1 }
        for raise in [{ model.choosingFile = .legacyBackup }, { model.pendingExport = FileExport(data: Data(), fileName: "x.pdf") }] as [() -> Void] {
            raise()
            model.whenFree {}
            #expect(model.isBusy)
            model.choosingFile = nil
            model.pendingExport = nil
        }
        #expect(beeps == 2)
    }

    /// `QP_LIBRARY_FOLDER` points the app at a demo library; its mailed copies go beside it, never
    /// into ~/Documents. (Only URLs are worked out here; no folder is touched.)
    @Test func aDemoLibraryKeepsItsSentCopiesBesideIt() {
        let demo = AppFolders(environment: ["QP_LIBRARY_FOLDER": "/tmp/qp-demo"])
        #expect(demo.library == URL(fileURLWithPath: "/tmp/qp-demo", isDirectory: true))
        #expect(demo.sent == URL(fileURLWithPath: "/tmp/qp-demo", isDirectory: true).appendingPathComponent("Sent", isDirectory: true))
        let real = AppFolders(environment: [:])
        #expect(real.library == LibraryStore.defaultFolder)
        #expect(real.sent == SentArchive.defaultFolder)
    }

    @Test func choosingQuotesAgainGoesBackToTheList() throws {
        let model = try UIFixture.model()
        model.newQuote()
        #expect(model.section == .quotes)
        #expect(model.openQuoteID != nil)

        // Coming back from another section shows the quote that was open.
        model.go(to: .invoices)
        model.go(to: .quotes)
        #expect(model.openQuoteID != nil)

        // Choosing Quotes while already there goes back to the list.
        model.go(to: .quotes)
        #expect(model.section == .quotes)
        #expect(model.openQuoteID == nil)
    }

    @Test func cancellingTheSavePanelIsNotAnError() throws {
        let model = try UIFixture.model()
        let export = FileExport(data: Data("%PDF".utf8), fileName: "Q-0001.pdf")

        model.pendingExport = export
        model.finishExport(.failure(CocoaError(.userCancelled)))
        #expect(model.message == nil)
        #expect(model.pendingExport == nil)

        model.pendingExport = export
        model.finishExport(.failure(CocoaError(.fileWriteOutOfSpace)))
        #expect(model.message?.title == "Couldn't save the PDF")
        #expect(model.pendingExport == nil)

        model.message = nil
        model.pendingExport = export
        model.finishExport(.success(URL(fileURLWithPath: "/tmp/Q-0001.pdf")))
        #expect(model.message == nil)
        #expect(model.pendingExport == nil)
    }

    @Test func sectionsAreInSidebarOrderWithShortcutsOneToSix() {
        #expect(AppSection.allCases.map(\.title) == ["Dashboard", "Quotes", "Invoices", "Clients", "Activity", "Brand"])
        #expect(AppSection.allCases.map(\.shortcut) == ["1", "2", "3", "4", "5", "6"])
    }
}
