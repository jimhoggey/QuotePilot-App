import Foundation
import QuotePilotCore

/// Why a change was refused while the fee lock is on.
struct FeeLockedError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

extension AppModel {
    // MARK: The Quote Pilot fee bar and lock

    /// What the red fee bar shows today; nil while the fee isn't calculated (no bar, no lock) or the
    /// library can't be read.
    public var appFeeState: AppFeeState? {
        guard libraryIsOpen else { return nil }
        return library.appFeeState(today: today)
    }

    /// True while a closed month's fee is more than 3 days late. Creating, editing, deleting, sending,
    /// payments, Read Reply, Import and New Expense are greyed out; viewing, PDFs, backups, exports,
    /// Restore Backup…, Help and Brand → Settings stay open.
    public var isLocked: Bool { appFeeState?.isLocked ?? false }

    /// Whether the library can be changed: it's open and the fee lock is off. The menus, the toolbar
    /// and the editors grey out what changes it when this is false.
    public var canEdit: Bool { libraryIsOpen && !isLocked }

    /// The bar's one line, or nil when there's no bar. It shows only once a fee is due, from the 1st;
    /// during the month nothing is owed, so there's no bar and the running figures stay in Brand →
    /// Settings (the user, 24 Oct 2026).
    public var feeBarText: String? {
        guard let state = appFeeState else { return nil }
        switch state {
        case .running:
            return nil
        case .due(let month, let fee):
            return "\(month.name) fee \(money(fee)) is due."
        case .locked(let month, let fee):
            return "Quote Pilot is locked until the \(month.name) fee (\(money(fee))) is paid. You can still view, back up and export."
        }
    }

    /// What a change refused by the lock says; nil while unlocked.
    var lockedError: FeeLockedError? {
        guard case .locked(let month, let fee)? = appFeeState else { return nil }
        return FeeLockedError(text: "Quote Pilot is locked until the \(month.name) fee (\(money(fee))) is paid. Press I've paid in the red bar once it is.")
    }

    /// The bar's I've paid: marks the owed month paid, honour system, with no question. Activity says so.
    public func markFeePaid() {
        guard let month = appFeeState?.monthToPay else { return beep() }
        let time = now()
        let day = today
        guard change("Couldn't mark the fee paid", whileLocked: true, { $0.markAppFeePaid(month, on: day, at: time) })
        else { return }
        if let paid = library.brand.appFee.paidMonths[month.key] { track(.feePaid, feeProps(month, paid.amount)) }
        note("Marked the \(month.name) fee paid")
    }
}
