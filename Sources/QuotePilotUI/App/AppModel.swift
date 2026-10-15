import AppKit
import CoreText
import Foundation
import Observation
import QuotePilotCore
import QuotePilotPDF
import SwiftUI

/// A PDF waiting for the save panel.
public struct PDFExport {
    public var data: Data
    public var fileName: String
}

/// The app's state, and the only way the screens change the library. Every change is made to a
/// copy and saved; the app keeps it only once the save has worked.
@MainActor
@Observable
public final class AppModel {
    public enum LoadState: Equatable {
        case ready
        /// The library file can't be read. Nothing is saved until a backup is restored.
        case unreadable(reason: String)
    }

    public let store: LibraryStore
    public private(set) var library: Library
    public private(set) var loadState: LoadState
    public private(set) var lastSaved: Date?

    public var section: AppSection = .dashboard
    public var selectedQuoteID: UUID?
    /// The quote open in the editor; nil shows the quote list.
    public var openQuoteID: UUID?
    public var selectedInvoiceID: UUID?
    public var selectedClientID: UUID?
    public var message: MessageBox?
    public var pendingExport: PDFExport?

    private let now: () -> Date
    /// What `whenFree` does when a message box is up. Tests swap it for a counter.
    @ObservationIgnored var beep: () -> Void = { NSSound.beep() }
    @ObservationIgnored private var lastBackupDay: Day?

    public init(store: LibraryStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        var loadedExisting = false
        switch store.load() {
        case .loaded(let library):
            self.library = library
            loadState = .ready
            loadedExisting = true
        case .fresh(let library):
            self.library = library
            loadState = .ready
        case .unreadable(let reason):
            library = Library()
            loadState = .unreadable(reason: reason)
        }
        if loadedExisting { backUpIfDue() }
    }

    // MARK: Figures

    public var today: Day { Day(now()) }
    public var dashboard: Dashboard { Dashboard(library: library, today: today) }
    public var currencyCode: String { library.brand.currencyCode }

    public func money(_ amount: Money) -> String {
        amount.formatted(currencyCode: currencyCode)
    }

    // MARK: The change path

    /// Applies `edit` to a copy of the library and saves the copy; only then does the app keep it.
    /// When the edit or the save fails, nothing changes and a message box says why.
    @discardableResult
    public func change(_ failureTitle: String, _ edit: (inout Library) throws -> Void) -> Bool {
        guard loadState == .ready else {
            show(LibraryStore.StoreError.wouldOverwriteUnreadableLibrary, title: failureTitle)
            return false
        }
        var copy = library
        do {
            try edit(&copy)
            try store.save(copy)
        } catch {
            show(error, title: failureTitle)
            return false
        }
        library = copy
        lastSaved = now()
        backUpIfDue()
        return true
    }

    /// Today's backup, tried once a day.
    private func backUpIfDue() {
        let day = today
        guard lastBackupDay != day else { return }
        lastBackupDay = day
        do {
            try store.backUpIfDue(today: day)
        } catch {
            show(error, title: "Couldn't make today's backup")
        }
    }

    // MARK: Message boxes

    public func show(_ error: Error, title: String) {
        message = MessageBox(kind: .warning, title: title, text: error.localizedDescription)
    }

    public func show(title: String, text: String, kind: MessageBox.Kind = .info) {
        message = MessageBox(kind: kind, title: title, text: text)
    }

    /// Asks before something that can't be undone. Cancel is the default button.
    public func confirm(title: String, text: String, confirm: String, action: @escaping () -> Void) {
        message = MessageBox(kind: .question, title: title, text: text, choices: [
            MessageBox.Choice(confirm, action: action),
            MessageBox.Choice("Cancel", isDefault: true, isCancel: true),
        ])
    }

    public func respond(_ choice: MessageBox.Choice) {
        message = nil
        choice.action()
    }

    /// Runs `action` only when no message box is up, and beeps otherwise. A message box is modal to
    /// the keyboard and the menus as well as the mouse, as in Windows 95: every menu command goes
    /// through here, so a second command can't replace an error that hasn't been read.
    public func whenFree(_ action: () -> Void) {
        guard message == nil else {
            beep()
            return
        }
        action()
    }

    /// Called when the save panel closes. Cancelling it is not an error.
    public func finishExport(_ result: Result<URL, Error>) {
        if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
            show(error, title: "Couldn't save the PDF")
        }
        pendingExport = nil
    }

    // MARK: Going places

    /// Shows a section. Choosing Quotes while already on Quotes goes back to the list from the
    /// editor; the tree, its arrow keys and the Go menu all come through here.
    public func go(to section: AppSection) {
        if section == .quotes, self.section == .quotes { openQuoteID = nil }
        self.section = section
    }

    public func openQuote(_ id: UUID) {
        section = .quotes
        selectedQuoteID = id
        openQuoteID = id
    }

    public func openInvoice(_ id: UUID) {
        section = .invoices
        selectedInvoiceID = id
    }

    // MARK: Quotes

    public func newQuote(for clientID: UUID? = nil) {
        var created: UUID?
        // Open the new quote only when it was saved and kept: a failed save leaves nothing to open.
        guard change("Couldn't start a new quote", { library in
            created = library.newQuote(on: today, clientID: clientID).id
        }), let created else { return }
        openQuote(created)
    }

    public func updateQuote(_ quote: Quote) {
        change("Couldn't save \(quote.number)") { try $0.update(quote) }
    }

    /// The editor's view of a quote: it reads the stored quote and writes through `updateQuote`, so
    /// a refused edit shows the stored value again.
    public func quoteBinding(_ id: UUID) -> Binding<Quote> {
        Binding(
            get: { self.library.quote(id) ?? Quote(id: id, number: "", issued: self.today, validUntil: self.today) },
            set: { self.updateQuote($0) })
    }

    public func duplicateQuote(_ id: UUID) {
        var created: UUID?
        guard change("Couldn't duplicate the quote", { library in
            created = try library.duplicateQuote(id, on: today).id
        }), let created else { return }
        openQuote(created)
    }

    public func deleteDraftQuote(_ id: UUID) {
        guard let quote = library.quote(id) else { return }
        guard quote.stage == .draft else {
            show(title: "Can't Delete", text: "Only draft quotes can be deleted. \(quote.number) has been sent.", kind: .warning)
            return
        }
        confirm(title: "Delete Draft", text: "Delete draft quote \(quote.number)? Its number won't be used again.",
                confirm: "Delete") {
            guard self.change("Couldn't delete \(quote.number)", { try $0.deleteDraft(quote: id) }) else { return }
            if self.openQuoteID == id { self.openQuoteID = nil }
            if self.selectedQuoteID == id { self.selectedQuoteID = nil }
        }
    }

    // MARK: Clients

    public func newClient() {
        let client = Client(name: "New client")
        guard change("Couldn't add a client", { $0.addClient(client) }) else { return }
        section = .clients
        selectedClientID = client.id
    }

    public func updateClient(_ client: Client) {
        change("Couldn't save \(client.name)") { library in
            guard let index = library.clients.firstIndex(where: { $0.id == client.id }) else {
                throw LibraryError.notFound
            }
            library.clients[index] = client
        }
    }

    public func clientBinding(_ id: UUID) -> Binding<Client> {
        Binding(get: { self.library.client(id) ?? Client(id: id, name: "") }, set: { self.updateClient($0) })
    }

    // MARK: Brand

    public func updateBrand(_ brand: Brand) {
        change("Couldn't save the brand") { $0.brand = brand }
    }

    public var brandBinding: Binding<Brand> {
        Binding(get: { self.library.brand }, set: { self.updateBrand($0) })
    }

    public var logoURL: URL? {
        library.brand.logoFile.map { store.assetsFolder.appendingPathComponent($0) }
    }

    /// The heading font's name as people know it ("Avenir Next Demi Bold"), or nil.
    public var headingFontName: String? {
        guard let name = library.brand.headingFontFile,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(
                  store.assetsFolder.appendingPathComponent(name) as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first
        else { return nil }
        return CTFontDescriptorCopyAttribute(first, kCTFontDisplayNameAttribute) as? String
    }

    /// Copies a PNG, JPG or PDF into the library's Assets folder and makes it the logo.
    public func importLogo(from url: URL) {
        guard Logo(url: url) != nil else {
            show(title: "Not an Image",
                 text: "\(url.lastPathComponent) isn't an image Quote Pilot can use. Choose a PNG, JPG or PDF.",
                 kind: .warning)
            return
        }
        guard let name = copyAsset(url, prefix: "logo") else { return }
        change("Couldn't use that logo") { $0.brand.logoFile = name }
    }

    /// Copies a TTF or OTF into the Assets folder and makes it the heading font.
    public func importHeadingFont(from url: URL) {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        guard !descriptors.isEmpty else {
            show(title: "Not a Font",
                 text: "\(url.lastPathComponent) isn't a font Quote Pilot can use. Choose a TTF or OTF file.",
                 kind: .warning)
            return
        }
        guard let name = copyAsset(url, prefix: "heading-font") else { return }
        change("Couldn't use that font") { $0.brand.headingFontFile = name }
    }

    public func removeLogo() {
        change("Couldn't remove the logo") { $0.brand.logoFile = nil }
    }

    public func removeHeadingFont() {
        change("Couldn't remove the heading font") { $0.brand.headingFontFile = nil }
    }

    /// Copies a file into Assets under a fresh name ("logo-1A2B3C4D.png"), so a document already
    /// showing the old file never meets a half-copied one. Returns the new name.
    private func copyAsset(_ url: URL, prefix: String) -> String? {
        let name = "\(prefix)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.lowercased())"
        do {
            try FileManager.default.createDirectory(at: store.assetsFolder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: store.assetsFolder.appendingPathComponent(name))
            return name
        } catch {
            show(error, title: "Couldn't copy \(url.lastPathComponent)")
            return nil
        }
    }

    // MARK: Documents

    public func quoteContent(_ id: UUID) -> DocumentContent? {
        guard let quote = library.quote(id) else { return nil }
        return .quote(quote, client: library.client(quote.clientID), brand: library.brand)
    }

    public func invoiceContent(_ id: UUID) -> DocumentContent? {
        guard let invoice = library.invoice(id) else { return nil }
        let quoteNumber = invoice.quoteID.flatMap { library.quote($0)?.number }
        return .invoice(invoice, client: library.client(invoice.clientID), brand: library.brand, quoteNumber: quoteNumber)
    }

    /// A made-up quote in the current brand, for the Brand screen's preview.
    public func sampleContent() -> DocumentContent {
        let brand = library.brand
        var quote = Quote(number: "Q-0000", title: "Sample job", issued: today,
                          validUntil: today.adding(days: brand.quoteValidDays), taxed: brand.gstRegistered,
                          summary: "What's included:\n- A planning meeting\n- Design and build", terms: brand.quoteTerms)
        quote.addLine(LineItem(title: "Planning meeting", quantity: 2, unit: .hours, rate: Money(dollars: 90)))
        quote.addLine(LineItem(title: "Design", rate: Money(dollars: 600)))
        quote.addLine(LineItem(title: "Build", rate: Money(dollars: 1200)))
        let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example", email: "sam@example.com")
        return .quote(quote, client: client, brand: brand)
    }

    public func pdf(_ content: DocumentContent) -> Data {
        DocumentRenderer.render(content, style: PDFStyle(brand: library.brand, assetsFolder: store.assetsFolder))
    }

    /// What ⌘P saves: the open or selected quote on Quotes, the selected invoice on Invoices.
    public var exportableContent: DocumentContent? {
        switch section {
        case .quotes: return (openQuoteID ?? selectedQuoteID).flatMap(quoteContent)
        case .invoices: return selectedInvoiceID.flatMap(invoiceContent)
        default: return nil
        }
    }

    public var canExportPDF: Bool { exportableContent != nil }

    public func exportPDF() {
        guard let content = exportableContent else {
            show(title: "Save PDF", text: "Open or select a quote or an invoice first.")
            return
        }
        pendingExport = PDFExport(data: pdf(content), fileName: content.fileName)
    }

    // MARK: Backups

    public var latestBackup: URL? { store.backups().first }

    /// Puts the newest backup back. The file it replaces is kept beside it by `LibraryStore`.
    public func restoreLatestBackup() {
        guard let backup = latestBackup else {
            show(title: "No Backup", text: "There's no backup to restore yet.", kind: .warning)
            return
        }
        do {
            library = try store.restore(from: backup, now: now())
        } catch {
            show(error, title: "Couldn't restore the backup")
            return
        }
        loadState = .ready
        lastSaved = now()
        // The backup is back whatever happens next. When only the Activity note fails, its message
        // box stays up (with a line saying the restore worked) instead of being replaced.
        guard change("Couldn't note the restore in Activity", { $0.log("Restored the backup \(backup.lastPathComponent)") }) else {
            message?.text += " The backup itself was restored."
            return
        }
        show(title: "Backup Restored",
             text: "Quote Pilot restored \(backup.lastPathComponent). The file it couldn't read is kept in the same folder, named library-replaced-….json.")
    }
}
