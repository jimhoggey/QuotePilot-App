import Foundation
import QuotePilotCore
import QuotePilotPDF
import UniformTypeIdentifiers

/// What the acceptance review shows and lets you change. Nothing is recorded until it's confirmed.
public struct AcceptanceReview: Equatable {
    public struct Line: Equatable, Identifiable {
        public var id: String { code }
        public var code: String
        public var title: String
        public var amount: Money
        public var accepted: Bool
    }

    public var quoteID: UUID
    public var source: AcceptanceSource
    public var fileName: String?
    public var lines: [Line]
    public var clientName: String
    public var clientDate: String
    public var problems: [AcceptanceProblem]

    public var canBeConfirmed: Bool { !problems.contains(where: \.isBlocking) }
    public var accepted: [String] { lines.filter(\.accepted).map(\.code) }
    public var declined: [String] { lines.filter { !$0.accepted }.map(\.code) }

    init(quote: Quote, proposal: AcceptanceProposal, source: AcceptanceSource, fileName: String?) {
        quoteID = quote.id
        self.source = source
        self.fileName = fileName
        lines = quote.lines.map {
            Line(code: $0.code, title: $0.title, amount: $0.amount, accepted: proposal.accepted.contains($0.code))
        }
        clientName = proposal.clientName
        clientDate = proposal.clientDate
        problems = proposal.problems
    }
}

/// What the File menu's open panel is choosing a file for.
public enum FileChoice: Equatable {
    case returnedQuote

    var contentTypes: [UTType] {
        switch self {
        case .returnedQuote: return [.pdf]
        }
    }
}

extension AppModel {
    /// File → Read Returned Quote…, or a PDF dropped on the window.
    public func readReturnedQuote(at url: URL) {
        guard loadState == .ready else { return }
        guard let data = try? Data(contentsOf: url) else {
            return show(title: "Can't Read That PDF", text: ReturnedQuoteError.unreadable.message, kind: .warning)
        }
        let form: ReturnedForm
        do {
            form = try ReturnedQuoteReader.read(data)
        } catch ReturnedQuoteError.noForm {
            return offerHandTicking(data: data, fileName: url.lastPathComponent)
        } catch let error as ReturnedQuoteError {
            return show(title: "Can't Read That PDF", text: error.message, kind: .warning)
        } catch {
            return show(error, title: "Can't Read That PDF")
        }
        guard let quote = library.quote(number: form.quoteNumber) else {
            return show(title: "No Such Quote",
                        text: "This PDF is for quote \(form.quoteNumber), which isn't in Quote Pilot. Nothing was changed.",
                        kind: .warning)
        }
        guard canRecordAcceptance(quote) else { return }
        openQuote(quote.id)
        dialog = .acceptance(AcceptanceReview(quote: quote, proposal: quote.proposal(from: form, today: today),
                                              source: .returnedPDF, fileName: url.lastPathComponent))
    }

    /// "Record Acceptance…": every line starts unticked.
    public func startHandTicking(_ quoteID: UUID, fileName: String? = nil) {
        guard let quote = library.quote(quoteID), canRecordAcceptance(quote) else { return }
        // A form with nothing ticked on every line. The proposal's own "nothing ticked" warning is
        // dropped: unticked is where hand-ticking starts, so only the expiry warning is left.
        var proposal = quote.proposal(from: ReturnedForm(quoteNumber: quote.number, acceptAll: false, ticked: [],
                                                         unticked: quote.lineCodes),
                                      today: today)
        proposal.problems.removeAll { $0 == .nothingTicked }
        dialog = .acceptance(AcceptanceReview(quote: quote, proposal: proposal, source: .byHand, fileName: fileName))
    }

    /// Records the review. Nothing ticked asks first; a 50/50 quote then gets its deposit drafted and
    /// opened, in the same save.
    public func confirmAcceptance(_ review: AcceptanceReview) {
        guard review.canBeConfirmed, let quote = library.quote(review.quoteID) else { return }
        guard !review.accepted.isEmpty else {
            return confirm(title: "Declined?",
                           text: "No lines are ticked. Record that the client declined every line of \(quote.number)?",
                           confirm: "Record as Declined") { self.record(review) }
        }
        record(review)
    }

    private func record(_ review: AcceptanceReview) {
        let acceptance = Acceptance(recordedAt: now(), source: review.source, fileName: review.fileName,
                                    clientName: review.clientName, clientDate: review.clientDate,
                                    accepted: review.accepted, declined: review.declined)
        var deposit: UUID?
        let saved = change("Couldn't record the acceptance") { library in
            try library.recordAcceptance(acceptance, forQuote: review.quoteID)
            if library.quote(review.quoteID)?.plan == .fiftyFifty, !review.accepted.isEmpty {
                deposit = try library.draftNextInvoice(forQuote: review.quoteID, on: today).id
            }
        }
        guard saved else { return }
        dialog = nil
        if let deposit { openInvoice(deposit) }
    }

    /// Sent quotes without invoices only; says why otherwise.
    private func canRecordAcceptance(_ quote: Quote) -> Bool {
        if quote.stage == .draft {
            show(LibraryError.notSent, title: "Can't Record It")
            return false
        }
        if !library.invoices(forQuote: quote.id).isEmpty {
            show(LibraryError.alreadyInvoiced, title: "Can't Record It")
            return false
        }
        return true
    }

    /// A PDF with no form: if it still names its quote, offer to tick that quote by hand.
    private func offerHandTicking(data: Data, fileName: String) {
        if let number = ReturnedQuoteReader.quoteNumber(inMetadataOf: data), let quote = library.quote(number: number) {
            message = MessageBox(kind: .warning, title: "No Tick Boxes",
                                 text: "This is quote \(quote.number), but its tick boxes are gone. The client's app may have flattened it (printing to PDF does this). Tick the lines by hand from what the client marked.",
                                 choices: [MessageBox.Choice("Tick by Hand", isDefault: true) {
                                               self.startHandTicking(quote.id, fileName: fileName)
                                           },
                                           MessageBox.Choice("Cancel", isCancel: true)])
        } else {
            show(title: "No Tick Boxes", text: ReturnedQuoteError.noForm.message, kind: .warning)
        }
    }

    /// Files dropped on the window: the first PDF is read as a returned quote. A message box, dialog
    /// or panel that's already up is modal, so a drop behind it beeps and does nothing.
    public func dropped(_ urls: [URL]) -> Bool {
        guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
        var handled = false
        whenFree {
            readReturnedQuote(at: pdf)
            handled = true
        }
        return handled
    }

    /// The open panel's answer.
    public func fileChosen(_ result: Result<URL, Error>) {
        // SwiftUI may close the panel (which clears `choosingFile`) before it reports the file.
        let choice = choosingFile ?? lastFileChoice
        choosingFile = nil
        lastFileChoice = nil
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                show(error, title: "Couldn't open that file")
            }
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            switch choice {
            case .returnedQuote?: readReturnedQuote(at: url)
            case nil: break
            }
        }
    }
}
