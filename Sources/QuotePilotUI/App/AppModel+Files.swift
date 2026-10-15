import Foundation
import QuotePilotCore
import QuotePilotPDF
import UniformTypeIdentifiers

extension AppModel {
    // MARK: What the File menu can run

    /// Whether the library can be worked with. While it can't be read (`loadState` is unreadable) the
    /// File menu greys out Read Returned Quote…, Import from Invoice Generator… and Export Payments
    /// for Tax Time…, and the New commands: nothing they would make can be saved. Restore Backup… is
    /// the one command that stays on, since it is the way out (`canRestoreBackup`).
    public var libraryIsOpen: Bool { loadState == .ready }

    /// Whether Restore Backup… has a backup to offer. A save sets `lastSaved`, which is read first so
    /// the menu looks again when the first one makes the library's first backup.
    public var canRestoreBackup: Bool {
        _ = lastSaved
        return !store.backups().isEmpty
    }

    // MARK: Import from Invoice Generator

    /// Reads the old tool's backup file, adds what it holds that Quote Pilot doesn't have, and shows
    /// what came in and what is left to do by hand. A file that isn't a backup changes nothing.
    public func importLegacyBackup(at url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            return show(LegacyImportError.notABackup, title: "Can't Import That File")
        }
        var report: ImportReport?
        let saved = change("Can't Import That File") { library in
            report = try LegacyImport.importBackup(data, into: &library, today: today)
        }
        guard saved, var report else { return }
        if let logo = report.logoData, library.brand.logoFile == nil, let problem = useImportedLogo(logo) {
            report.notes.append("The old tool's logo \(problem). Add your logo on the Brand page.")
        }
        dialog = .importReport(report)
    }

    /// Saves the old tool's logo into Assets as the brand logo. Nil when it was saved. Otherwise what
    /// went wrong, to finish "The old tool's logo …": "couldn't be read" when it isn't a usable image,
    /// "couldn't be saved" when the image is fine but can't be stored. It shows no message box of its
    /// own either way: the import report is already up for it, and it carries a note saying the logo
    /// didn't come in. The old tool keeps a PNG, a JPG, or an SVG (which it doesn't shrink); an SVG
    /// goes through the same conversion to a PDF as one chosen on the Brand page.
    private func useImportedLogo(_ data: Data) -> String? {
        let unreadable = "couldn't be read"
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF]
        let ext: String
        if data.starts(with: png) {
            ext = "png"
        } else if data.starts(with: jpeg) {
            ext = "jpg"
        } else if SVGLogo.looksLikeSVG(data) {
            ext = "svg"
        } else {
            return unreadable
        }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("imported-logo-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (try? data.write(to: temporary)) != nil else { return unreadable }
        let stored: String?
        do {
            stored = try storeLogoQuietly(temporary)
        } catch {
            return "couldn't be saved"
        }
        guard let name = stored else { return unreadable }
        guard tryChange({ $0.brand.logoFile = name }) == nil else { return "couldn't be saved" }
        return nil
    }

    // MARK: Tax time

    /// Financial years with payments, plus this one, newest first.
    public var taxYears: [FinancialYear] {
        var years = Set(library.invoices.filter { $0.stage == .sent }.flatMap(\.payments)
            .map { FinancialYear(containing: $0.date) })
        years.insert(FinancialYear(containing: today))
        return years.sorted { $0.startYear > $1.startYear }
    }

    /// Closes the tax-time dialog and opens the save panel for that year's payments CSV.
    public func exportPayments(for year: FinancialYear) {
        dialog = nil
        let name = "Payments FY \(year.startYear)-\(String(format: "%02d", (year.startYear + 1) % 100)).csv"
        pendingExport = FileExport(data: Data(library.paymentsCSV(for: year).utf8), fileName: name,
                                   contentType: .commaSeparatedText)
    }

    // MARK: Back Up To…

    /// Whether Back Up To… has a library file to copy: the library is open, and a save has put its
    /// file on disk. The menu item is greyed out until then. A save sets `lastSaved`, which is read
    /// first so the menu looks again when the first one happens.
    public var canBackUp: Bool {
        guard loadState == .ready else { return false }
        return lastSaved != nil || FileManager.default.fileExists(atPath: store.libraryURL.path)
    }

    /// File → Back Up To…: a copy of the library file, saved wherever you choose. With no saved
    /// library to copy it only beeps; the menu item is greyed out then, so this is the fallback.
    public func exportBackupCopy() {
        guard canBackUp, let data = try? Data(contentsOf: store.libraryURL) else { return beep() }
        pendingExport = FileExport(data: data, fileName: "Quote Pilot backup \(today.iso).json", contentType: .json)
    }
}
