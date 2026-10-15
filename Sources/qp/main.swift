import Foundation
import QuotePilotCore
import QuotePilotPDF

// qp: try Quote Pilot's documents before the app exists. All data here is made up.
//   qp samples <folder>   writes a sample quote, deposit invoice, final invoice and receipt
//   qp read <pdf>         reads a returned quote and shows what Quote Pilot would record

func sampleLibrary() -> (library: Library, quoteID: UUID) {
    var library = Library()
    library.brand.businessName = "Sample Studio"
    library.brand.details = "hello@example.com\n0400 000 000"
    library.brand.paymentDetails = "BSB 000-000, account 00000000"
    let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example", email: "sam@example.com",
                        address: "1 Example St\nExampleton")
    library.addClient(client)
    var quote = library.newQuote(on: Day.today(), clientID: client.id)
    quote.title = "Booking app, phase 1"
    quote.summary = "What's included:\n- A walkthrough of how bookings work today\n- Screens for booking, rescheduling and reminders\n- Testing on your own iPad"
    quote.addLine(LineItem(title: "Discovery", detail: "Walkthrough and notes", quantity: 2, unit: .hours, rate: Money(dollars: 40)))
    quote.addLine(LineItem(title: "Build", detail: "Booking, rescheduling and reminder screens", rate: Money(dollars: 1000)))
    quote.addLine(LineItem(title: "Extra screens", detail: "Staff roster view", rate: Money(dollars: 420)))
    try! library.update(quote)
    return (library, quote.id)
}

func write(_ content: DocumentContent, to folder: URL, style: PDFStyle) throws {
    let url = folder.appendingPathComponent(content.fileName)
    try DocumentRenderer.render(content, style: style).write(to: url)
    print(url.path)
}

func samples(into folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var (library, quoteID) = sampleLibrary()
    let style = PDFStyle(brand: library.brand, assetsFolder: nil)
    let client = library.clients[0]
    let today = Day.today()

    try write(.quote(library.quote(quoteID)!, client: client, brand: library.brand), to: folder, style: style)

    try library.markSent(quote: quoteID)
    try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: ["03"]), forQuote: quoteID)
    let deposit = try library.draftNextInvoice(forQuote: quoteID, on: today)
    try library.markSent(invoice: deposit.id)
    try write(.invoice(deposit, client: client, brand: library.brand, quoteNumber: "Q-0001"), to: folder, style: style)

    try library.recordPayment(Payment(date: today, amount: deposit.amount), toInvoice: deposit.id)
    try write(.receipt(library.invoice(deposit.id)!, client: client, brand: library.brand), to: folder, style: style)

    if let closing = try library.completeJob(quote: quoteID, on: today) {
        try write(.invoice(closing, client: client, brand: library.brand, quoteNumber: "Q-0001"), to: folder, style: style)
    }
}

func read(_ path: String) {
    do {
        let form = try ReturnedQuoteReader.read(contentsOf: URL(fileURLWithPath: path))
        print("Quote:       \(form.quoteNumber)")
        print("Accept all:  \(form.acceptAll ? "ticked" : "not ticked")")
        print("Ticked:      \(form.ticked.isEmpty ? "none" : form.ticked.joined(separator: ", "))")
        print("Not ticked:  \(form.unticked.isEmpty ? "none" : form.unticked.joined(separator: ", "))")
        print("Name:        \(form.clientName.isEmpty ? "(blank)" : form.clientName)")
        print("Date:        \(form.clientDate.isEmpty ? "(blank)" : form.clientDate)")
        let (library, quoteID) = sampleLibrary()
        let proposal = library.quote(quoteID)!.proposal(from: form, today: Day.today())
        print("Would record: accept \(proposal.accepted.isEmpty ? "none" : proposal.accepted.joined(separator: ", ")); decline \(proposal.declined.isEmpty ? "none" : proposal.declined.joined(separator: ", "))")
        for problem in proposal.problems {
            print("Check:       \(problem.message)")
        }
    } catch let error as ReturnedQuoteError {
        print(error.message)
        exit(1)
    } catch {
        print(error.localizedDescription)
        exit(1)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.count) {
case ("samples", 2):
    do {
        try samples(into: URL(fileURLWithPath: arguments[1], isDirectory: true))
    } catch {
        print("Couldn't write the samples: \(error.localizedDescription)")
        exit(1)
    }
case ("read", 2):
    read(arguments[1])
default:
    print("usage: qp samples <folder>   |   qp read <returned quote.pdf>")
    exit(2)
}
