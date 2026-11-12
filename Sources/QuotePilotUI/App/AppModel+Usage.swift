import Foundation
import QuotePilotCore

extension AppModel {
    // MARK: Usage counts (see `Usage`)

    /// Sends one usage event, after saying once, the first time it's seen, that a month's fee is due
    /// or has locked Quote Pilot.
    func track(_ event: UsageEvent, _ props: [String: Any] = [:]) {
        trackFeeState()
        usage.track(event, props, required: usageIsRequired)
    }

    /// Whether usage counts go whatever Brand → Settings' box says: while the Quote Pilot fee is on,
    /// its figures are how the fee gets invoiced, so the box shows ticked and greyed out (the user,
    /// 12 Nov 2026). Turning the fee off gives the box back.
    public var usageIsRequired: Bool { library.brand.appFee.calculates }

    /// fee_due for each month whose fee falls due, and fee_locked if it locks, each once.
    func trackFeeState() {
        let required = usageIsRequired
        switch appFeeState {
        case .due(let month, let fee)?:
            usage.trackOnce(.feeDue, month: month.key, feeProps(month, fee), required: required)
        case .locked(let month, let fee)?:
            usage.trackOnce(.feeDue, month: month.key, feeProps(month, fee), required: required)
            usage.trackOnce(.feeLocked, month: month.key, feeProps(month, fee), required: required)
        case .running?, nil:
            break
        }
    }

    /// A month's fee as the fee events carry it: "2026-10", 3 and 22.5, and who to invoice it to
    /// (Brand → Settings), so the developer can send the invoice.
    func feeProps(_ month: CalendarMonth, _ fee: Money) -> [String: Any] {
        let payer = library.brand.appFee
        return ["month": month.key, "fee_percent": percentNumber, "fee": Double(fee.cents) / 100,
                "name": payer.name.trimmed,
                "email": payer.email.trimmed]
    }

    /// The fee's tick box and rate, as app_started and fee_setting_changed carry them.
    var feeSettingProps: [String: Any] {
        ["fee_on": library.brand.appFee.calculates, "fee_percent": percentNumber]
    }

    private var percentNumber: Double { NSDecimalNumber(decimal: library.brand.appFee.percent).doubleValue }
}
