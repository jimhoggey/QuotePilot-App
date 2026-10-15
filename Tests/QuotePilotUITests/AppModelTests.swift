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
        model.exportPDF()
        #expect(model.pendingExport == nil)
        #expect(model.message != nil)
        model.message = nil
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

    @Test func sectionsAreInSidebarOrderWithShortcutsOneToSix() {
        #expect(AppSection.allCases.map(\.title) == ["Dashboard", "Quotes", "Invoices", "Clients", "Activity", "Brand"])
        #expect(AppSection.allCases.map(\.shortcut) == ["1", "2", "3", "4", "5", "6"])
    }
}
