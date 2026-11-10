import Foundation

/// What each release brought, in the words the What's New box uses: newest first, a few short lines
/// each. Every release gets an entry, even one with no lines (a release of small fixes): the box then
/// shows earlier changes instead. `WhatsNewTests` checks the newest entry is the app's version.
enum WhatsNew {
    struct Release {
        let version: String
        let notes: [String]

        init(_ version: String, _ notes: String...) {
            self.version = version
            self.notes = notes
        }
    }

    static let releases: [Release] = [
        Release("1.11.0", "Expenses shows this financial year's profit as a pie: expenses in blue, profit in magenta, with your margin beside it."),
        Release("1.10.0", "Travel expenses record the trip: type From and To, and Apple Maps fills in the kilometres. Tick Return trip to count them twice."),
        Release("1.9.1"),
        Release("1.9.0", "Invoice templates: set one up in Brand → Documents, such as Billing for meeting time, then start an invoice from it with New Invoice in the toolbar."),
        Release("1.8.1", "Brand → Settings → Quote Pilot fee takes your first name and email, for the fee's invoice."),
        Release("1.8.0",
                "Quotes can be paid in your own split, such as 30/70. Choose it in Brand → Documents → Custom split.",
                "Send Together: ⌘-click draft invoices for one client in the Dashboard's Drafts list, then right-click to email them in one go."),
        Release("1.7.1"),
        Release("1.7.0",
                "The Dashboard lists the quotes and invoices you haven't sent yet, under Drafts not sent yet.",
                "After an update, this box says what changed. Help → What's New shows it again."),
        Release("1.6.1",
                "Hover over a button at the top of a quote or invoice to see what it does."),
        Release("1.6.0",
                "A quote shows only the buttons that still apply to it.",
                "Tick off lines as the job goes: Brand → Settings → Job tracking adds a Done column.",
                "Full View shows the preview on its own. Esc goes back to the form."),
        Release("1.5.0",
                "The payment plan on a quote shows the amounts, such as 50% ($750.00) when accepted.",
                "Quotes over $1,000 are split 50/50, smaller ones are paid in full. Set the amount in Brand → Documents."),
        Release("1.4.0",
                "Claude can also fill in a quote's title, Work summary, Included lists, terms and payment plan."),
        Release("1.3.0",
                "Claude can start and fill in draft quotes for you. Turn it on in Brand → Settings."),
        Release("1.2.1",
                "Sending after hours? Quote Pilot reminds you about Mail's Send Later."),
        Release("1.2.0",
                "Quote Pilot counts which features get used, without client details. Brand → Settings → Usage turns it off."),
    ]

    /// Below this many new lines the box adds earlier ones, so a small release still says something.
    static let fewest = 3

    /// The box's text for `current`: the lines of every release after `seen` (of `current` alone when
    /// `seen` is nil), then, when that's fewer than `fewest`, the newest lines from before them. Nil
    /// when there's nothing to say.
    static func text(since seen: String?, current: String, releases: [Release] = releases) -> String? {
        guard let current = VersionNumber(current) else { return nil }
        let since = seen.flatMap(VersionNumber.init)
        let shipped: [(version: VersionNumber, notes: [String])] = releases.compactMap { release in
            guard let version = VersionNumber(release.version), version <= current else { return nil }
            return (version, release.notes)
        }
        let isNew = { (version: VersionNumber) in since.map { version > $0 } ?? (version == current) }
        let new = shipped.filter { isNew($0.version) }.flatMap { $0.notes }
        let earlier = shipped.filter { !isNew($0.version) }.flatMap { $0.notes }.prefix(max(0, fewest - new.count))
        let sections = [(since.map { "New since \($0):" } ?? "New in \(current):", new),
                        ("In case you missed it:", Array(earlier))]
        let text = sections.filter { !$0.1.isEmpty }
            .map { heading, lines in ([heading] + lines.map { "• \($0)" }).joined(separator: "\n") }
            .joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }
}
