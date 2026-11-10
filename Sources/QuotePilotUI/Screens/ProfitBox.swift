import QuotePilotCore
import SwiftUI

/// The Expenses tab's Profit box: this financial year's pie, the way Windows 95's drive Properties
/// showed used and free space, with the figures beside it. Income is the whole disc, expenses the blue
/// slice of it and profit the magenta rest.
struct ProfitBox: View {
    let profit: Profit
    let gstRegistered: Bool
    let money: (Money) -> String

    var body: some View {
        let isLoss = profit.profit < .zero
        GroupBox("Profit for \(profit.year.label)") {
            HStack(spacing: 14) {
                RetroPie(share: profit.expenseShare)
                    .accessibilityElement()
                    .accessibilityLabel(Self.pieDescription(profit))
                VStack(alignment: .leading, spacing: 5) {
                    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) {
                        GridRow {
                            LegendSwatch(color: RetroPie.firstColor)
                            Text("Expenses:")
                            Text(money(profit.expenses)).gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            // No profit leaves no magenta slice to point at.
                            LegendSwatch(color: profit.profit > .zero ? RetroPie.restColor : nil)
                            Text(isLoss ? "Loss:" : "Profit:")
                            Text(money(Money(cents: abs(profit.profit.cents))))
                        }
                        .foregroundStyle(isLoss ? Win95.overdue : Win95.text)
                        GridRow {
                            VStack(spacing: 0) {
                                Win95.shadow.frame(height: 1)
                                Win95.highlight.frame(height: 1)
                            }
                            .gridCellColumns(3)
                            .gridCellUnsizedAxes(.horizontal)
                        }
                        GridRow {
                            LegendSwatch(color: nil)
                            Text("Income:")
                            Text(money(profit.income))
                        }
                        GridRow {
                            LegendSwatch(color: nil)
                            Text("Margin:")
                            Text(Self.marginText(profit.margin))
                        }
                    }
                    .font(Win95.money)
                    if let note = Self.note(profit, gstRegistered: gstRegistered) {
                        Text(note)
                            .font(Win95.small)
                            .foregroundStyle(Win95.note)
                    }
                }
                .foregroundStyle(Win95.text)
                .fixedSize()
                Spacer(minLength: 0)
            }
        }
        .groupBoxStyle(.win95)
    }

    /// "73%", "−25%" for a loss, or a dash before any income.
    static func marginText(_ margin: Int?) -> String {
        guard let margin else { return "–" }
        return margin < 0 ? "−\(-margin)%" : "\(margin)%"
    }

    /// The small line under the figures, if any.
    static func note(_ profit: Profit, gstRegistered: Bool) -> String? {
        if profit.margin == nil { return "No payments yet this year." }
        return gstRegistered ? "Amounts ex GST." : nil
    }

    /// What the pie shows, for VoiceOver.
    static func pieDescription(_ profit: Profit) -> String {
        guard let margin = profit.margin else { return "Empty pie chart: no payments yet" }
        if profit.profit < .zero { return "Pie chart: expenses are more than income" }
        return "Pie chart: expenses \(100 - margin)% of income, profit \(margin)%"
    }
}

/// A legend's colour square with a black edge, or the same space left blank.
private struct LegendSwatch: View {
    let color: Color?

    var body: some View {
        Rectangle()
            .fill(color ?? .clear)
            .overlay { if color != nil { Rectangle().strokeBorder(Win95.dark, lineWidth: 1) } }
            .frame(width: 10, height: 10)
    }
}
