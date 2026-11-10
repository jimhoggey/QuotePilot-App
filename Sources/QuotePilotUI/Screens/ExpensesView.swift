import QuotePilotCore
import SwiftUI

/// Expenses: the list on the left, the selected expense's form on the right, as on Clients, with this
/// financial year's profit pie under the form. New Expense lives in the list's button row only, not
/// the toolbar.
struct ExpensesView: View {
    @Bindable var model: AppModel

    var body: some View {
        let expenses = model.library.expenses
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button("New Expense") { model.newExpense() }
                        .buttonStyle(.win95)
                        .fixedSize()
                        .disabled(!model.canEdit)
                    Button("Delete Expense") { model.deleteSelectedExpense() }
                        .buttonStyle(.win95)
                        .fixedSize()
                        .disabled(!model.canEdit || model.selectedExpenseID.flatMap { model.library.expense($0) } == nil)
                        .help("Delete the selected expense")
                    Spacer()
                }
                DetailsList(expenses, id: \.id, columns: columns, selection: $model.selectedExpenseID,
                            sort: DetailsSort(column: 0, ascending: false),
                            emptyText: "No expenses yet. Press New Expense to add one.")
                Text(Self.summary(expenses, money: model.money))
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // At the smallest window the list and the form have 754 points between them.
            .frame(minWidth: Self.listMinimum, maxWidth: .infinity)
            let shown = model.selectedExpenseID.flatMap { model.library.expense($0) }?.id
            VStack(spacing: 8) {
                if let id = shown {
                    // A fresh form for each expense, so no half-typed text lands on the next one.
                    ExpenseForm(model: model, expenseID: id)
                        .id(id)
                } else {
                    Text("Select an expense to see it.")
                        .font(Win95.label)
                        .foregroundStyle(Win95.highlight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Win95.desktop)
                        .overlay(Bevel(.sunken))
                }
                ProfitBox(profit: model.library.profit(in: FinancialYear(containing: model.today)),
                          gstRegistered: model.library.brand.gstRegistered, money: model.money)
                    // In line with the form's boxes, which leave room for its scroll bar.
                    .padding(.trailing, shown == nil ? 0 : 6)
            }
            .frame(minWidth: Self.formMinimum, idealWidth: 440, maxWidth: 440)
            .layoutPriority(1)
        }
        .padding(8)
    }

    /// The least the list and the form take: with the padding and the gap, 764 of the 778 beside the
    /// tree in the smallest window. The list's columns need 415 of their 420.
    static let listMinimum: CGFloat = 420
    static let formMinimum: CGFloat = 320

    /// "3 expenses · $330.00, $30.00 GST"
    static func summary(_ expenses: [Expense], money: (Money) -> String) -> String {
        let total = expenses.reduce(Money.zero) { $0 + $1.total }
        let gst = expenses.reduce(Money.zero) { $0 + $1.gst }
        return "\(DashboardView.count(expenses.count, "expense", "expenses")) · \(money(total)), \(money(gst)) GST"
    }

    private var columns: [DetailsColumn<Expense>] {
        [
            .day("Date", width: 92) { $0.date },
            .text("Supplier", width: .flexible(min: 70)) { $0.supplier },
            .text("Category", width: .flexible(min: 70)) { $0.category },
            .money("Total", width: 86, currencyCode: model.currencyCode) { $0.total },
            .money("GST", width: 76, currencyCode: model.currencyCode) { $0.gst },
        ]
    }
}

/// One expense. Every change saves as you type; greyed out while the fee lock is on, except opening
/// the attachment.
struct ExpenseForm: View {
    let model: AppModel
    let expenseID: UUID
    /// Set when Other is picked, so the text field stays while you type a name that happens to be a
    /// standard one on the way ("Office" in "Office chair").
    @State private var typingOther = false

    /// The categories with a name of their own: every standard one but Other.
    static let named = Array(Expense.categories.dropLast())

    /// What the picker shows: the category, or Other for free text.
    static func pickerValue(_ category: String, typingOther: Bool) -> String {
        named.contains(category) && !typingOther ? category : Expense.otherCategory
    }

    /// What Other's text field shows, and what typing in it stores: blank is plain "Other".
    static func otherText(_ category: String) -> String { category == Expense.otherCategory ? "" : category }
    static func category(fromOther text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? Expense.otherCategory : text
    }

    /// The GST field takes $0 up to the total.
    static func gst(_ text: String, total: Money) -> Money? {
        FieldParser.amountOrBlank(text).flatMap { $0 <= total ? $0 : nil }
    }

    var body: some View {
        let expense = model.expenseBinding(expenseID)
        let current = expense.wrappedValue
        let picked = Self.pickerValue(current.category, typingOther: typingOther)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Expense") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95FieldRow("Date:") { DayPicker(label: "Date", day: expense.date) }
                        Win95FieldRow("Supplier:") {
                            Win95TextField("Supplier", text: expense.supplier, prompt: "Who was paid")
                        }
                        Win95FieldRow("Description:") {
                            Win95TextField("Description", text: expense.description, prompt: "What for")
                        }
                        Win95FieldRow("Category:") {
                            Picker("Category", selection: Binding(get: { picked }, set: { choice in
                                typingOther = choice == Expense.otherCategory
                                expense.wrappedValue.category = choice
                            })) {
                                ForEach(Expense.categories, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 220, alignment: .leading)
                        }
                        if picked == Expense.otherCategory {
                            Win95FieldRow("Other:") {
                                Win95TextField("Other category",
                                               text: Binding(get: { Self.otherText(current.category) },
                                                             set: { expense.wrappedValue.category = Self.category(fromOther: $0) }),
                                               prompt: "Name the category")
                            }
                        }
                        if current.category == Expense.travelCategory {
                            TripFields(model: model, expenseID: expenseID, expense: expense)
                        }
                        Win95FieldRow("Total:") {
                            CommitField(label: "Total, GST included", value: current.total, format: { model.money($0) },
                                        parse: FieldParser.amountOrBlank, alignment: .leading, prompt: "$0.00") {
                                expense.wrappedValue = expense.wrappedValue.withTotal($0)
                            }
                            .frame(width: 120)
                        }
                        Win95FieldRow("") {
                            // Ticked fills in total ÷ 11; the amount can then be changed by hand.
                            Toggle("Includes GST", isOn: Binding(get: { current.includesGST },
                                                                 set: { expense.wrappedValue = expense.wrappedValue.includingGST($0) }))
                                .toggleStyle(.win95)
                                .fixedSize()
                                .disabled(current.total == .zero)
                        }
                        Win95FieldRow("GST:") {
                            CommitField(label: "GST", value: current.gst, format: { model.money($0) },
                                        parse: { Self.gst($0, total: expense.wrappedValue.total) }, alignment: .leading) {
                                expense.wrappedValue.gst = $0
                            }
                            .frame(width: 120)
                        }
                        Win95FieldRow("Method:") {
                            Picker("Method", selection: expense.method) {
                                ForEach(PaymentMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 160, alignment: .leading)
                        }
                        Win95FieldRow("Note:") { Win95TextField("Note", text: expense.note, prompt: "Optional") }
                    }
                }
                .disabled(!model.canEdit)
                GroupBox("Quote or invoice") {
                    VStack(alignment: .leading, spacing: 6) {
                        // Attached, the file shows as a list to open or remove it; to swap it, remove it
                        // first or drop another PDF on the window.
                        if let file = current.attachmentTitle {
                            AttachmentList(fileName: file, canRemove: model.canEdit,
                                           open: { model.openAttachment(expenseID) },
                                           remove: { model.removeAttachment(expenseID) })
                        } else {
                            Text("Nothing attached. Attach the supplier's PDF or picture, or drop a PDF on this window.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Attach Quote or Invoice…") { model.choosingFile = .expenseAttachment(expenseID) }
                                .disabled(!model.canEdit)
                        }
                    }
                    .buttonStyle(.win95)
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.trailing, 6)
        }
        .groupBoxStyle(.win95)
    }
}

/// A Travel expense's trip. Once From and To are typed, Apple Maps fills in the driving distance a
/// second after typing stops; changing either end works it out again, and the distance can be typed
/// over. Return trip counts it twice.
struct TripFields: View {
    let model: AppModel
    let expenseID: UUID
    @Binding var expense: Expense
    /// Set when Maps found no route for these ends.
    @State private var notFound = false

    var body: some View {
        let current = expense.trip ?? Trip()
        // Nothing is looked up while the fee lock is on.
        let ready = current.hasEnds && model.canEdit
        Group {
            Win95FieldRow("From:") { Win95TextField("Trip from", text: end(\.from), prompt: "e.g. Fraser ACT") }
            Win95FieldRow("To:") { Win95TextField("Trip to", text: end(\.to), prompt: "e.g. Canberra City") }
            Win95FieldRow("Distance:") {
                HStack(spacing: 6) {
                    CommitField(label: "Kilometres one way", value: current.kilometres,
                                format: { $0.map(FieldParser.quantityText) ?? "" }, parse: Self.kilometres,
                                alignment: .leading, prompt: ready && !notFound ? "Finding…" : "km") { trip.wrappedValue.kilometres = $0 }
                        .frame(width: 80)
                    Text("km one way")
                }
            }
            Win95FieldRow("") {
                Toggle("Return trip", isOn: trip.returnTrip)
                    .toggleStyle(.win95)
                    .fixedSize()
            }
            Win95FieldRow("") {
                Text(Self.note(current, notFound: notFound))
                    .font(Win95.small)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: [current.from, current.to, current.kilometres == nil ? "" : "set"]) {
            notFound = false
            guard ready, current.kilometres == nil else { return }
            // Wait for typing to stop; a new keystroke cancels this and starts again.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let found = await model.fillTripDistance(expenseID)
            // Typing again while Maps worked cancels this; the next lookup speaks for the new ends.
            guard !Task.isCancelled else { return }
            notFound = !found
        }
    }

    /// What the note under the trip says.
    static func note(_ trip: Trip, notFound: Bool) -> String {
        if notFound { return "Apple Maps couldn't work out that route. Type the kilometres." }
        guard let business = trip.businessKilometres else {
            return "Type where from and to; Apple Maps fills in the driving distance."
        }
        return "Business kilometres: \(business). Apple Maps works it out from the places as typed; change it if you drove another way."
    }

    /// The distance field: blank clears it, so Maps works it out again; otherwise up to 100,000 km.
    static func kilometres(_ text: String) -> Decimal?? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? .some(nil) : FieldParser.quantity(text).map { .some($0) }
    }

    /// The expense's trip, a blank one until something is typed.
    private var trip: Binding<Trip> {
        Binding(get: { expense.trip ?? Trip() }, set: { expense.trip = $0 })
    }

    /// An end of the trip. Changing it clears the distance, so Maps works out the new one.
    private func end(_ keyPath: WritableKeyPath<Trip, String>) -> Binding<String> {
        Binding(get: { trip.wrappedValue[keyPath: keyPath] },
                set: { text in
                    guard trip.wrappedValue[keyPath: keyPath] != text else { return }
                    var edited = trip.wrappedValue
                    edited[keyPath: keyPath] = text
                    edited.kilometres = nil
                    trip.wrappedValue = edited
                })
    }
}
