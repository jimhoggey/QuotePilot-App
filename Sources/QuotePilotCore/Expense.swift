import Foundation

/// Something the business paid for, kept for the accountant: who, what, how much and the GST in it,
/// with the supplier's quote or invoice attached if there is one.
public struct Expense: Codable, Hashable, Identifiable, Sendable {
    /// The standard categories, in the order the picker lists them. Other takes free text.
    public static let categories = ["Equipment", "Software and subscriptions", "Materials", "Subcontractors",
                                    "Travel", "Phone and internet", "Office", "Other"]
    public static let otherCategory = "Other"

    public var id: UUID
    public var date: Day
    public var supplier: String
    public var description: String
    /// One of `categories`, or free text typed for Other.
    public var category: String
    /// What was paid, GST included.
    public var total: Money
    /// The GST inside `total`; 0 when there's none.
    public var gst: Money
    public var method: PaymentMethod
    public var note: String
    /// The attached quote or invoice: a file name in the library's Assets/Expenses folder.
    public var attachment: String?

    public init(id: UUID = UUID(), date: Day, supplier: String = "", description: String = "",
                category: String = Expense.otherCategory, total: Money = .zero, gst: Money = .zero,
                method: PaymentMethod = .bankTransfer, note: String = "", attachment: String? = nil) {
        self.id = id
        self.date = date
        self.supplier = supplier
        self.description = description
        self.category = category
        self.total = total
        self.gst = gst
        self.method = method
        self.note = note
        self.attachment = attachment
    }

    /// What was paid less GST.
    public var exGST: Money { total - gst }

    /// The GST inside a GST-inclusive total: one eleventh, rounded half up to the cent.
    public static func gst(inTotal total: Money) -> Money { total.times(Decimal(1) / 11) }

    /// Whether the "Includes GST" box is ticked: there's GST in the total.
    public var includesGST: Bool { gst != .zero }

    /// The "Includes GST" box: ticked fills in the GST as a tenth of the price (total ÷ 11); unticked
    /// clears it. The GST field can then be changed by hand.
    public func includingGST(_ includes: Bool) -> Expense {
        var expense = self
        expense.gst = includes ? Expense.gst(inTotal: total) : .zero
        return expense
    }

    /// A new total. While the expense includes GST the GST follows it (total ÷ 11 again).
    public func withTotal(_ total: Money) -> Expense {
        var expense = self
        expense.total = total
        if includesGST { expense.gst = Expense.gst(inTotal: total) }
        return expense
    }

    /// "Officeworks, 20 Oct 2026, $120.00", as Activity names it.
    func activityLabel(currencyCode: String) -> String {
        let who = supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(who.isEmpty ? "(no supplier)" : who), \(date.short), \(total.formatted(currencyCode: currencyCode))"
    }
}

extension Library {
    public func expense(_ id: UUID) -> Expense? { expenses.first { $0.id == id } }

    public mutating func addExpense(_ expense: Expense, at time: Date = Date()) throws {
        guard expense.gst <= expense.total else { throw LibraryError.gstMoreThanTotal }
        expenses.append(expense)
        log("Added expense \(expense.activityLabel(currencyCode: brand.currencyCode))", at: time)
    }

    /// Stores an edited expense. Activity gets one line per run of edits to the same expense, as
    /// fields save while you type: an edit right after the last one replaces its line.
    public mutating func update(_ expense: Expense, at time: Date = Date()) throws {
        guard let index = expenses.firstIndex(where: { $0.id == expense.id }) else { throw LibraryError.notFound }
        guard expense.gst <= expense.total else { throw LibraryError.gstMoreThanTotal }
        let currency = brand.currencyCode
        let previous = "Changed expense \(expenses[index].activityLabel(currencyCode: currency))"
        expenses[index] = expense
        if activity.first?.message == previous { activity.removeFirst() }
        log("Changed expense \(expense.activityLabel(currencyCode: currency))", at: time)
    }

    public mutating func deleteExpense(_ id: UUID, at time: Date = Date()) throws {
        guard let index = expenses.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        let expense = expenses.remove(at: index)
        log("Deleted expense \(expense.activityLabel(currencyCode: brand.currencyCode))", at: time)
    }
}
