import Foundation
import QuotePilotCore

extension AppModel {
    // MARK: Usage counts (see `Usage`)

    /// Sends one usage event, after saying once, the first time it's seen, that a month's fee is due
    /// or has locked Quote Pilot.
    func track(_ event: UsageEvent, _ props: [String: Any] = [:]) {
        trackFeeState()
        usage.track(event, props)
    }

    /// fee_due for each month whose fee falls due, and fee_locked if it locks, each once.
    func trackFeeState() {
        switch appFeeState {
        case .due(let month, let fee)?:
            usage.trackOnce(.feeDue, month: month.key, feeProps(month, fee))
        case .locked(let month, let fee)?:
            usage.trackOnce(.feeDue, month: month.key, feeProps(month, fee))
            usage.trackOnce(.feeLocked, month: month.key, feeProps(month, fee))
        case .running?, nil:
            break
        }
    }

    /// A month's fee as the fee events carry it: "2026-10", 3 and 22.5.
    func feeProps(_ month: CalendarMonth, _ fee: Money) -> [String: Any] {
        ["month": month.key, "fee_percent": percentNumber, "fee": Double(fee.cents) / 100]
    }

    /// The fee's tick box and rate, as app_started and fee_setting_changed carry them.
    var feeSettingProps: [String: Any] {
        ["fee_on": library.brand.appFee.calculates, "fee_percent": percentNumber]
    }

    private var percentNumber: Double { NSDecimalNumber(decimal: library.brand.appFee.percent).doubleValue }
}
