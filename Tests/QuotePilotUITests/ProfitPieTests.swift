import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The Expenses tab's profit pie, drawn pixel by pixel as Windows 95 drew a drive's.
@MainActor
@Suite struct ProfitPieTests {
    let year = FinancialYear(startYear: 2026)

    func pie(_ share: Double?) -> PiePixels { PiePixels(share: share, width: 112, faceHeight: 48, depth: 12) }

    @Test func theDiscIsOutlinedAndTheCornersAreClear() {
        let pixels = pie(0.3)
        #expect(pixels.rows.count == 60 && pixels.rows.allSatisfy { $0.count == 112 })
        #expect(pixels.rows[0][0] == nil && pixels.rows[59][111] == nil)
        #expect(pixels.rows[24][0] == .outline, "the left edge of the face")
        #expect(pixels.rows[59][56] == .outline, "the bottom of the rim")
    }

    /// Expenses start at three o'clock and run towards you, so the front of the rim is theirs once
    /// they're over a quarter.
    @Test func theFirstSliceRunsClockwiseFromThreeOClock() {
        #expect(pie(0.3).rows[53][56] == .rim(.first))
        #expect(pie(0.1).rows[53][56] == .rim(.rest))
        #expect(pie(0.3).rows[30][80] == .top(.first), "just below three o'clock")
        #expect(pie(0.3).rows[10][56] == .top(.rest), "the back of the face")
        #expect(pie(0.3).rows[23][80] == .outline, "the radius along three o'clock")
        #expect(pie(0).rows[23][80] == .top(.rest), "one slice has no radius")
        #expect(!pie(0).rows.joined().contains(.top(.first)))
        #expect(!pie(1).rows.joined().contains(.top(.rest)))
    }

    @Test func noIncomeIsAnEmptyGreyDisc() {
        let paints = pie(nil).rows.joined().compactMap { $0 }
        #expect(paints.allSatisfy { [.outline, .top(.empty), .rim(.empty)].contains($0) })
        #expect(paints.contains(.top(.empty)) && paints.contains(.rim(.empty)))
    }

    @Test func theFiguresReadPlainly() {
        #expect(ProfitBox.marginText(73) == "73%")
        #expect(ProfitBox.marginText(-25) == "−25%")
        #expect(ProfitBox.marginText(nil) == "–")

        let none = Profit(year: year, income: .zero, expenses: Money(dollars: 40))
        let healthy = Profit(year: year, income: Money(dollars: 1000), expenses: Money(dollars: 270))
        let loss = Profit(year: year, income: Money(dollars: 1000), expenses: Money(dollars: 1250))
        #expect(ProfitBox.note(none, gstRegistered: true) == "No payments yet this year.")
        #expect(ProfitBox.note(healthy, gstRegistered: true) == "Amounts ex GST.")
        #expect(ProfitBox.note(healthy, gstRegistered: false) == nil)
        #expect(ProfitBox.pieDescription(healthy) == "Pie chart: expenses 27% of income, profit 73%")
        #expect(ProfitBox.pieDescription(loss) == "Pie chart: expenses are more than income")
        #expect(ProfitBox.pieDescription(none) == "Empty pie chart: no payments yet")
    }

    /// Snapshots: profit-box (a profit, a loss, no income) and expenses-profit (the whole tab).
    @Test func theBoxDraws() throws {
        let money = { (amount: Money) in amount.formatted() }
        let boxes = VStack(spacing: 8) {
            ProfitBox(profit: Profit(year: year, income: Money(dollars: 12000), expenses: Money(dollars: 3200)),
                      gstRegistered: true, money: money)
            // The widest figures a one-person business is likely to see, at the narrowest form.
            ProfitBox(profit: Profit(year: year, income: Money(dollars: 987_654, cents: 32),
                                     expenses: Money(dollars: 123_456, cents: 78)),
                      gstRegistered: true, money: money)
            ProfitBox(profit: Profit(year: year, income: Money(dollars: 1000), expenses: Money(dollars: 1250)),
                      gstRegistered: false, money: money)
            ProfitBox(profit: Profit(year: year, income: .zero, expenses: Money(dollars: 40)),
                      gstRegistered: false, money: money)
        }
        .padding(8)
        .frame(width: 320)
        .background(Win95.face)
        let rep = Snapshot.render(boxes, size: CGSize(width: 320, height: 500), name: "profit-box")
        #expect(rep.map(Snapshot.hasContent) == true)

        let model = try UIFixture.sampleModel()
        model.newExpense()
        let id = try #require(model.selectedExpenseID)
        var expense = try #require(model.library.expense(id))
        expense.supplier = "Sample Supplies"
        expense.total = Money(dollars: 550)
        model.updateExpense(expense)
        model.section = .expenses
        let tab = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "expenses-profit")
        #expect(tab.map(Snapshot.hasContent) == true)
    }
}
