import AppKit
import Foundation
import QuotePilotCore
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import QuotePilotUI

/// The Expenses section: New Expense, the form's helpers, attachments and their routing, Delete.
/// Made-up suppliers; every folder is temporary.
@MainActor
@Suite struct ExpensesUITests {
    /// A file in a fresh temporary folder, standing in for something the user picked or dropped.
    func file(_ name: String, _ text: String = "%PDF-1.4 sample") throws -> URL {
        let folder = UIFixture.makeFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func modelWithExpense() throws -> (AppModel, UUID) {
        let model = try UIFixture.model()
        model.newExpense()
        return (model, try #require(model.selectedExpenseID))
    }

    @Test func newExpenseIsDatedTodayAndSelected() throws {
        let (model, id) = try modelWithExpense()
        #expect(model.section == .expenses)
        #expect(model.library.expenses.map(\.id) == [id])
        #expect(model.library.expense(id)?.date == UIFixture.today)
        #expect(model.library.activity.first?.message == "Added expense (no supplier), 15 Oct 2026, $0.00")
    }

    @Test func theFormSavesThroughTheBinding() throws {
        let (model, id) = try modelWithExpense()
        let binding = model.expenseBinding(id)
        binding.wrappedValue.supplier = "Sample Supplies"
        binding.wrappedValue = binding.wrappedValue.withTotal(Money(dollars: 55)).includingGST(true)
        let saved = try #require(model.library.expense(id))
        #expect(saved.supplier == "Sample Supplies")
        #expect(saved.gst == Money(dollars: 5), "Includes GST fills in total ÷ 11")
        #expect(ExpensesView.summary(model.library.expenses, money: model.money) == "1 expense · $55.00, $5.00 GST")
    }

    @Test func theCategoryPickerAndOthersText() {
        #expect(ExpenseForm.pickerValue("Travel", typingOther: false) == "Travel")
        #expect(ExpenseForm.pickerValue("Training", typingOther: false) == "Other")
        #expect(ExpenseForm.pickerValue("Other", typingOther: false) == "Other")
        #expect(ExpenseForm.pickerValue("Office", typingOther: true) == "Other", "still typing Other's name")
        #expect(ExpenseForm.otherText("Other") == "")
        #expect(ExpenseForm.otherText("Training") == "Training")
        #expect(ExpenseForm.category(fromOther: "Training") == "Training")
        #expect(ExpenseForm.category(fromOther: "  ") == "Other")
    }

    @Test func theGSTFieldTakesUpToTheTotal() {
        #expect(ExpenseForm.gst("10", total: Money(dollars: 110)) == Money(dollars: 10))
        #expect(ExpenseForm.gst("", total: Money(dollars: 110)) == .zero)
        #expect(ExpenseForm.gst("111", total: Money(dollars: 110)) == nil)
        #expect(ExpenseForm.gst("-1", total: Money(dollars: 110)) == nil)
    }

    @Test func attachingCopiesTheFileIntoAssetsExpenses() throws {
        let (model, id) = try modelWithExpense()
        let source = try file("supplier invoice.pdf")
        model.attach(source, toExpense: id)
        let name = try #require(model.library.expense(id)?.attachment)
        #expect(name.hasPrefix("Expenses/expense-") && name.hasSuffix(".pdf"))
        let copy = try #require(model.library.expense(id).flatMap(model.attachmentURL))
        #expect(copy.deletingLastPathComponent().standardizedFileURL == model.expenseAttachmentsFolder.standardizedFileURL)
        #expect(try Data(contentsOf: copy) == Data(contentsOf: source))

        var opened: [URL] = []
        model.openInFinder = { opened.append($0) }
        model.openAttachment(id)
        #expect(opened == [copy])

        model.removeAttachment(id)
        #expect(model.library.expense(id)?.attachment == nil)
        #expect(FileManager.default.fileExists(atPath: copy.path), "the copy stays in Assets")
    }

    @Test func aPictureAttachesButOtherFilesDont() throws {
        let (model, id) = try modelWithExpense()
        model.attach(try file("receipt.jpg"), toExpense: id)
        #expect(model.library.expense(id)?.attachment?.hasSuffix(".jpg") == true)
        model.attach(try file("notes.txt"), toExpense: id)
        #expect(model.message?.title == "Not a PDF or Picture")
        #expect(model.library.expense(id)?.attachment?.hasSuffix(".jpg") == true)
    }

    @Test func theOpenPanelAndADropRouteToTheExpense() throws {
        let (model, id) = try modelWithExpense()
        #expect(FileChoice.expenseAttachment(id).contentTypes == [.pdf, .image])
        model.choosingFile = .expenseAttachment(id)
        model.fileChosen(.success(try file("quote.pdf")))
        #expect(model.library.expense(id)?.attachment != nil)

        model.removeAttachment(id)
        #expect(model.dropped([try file("dropped.pdf")]))
        #expect(model.library.expense(id)?.attachment != nil, "a PDF dropped on Expenses attaches")
        #expect(model.message == nil && model.dialog == nil, "it isn't read as a reply")

        // Anywhere else a dropped PDF is still a returned quote.
        model.go(to: .dashboard)
        #expect(model.dropped([try file("reply.pdf", "not really a PDF")]))
        #expect(model.message?.title == "Can't Read That PDF")
    }

    @Test func deleteAsksOnceThenRemovesIt() throws {
        let (model, id) = try modelWithExpense()
        model.deleteSelectedExpense()
        let box = try #require(model.message)
        #expect(box.text == "Delete the expense on 15 Oct 2026? This can't be undone.")
        model.respond(box.choices[0])
        #expect(model.library.expenses.isEmpty)
        #expect(model.selectedExpenseID == nil)
        #expect(model.library.activity.first?.message == "Deleted expense (no supplier), 15 Oct 2026, $0.00")
        _ = id
    }

    @Test func theFeeLockStopsNewExpenseAndAttaching() throws {
        let (model, id) = try modelWithExpense()
        var brand = model.library.brand
        brand.appFee = AppFee(startMonth: CalendarMonth(year: 2026, month: 9))
        model.updateBrand(brand)
        // A September payment, unpaid since 1 Oct: locked on 15 Oct.
        #expect(model.change("Add a payment") { library in
            var invoice = library.newInvoice(on: Day(year: 2026, month: 9, day: 10))
            invoice.lines = [LineItem(title: "Sample work", rate: Money(dollars: 100))]
            try library.update(invoice)
            try library.markSent(invoice: invoice.id)
            try library.recordPayment(Payment(date: Day(year: 2026, month: 9, day: 10), amount: Money(dollars: 100)), toInvoice: invoice.id)
        })
        #expect(model.isLocked)
        model.newExpense()
        #expect(model.library.expenses.count == 1)
        model.message = nil
        #expect(!model.dropped([try file("dropped.pdf")]))
        model.attach(try file("quote.pdf"), toExpense: id)
        #expect(model.library.expense(id)?.attachment == nil)
    }

    @Test func theSectionFitsTheSmallestWindow() throws {
        let (model, id) = try modelWithExpense()
        model.expenseBinding(id).wrappedValue.supplier = "Sample Supplies"
        model.expenseBinding(id).wrappedValue.category = "Training"
        // The list and the form at their least, with the padding either side and the gap between.
        #expect(ExpensesView.listMinimum + ExpensesView.formMinimum + 24 <= 778)
        // The columns (Date 92, Supplier 70+, Category 70+, Total 86, GST 76), the border and a scroller.
        #expect(92 + 70 + 70 + 86 + 76 + 4 + DetailsLayout.classicScrollerWidth <= ExpensesView.listMinimum)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "expenses-small")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
