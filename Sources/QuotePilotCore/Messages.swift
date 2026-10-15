import Foundation

// Every error the app can show, in a sentence that says what happened and what to do.

extension LibraryError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .notFound:
            return "That item no longer exists."
        case .notDraft:
            return "Only drafts can be deleted. A sent invoice can be voided instead."
        case .notSent:
            return "Mark it as sent first."
        case .notAccepted:
            return "This quote hasn't been accepted yet."
        case .nothingAccepted:
            return "The client didn't accept any lines, so there's nothing to invoice."
        case .nothingLeftToInvoice:
            return "Everything on this quote has already been invoiced."
        case .alreadyInvoiced:
            return "This quote already has invoices, so its prices, lines and payment plan are locked. Void its invoices first to change them."
        case .isVoid:
            return "This invoice is void."
        case .hasPayments:
            return "This invoice has payments recorded. Remove them before voiding it."
        case .deductedByFinal(let final):
            return "The final invoice \(final) subtracts this deposit. Void or delete \(final) first."
        case .unknownLineCodes(let codes):
            return "This quote has no \(lineList(codes))."
        }
    }
}

extension LibraryStore.StoreError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .wouldOverwriteUnreadableLibrary:
            return "The library file can't be read, so Quote Pilot won't save over it. Restore a backup first."
        case .wouldWriteUnreadableLibrary:
            return "That change would have made the library unreadable, so it wasn't saved."
        case .backupFromNewerVersion(let format):
            return "That backup was made by a newer version of Quote Pilot (library format \(format)). Update Quote Pilot to restore it."
        }
    }
}

extension LegacyImportError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .notABackup:
            return "That file isn't a backup from Invoice Generator. Use its Saved documents → Back up to file button."
        }
    }
}
