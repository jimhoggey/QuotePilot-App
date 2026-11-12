import Foundation

extension AppModel {
    // MARK: The tour (`Tour`)

    /// Take the Tour (the welcome box, What's New, Help → Take the Tour): step 1, on the Dashboard.
    /// Called once any message box has gone. Not while the library can't be read: there's no section
    /// tree to point at.
    public func takeTour() {
        guard libraryIsOpen else { return beep() }
        go(to: .dashboard)
        tour = Tour()
    }

    /// The balloon's Next: clicks the step's section if it isn't showing; otherwise the next step, or
    /// the end after the last.
    public func tourNext() {
        guard let tour else { return }
        if section != tour.step.section {
            go(to: tour.step.section)
        } else {
            self.tour = tour.advanced()
        }
    }

    /// The welcome box on a new install's first launch: the Pilot offers the tour, once.
    var welcomeBox: MessageBox {
        MessageBox(kind: .welcome, title: "Welcome to Quote Pilot",
                   text: "Quotes, invoices and payments in one place. Want a quick look around? Five steps, about a minute.",
                   choices: [MessageBox.Choice("Take the Tour", isDefault: true) { [weak self] in self?.takeTour() },
                             MessageBox.Choice("Not Now", isCancel: true)])
    }
}
