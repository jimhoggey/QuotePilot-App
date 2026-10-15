import AppKit
import CoreText
import Foundation
import Observation
import QuotePilotCore
import QuotePilotPDF
import SwiftUI

/// Where the app keeps the library and the copies of mailed PDFs.
public struct AppFolders: Equatable {
    public var library: URL
    public var sent: URL

    /// The real folders, or, when `QP_LIBRARY_FOLDER` points at another library (such as the one
    /// `qp demo` writes), that folder with a Sent folder inside it, so a demo never writes to
    /// ~/Documents.
    public init(environment: [String: String]) {
        if let path = environment["QP_LIBRARY_FOLDER"] {
            library = URL(fileURLWithPath: path, isDirectory: true)
            sent = library.appendingPathComponent("Sent", isDirectory: true)
        } else {
            library = LibraryStore.defaultFolder
            sent = SentArchive.defaultFolder
        }
    }
}

/// A PDF waiting for the save panel.
public struct PDFExport {
    public var data: Data
    public var fileName: String
}

/// A short line for the status bar's last cell, such as "Recorded $135.00 for INV-0003": what the
/// last action did, where no message box is wanted. It shows until the next change saves.
public struct StatusNote: Equatable {
    public let text: String
    public let at: Date

    public init(text: String, at: Date) {
        self.text = text
        self.at = at
    }
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

        /// The file was saved by a newer Quote Pilot. Restoring a backup would roll it back, so the
        /// unreadable screen makes Quit the default instead.
        public var isFromNewerVersion: Bool {
            guard case .unreadable(let reason) = self else { return false }
            return reason.hasPrefix(LibraryStore.newerVersionReason)
        }
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
    /// The invoice open in the editor; nil shows the invoice list.
    public var openInvoiceID: UUID?
    public var selectedClientID: UUID?
    /// Each list's search text, kept while you move between sections.
    public var findText: [AppSection: String] = [:]
    /// Bumped by ⌘F; the current list's Find field takes the cursor.
    public var findRequest = 0
    public var message: MessageBox?
    /// What the last action did, for the status bar (see `note(_:)`).
    public private(set) var statusNote: StatusNote?
    public var pendingExport: PDFExport?
    /// The dialog panel showing over the window, if any (the email prompt, the acceptance review…).
    public var dialog: Dialog?
    /// What the open panel is choosing a file for, while it's showing.
    public var choosingFile: FileChoice? {
        didSet { if let choosingFile { lastFileChoice = choosingFile } }
    }
    /// The last thing the open panel was asked for, kept for `fileChosen`: SwiftUI may clear
    /// `choosingFile` as the panel closes, before it hands over the file.
    @ObservationIgnored var lastFileChoice: FileChoice?
    /// Opens Mail drafts; tests use a fake.
    @ObservationIgnored public let mail: any MailComposer
    /// Where copies of mailed PDFs go: `~/Documents/Quote Pilot`, or a temporary folder in tests.
    @ObservationIgnored public let sentFolder: URL

    let now: () -> Date
    /// What `whenFree` does when a message box is up. Tests swap it for a counter.
    @ObservationIgnored var beep: () -> Void = { NSSound.beep() }
    @ObservationIgnored private var lastBackupDay: Day?

    public init(store: LibraryStore, now: @escaping () -> Date = Date.init,
                mail: any MailComposer = SystemMailComposer(), sentFolder: URL = SentArchive.defaultFolder) {
        self.store = store
        self.now = now
        self.mail = mail
        self.sentFolder = sentFolder
        var loadedExisting = false
        var startedFresh = false
        switch store.load() {
        case .loaded(let library):
            self.library = library
            loadState = .ready
            loadedExisting = true
        case .fresh(let library):
            self.library = library
            loadState = .ready
            startedFresh = true
        case .unreadable(let reason):
            library = Library()
            loadState = .unreadable(reason: reason)
        }
        if loadedExisting { backUpIfDue() }
        if startedFresh { askToRestoreMissingLibrary() }
    }

    /// No library file, but backups: the file was moved or deleted. Starting empty without a word
    /// would save an empty library at the first change and, a month of daily backups later, prune
    /// the good ones, so ask first.
    private func askToRestoreMissingLibrary() {
        guard let backup = latestBackup else { return }
        message = MessageBox(
            kind: .question, title: "Library Missing",
            text: "Quote Pilot can't find your library file, but there's a backup from \(Self.backupLabel(backup)). Restore it?",
            choices: [
                MessageBox.Choice("Restore", isDefault: true) { [weak self] in self?.restoreLatestBackup() },
                MessageBox.Choice("Start Empty", isCancel: true),
            ])
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

    /// Says what just happened in the status bar's last cell, in a few words (the cell is about 300 pt
    /// wide). The next change that saves replaces it with the time of that save, so call it after
    /// the change that it describes.
    public func note(_ text: String) {
        statusNote = StatusNote(text: text, at: now())
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

    /// Runs `action` only when no message box, dialog, save panel or open panel is up, and beeps
    /// otherwise. A message box or dialog is modal to the keyboard and the menus as well as the mouse,
    /// as in Windows 95: every menu command goes through here, so a second command can't replace an
    /// error that hasn't been read.
    public func whenFree(_ action: () -> Void) {
        // The save and open panels are modal as well: a command behind one could change what it's
        // saving or opening for.
        guard message == nil, dialog == nil, pendingExport == nil, choosingFile == nil else {
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

    // MARK: Find

    /// ⌘F
    public func find() {
        findRequest += 1
    }

    public func findBinding(_ section: AppSection) -> Binding<String> {
        Binding(get: { self.findText[section, default: ""] }, set: { self.findText[section] = $0 })
    }

    // MARK: Going places

    /// Shows a section. Choosing Quotes (or Invoices) while already there goes back to the list from
    /// the editor; the tree, its arrow keys and the Go menu all come through here.
    public func go(to section: AppSection) {
        if section == .quotes, self.section == .quotes { openQuoteID = nil }
        if section == .invoices, self.section == .invoices { openInvoiceID = nil }
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
        openInvoiceID = id
    }

    /// Opens the quote or invoice with this number, as Activity's double-click does.
    public func openDocument(number: String) {
        if let quote = library.quote(number: number) {
            openQuote(quote.id)
        } else if let invoice = library.invoices.first(where: { $0.number.caseInsensitiveCompare(number) == .orderedSame }) {
            openInvoice(invoice.id)
        }
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

    /// Saves the brand, with its day counts kept within 0 to 365: beyond that a due date could land
    /// where a `Day` can't go, and the library would no longer open.
    public func updateBrand(_ brand: Brand) {
        var brand = brand
        let days = Library.dayCountLimit
        brand.paymentDueDays = min(max(brand.paymentDueDays, days.lowerBound), days.upperBound)
        brand.quoteValidDays = min(max(brand.quoteValidDays, days.lowerBound), days.upperBound)
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

    /// What ⌘P saves: the open or selected quote on Quotes, the open or selected invoice on Invoices.
    public var exportableContent: DocumentContent? {
        switch section {
        case .quotes: return (openQuoteID ?? selectedQuoteID).flatMap(quoteContent)
        case .invoices: return (editingInvoiceID ?? selectedInvoiceID).flatMap(invoiceContent)
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

    /// "library-2026-10-15.json" → "15 Oct 2026", as the restore list shows it; any other name as it is.
    static func backupLabel(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("library-"), let day = Day(iso: String(name.dropFirst("library-".count))) else { return name }
        return day.short
    }

    /// Puts the newest backup back. The file it replaces is kept beside it by `LibraryStore`.
    public func restoreLatestBackup() {
        guard let backup = latestBackup else {
            show(title: "No Backup", text: "There's no backup to restore yet.", kind: .warning)
            return
        }
        // When the library file is missing there's nothing to keep, and the message says no more.
        let replacing = FileManager.default.fileExists(atPath: store.libraryURL.path)
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
        var text = "Quote Pilot restored \(backup.lastPathComponent)."
        if replacing {
            text += " The file it couldn't read is kept in the same folder, named library-replaced-….json."
        }
        show(title: "Backup Restored", text: text)
    }
}
