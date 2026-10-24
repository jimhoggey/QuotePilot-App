import Foundation
import QuotePilotCore
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    // MARK: Expenses

    /// Assets/Expenses: copies of the suppliers' quotes and invoices attached to expenses.
    public var expenseAttachmentsFolder: URL {
        store.assetsFolder.appendingPathComponent("Expenses", isDirectory: true)
    }

    /// Where an expense's attachment is kept, or nil when it has none.
    public func attachmentURL(_ expense: Expense) -> URL? {
        expense.attachment.map { store.assetsFolder.appendingPathComponent($0) }
    }

    /// The list's New Expense: a blank expense dated today, selected so its form shows.
    public func newExpense() {
        let expense = Expense(date: today)
        let time = now()
        guard change("Couldn't add an expense", { try $0.addExpense(expense, at: time) }) else { return }
        section = .expenses
        selectedExpenseID = expense.id
    }

    public func updateExpense(_ expense: Expense) {
        let time = now()
        change("Couldn't save the expense") { try $0.update(expense, at: time) }
    }

    /// The form's view of an expense: it reads the stored one and writes through `updateExpense`.
    public func expenseBinding(_ id: UUID) -> Binding<Expense> {
        Binding(get: { self.library.expense(id) ?? Expense(id: id, date: self.today) },
                set: { self.updateExpense($0) })
    }

    /// Delete Expense: asks once, then removes the selected expense. Its attachment stays in
    /// Assets/Expenses, as a replaced logo does.
    public func deleteSelectedExpense() {
        guard canEdit, let id = selectedExpenseID, let expense = library.expense(id) else { return beep() }
        let who = expense.supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        confirm(title: "Delete Expense",
                text: "Delete the expense\(who.isEmpty ? "" : " from \(who)") on \(expense.date.short)? This can't be undone.",
                confirm: "Delete") { [weak self] in
            guard let self else { return }
            let time = now()
            guard change("Couldn't delete the expense", { try $0.deleteExpense(id, at: time) }) else { return }
            if selectedExpenseID == id { selectedExpenseID = nil }
        }
    }

    /// Attach Quote or Invoice… (or a PDF dropped on the form): copies a PDF or picture into
    /// Assets/Expenses under a fresh name and attaches it, in place of any attachment before.
    public func attach(_ url: URL, toExpense id: UUID) {
        guard canEdit, var expense = library.expense(id) else { return beep() }
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        guard type?.conforms(to: .pdf) == true || type?.conforms(to: .image) == true else {
            return show(title: "Not a PDF or Picture",
                        text: "\(url.lastPathComponent) isn't a PDF or a picture. Choose the supplier's quote or invoice as a PDF, PNG or JPG.",
                        kind: .warning)
        }
        do {
            try FileManager.default.createDirectory(at: expenseAttachmentsFolder, withIntermediateDirectories: true)
            expense.attachment = try copyAssetQuietly(url, prefix: "Expenses/expense")
        } catch {
            return show(error, title: "Couldn't copy \(url.lastPathComponent)")
        }
        updateExpense(expense)
    }

    /// Open Attachment: the attached file in its own app (Preview, usually).
    public func openAttachment(_ id: UUID) {
        guard let expense = library.expense(id), let url = attachmentURL(expense) else { return beep() }
        openInFinder(url)
    }

    /// Remove Attachment: the expense no longer points at the file; the copy stays in Assets/Expenses.
    public func removeAttachment(_ id: UUID) {
        guard var expense = library.expense(id), expense.attachment != nil else { return beep() }
        expense.attachment = nil
        updateExpense(expense)
    }
}
