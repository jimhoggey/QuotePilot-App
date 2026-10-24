import Foundation
import Testing
@testable import QuotePilotCore

/// Expenses: adding, changing and deleting them, GST, decoding and the limits. Made-up suppliers.
@Suite struct ExpenseTests {
    let day = Day(year: 2026, month: 10, day: 20)

    func sample() -> Expense {
        Expense(date: day, supplier: "Sample Supplies", description: "Printer paper", category: "Office",
                total: Money(dollars: 110), gst: Money(dollars: 10), method: .card)
    }

    @Test func addUpdateAndDeleteAreLoggedInActivity() throws {
        var library = Library()
        let expense = sample()
        try library.addExpense(expense)
        #expect(library.expenses == [expense])
        #expect(library.activity.first?.message == "Added expense Sample Supplies, 20 Oct 2026, $110.00")

        var changed = expense
        changed.note = "Receipt in the drawer"
        try library.update(changed)
        #expect(library.expense(expense.id)?.note == "Receipt in the drawer")
        #expect(library.activity.first?.message == "Changed expense Sample Supplies, 20 Oct 2026, $110.00")

        try library.deleteExpense(expense.id)
        #expect(library.expenses.isEmpty)
        #expect(library.activity.first?.message == "Deleted expense Sample Supplies, 20 Oct 2026, $110.00")
        #expect(throws: LibraryError.notFound) { try library.deleteExpense(expense.id) }
        #expect(throws: LibraryError.notFound) { try library.update(changed) }
    }

    /// Fields save as you type, so a run of edits to one expense keeps one Activity line, the newest.
    @Test func aRunOfEditsKeepsOneActivityLine() throws {
        var library = Library()
        var expense = Expense(date: day)
        try library.addExpense(expense)
        for typed in ["S", "Sa", "Sam"] {
            expense.supplier = typed
            try library.update(expense)
        }
        expense = expense.withTotal(Money(dollars: 5))
        try library.update(expense)
        #expect(library.activity.map(\.message) == ["Changed expense Sam, 20 Oct 2026, $5.00",
                                                    "Added expense (no supplier), 20 Oct 2026, $0.00"])
        // Another expense's edit gets its own line.
        let other = Expense(date: day, supplier: "Other Supplier")
        try library.addExpense(other)
        var edited = other
        edited.note = "x"
        try library.update(edited)
        try library.update(expense.withTotal(Money(dollars: 6)))
        #expect(library.activity.prefix(3).map(\.message) == ["Changed expense Sam, 20 Oct 2026, $6.00",
                                                             "Changed expense Other Supplier, 20 Oct 2026, $0.00",
                                                             "Added expense Other Supplier, 20 Oct 2026, $0.00"])
    }

    @Test func includesGSTFillsInAnEleventhAndFollowsTheTotal() {
        #expect(Expense.gst(inTotal: Money(dollars: 110)) == Money(dollars: 10))
        // $100 ÷ 11 is $9.0909…: $9.09. $1.00 ÷ 11 is 9.09c: 9c. 6c ÷ 11 is 0.545c: 1c.
        #expect(Expense.gst(inTotal: Money(dollars: 100)) == Money(dollars: 9, cents: 9))
        #expect(Expense.gst(inTotal: Money(cents: 100)) == Money(cents: 9))
        #expect(Expense.gst(inTotal: Money(cents: 6)) == Money(cents: 1))

        let plain = Expense(date: day, total: Money(dollars: 220))
        #expect(!plain.includesGST)
        let ticked = plain.includingGST(true)
        #expect(ticked.gst == Money(dollars: 20))
        #expect(ticked.exGST == Money(dollars: 200))
        #expect(ticked.withTotal(Money(dollars: 330)).gst == Money(dollars: 30), "the GST follows the total")
        #expect(ticked.includingGST(false).gst == .zero)
        #expect(plain.withTotal(Money(dollars: 330)).gst == .zero, "no GST stays no GST")
    }

    @Test func gstCantBeMoreThanTheTotal() throws {
        var library = Library()
        var expense = Expense(date: day, total: Money(dollars: 10), gst: Money(dollars: 11))
        #expect(throws: LibraryError.gstMoreThanTotal) { try library.addExpense(expense) }
        expense.gst = Money(dollars: 1)
        try library.addExpense(expense)
        expense.gst = Money(dollars: 20)
        #expect(throws: LibraryError.gstMoreThanTotal) { try library.update(expense) }
        #expect(library.expense(expense.id)?.gst == Money(dollars: 1))
    }

    @Test func theStandardCategoriesEndWithOther() {
        #expect(Expense.categories == ["Equipment", "Software and subscriptions", "Materials", "Subcontractors",
                                       "Travel", "Phone and internet", "Office", "Other"])
        #expect(Expense(date: day).category == "Other")
    }

    @Test func expensesRoundTripAndAnOldLibraryHasNone() throws {
        var library = Library()
        var expense = sample()
        expense.attachment = "expense-1A2B3C4D.pdf"
        try library.addExpense(expense)
        let data = try Library.makeEncoder().encode(library)
        let back = try Library.makeDecoder().decode(Library.self, from: data)
        #expect(back.expenses == [expense])

        let old = try Library.makeDecoder().decode(Library.self, from: Data(#"{"format": 1, "clients": []}"#.utf8))
        #expect(old.expenses.isEmpty)
        // An expense saved without an attachment has none.
        let json = #"{"expenses": [{"id": "\#(UUID().uuidString)", "date": "2026-10-20", "supplier": "Sample", "description": "", "category": "Travel", "total": 500, "gst": 0, "method": "cash", "note": ""}]}"#
        let noAttachment = try Library.makeDecoder().decode(Library.self, from: Data(json.utf8))
        #expect(noAttachment.expenses.first?.attachment == nil)
        #expect(noAttachment.expenses.first?.total == Money(dollars: 5))
    }

    @Test func problemsCapTheAmountsAndTheGST() {
        var library = Library()
        library.expenses = [Expense(date: day, supplier: "Sample", total: Money(cents: Int.max))]
        #expect(library.problems().contains { $0.hasPrefix("The expense from Sample on 20 Oct 2026") })
        library.expenses = [Expense(date: day, total: Money(dollars: 10), gst: Money(dollars: 11))]
        #expect(library.problems() == ["The expense from (no supplier) on 20 Oct 2026 has more GST ($11.00) than its total ($10.00)."])
        library.expenses = [sample()]
        #expect(library.problems().isEmpty)
    }
}
