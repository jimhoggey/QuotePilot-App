import Foundation

// Every error the app can show, in a sentence that says what happened and what to do.

extension LibraryError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .notFound:
            return "That item no longer exists."
        case .notDraft:
            return "Only drafts can be deleted. A sent invoice can be voided instead, and a sent quote stays on record."
        case .notSent:
            return "This is still a draft, so it hasn't gone to the client. Send it first, or delete the draft instead."
        case .notAccepted:
            return "This quote hasn't been accepted yet."
        case .nothingAccepted:
            return "The client didn't accept any lines, so there's nothing to invoice."
        case .nothingLeftToInvoice:
            return "Everything on this quote has already been invoiced."
        case .alreadyInvoiced:
            return "This quote already has invoices, so its client, what the client accepted and what's billed are locked. Void its invoices first to change them."
        case .isVoid:
            return "This invoice is void."
        case .hasPayments:
            return "This invoice has payments recorded. Remove them before voiding it."
        case .deductedByFinal(let final):
            return "The final invoice \(final) subtracts this deposit. Void or delete \(final) first."
        case .unknownLineCodes(let codes):
            return "This quote has no \(lineList(codes))."
        case .notEditable:
            return "This invoice has been sent, so it can't be changed. Void it and draft a new one instead."
        case .noPayments:
            return "There are no payments on this invoice yet, so there's nothing to give a receipt for."
        case .paymentNotPositive:
            return "A payment has to be more than $0.00."
        case .paymentMoreThanOwing(let owing):
            return "That's more than the \(owing.formatted()) still owing on this invoice."
        case .clientInUse(let name):
            let who = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "This client" : name
            return "\(who) has quotes or invoices, so it can't be deleted."
        case .depositStillDeducted(let final):
            return "\(final) deducts this deposit. Delete \(final) first."
        case .quoteHasInvoices(let quote, let invoices):
            return "\(quote) has invoices (\(invoices.joined(separator: ", "))), so they have to be deleted with it."
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
        case .backupHasProblems(let problems):
            return Library.describe(problems, opening: "That backup holds numbers Quote Pilot can't work with, so it wasn't restored.")
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
