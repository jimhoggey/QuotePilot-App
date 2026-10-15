import AppKit
import Foundation
import QuotePilotCore
@testable import QuotePilotUI

/// Stands in for Mail: records each draft, and can pretend Mail isn't available.
final class FakeMail: MailComposer {
    struct Draft: Equatable {
        var to: String
        var subject: String
        var body: String
        var attachment: URL
    }

    var available = true
    var drafts: [Draft] = []
    var setAside: [(message: String, attachment: URL)] = []

    func compose(to: String, subject: String, body: String, attachment: URL) -> Bool {
        guard available else { return false }
        drafts.append(Draft(to: to, subject: subject, body: body, attachment: attachment))
        return true
    }

    func setAside(message: String, attachment: URL) {
        setAside.append((message, attachment))
    }
}

/// Made-up data for the UI tests. Never real clients: this repo is public.
enum UIFixture {
    static let today = Day(year: 2026, month: 10, day: 15)

    /// A new temporary folder. Tests never touch the real library.
    static func makeFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotePilotUITests-\(UUID().uuidString)", isDirectory: true)
    }

    /// An accepted 50/50 quote (Design $600, Build $1,200) with its deposit invoice drafted, so its
    /// prices are locked.
    static func invoicedLibrary() throws -> (library: Library, quoteID: UUID) {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example")
        library.addClient(client)
        var quote = library.newQuote(on: today, clientID: client.id)
        quote.addLine(LineItem(title: "Design", rate: Money(dollars: 600)))
        quote.addLine(LineItem(title: "Build", rate: Money(dollars: 1200)))
        try library.update(quote)
        try library.markSent(quote: quote.id)
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: []), forQuote: quote.id)
        try library.draftNextInvoice(forQuote: quote.id, on: today)
        return (library, quote.id)
    }

    /// A model on its own temporary folder, starting from `library` when one is given. Mail is a fake
    /// and mailed PDFs go to a temporary folder.
    @MainActor
    static func model(_ library: Library? = nil, folder: URL = makeFolder(), mail: FakeMail = FakeMail()) throws -> AppModel {
        let store = LibraryStore(folder: folder)
        if let library { try store.save(library) }
        return AppModel(store: store, now: { today.date() }, mail: mail, sentFolder: makeFolder())
    }

    /// A model holding the made-up sample business, on its own temporary folder.
    @MainActor
    static func sampleModel(mail: FakeMail = FakeMail()) throws -> AppModel {
        try model(SampleLibrary.make(today: today, now: today.date()), mail: mail)
    }

    /// A real 2×2 PNG.
    static func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// Writes `data` to a file called `name` in a new temporary folder.
    static func file(_ name: String, _ data: Data) throws -> URL {
        let folder = makeFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
