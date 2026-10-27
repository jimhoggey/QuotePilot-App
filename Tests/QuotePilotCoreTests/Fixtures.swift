import Foundation
@testable import QuotePilotCore

/// Made-up data shared by the core tests. Never real clients: this repo is public.
enum Fixture {
    static let today = Day(year: 2026, month: 10, day: 15)

    /// One client and quote Q-0001: 01 Discovery (2 hrs × $40), 02 Build ($1,000), 03 Extra screens ($420).
    static func libraryWithQuote(stage: QuoteStage = .sent, plan: PaymentPlan = .fiftyFifty) -> (library: Library, quoteID: UUID) {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example", email: "sam@example.com")
        library.addClient(client)
        var quote = library.newQuote(on: today, clientID: client.id)
        quote.title = "Booking app, phase 1"
        quote.plan = plan
        quote.planIsAutomatic = false
        quote.addLine(LineItem(title: "Discovery", quantity: 2, unit: .hours, rate: Money(dollars: 40)))
        quote.addLine(LineItem(title: "Build", rate: Money(dollars: 1000)))
        quote.addLine(LineItem(title: "Extra screens", rate: Money(dollars: 420)))
        quote.stage = stage
        try! library.update(quote)
        return (library, quote.id)
    }

    /// The fixture quote with 01 and 02 accepted ($1,080) and 03 declined.
    static func acceptedLibrary(plan: PaymentPlan = .fiftyFifty) -> (library: Library, quoteID: UUID) {
        var (library, id) = libraryWithQuote(plan: plan)
        try! library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: ["03"]), forQuote: id)
        return (library, id)
    }
}
