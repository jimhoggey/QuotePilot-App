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
    /// "This replaces the decision recorded on …", when the quote already has one (and no invoice
    /// yet, which is the only time it can be recorded again). Nil the first time.
    public var replacementNote: String?

    /// What can't change as ticks do: the PDF is for another quote, or names lines this one lacks.
    private var blocking: [AcceptanceProblem]
    /// Lines the client's PDF didn't have.
    private var missingCodes: [String]
    private var expiredOn: Day?

    /// The warnings for the ticks as they are now. A line the PDF didn't have is only "marked
    /// declined" while it's unticked, and "nothing is ticked" is only news for a returned PDF: hand-
    /// ticking starts with nothing ticked.
    public var problems: [AcceptanceProblem] {
        var result = blocking
        let stillDeclined = missingCodes.filter { code in lines.contains { $0.code == code && !$0.accepted } }
        if !stillDeclined.isEmpty { result.append(.missingLines(stillDeclined)) }
        if source == .returnedPDF, accepted.isEmpty { result.append(.nothingTicked) }
        if let expiredOn { result.append(.expired(validUntil: expiredOn)) }
        return result
    }

    public var canBeConfirmed: Bool { !blocking.contains(where: \.isBlocking) }
    public var accepted: [String] { lines.filter(\.accepted).map(\.code) }
    public var declined: [String] { lines.filter { !$0.accepted }.map(\.code) }

    /// The line at the top of the review: where the ticks came from. A hand-ticked review that
    /// has a file is one whose PDF had no tick boxes to read.
    public var intro: String {
        switch source {
        case .returnedPDF:
            return "From \(fileName ?? "the returned PDF"). Check the ticks and change any that are wrong, then confirm."
        case .byHand where fileName != nil:
            return "This PDF has no tick boxes (it was probably printed or scanned). Tick the lines the client accepted."
        case .byHand:
            return "Tick the lines the client accepted, then confirm."
        }
    }

    /// With nothing ticked the default button records a decline, and says so: one step, no box.
    public var confirmTitle: String { accepted.isEmpty ? "Record as Declined" : "Confirm" }

    /// Whether the button is the dialog's default one (heavy outline, Return). Hand-ticking starts
    /// with nothing ticked, so a stray Return there must not record a decline: it has no default
    /// until a line is ticked, and a deliberate click on "Record as Declined" still works. A returned
    /// PDF is the client's own answer, so it keeps its default even when nothing is ticked.
    public var confirmIsDefault: Bool { source == .returnedPDF || !accepted.isEmpty }

    init(quote: Quote, proposal: AcceptanceProposal, source: AcceptanceSource, fileName: String?) {
        quoteID = quote.id
        self.source = source
        self.fileName = fileName
        lines = quote.lines.map {
            Line(code: $0.code, title: $0.title, amount: $0.amount, accepted: proposal.accepted.contains($0.code))
        }
        clientName = proposal.clientName
        clientDate = proposal.clientDate
        blocking = []
        missingCodes = []
        for problem in proposal.problems {
            switch problem {
            case .wrongQuote, .unknownLines: blocking.append(problem)
            case .missingLines(let codes): missingCodes = codes
            case .nothingTicked: break  // worked out from the ticks as they are
            case .expired(let validUntil): expiredOn = validUntil
            }
        }
        switch quote.stage {
        case .accepted, .declined:
            replacementNote = quote.acceptance.map { "This replaces the decision recorded on \(Day($0.recordedAt).long)." }
                ?? "This replaces the decision already recorded."
        case .draft, .sent:
            replacementNote = nil
        }
    }
}

/// What the open panel is choosing a file for. The whole app has one open panel (RootView's
/// `fileImporter`), so every pick, the Brand screen's included, is one of these: stacked importers
/// are a known SwiftUI hazard, where a pick can reach the wrong handler.
public enum FileChoice: Equatable {
    case returnedQuote
    /// Invoice Generator's "Back up to file" JSON.
    case legacyBackup
    /// The Brand screen's logo.
    case logo
    /// The Brand screen's heading font.
    case headingFont

    var contentTypes: [UTType] {
        switch self {
        case .returnedQuote: return [.pdf]
        case .legacyBackup: return [.json]
        case .logo: return [.png, .jpeg, .svg, .pdf]
        case .headingFont: return [.font]
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
            return openHandTickingForFlattened(data: data, fileName: url.lastPathComponent)
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
        dialog = .acceptance(acceptanceReview(quote, proposal: quote.proposal(from: form, today: today),
                                              source: .returnedPDF, fileName: url.lastPathComponent))
    }

    /// The review for a quote. An empty Date field (hand-ticking has none, and a client may leave it
    /// blank on the PDF) starts as today, written the way people fill in the PDF's Date field
    /// ("16/10/2026"). A date the client filled in is kept as it is.
    private func acceptanceReview(_ quote: Quote, proposal: AcceptanceProposal, source: AcceptanceSource,
                                  fileName: String?) -> AcceptanceReview {
        var review = AcceptanceReview(quote: quote, proposal: proposal, source: source, fileName: fileName)
        if review.clientDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let day = today
            review.clientDate = String(format: "%02d/%02d/%04d", day.day, day.month, day.year)
        }
        return review
    }

    /// "Record Acceptance…": every line starts unticked. `fileName` is the PDF the client sent when it
    /// had no tick boxes to read.
    public func startHandTicking(_ quoteID: UUID, fileName: String? = nil) {
        guard let quote = library.quote(quoteID), canRecordAcceptance(quote) else { return }
        openQuote(quote.id)
        // A form with nothing ticked on every line. The review shows no "nothing ticked" warning for
        // a hand-ticked quote (that's where it starts), so only the expiry warning is left.
        let proposal = quote.proposal(from: ReturnedForm(quoteNumber: quote.number, acceptAll: false, ticked: [],
                                                         unticked: quote.lineCodes),
                                      today: today)
        dialog = .acceptance(acceptanceReview(quote, proposal: proposal, source: .byHand, fileName: fileName))
    }

    /// Records the review as it stands, with no question. Nothing ticked records a decline: the
    /// review's own button says so (`confirmTitle`). A 50/50 quote that has something accepted also
    /// gets its deposit drafted and opened, in the same save.
    public func confirmAcceptance(_ review: AcceptanceReview) {
        guard review.canBeConfirmed, library.quote(review.quoteID) != nil else { return }
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

    /// A PDF with no form (printed or scanned). If its quote can be told, the hand-ticking review opens
    /// at once, with a line in it saying why: no box first. If not, the one error box stands.
    private func openHandTickingForFlattened(data: Data, fileName: String) {
        guard let quote = quoteBehindFlattened(data: data, fileName: fileName) else {
            return show(title: "No Tick Boxes", text: ReturnedQuoteError.noForm.message, kind: .warning)
        }
        startHandTicking(quote.id, fileName: fileName)
    }

    /// The quote a PDF with no form belongs to: the number in its keywords, which usually survive
    /// flattening, or else the one quote number its file name holds. Nil, so the one error box shows,
    /// when the keywords name a quote this library doesn't have (the PDF is for another quote, and its
    /// file name mustn't pick a different one in its place) and when the file name holds more than
    /// one of the library's quote numbers (it could be either).
    private func quoteBehindFlattened(data: Data, fileName: String) -> Quote? {
        if let number = ReturnedQuoteReader.quoteNumber(inMetadataOf: data) {
            return library.quote(number: number)
        }
        let named = library.quotes.filter { Self.fileName(fileName, mentions: $0.number) }
        return named.count == 1 ? named[0] : nil
    }

    /// True when `number` is in `name` as a whole number: not run into letters or digits before it or
    /// digits after it ("Q-00021" isn't Q-0002, "XQ-0002" isn't either). Case doesn't matter.
    static func fileName(_ name: String, mentions number: String) -> Bool {
        var searching = name.startIndex..<name.endIndex
        while let found = name.range(of: number, options: .caseInsensitive, range: searching) {
            let before = found.lowerBound == name.startIndex ? nil : name[name.index(before: found.lowerBound)]
            let after = found.upperBound == name.endIndex ? nil : name[found.upperBound]
            if before?.isLetter != true, before?.isNumber != true, after?.isNumber != true { return true }
            searching = found.upperBound..<name.endIndex
        }
        return false
    }

    /// Files dropped on the window: the first PDF file is read as a returned quote. A web link isn't
    /// a file (reading it would download it on the main thread), and with the library unusable there's
    /// nothing a drop could do; both return false. A message box, dialog or panel that's already up is
    /// modal, so a drop behind it beeps and does nothing.
    public func dropped(_ urls: [URL]) -> Bool {
        guard loadState == .ready,
              let pdf = urls.first(where: { $0.isFileURL && $0.pathExtension.lowercased() == "pdf" })
        else { return false }
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
            case .legacyBackup?: importLegacyBackup(at: url)
            case .logo?: importLogo(from: url)
            case .headingFont?: importHeadingFont(from: url)
            case nil: break
            }
        }
    }
}
