import Foundation

/// A made-up business for trying the app and for screenshots: `qp demo` writes it as a library.
/// Every name, address and amount here is invented, because the repo is public.
public enum SampleLibrary {
    public static func make(today: Day, now: Date = Date()) throws -> Library {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        library.brand.details = "1 Example Lane\nBrisbane QLD 4000\nhello@example.com"
        library.brand.paymentDetails = "BSB 000-000, account 0000 0000 (sample only)"

        let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example", email: "sam@example.com",
                            phone: "0400 000 000")
        let bakery = Client(name: "Example Bakery", contactName: "Alex Sample", email: "alex@example.com")
        let acme = Client(name: "Acme Test Co", contactName: "Jordan Test", email: "jordan@example.com")
        for each in [client, bakery, acme] {
            library.addClient(each)
        }

        // Q-0001: accepted 50/50. The deposit is invoiced and paid; the balance is still to invoice.
        var website = library.newQuote(on: today.adding(days: -30), clientID: client.id)
        website.title = "Website rebuild, phase 1"
        website.summary = "What's included:\n- A discovery workshop\n- Design and build of five pages"
        website.addLine(LineItem(title: "Discovery workshop", quantity: 3, unit: .hours, rate: Money(dollars: 90)))
        website.addLine(LineItem(title: "Design", rate: Money(dollars: 1200)))
        website.addLine(LineItem(title: "Build", rate: Money(dollars: 2400)))
        website.addLine(LineItem(title: "Extra page templates", rate: Money(dollars: 600)))
        try library.update(website)
        try library.markSent(quote: website.id, at: now)
        try library.recordAcceptance(Acceptance(recordedAt: now, source: .byHand,
                                                accepted: ["01", "02", "03"], declined: ["04"]),
                                     forQuote: website.id)
        let deposit = try library.draftNextInvoice(forQuote: website.id, on: today.adding(days: -25))
        try library.markSent(invoice: deposit.id, at: now)
        try library.recordPayment(Payment(date: today, amount: deposit.amount), toInvoice: deposit.id)

        // Q-0002: sent last week, waiting on a reply.
        var menu = library.newQuote(on: today.adding(days: -6), clientID: bakery.id)
        menu.title = "Menu boards"
        menu.addLine(LineItem(title: "Menu board design", rate: Money(dollars: 450)))
        menu.addLine(LineItem(title: "Printing", quantity: 2, rate: Money(dollars: 85)))
        try library.update(menu)
        try library.markSent(quote: menu.id, at: now)

        // Q-0003: sent 40 days ago and never answered, so it has expired.
        var logo = library.newQuote(on: today.adding(days: -40), clientID: acme.id)
        logo.title = "Logo refresh"
        logo.addLine(LineItem(title: "Logo refresh", rate: Money(dollars: 800)))
        try library.update(logo)
        try library.markSent(quote: logo.id, at: now)

        // Q-0004: a draft.
        var social = library.newQuote(on: today, clientID: bakery.id)
        social.title = "Social media kit"
        social.addLine(LineItem(title: "Post templates", quantity: 6, unit: .hours, rate: Money(dollars: 90)))
        try library.update(social)

        // INV-0002: monthly care, five days overdue.
        var care = library.newInvoice(on: today.adding(days: -19), clientID: bakery.id)
        care.title = "Website care"
        care.lines = [LineItem(title: "Monthly website care", rate: Money(dollars: 150))]
        try library.update(care)
        try library.markSent(invoice: care.id, at: now)

        // INV-0003: hosting and support, part paid, due in nine days.
        var hosting = library.newInvoice(on: today.adding(days: -5), clientID: acme.id)
        hosting.title = "Hosting and support"
        hosting.lines = [LineItem(title: "Hosting, this month", rate: Money(dollars: 60)),
                         LineItem(title: "Support", quantity: Decimal(3) / 2, unit: .hours, rate: Money(dollars: 90))]
        try library.update(hosting)
        try library.markSent(invoice: hosting.id, at: now)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 60)), toInvoice: hosting.id)
        return library
    }
}
