import AppKit
import CoreText
import Foundation
import Observation
import QuotePilotCore
import QuotePilotPDF
import SwiftUI
import UniformTypeIdentifiers

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

/// A file waiting for the save panel: a PDF, the tax-time CSV, or a copy of the library.
public struct FileExport {
    public var data: Data
    public var fileName: String
    public var contentType: UTType

    public init(data: Data, fileName: String, contentType: UTType = .pdf) {
        self.data = data
        self.fileName = fileName
        self.contentType = contentType
    }

    /// What a failed save calls it: "Couldn't save the PDF".
    var kindName: String {
        if contentType == .pdf { return "PDF" }
        if contentType == .commaSeparatedText { return "CSV" }
        if contentType == .json { return "backup" }
        return "file"
    }
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
    public var openQuoteID: UUID? {
        // Back at the list, a quote that fell outside the search isn't left selected there.
        didSet { if openQuoteID == nil { dropHiddenSelections() } }
    }
    public var selectedInvoiceID: UUID?
    /// The invoice open in the editor; nil shows the invoice list.
    public var openInvoiceID: UUID? {
        didSet { if openInvoiceID == nil { dropHiddenSelections() } }
    }
    public var selectedClientID: UUID?
    /// Each list's search text, kept while you move between sections. A search that hides the
    /// selected quote, invoice or client clears that selection (`dropHiddenSelections`).
    public var findText: [AppSection: String] = [:] {
        didSet { dropHiddenSelections() }
    }
    /// Bumped by ⌘F; the current list's Find field takes the cursor.
    public var findRequest = 0
    public var message: MessageBox?
    /// What the last action did, for the status bar (see `note(_:)`).
    public private(set) var statusNote: StatusNote?
    public var pendingExport: FileExport? {
        didSet { if let pendingExport { lastExport = pendingExport } }
    }
    /// The last file the save panel was asked for, kept for `finishExport`: SwiftUI may clear
    /// `pendingExport` as the panel closes, before it reports.
    @ObservationIgnored var lastExport: FileExport?
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
        if let error = tryChange(edit) {
            show(error, title: failureTitle)
            return false
        }
        return true
    }

    /// `change` without its message box: nil when the change was made and saved, otherwise why not,
    /// with nothing changed. For a step that already has its own place on screen to say so (the
    /// import report's notes), so one action never shows two.
    func tryChange(_ edit: (inout Library) throws -> Void) -> Error? {
        guard loadState == .ready else { return LibraryStore.StoreError.wouldOverwriteUnreadableLibrary }
        var copy = library
        do {
            try edit(&copy)
            try store.save(copy)
        } catch {
            return error
        }
        library = copy
        lastSaved = now()
        // The change may have taken the selected quote or invoice out of the list's search.
        dropHiddenSelections(afterChange: true)
        backUpIfDue()
        return nil
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

    /// Whether a message box, dialog, save panel or open panel is up. The window behind is modal to
    /// the keyboard and the menus as well as the mouse, as in Windows 95: the toolbar, the section
    /// tree and the section are disabled while this is true, and `whenFree` waits on it. The save and
    /// open panels count as well: a command behind one could change what it's saving or opening for.
    public var isBusy: Bool {
        message != nil || dialog != nil || pendingExport != nil || choosingFile != nil
    }

    /// Runs `action` only when nothing is `isBusy`, and beeps otherwise. Every menu command goes
    /// through here, so a second command can't replace an error that hasn't been read.
    public func whenFree(_ action: () -> Void) {
        guard !isBusy else {
            beep()
            return
        }
        action()
    }

    /// Called when the save panel closes. Cancelling it is not an error.
    public func finishExport(_ result: Result<URL, Error>) {
        if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
            show(error, title: "Couldn't save the \((pendingExport ?? lastExport)?.kindName ?? "file")")
        }
        pendingExport = nil
        lastExport = nil
    }

    // MARK: Find

    /// Whether a Find field is on screen: the Quotes, Invoices, Clients and Activity lists have one;
    /// the Dashboard, Brand and an open editor don't.
    public var showsFindField: Bool {
        guard loadState == .ready else { return false }
        switch section {
        case .quotes: return openQuoteID.flatMap { library.quote($0) } == nil
        case .invoices: return editingInvoiceID == nil
        case .clients, .activity: return true
        case .dashboard, .brand: return false
        }
    }

    /// ⌘F: puts the cursor in the list's Find field, and beeps when there is none on screen.
    public func find() {
        guard showsFindField else { return beep() }
        findRequest += 1
    }

    /// A search that hides the selected quote, invoice or client clears that selection, so Open,
    /// Duplicate, Delete Draft, ⌘S and Save PDF never act on a row the list doesn't show. Run when a
    /// search changes, when an editor closes onto its list, and after every change that saved (a
    /// payment that makes an invoice Paid hides it from a "sent" search). A change leaves the selected
    /// client alone (`afterChange`): renaming them leaves their form open, where clearing it would
    /// close the form under the cursor on the keystroke that stops matching the search.
    private func dropHiddenSelections(afterChange: Bool = false) {
        if let id = selectedQuoteID, !QuoteListView.visibleRows(self).contains(where: { $0.id == id }) {
            selectedQuoteID = nil
        }
        if let id = selectedInvoiceID, !InvoicesView.visibleRows(self).contains(where: { $0.id == id }) {
            selectedInvoiceID = nil
        }
        if !afterChange, let id = selectedClientID, !ClientsView.visibleClients(self).contains(where: { $0.id == id }) {
            selectedClientID = nil
        }
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

    /// Saves the brand, with its day counts kept within 0 to 365 (beyond that a due date could land
    /// where a `Day` can't go) and its hourly rate within $0 to $10,000,000: the library would no
    /// longer open with numbers outside those.
    public func updateBrand(_ brand: Brand) {
        var brand = brand
        let days = Library.dayCountLimit
        brand.paymentDueDays = min(max(brand.paymentDueDays, days.lowerBound), days.upperBound)
        brand.quoteValidDays = min(max(brand.quoteValidDays, days.lowerBound), days.upperBound)
        brand.hourlyRate = brand.hourlyRate.map { Money(cents: min(max($0.cents, 0), Library.amountLimit.cents)) }
        change("Couldn't save the brand") { $0.brand = brand }
    }

    public var brandBinding: Binding<Brand> {
        Binding(get: { self.library.brand }, set: { self.updateBrand($0) })
    }

    public var logoURL: URL? {
        library.brand.logoFile.map { store.assetsFolder.appendingPathComponent($0) }
    }

    /// The heading font's file in Assets, or nil when there's none.
    public var headingFontURL: URL? {
        library.brand.headingFontFile.map { store.assetsFolder.appendingPathComponent($0) }
    }

    /// The heading font's name as people know it ("Georgia"; a font with several styles by its
    /// family, "Archivo", since the Style picker names the style), or nil.
    public var headingFontName: String? {
        headingFontURL.flatMap(FontFile.displayName(at:))
    }

    /// Puts a PNG, JPG, SVG or PDF into the library's Assets folder and makes it the logo. An SVG is
    /// turned into a one-page PDF on the way in (only the PDF is kept), so it stays sharp at any size.
    public func importLogo(from url: URL) {
        let name: String?
        do {
            name = try storeLogoQuietly(url)
        } catch {
            show(error, title: "Couldn't copy \(url.lastPathComponent)")
            return
        }
        guard let name else {
            show(title: "Not an Image",
                 text: "\(url.lastPathComponent) isn't an image Quote Pilot can use. Choose a PNG, JPG, SVG or PDF.",
                 kind: .warning)
            return
        }
        change("Couldn't use that logo") { $0.brand.logoFile = name }
    }

    /// Saves a logo file into Assets and returns its new name. Nil, with nothing saved, when the file
    /// isn't an image Quote Pilot can use. A PNG, JPG or PDF is copied as it is; an SVG is converted
    /// to a one-page PDF (`SVGLogo`) and saved as that, since the PDF logo path draws it as vectors.
    /// Throws when the image is fine but can't be saved.
    func storeLogoQuietly(_ url: URL) throws -> String? {
        if SVGLogo.isSVG(url) {
            guard let pdf = SVGLogo.pdfData(from: url) else { return nil }
            return try writeAssetQuietly(pdf, prefix: "logo", pathExtension: "pdf")
        }
        guard Logo(url: url) != nil else { return nil }
        return try copyAssetQuietly(url, prefix: "logo")
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
        // A style belongs to the font it was chosen from, so a new font starts on its own default.
        change("Couldn't use that font") { $0.brand.headingFontFile = name; $0.brand.headingFontStyle = nil }
    }

    public func removeLogo() {
        change("Couldn't remove the logo") { $0.brand.logoFile = nil }
    }

    public func removeHeadingFont() {
        change("Couldn't remove the heading font") { $0.brand.headingFontFile = nil; $0.brand.headingFontStyle = nil }
    }

    /// Copies a file into Assets under a fresh name ("logo-1A2B3C4D.png"), so a document already
    /// showing the old file never meets a half-copied one. Returns the new name.
    func copyAsset(_ url: URL, prefix: String) -> String? {
        do {
            return try copyAssetQuietly(url, prefix: prefix)
        } catch {
            show(error, title: "Couldn't copy \(url.lastPathComponent)")
            return nil
        }
    }

    /// `copyAsset` that throws instead of showing a message box.
    func copyAssetQuietly(_ url: URL, prefix: String) throws -> String {
        let name = "\(prefix)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.lowercased())"
        try FileManager.default.createDirectory(at: store.assetsFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: store.assetsFolder.appendingPathComponent(name))
        return name
    }

    /// Saves data into Assets under a fresh name ("logo-1A2B3C4D.pdf"), the way `copyAssetQuietly`
    /// does a file. Returns the new name.
    func writeAssetQuietly(_ data: Data, prefix: String, pathExtension: String) throws -> String {
        let name = "\(prefix)-\(UUID().uuidString.prefix(8)).\(pathExtension)"
        try FileManager.default.createDirectory(at: store.assetsFolder, withIntermediateDirectories: true)
        try data.write(to: store.assetsFolder.appendingPathComponent(name), options: .atomic)
        return name
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

    /// Whether there is something for Save PDF… to save; the menu item and the toolbar button are
    /// greyed out when there isn't.
    public var canExportPDF: Bool { exportableContent != nil }

    /// Opens the save panel for the PDF. With nothing to save it only beeps: the menu item and the
    /// toolbar button are greyed out then, so this is the fallback.
    public func exportPDF() {
        guard let content = exportableContent else { return beep() }
        pendingExport = FileExport(data: pdf(content), fileName: content.fileName)
    }

    // MARK: Backups

    public var latestBackup: URL? { store.backups().first }

    /// "library-2026-10-15.json" → "15 Oct 2026", as the restore list shows it; any other name as it is.
    static func backupLabel(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("library-"), let day = Day(iso: String(name.dropFirst("library-".count))) else { return name }
        return day.short
    }

    /// Puts the newest backup back (the unreadable-library screen's button, and the Library Missing
    /// prompt's).
    public func restoreLatestBackup() {
        guard let backup = latestBackup else {
            show(title: "No Backup", text: "There's no backup to restore yet.", kind: .warning)
            return
        }
        restore(from: backup)
    }

    /// Replaces the library with a backup, at once: the Restore dialog says the library it replaces is
    /// kept beside it (`LibraryStore` copies it to library-replaced-….json). A restore that worked
    /// shows no box: the dialog closes and the status bar says which backup came back. A restore that
    /// failed shows its box and leaves the dialog up, to choose another.
    ///
    /// Numbers are never reused, so a restore keeps every number the library it replaces had issued,
    /// and every number in a mailed PDF's file name in the sent folder (which still counts when the
    /// replaced library couldn't be read), alongside the backup's own. They're saved in the same
    /// change as the Activity entry, and held in memory at once so none can be issued in between.
    public func restore(from backup: URL) {
        let issued = library.usedNumbers + library.documentNumbers + SentArchive.numbers(in: sentFolder)
        do {
            library = try store.restore(from: backup, now: now())
        } catch {
            show(error, title: "Couldn't restore the backup")
            return
        }
        library.keepUsed(issued)
        loadState = .ready
        lastSaved = now()
        openQuoteID = nil
        openInvoiceID = nil
        dialog = nil
        // The backup is back whatever happens next. When the Activity note (or today's backup) then
        // fails, that message box stays up (with a line saying the restore worked) instead of being
        // replaced by the note.
        guard change("Couldn't note the restore in Activity", {
                  $0.keepUsed(issued)
                  $0.log("Restored the \(Self.backupLabel(backup)) backup")
              }),
              message == nil
        else {
            message?.text += " The backup itself was restored."
            return
        }
        note("Restored the \(Self.backupLabel(backup)) backup")
    }
}
