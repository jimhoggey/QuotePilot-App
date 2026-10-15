# Quote Pilot, plan 2b: Mail, returned quotes, invoices, payments, and the File menu

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Quote Pilot so the whole spec works from the app:
- Mail drafts with "Did you send it?";
- reading returned quotes (dropped on the window or opened from the File menu), with the acceptance
  review and hand-ticking;
- invoices, from quotes and on their own: the editor, payments, receipts and voiding;
- ⌘F filtering;
- the File menu: import from Invoice Generator, the tax-time export, Back up to…, and Restore backup….

**Architecture:** Plan 2a's shape stays.
- **Core rules:** the core gains the rules the screens need: stage guards, payment checks, mail
  wording, the sent-PDF archive path, and tolerant decoding for nested types.
- **AppModel:** `AppModel` stays the only route to the library. Mail goes through a small
  `MailComposer` protocol, so tests use a fake and the app uses macOS's compose service.
- **Dialogs:** each is a Windows 95 panel drawn over the window, like plan 2a's message box: the
  acceptance review, the payment entry, the client email prompt, the import report, the tax-year
  choice and the backup list.

**Tech Stack:** Swift 6.4 (Command Line Tools 27.0) against the macOS 26.5 SDK, SwiftUI (macOS 14+),
Observation, AppKit (NSSharingService, NSPasteboard, NSWorkspace), PDFKit, UniformTypeIdentifiers,
Swift Testing. No third-party packages.

**Spec:** `docs/superpowers/specs/2026-10-15-quote-pilot-design.md` (§1, §2, §6–§10 and §15).

**Builds on:** plan 2a (`docs/superpowers/plans/2026-10-16-quote-pilot-plan-2a-app-shell.md`). Its
Global Constraints all still apply. Read its Task 5 (`AppModel`), Task 6 (`RootView`, `MessageBox`,
the chrome) and Task 9 (the quote editor, `CommitField`, `LivePDFPreview`) before starting.

## Global Constraints

Everything in plan 2a's Global Constraints, plus:

- **Build and test** with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` on every
  `swift build` and `swift test` (plan 2a's toolchain note). `build.sh` sets it itself.
- **The app never sends anything.** Quote Pilot opens a Mail draft, and you press Send. A document is
  marked Sent only after you answer **Yes** to "Did you send it?". **Not Yet** changes nothing.
- **Every PDF that goes into a Mail draft** is also saved to `~/Documents/Quote Pilot/<year>/<file
  name>` (spec §2). Tests point that folder at a temporary one.
- **Returned quotes change nothing until you confirm.** A blocking problem (a different quote, or
  lines the quote doesn't have) disables Confirm.
- **Payments are always more than $0 and never more than what's owing.** Payments go through
  `recordPayment` and `removePayment` only, never through `update(_ invoice:)`.
- **Dialogs are Windows 95 panels drawn over the window,** never macOS sheets. Return presses the
  default button and Escape cancels.
- **Shortcuts added:** ⇧⌘N new invoice, ⌘S send by Mail, ⌘O read returned quote, ⌘F find in the
  current list.

## Review Focus

1. **A payment that's zero, negative, or more than what's owing** (typed by hand) is refused with a
   plain message. Nothing is recorded. Task 1, `paymentsMustBePositiveAndNotMoreThanOwing`; Task 6,
   `aPaymentOverWhatsOwingIsRefused`.
2. **Answering "Not Yet" to "Did you send it?"**, or closing Mail without sending, leaves the document
   exactly as it was: still a draft, with no Sent date. Task 3, `notYetChangesNothing`.
3. **A returned PDF for another quote, with unknown line IDs, or with no form at all** changes
   nothing. The first two show what didn't match; a flattened PDF offers hand-ticking. Task 4,
   `aPDFForAnotherQuoteChangesNothing` and `aFlattenedPDFOffersHandTicking`.
4. **A sent invoice** can't be edited through the editor, and an invoice drafted from a quote keeps
   that quote's client. The editor shows them read-only and explains why. Task 1,
   `sentInvoicesCantBeEdited` and `quoteInvoicesKeepTheirQuotesClient`.
5. **A client with no email address:** pressing Send asks for one, saves it to the client, and then
   opens Mail. Cancel opens nothing. Task 3, `aMissingEmailIsAskedForFirst`.

---

## File structure

```
Sources/QuotePilotCore/
  Library.swift, Invoicing.swift, QuoteLifecycle.swift   stage guards, safe invoice editing,
                                                         payment checks, completeJob once (Task 1)
  Models.swift                         tolerant decoding for nested types (Task 1)
  Messages.swift                       wording for the new and changed errors (Task 1)
  Dashboard.swift                      CSV formula guard (Task 1)
  MailDraft.swift                      email wording from the brand's templates (Task 1)
  SentArchive.swift                    where mailed PDFs are kept (Task 1)
Sources/QuotePilotPDF/
  DocumentRenderer.swift               hasForm(_:) (Task 2)
  ReturnedQuoteReader.swift            quote number from a flattened PDF's metadata (Task 2)
Sources/QuotePilotUI/
  App/MailComposer.swift               the compose-service protocol, the system one, the fallback (Task 3)
  App/AppModel+Mail.swift              send flows, the email prompt, "Did you send it?" (Task 3)
  App/AppModel+Acceptance.swift        reading returned quotes, hand-ticking, confirming (Task 4)
  App/AppModel+Invoices.swift          invoice actions, payments, receipts (Tasks 5–6)
  App/AppModel+Files.swift             import, tax export, backup and restore (Task 8)
  App/Dialogs.swift                    the dialog panels and the overlay that shows them (Tasks 3–8)
  Screens/AcceptanceReviewView.swift   the acceptance review dialog (Task 4)
  Screens/InvoiceEditorView.swift      the invoice editor (Task 5)
  Screens/PaymentDialog.swift          recording a payment (Task 6)
  Screens/LinesEditor.swift            the line table, shared by quotes and invoices (Task 5)
  Screens/FindField.swift              ⌘F filtering (Task 7)
  Screens/FileDialogs.swift            import report, tax year, restore list (Task 8)
  App/AppIcon.swift                    the Dock icon, drawn from the pixel art (Task 9)
Tests/QuotePilotCoreTests/AppRulesTests.swift
Tests/QuotePilotPDFTests/FlattenedAndFormCheckTests.swift
Tests/QuotePilotUITests/               MailTests, AcceptanceTests, InvoiceEditorTests, PaymentTests,
                                       FindTests, FileMenuTests
```

---

### Task 1: Core rules the screens need

The editors and dialogs in this plan lean on rules that belong in the core. Tests cover each one, so
no screen has to re-implement them.

**Files:**
- Modify: `Sources/QuotePilotCore/Library.swift` (new errors; safe `update(_ invoice:)`)
- Modify: `Sources/QuotePilotCore/Invoicing.swift` (payment checks, receipts need a payment,
  `completeJob` once)
- Modify: `Sources/QuotePilotCore/QuoteLifecycle.swift` (acceptance needs a sent quote)
- Modify: `Sources/QuotePilotCore/Models.swift` (tolerant decoding for nested types)
- Modify: `Sources/QuotePilotCore/Messages.swift` (wording)
- Modify: `Sources/QuotePilotCore/Dashboard.swift` (CSV formula guard)
- Create: `Sources/QuotePilotCore/MailDraft.swift`
- Create: `Sources/QuotePilotCore/SentArchive.swift`
- Modify: `Tests/QuotePilotCoreTests/ToleranceAndMessagesTests.swift` (the new errors)
- Test: `Tests/QuotePilotCoreTests/AppRulesTests.swift`

**Interfaces:**
- Consumes: the plan 1 core, and plan 2a Task 1's `KeyedDecodingContainer.value(_:or:)` and
  `Messages.swift`.
- Produces:
  - **New `LibraryError` cases:** `.notEditable`, `.noPayments`, `.paymentNotPositive` and
    `.paymentMoreThanOwing(Money)`, each with a plain message.
  - **`update(_ invoice:)`:**
    - only a draft can be edited;
    - it applies only the editable fields: `title`, `issued`, `due`, `terms`, `lines`, `taxed`, and
      `clientID` for a standalone invoice (one from a quote keeps the quote's client);
    - stage, payments, Sent dates, kind, quote, deposit share and deductions always stay as stored;
    - the plan 1 guard is kept: a deposit a live final deducts can't change what it bills.
  - **Other rule changes:**
    - `recordPayment` refuses an amount of $0 or less, or more than what's owing;
    - `markReceiptSent` needs a payment;
    - `recordAcceptance` needs a quote that has been sent;
    - `completeJob` records the completion date and logs it only the first time.
  - `MailDraft(to:subject:body:)`, plus `Library.mailDraft(forQuote:)`, `mailDraft(forInvoice:)` and
    `mailDraft(forReceipt:)`, each returning `MailDraft?`.
  - `SentArchive.defaultFolder` and `SentArchive.freshURL(for:year:in:)`.
  - `csvText(_:)`, which `paymentsCSV` uses for the client and note columns.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotCoreTests/AppRulesTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct AppRulesTests {
    let today = Fixture.today

    /// A sent standalone invoice for $300, with the sample client.
    func sentStandalone(_ library: inout Library) throws -> Invoice {
        var invoice = library.newInvoice(on: today, clientID: library.clients[0].id)
        invoice.lines = [LineItem(title: "Extra work", rate: Money(dollars: 300))]
        try library.update(invoice)
        try library.markSent(invoice: invoice.id)
        return library.invoice(invoice.id)!
    }

    @Test func sentInvoicesCantBeEdited() throws {
        var (library, _) = Fixture.acceptedLibrary()
        var invoice = try sentStandalone(&library)
        invoice.title = "Renamed"
        #expect(throws: LibraryError.notEditable) { try library.update(invoice) }
        #expect(library.invoice(invoice.id)?.title == "")
    }

    @Test func quoteInvoicesKeepTheirQuotesClient() throws {
        var (library, quoteID) = Fixture.acceptedLibrary()
        let other = Client(name: "Example Bakery")
        library.addClient(other)
        let deposit = try library.draftNextInvoice(forQuote: quoteID, on: today)
        var edited = deposit
        edited.clientID = other.id
        edited.title = "Deposit for the booking app"
        try library.update(edited)
        #expect(library.invoice(deposit.id)?.clientID == deposit.clientID)
        #expect(library.invoice(deposit.id)?.title == "Deposit for the booking app")
    }

    @Test func editingADraftNeverChangesItsStageOrMoneyTrail() throws {
        var (library, _) = Fixture.acceptedLibrary()
        var invoice = library.newInvoice(on: today, clientID: library.clients[0].id)
        invoice.lines = [LineItem(title: "Work", rate: Money(dollars: 100))]
        invoice.stage = .sent
        invoice.sentAt = Date()
        invoice.payments = [Payment(date: today, amount: Money(dollars: 5))]
        invoice.kind = .deposit
        try library.update(invoice)
        let stored = try #require(library.invoice(invoice.id))
        #expect(stored.stage == .draft)
        #expect(stored.sentAt == nil)
        #expect(stored.payments.isEmpty)
        #expect(stored.kind == .standalone)
        #expect(stored.lines.map(\.title) == ["Work"])
    }

    @Test func paymentsMustBePositiveAndNotMoreThanOwing() throws {
        var (library, _) = Fixture.acceptedLibrary()
        let invoice = try sentStandalone(&library)
        #expect(throws: LibraryError.paymentNotPositive) {
            try library.recordPayment(Payment(date: today, amount: .zero), toInvoice: invoice.id)
        }
        #expect(throws: LibraryError.paymentNotPositive) {
            try library.recordPayment(Payment(date: today, amount: Money(dollars: -5)), toInvoice: invoice.id)
        }
        #expect(throws: LibraryError.paymentMoreThanOwing(Money(dollars: 300))) {
            try library.recordPayment(Payment(date: today, amount: Money(dollars: 301)), toInvoice: invoice.id)
        }
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 300)), toInvoice: invoice.id)
        #expect(library.invoice(invoice.id)?.owing == .zero)
    }

    @Test func receiptsNeedAPayment() throws {
        var (library, _) = Fixture.acceptedLibrary()
        let invoice = try sentStandalone(&library)
        #expect(throws: LibraryError.noPayments) { try library.markReceiptSent(invoice: invoice.id) }
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 100)), toInvoice: invoice.id)
        try library.markReceiptSent(invoice: invoice.id)
        #expect(library.invoice(invoice.id)?.receiptSentAt != nil)
    }

    @Test func acceptanceNeedsASentQuote() {
        var (library, id) = Fixture.libraryWithQuote(stage: .draft)
        #expect(throws: LibraryError.notSent) {
            try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: ["02", "03"]), forQuote: id)
        }
        #expect(library.quote(id)?.stage == .draft)
    }

    @Test func completingTwiceChangesNothing() throws {
        var (library, id) = Fixture.acceptedLibrary(plan: .fullAmount)
        try library.completeJob(quote: id, on: today)
        let entries = library.activity.count
        #expect(try library.completeJob(quote: id, on: today.adding(days: 3)) == nil)
        #expect(library.quote(id)?.completedOn == today)
        #expect(library.activity.count == entries)
    }

    @Test func mailDraftsFillTheBrandsWording() throws {
        var (library, quoteID) = Fixture.acceptedLibrary()
        let quote = try #require(library.mailDraft(forQuote: quoteID))
        #expect(quote.to == "sam@example.com")
        #expect(quote.subject == "Quote Q-0001 from Sample Studio")
        #expect(quote.body.hasPrefix("Hi Sam,"))

        let deposit = try library.draftNextInvoice(forQuote: quoteID, on: today)
        let invoice = try #require(library.mailDraft(forInvoice: deposit.id))
        #expect(invoice.subject == "Invoice INV-0001 from Sample Studio")
        #expect(invoice.body.contains("for $540.00, due 29 October 2026"))

        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 540)), toInvoice: deposit.id)
        let receipt = try #require(library.mailDraft(forReceipt: deposit.id))
        #expect(receipt.subject == "Receipt for invoice INV-0001")
        #expect(library.mailDraft(forQuote: UUID()) == nil)
    }

    @Test func nestedTypesTolerateMissingFields() throws {
        let decoder = Library.makeDecoder()
        let payment = try decoder.decode(Payment.self, from: Data(#"""
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-10-15","amount":5000}
            """#.utf8))
        #expect(payment.method == .bankTransfer)
        #expect(payment.note == "")
        let templates = try decoder.decode(EmailTemplates.self, from: Data(#"""
            {"quote":{"subject":"Q {number}","body":"Hi"}}
            """#.utf8))
        #expect(templates.quote.subject == "Q {number}")
        #expect(templates.receipt == EmailTemplates.standard.receipt)
        let entry = try decoder.decode(ActivityEntry.self, from: Data(#"""
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","at":"2026-10-15T01:02:03Z"}
            """#.utf8))
        #expect(entry.number == nil)
        #expect(entry.message == "")
        let acceptance = try decoder.decode(Acceptance.self, from: Data(#"""
            {"recordedAt":"2026-10-15T01:02:03Z","source":"byHand"}
            """#.utf8))
        #expect(acceptance.accepted.isEmpty)
        #expect(acceptance.clientName == "")
    }

    @Test func theArchivePicksAFreshNameEachTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QuotePilotArchive-\(UUID().uuidString)")
        let first = SentArchive.freshURL(for: "Q-0001 Sample Client Pty Ltd.pdf", year: 2026, in: root)
        #expect(first.path.hasSuffix("/2026/Q-0001 Sample Client Pty Ltd.pdf"))
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: first)
        let second = SentArchive.freshURL(for: "Q-0001 Sample Client Pty Ltd.pdf", year: 2026, in: root)
        #expect(second.lastPathComponent == "Q-0001 Sample Client Pty Ltd (2).pdf")
    }

    @Test func theTaxExportNeverStartsAFieldWithAFormula() {
        #expect(csvText("=SUM(A1)") == "'=SUM(A1)")
        #expect(csvText("+61 400") == "'+61 400")
        #expect(csvText("@home, office") == "\"'@home, office\"")
        #expect(csvText("Sample Client") == "Sample Client")
    }
}
```

In `Tests/QuotePilotCoreTests/ToleranceAndMessagesTests.swift`, extend the error list in
`everyErrorHasAPlainMessage` with the new cases:

```swift
        let errors: [LibraryError] = [.notFound, .notDraft, .notSent, .notAccepted, .nothingAccepted,
                                      .nothingLeftToInvoice, .alreadyInvoiced, .isVoid, .hasPayments,
                                      .deductedByFinal("INV-0002"), .unknownLineCodes(["09"]),
                                      .notEditable, .noPayments, .paymentNotPositive,
                                      .paymentMoreThanOwing(Money(dollars: 300))]
```

and add after the existing `#expect` lines in that test:

```swift
        #expect(LibraryError.paymentMoreThanOwing(Money(dollars: 300)).message.contains("$300.00"))
```

- [ ] **Step 2: Run them to watch them fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter "AppRulesTests|ToleranceAndMessagesTests"`
Expected: build failure, `type 'LibraryError' has no member 'notEditable'`.

- [ ] **Step 3: New errors (`Library.swift`)**

Add to `enum LibraryError` after `case unknownLineCodes([String])`:

```swift
    /// Sent and void invoices are records; only drafts change.
    case notEditable
    case noPayments
    case paymentNotPositive
    /// More than the amount still owing (given).
    case paymentMoreThanOwing(Money)
```

- [ ] **Step 4: Safe invoice editing (`Library.swift`)**

Replace `update(_ invoice:)` with:

```swift
    /// Stores the editable parts of a draft invoice: title, dates, terms, lines and tax, and the client
    /// for a standalone invoice (one from a quote keeps the quote's client). Stage, payments, Sent
    /// dates, kind, quote, deposit share and deductions only change through their own actions, so an
    /// editor can never rewrite them. A deposit that a live final invoice subtracts keeps what it
    /// bills, or the final would deduct a different amount than the deposit asks for.
    public mutating func update(_ invoice: Invoice) throws {
        let index = try invoiceIndex(invoice.id)
        let old = invoices[index]
        if let final = liveFinalDeducting(old),
           invoice.lines != old.lines || invoice.taxed != old.taxed || invoice.depositPercent != old.depositPercent
            || invoice.number != old.number || invoice.stage != old.stage || invoice.kind != old.kind
            || invoice.quoteID != old.quoteID || invoice.deductions != old.deductions {
            throw LibraryError.deductedByFinal(final.number)
        }
        guard old.stage == .draft else { throw LibraryError.notEditable }
        var updated = old
        updated.title = invoice.title
        updated.issued = invoice.issued
        updated.due = invoice.due
        updated.terms = invoice.terms
        updated.lines = invoice.lines
        updated.taxed = invoice.taxed
        if old.quoteID == nil { updated.clientID = invoice.clientID }
        invoices[index] = updated
    }
```

- [ ] **Step 5: Payments, receipts and completing a job (`Invoicing.swift`)**

In `recordPayment(_:toInvoice:)`, after the `switch` on the stage, add:

```swift
        guard payment.amount > .zero else { throw LibraryError.paymentNotPositive }
        let owing = invoices[index].owing
        guard payment.amount <= owing else { throw LibraryError.paymentMoreThanOwing(owing) }
```

In `markReceiptSent(invoice:at:)`, after `let index = try invoiceIndex(id)`, add:

```swift
        guard !invoices[index].payments.isEmpty else { throw LibraryError.noPayments }
```

In `completeJob(quote:on:)`, replace

```swift
        quotes[index].completedOn = day
        log("Marked the job for \(found.number) complete", number: found.number)
```

with:

```swift
        if quotes[index].completedOn == nil {
            quotes[index].completedOn = day
            log("Marked the job for \(found.number) complete", number: found.number)
        }
```

- [ ] **Step 6: Acceptance needs a sent quote (`QuoteLifecycle.swift`)**

In `recordAcceptance(_:forQuote:)`, after `let index = try quoteIndex(id)`, add:

```swift
        guard quotes[index].stage != .draft else { throw LibraryError.notSent }
```

- [ ] **Step 7: Wording (`Messages.swift`)**

Change these three cases in `LibraryError.message`:

```swift
        case .notDraft:
            return "Only drafts can be deleted. A sent invoice can be voided instead, and a sent quote stays on record."
        case .notSent:
            return "This is still a draft, so it hasn't gone to the client. Send it first, or delete the draft instead."
```

```swift
        case .alreadyInvoiced:
            return "This quote already has invoices, so what the client accepted and what's billed are locked. Void its invoices first to change them."
```

Then add the new cases before the closing brace of the `switch`:

```swift
        case .notEditable:
            return "This invoice has been sent, so it can't be changed. Void it and draft a new one instead."
        case .noPayments:
            return "There are no payments on this invoice yet, so there's nothing to give a receipt for."
        case .paymentNotPositive:
            return "A payment has to be more than $0.00."
        case .paymentMoreThanOwing(let owing):
            return "That's more than the \(owing.formatted()) still owing on this invoice."
```

- [ ] **Step 8: Tolerant decoding for nested types (`Models.swift`)**

Add at the end of the `// MARK: - Tolerant decoding` section:

```swift
extension EmailTemplate {
    enum CodingKeys: String, CodingKey {
        case subject, body
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.value(.subject, or: "")
        body = try c.value(.body, or: "")
    }
}

extension EmailTemplates {
    enum CodingKeys: String, CodingKey {
        case quote, invoice, receipt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let standard = EmailTemplates.standard
        quote = try c.value(.quote, or: standard.quote)
        invoice = try c.value(.invoice, or: standard.invoice)
        receipt = try c.value(.receipt, or: standard.receipt)
    }
}

extension Acceptance {
    enum CodingKeys: String, CodingKey {
        case recordedAt, source, fileName, clientName, clientDate, accepted, declined
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        source = try c.decode(AcceptanceSource.self, forKey: .source)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        clientName = try c.value(.clientName, or: "")
        clientDate = try c.value(.clientDate, or: "")
        accepted = try c.value(.accepted, or: [])
        declined = try c.value(.declined, or: [])
    }
}

extension Payment {
    enum CodingKeys: String, CodingKey {
        case id, date, amount, method, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Day.self, forKey: .date)
        amount = try c.decode(Money.self, forKey: .amount)
        method = try c.value(.method, or: .bankTransfer)
        note = try c.value(.note, or: "")
    }
}

extension Deduction {
    enum CodingKeys: String, CodingKey {
        case label, invoiceNumber, amount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.value(.label, or: "Less deposit")
        invoiceNumber = try c.decode(String.self, forKey: .invoiceNumber)
        amount = try c.decode(Money.self, forKey: .amount)
    }
}

extension ActivityEntry {
    enum CodingKeys: String, CodingKey {
        case id, at, number, message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        at = try c.decode(Date.self, forKey: .at)
        number = try c.decodeIfPresent(String.self, forKey: .number)
        message = try c.value(.message, or: "")
    }
}
```

- [ ] **Step 9: Mail wording (`MailDraft.swift`)**

```swift
import Foundation

/// What a Mail draft says: who it's to, the subject and the body, filled in from the brand's email
/// wording. The app adds the PDF; you press Send.
public struct MailDraft: Equatable, Sendable {
    /// The client's email, trimmed. Empty when the client has none yet.
    public var to: String
    public var subject: String
    public var body: String

    public init(to: String, subject: String, body: String) {
        self.to = to
        self.subject = subject
        self.body = body
    }
}

extension Library {
    public func mailDraft(forQuote id: UUID) -> MailDraft? {
        guard let quote = quote(id) else { return nil }
        return mailDraft(brand.emails.quote, client: client(quote.clientID), number: quote.number,
                         amount: quote.totals.total, due: quote.validUntil)
    }

    public func mailDraft(forInvoice id: UUID) -> MailDraft? {
        guard let invoice = invoice(id) else { return nil }
        return mailDraft(brand.emails.invoice, client: client(invoice.clientID), number: invoice.number,
                         amount: invoice.amount, due: invoice.due)
    }

    public func mailDraft(forReceipt id: UUID) -> MailDraft? {
        guard let invoice = invoice(id) else { return nil }
        return mailDraft(brand.emails.receipt, client: client(invoice.clientID), number: invoice.number,
                         amount: invoice.paid, due: invoice.due)
    }

    /// Fills {client}, {contact}, {number}, {amount}, {due} and {business}.
    private func mailDraft(_ template: EmailTemplate, client: Client?, number: String, amount: Money, due: Day) -> MailDraft {
        let filled = template.filled([
            "client": client?.name ?? "",
            "contact": client?.greetingName ?? "there",
            "number": number,
            "amount": amount.formatted(currencyCode: brand.currencyCode),
            "due": due.long,
            "business": brand.businessName,
        ])
        return MailDraft(to: (client?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                         subject: filled.subject, body: filled.body)
    }
}
```

- [ ] **Step 10: The sent-PDF archive (`SentArchive.swift`)**

```swift
import Foundation

/// Where a copy of every mailed PDF is kept: `~/Documents/Quote Pilot/<year>/` (spec §2), a record of
/// exactly what each client received.
public enum SentArchive {
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quote Pilot", isDirectory: true)
    }

    /// A file in `root/<year>/` that doesn't exist yet: the name itself, then "… (2).pdf", "… (3).pdf",
    /// so sending a document again never overwrites what went before.
    public static func freshURL(for fileName: String, year: Int, in root: URL) -> URL {
        let folder = root.appendingPathComponent(String(year), isDirectory: true)
        let name = fileName as NSString
        let base = name.deletingPathExtension
        let suffix = name.pathExtension.isEmpty ? "" : "." + name.pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var copy = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(copy))\(suffix)")
            copy += 1
        }
        return candidate
    }
}
```

- [ ] **Step 11: The CSV formula guard (`Dashboard.swift`)**

In `paymentsCSV(for:)`, replace

```swift
            return [payment.date.iso, client(invoice.clientID)?.name ?? "", invoice.number,
                    payment.amount.plain, payment.method.label, payment.note]
                .map(csvField)
                .joined(separator: ",")
```

with:

```swift
            return [csvField(payment.date.iso), csvText(client(invoice.clientID)?.name ?? ""),
                    csvField(invoice.number), csvField(payment.amount.plain), csvField(payment.method.label),
                    csvText(payment.note)]
                .joined(separator: ",")
```

and add after `csvField(_:)`:

```swift
/// Text someone typed, made safe for a spreadsheet: a field starting with =, +, - or @ would run as
/// a formula, so it gets a leading apostrophe.
func csvText(_ text: String) -> String {
    guard let first = text.first, "=+-@".contains(first) else { return csvField(text) }
    return csvField("'" + text)
}
```

- [ ] **Step 12: Run the tests**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter "AppRulesTests|ToleranceAndMessagesTests"`
Expected: all pass.

- [ ] **Step 13: Run everything and commit**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test`
Expected: everything passes, including every plan 1 and plan 2a test. If an older test relied on
editing a sent invoice or on a zero payment, say which in the report: the new rule wins (spec §5,
§6), so fix the test's setup, not the rule.

```bash
git add Sources/QuotePilotCore Tests/QuotePilotCoreTests
git commit -m "Core rules for the editors: safe invoice edits, payment checks, mail wording, the PDF archive

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: PDF checks: is the form there, and which quote is a flattened PDF?

Two facts the Mail and returned-quote steps need from a PDF. Is a quote's tick-box form really in it?
A release build otherwise sends a form-less quote silently. And which quote does a returned PDF
belong to, when the client's app flattened the form away? Quote Pilot writes the number into the
PDF's keywords, and those usually survive.

**Files:**
- Modify: `Sources/QuotePilotPDF/DocumentRenderer.swift` (add `hasForm(_:quoteNumber:)`)
- Modify: `Sources/QuotePilotPDF/ReturnedQuoteReader.swift` (add `quoteNumber(inMetadataOf:)`)
- Test: `Tests/QuotePilotPDFTests/FlattenedAndFormCheckTests.swift`

**Interfaces:**
- Consumes: `DocumentRenderer.render`, `QuoteFormFields.acceptAll(_:)`, the test helper `Sample`.
- Produces: `DocumentRenderer.hasForm(_ data: Data, quoteNumber: String) -> Bool` and
  `ReturnedQuoteReader.quoteNumber(inMetadataOf data: Data) -> String?`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotPDFTests/FlattenedAndFormCheckTests.swift`:

```swift
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

@Suite struct FlattenedAndFormCheckTests {
    func quotePDF() -> Data {
        DocumentRenderer.render(.quote(Sample.quote(), client: Sample.client, brand: Sample.brand), style: PDFStyle())
    }

    /// Draws page 1 into a new PDF, the way printing to PDF does, keeping only the info given.
    func flattened(_ data: Data, info: [CFString: Any]? = nil) -> Data {
        let document = PDFDocument(data: data)!
        let flat = NSMutableData()
        var box = CGRect(origin: .zero, size: PageWriter.pageSize)
        let context = CGContext(consumer: CGDataConsumer(data: flat as CFMutableData)!, mediaBox: &box,
                                info as CFDictionary?)!
        context.beginPDFPage(nil)
        document.page(at: 0)!.draw(with: .mediaBox, to: context)
        context.endPDFPage()
        context.closePDF()
        return flat as Data
    }

    @Test func aRenderedQuoteHasItsForm() {
        #expect(DocumentRenderer.hasForm(quotePDF(), quoteNumber: "Q-0001"))
        #expect(!DocumentRenderer.hasForm(quotePDF(), quoteNumber: "Q-0002"))
    }

    @Test func aFlattenedQuoteOrAnInvoiceHasNone() {
        #expect(!DocumentRenderer.hasForm(flattened(quotePDF()), quoteNumber: "Q-0001"))
        let invoice = DocumentRenderer.render(.invoice(Sample.invoice(.standalone), client: Sample.client,
                                                       brand: Sample.brand, quoteNumber: nil), style: PDFStyle())
        #expect(!DocumentRenderer.hasForm(invoice, quoteNumber: "Q-0001"))
        #expect(!DocumentRenderer.hasForm(Data("hello".utf8), quoteNumber: "Q-0001"))
    }

    @Test func theQuoteNumberComesFromTheKeywords() {
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: quotePDF()) == "Q-0001")
        let kept = flattened(quotePDF(), info: [kCGPDFContextKeywords: ["quotepilot", "Q-0001"]])
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: kept) == "Q-0001")
    }

    @Test func aPDFWithoutQuotePilotKeywordsNamesNoQuote() {
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: flattened(quotePDF())) == nil)
        let other = flattened(quotePDF(), info: [kCGPDFContextKeywords: ["Q-0001"]])
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: other) == nil)
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: Data("hello".utf8)) == nil)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter FlattenedAndFormCheckTests`
Expected: build failure, `type 'DocumentRenderer' has no member 'hasForm'`.

- [ ] **Step 3: Add `hasForm` (`DocumentRenderer.swift`)**

Add at the end of the file:

```swift
extension DocumentRenderer {
    /// True when quote PDF data carries its fillable form: the catalog's AcroForm and the quote's
    /// Accept-all box. Checked before a quote goes into a Mail draft, so a form-less quote is never
    /// sent by accident.
    public static func hasForm(_ data: Data, quoteNumber: String) -> Bool {
        guard data.range(of: Data("/AcroForm".utf8)) != nil, let document = PDFDocument(data: data) else { return false }
        let acceptAll = QuoteFormFields.acceptAll(quoteNumber)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if page.annotations.contains(where: { $0.fieldName == acceptAll }) { return true }
        }
        return false
    }
}
```

- [ ] **Step 4: Add `quoteNumber(inMetadataOf:)` (`ReturnedQuoteReader.swift`)**

Add inside `enum ReturnedQuoteReader`:

```swift
    /// The quote number a Quote Pilot PDF carries in its keywords ("quotepilot", "Q-0007"). That
    /// usually survives when a PDF app flattens the form away, so a flattened quote can still be
    /// matched to its quote for hand-ticking. Nil when the keywords aren't Quote Pilot's.
    public static func quoteNumber(inMetadataOf data: Data) -> String? {
        guard let document = PDFDocument(data: data),
              let value = document.documentAttributes?[PDFDocumentAttribute.keywordsAttribute]
        else { return nil }
        let keywords: [String]
        if let list = value as? [String] {
            keywords = list
        } else if let text = value as? String {
            keywords = text.components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty }
        } else {
            return nil
        }
        guard keywords.contains(where: { $0.caseInsensitiveCompare("quotepilot") == .orderedSame }) else { return nil }
        return keywords.first { $0.uppercased().hasPrefix("Q-") }
    }
```

- [ ] **Step 5: Run the tests**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter FlattenedAndFormCheckTests`
Expected: all four pass. If PDFKit hands the keywords back in another shape (a single string joined
another way), adapt the parsing, keep the tests as they are, and say so in the report.

- [ ] **Step 6: Run everything and commit**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotPDF Tests/QuotePilotPDFTests/FlattenedAndFormCheckTests.swift
git commit -m "PDF checks: is a quote's form there, and which quote a flattened PDF belongs to

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Mail drafts and "Did you send it?"

Send by Mail does the following:
1. It saves the PDF to `~/Documents/Quote Pilot/<year>/`.
2. It opens a Mail draft with the client's address, the brand's wording and the PDF attached.
3. It asks "Did you send it?". **Yes** marks the document Sent; **Not Yet** changes nothing.

If the client has no email, it asks for one first. If Mail can't open a draft, the PDF is shown in
Finder and the message goes to the clipboard.

This task also adds the dialog overlay that later dialogs reuse.

**Files:**
- Create: `Sources/QuotePilotUI/App/MailComposer.swift`
- Create: `Sources/QuotePilotUI/App/AppModel+Mail.swift`
- Create: `Sources/QuotePilotUI/App/Dialogs.swift`
- Modify: `Sources/QuotePilotUI/App/AppModel.swift` (stored `mail`, `sentFolder`, `dialog`; init
  parameters)
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (show dialogs; toolbar Send)
- Modify: `Sources/QuotePilotUI/App/Commands.swift` (⌘S)
- Modify: `Sources/QuotePilotUI/Screens/QuoteEditorView.swift` (a Send by Mail button)
- Modify: `Sources/QuotePilotUI/Screens/BrandView.swift` (the Emails tab's note)
- Modify: `Resources/Info.plist` (why Quote Pilot uses the Documents folder)
- Modify: `Tests/QuotePilotUITests/UIFixture.swift` (a fake Mail; a temporary sent folder)
- Test: `Tests/QuotePilotUITests/MailTests.swift`

**Interfaces:**
- Consumes:
  - core: `Library.mailDraft(forQuote:/forInvoice:/forReceipt:)` and `SentArchive.freshURL` (Task 1);
  - PDF: `DocumentRenderer.hasForm` (Task 2) and `DocumentContent.receipt`;
  - plan 2a: `MessageBox`, `TitleBar`, `Win95FieldRow`, `Win95TextField`.
- Produces:
  - **Mail:**
    - `protocol MailComposer` with `compose(to:subject:body:attachment:) -> Bool` and
      `setAside(message:attachment:)`; `SystemMailComposer`;
    - `MailDocument` (`.quote(UUID)`, `.invoice(UUID)`, `.receipt(UUID)`).
  - **AppModel properties:** `AppModel.dialog: Dialog?`, `AppModel.mail` and `AppModel.sentFolder`.
    The init gains `mail:` and `sentFolder:` with defaults.
  - **AppModel actions:** `AppModel.send(_:)`, `AppModel.sendableDocument`,
    `AppModel.saveEmailAndSend(_:clientID:document:)` and `AppModel.looksLikeEmail(_:)`.
  - **Dialogs:** `Dialog` (`.emailPrompt(clientID:document:)` for now), `DialogPanel(title:icon:content:)`,
    `DialogOverlay` and `EmailPromptView`.
  - **Tests:** `FakeMail` in `UIFixture.swift`.

- [ ] **Step 1: Give the test fixture a fake Mail**

In `Tests/QuotePilotUITests/UIFixture.swift`, add:

```swift
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
```

and change `UIFixture.model(_:folder:)` so no test ever opens the real Mail or writes to the real
Documents folder:

```swift
    /// A model on its own temporary folder, starting from `library` when one is given. Mail is a fake
    /// and mailed PDFs go to a temporary folder.
    @MainActor
    static func model(_ library: Library? = nil, folder: URL = makeFolder(), mail: FakeMail = FakeMail()) throws -> AppModel {
        let store = LibraryStore(folder: folder)
        if let library { try store.save(library) }
        return AppModel(store: store, now: { today.date() }, mail: mail, sentFolder: makeFolder())
    }
```

`sampleModel()` calls `model(_:)` and so picks this up. Give it the same `mail:` parameter and pass it
through:

```swift
    @MainActor
    static func sampleModel(mail: FakeMail = FakeMail()) throws -> AppModel {
        try model(SampleLibrary.make(today: today, now: today.date()), mail: mail)
    }
```

- [ ] **Step 2: Write the failing tests**

`Tests/QuotePilotUITests/MailTests.swift`:

```swift
import Foundation
import PDFKit
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct MailTests {
    /// The sample business's draft quote Q-0004, for Example Bakery (alex@example.com).
    func draftQuote(_ model: AppModel) throws -> UUID {
        try #require(model.library.quote(number: "Q-0004")?.id)
    }

    @Test func sendingAQuoteOpensADraftWithItsPDF() throws {
        let mail = FakeMail()
        let model = try UIFixture.sampleModel(mail: mail)
        let id = try draftQuote(model)
        model.send(.quote(id))
        let draft = try #require(mail.drafts.first)
        #expect(draft.to == "alex@example.com")
        #expect(draft.subject == "Quote Q-0004 from Sample Studio")
        #expect(draft.body.hasPrefix("Hi Alex,"))
        #expect(draft.attachment.path.hasPrefix(model.sentFolder.path))
        #expect(draft.attachment.deletingLastPathComponent().lastPathComponent == "2026")
        let data = try Data(contentsOf: draft.attachment)
        #expect(DocumentRenderer.hasForm(data, quoteNumber: "Q-0004"))
        #expect(model.message?.title == "Did You Send It?")
        #expect(model.library.quote(id)?.stage == .draft)
        #expect(model.library.activity.first?.message.hasPrefix("Opened a Mail draft of quote Q-0004") == true)
    }

    @Test func yesMarksItSent() throws {
        let model = try UIFixture.sampleModel()
        let id = try draftQuote(model)
        model.send(.quote(id))
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first(where: \.isDefault)))
        #expect(model.library.quote(id)?.stage == .sent)
        #expect(model.library.quote(id)?.sentAt != nil)
    }

    @Test func notYetChangesNothing() throws {
        let model = try UIFixture.sampleModel()
        let id = try draftQuote(model)
        let before = try #require(model.library.quote(id))
        model.send(.quote(id))
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first(where: \.isCancel)))
        #expect(model.library.quote(id) == before)
    }

    @Test func aMissingEmailIsAskedForFirst() throws {
        let mail = FakeMail()
        var library = try SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date())
        let bakery = try #require(library.clients.firstIndex { $0.name == "Example Bakery" })
        library.clients[bakery].email = ""
        let model = try UIFixture.model(library, mail: mail)
        let id = try draftQuote(model)
        model.send(.quote(id))
        #expect(mail.drafts.isEmpty)
        guard case .emailPrompt(let clientID, let document) = model.dialog else {
            Issue.record("Expected the email prompt")
            return
        }
        #expect(!AppModel.looksLikeEmail("not an email"))
        model.saveEmailAndSend("orders@example.com", clientID: clientID, document: document)
        #expect(model.dialog == nil)
        #expect(model.library.client(clientID)?.email == "orders@example.com")
        #expect(mail.drafts.first?.to == "orders@example.com")
    }

    @Test func whenMailIsntAvailableThePDFAndMessageAreSetAside() throws {
        let mail = FakeMail()
        mail.available = false
        let model = try UIFixture.sampleModel(mail: mail)
        model.send(.quote(try draftQuote(model)))
        let aside = try #require(mail.setAside.first)
        #expect(aside.message.contains("Subject: Quote Q-0004 from Sample Studio"))
        #expect(aside.message.contains("To: alex@example.com"))
        #expect(model.message?.text.contains("clipboard") == true)
    }

    @Test func receiptsNeedAPaymentAndVoidInvoicesCantBeSent() throws {
        let mail = FakeMail()
        var library = try SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date())
        let care = try #require(library.invoices.first { $0.number == "INV-0002" })
        let model = try UIFixture.model(library, mail: mail)
        model.send(.receipt(care.id))
        #expect(mail.drafts.isEmpty)
        #expect(model.message?.text == LibraryError.noPayments.message)

        try library.voidInvoice(care.id)
        let voided = try UIFixture.model(library, mail: mail)
        voided.send(.invoice(care.id))
        #expect(mail.drafts.isEmpty)
        #expect(voided.message?.text == LibraryError.isVoid.message)
    }

    @Test func theEmailPromptDraws() throws {
        let model = try UIFixture.sampleModel()
        let client = try #require(model.library.clients.first)
        model.dialog = .emailPrompt(clientID: client.id, document: .quote(model.library.quotes[3].id))
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "email-prompt")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 3: Run them to watch them fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter MailTests`
Expected: build failure, `cannot find type 'MailComposer' in scope`.

- [ ] **Step 4: Write `MailComposer.swift`**

```swift
import AppKit
import Foundation

/// Opens Mail drafts. Quote Pilot never sends anything: you press Send in Mail (spec §8).
public protocol MailComposer {
    /// Opens a new message with the PDF attached. False when the compose service isn't available.
    func compose(to: String, subject: String, body: String, attachment: URL) -> Bool
    /// When Mail can't open a draft: show the PDF in Finder and put the message on the clipboard.
    func setAside(message: String, attachment: URL)
}

/// macOS's own "compose email" share service.
public struct SystemMailComposer: MailComposer {
    public init() {}

    public func compose(to: String, subject: String, body: String, attachment: URL) -> Bool {
        guard let service = NSSharingService(named: .composeEmail) else { return false }
        service.recipients = to.isEmpty ? [] : [to]
        service.subject = subject
        let items: [Any] = [body as NSString, attachment as NSURL]
        guard service.canPerform(withItems: items) else { return false }
        service.perform(withItems: items)
        return true
    }

    public func setAside(message: String, attachment: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([attachment])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
    }
}

/// A document that goes out by Mail.
public enum MailDocument: Equatable, Hashable {
    case quote(UUID)
    case invoice(UUID)
    case receipt(UUID)
}
```

- [ ] **Step 5: Give `AppModel` its Mail and dialog state (`AppModel.swift`)**

Add these stored properties beside `pendingExport`:

```swift
    /// The dialog panel showing over the window, if any (the email prompt, the acceptance review…).
    public var dialog: Dialog?
    /// Opens Mail drafts; tests use a fake.
    @ObservationIgnored public let mail: any MailComposer
    /// Where copies of mailed PDFs go: `~/Documents/Quote Pilot`, or a temporary folder in tests.
    @ObservationIgnored public let sentFolder: URL
```

and change the initializer's signature and first lines to:

```swift
    public init(store: LibraryStore, now: @escaping () -> Date = Date.init,
                mail: any MailComposer = SystemMailComposer(), sentFolder: URL = SentArchive.defaultFolder) {
        self.store = store
        self.now = now
        self.mail = mail
        self.sentFolder = sentFolder
```

(the rest of the initializer is unchanged).

- [ ] **Step 6: Write `AppModel+Mail.swift`**

```swift
import Foundation
import QuotePilotCore
import QuotePilotPDF

extension AppModel {
    /// What ⌘S sends: the open quote on Quotes, the selected invoice on Invoices.
    public var sendableDocument: MailDocument? {
        switch section {
        case .quotes: return (openQuoteID ?? selectedQuoteID).map(MailDocument.quote)
        case .invoices: return selectedInvoiceID.map(MailDocument.invoice)
        default: return nil
        }
    }

    /// Saves the PDF to the sent folder, opens a Mail draft, then asks "Did you send it?". Yes marks
    /// the document Sent; Not Yet changes nothing.
    public func send(_ document: MailDocument) {
        guard loadState == .ready else { return }
        // What can't be sent says so before anything is written.
        switch document {
        case .quote:
            break
        case .invoice(let id):
            if library.invoice(id)?.stage == .void { return show(LibraryError.isVoid, title: "Can't Send") }
        case .receipt(let id):
            if library.invoice(id)?.payments.isEmpty ?? true { return show(LibraryError.noPayments, title: "Can't Send") }
        }
        guard let parts = mailParts(document) else { return }
        let (number, what, draft, content) = (parts.number, parts.what, parts.draft, parts.content)
        guard let clientID = parts.clientID else {
            return show(title: "No Client", text: "\(what.capitalizedFirst) \(number) has no client yet. Choose one first.", kind: .warning)
        }
        guard !draft.to.isEmpty else {
            dialog = .emailPrompt(clientID: clientID, document: document)
            return
        }
        let data = pdf(content)
        if case .quote = document, !DocumentRenderer.hasForm(data, quoteNumber: number) {
            return show(title: "Quote Not Sent",
                        text: "Quote Pilot couldn't add the tick boxes to \(number)'s PDF, so it isn't safe to send. Nothing was changed.",
                        kind: .warning)
        }
        let url = SentArchive.freshURL(for: content.fileName, year: today.year, in: sentFolder)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return show(error, title: "Couldn't save the PDF to send")
        }

        let question: String
        if mail.compose(to: draft.to, subject: draft.subject, body: draft.body, attachment: url) {
            change("Couldn't note the Mail draft") { $0.log("Opened a Mail draft of \(what) \(number) to \(draft.to)", number: number) }
            question = "Quote Pilot opened a Mail draft of \(what) \(number) to \(draft.to). Did you send it?"
        } else {
            mail.setAside(message: "To: \(draft.to)\nSubject: \(draft.subject)\n\n\(draft.body)", attachment: url)
            change("Couldn't note the Mail problem") {
                $0.log("Mail couldn't open a draft of \(what) \(number); the PDF and message were set aside", number: number)
            }
            question = "Mail couldn't open a draft. The PDF is shown in Finder and the message is on the clipboard, ready to paste into any email app. Did you send \(what) \(number)?"
        }
        message = MessageBox(kind: .question, title: "Did You Send It?", text: question, choices: [
            MessageBox.Choice("Yes, Sent", isDefault: true) { self.markSent(document) },
            MessageBox.Choice("Not Yet", isCancel: true),
        ])
    }

    /// Saves the client's email, then carries on sending.
    public func saveEmailAndSend(_ email: String, clientID: UUID, document: MailDocument) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppModel.looksLikeEmail(trimmed), var client = library.client(clientID) else {
            return show(title: "Email Address", text: "That doesn't look like an email address.", kind: .warning)
        }
        client.email = trimmed
        updateClient(client)
        guard library.client(clientID)?.email == trimmed else { return }
        dialog = nil
        send(document)
    }

    /// One "@", something before it, and a dot after it, with no spaces.
    public static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
            && !text.contains(where: \.isWhitespace)
    }

    private func markSent(_ document: MailDocument) {
        switch document {
        case .quote(let id): change("Couldn't mark it sent") { try $0.markSent(quote: id, at: now()) }
        case .invoice(let id): change("Couldn't mark it sent") { try $0.markSent(invoice: id, at: now()) }
        case .receipt(let id): change("Couldn't mark it sent") { try $0.markReceiptSent(invoice: id, at: now()) }
        }
    }

    /// The number, a word for it, its client, the Mail wording and the PDF content.
    private func mailParts(_ document: MailDocument)
        -> (number: String, what: String, clientID: UUID?, draft: MailDraft, content: DocumentContent)? {
        switch document {
        case .quote(let id):
            guard let quote = library.quote(id), let draft = library.mailDraft(forQuote: id),
                  let content = quoteContent(id) else { return nil }
            return (quote.number, "quote", quote.clientID, draft, content)
        case .invoice(let id):
            guard let invoice = library.invoice(id), let draft = library.mailDraft(forInvoice: id),
                  let content = invoiceContent(id) else { return nil }
            return (invoice.number, "invoice", invoice.clientID, draft, content)
        case .receipt(let id):
            guard let invoice = library.invoice(id), let draft = library.mailDraft(forReceipt: id) else { return nil }
            let content = DocumentContent.receipt(invoice, client: library.client(invoice.clientID), brand: library.brand)
            return (invoice.number, "the receipt for", invoice.clientID, draft, content)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
```

`now` is `private` in `AppModel.swift`. Change it to `let now: () -> Date` (internal), so this
extension in another file can use it.

- [ ] **Step 7: Write `Dialogs.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// The dialog panels Quote Pilot draws over the window. Later tasks add cases.
public enum Dialog: Equatable {
    /// The client has no email yet: ask for it, then carry on sending `document`.
    case emailPrompt(clientID: UUID, document: MailDocument)
}

/// A Windows 95 dialog: navy title bar, grey body, bevelled edge.
struct DialogPanel<Content: View>: View {
    let title: String
    let icon: PixelIcon
    let width: CGFloat
    let content: Content

    init(title: String, icon: PixelIcon, width: CGFloat = 440, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title, icon: icon)
                .padding(2)
            content
                .padding(14)
        }
        .frame(width: width)
        .background(Win95.face)
        .overlay(Bevel(.raised))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Shows the current dialog over the window; the window behind can't be clicked meanwhile.
struct DialogOverlay: View {
    let model: AppModel
    let dialog: Dialog

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
            switch dialog {
            case .emailPrompt(let clientID, let document):
                EmailPromptView(model: model, clientID: clientID, document: document)
            }
        }
    }
}

/// "Quote Pilot needs this client's email address."
struct EmailPromptView: View {
    let model: AppModel
    let clientID: UUID
    let document: MailDocument
    @State private var email = ""

    var body: some View {
        let name = model.library.client(clientID)?.name ?? "this client"
        DialogPanel(title: "Client's Email", icon: .mail) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quote Pilot needs \(name)'s email address to start the Mail draft. It's saved to the client for next time.")
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .fixedSize(horizontal: false, vertical: true)
                Win95FieldRow("Email:", labelWidth: 50) {
                    Win95TextField("Email", text: $email, prompt: "name@example.com")
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Save and Continue") {
                        model.saveEmailAndSend(email, clientID: clientID, document: document)
                    }
                    .buttonStyle(.win95Default)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!AppModel.looksLikeEmail(email.trimmingCharacters(in: .whitespacesAndNewlines)))
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
```

- [ ] **Step 8: Show dialogs in `RootView.swift`**

Replace `messageOverlay` with:

```swift
    /// The dialog, if one is open, with any message box above it.
    @ViewBuilder
    private var messageOverlay: some View {
        ZStack {
            if let dialog = model.dialog {
                DialogOverlay(model: model, dialog: dialog)
            }
            if let box = model.message {
                ZStack {
                    // As with a Windows 95 message box, the window behind stays visible but can't be clicked.
                    Color.white.opacity(0.001)
                    MessageBoxView(box: box) { model.respond($0) }
                }
            }
        }
    }
```

In `Win95Toolbar`, replace the Send button line with:

```swift
                tool("Send", .mail, help: "Open a Mail draft of the open quote or invoice (⌘S)",
                     enabled: model.sendableDocument != nil) {
                    if let document = model.sendableDocument { model.send(document) }
                }
```

Dialogs must be modal just as message boxes are (plan 2a Task 6's fix round). Make three changes:
- In `AppModel.whenFree(_:)`, run the action only when `message == nil && dialog == nil`.
- In `RootView`, change each `.disabled(model.message != nil)` to
  `.disabled(model.message != nil || model.dialog != nil)`.
- Every menu item this plan adds goes through `model.whenFree { … }`, as plan 2a's do. That covers
  Send by Mail…, Read Returned Quote…, New Invoice, Find… and the File menu items.

Add to `MailTests`:

```swift
    @Test func anOpenDialogBlocksMenuCommands() throws {
        let model = try UIFixture.sampleModel()
        model.dialog = .emailPrompt(clientID: model.library.clients[0].id, document: .quote(model.library.quotes[3].id))
        var ran = false
        model.whenFree { ran = true }
        #expect(!ran)
    }
```

- [ ] **Step 9: ⌘S (`Commands.swift`) and the editor's button (`QuoteEditorView.swift`)**

In `QuotePilotCommands.body`, inside `CommandGroup(replacing: .printItem)` before `Save PDF…`, add:

```swift
            Button("Send by Mail…") {
                if let document = model.sendableDocument {
                    model.send(document)
                } else {
                    model.show(title: "Send by Mail", text: "Open a quote or select an invoice first.")
                }
            }
            .keyboardShortcut("s")
```

Writing into `~/Documents` makes macOS ask once for permission to use the Documents folder. The
project's rule is that every permission explains itself. In `Resources/Info.plist`, add inside the
`<dict>`:

```xml
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Quote Pilot keeps a copy of every PDF you send by Mail in Documents › Quote Pilot, so you have a record of exactly what each client received.</string>
```

If the write is refused (permission denied), `send` already shows the error in a message box and
opens nothing. Leave it at that.

In `BrandView.swift`'s `EmailsTab`, the banner says Mail drafts arrive in the next build. Change it to:
"Quote Pilot fills in {client}, {contact}, {number}, {amount}, {due} and {business}. Send by Mail opens a
draft with the PDF attached, and you always press Send yourself."

In `QuoteEditorView.header(_:)`, add before the Duplicate button:

```swift
            Button("Send by Mail…") { model.send(.quote(quoteID)) }
                .buttonStyle(.win95Default)
                .help("Open a Mail draft with this quote attached (⌘S)")
```

- [ ] **Step 10: Run the tests and look at the prompt**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter MailTests`
Expected: all eight tests pass. Look at `build/snapshots/email-prompt.png`: a centred dialog with a
navy title, the sentence, a sunken email field, and Save and Continue (greyed while the field is
empty) beside Cancel.

- [ ] **Step 11: Run everything and commit**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests Resources/Info.plist
git commit -m "Send by Mail: a draft with the PDF, a saved copy, and Did you send it?

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Returned quotes: the acceptance review, hand-ticking, and dropping a PDF on the window

Drop a returned quote anywhere on the window, or choose File → Read Returned Quote… (⌘O). Quote
Pilot finds the quote from the form itself. It then shows every line as the PDF reported it, which
you can change, with the accepted total and the client's name and date.

Confirming records the acceptance. On a 50/50 quote it also drafts the deposit invoice and opens it.
A flattened PDF offers hand-ticking, and so does **Record Acceptance…** on any sent quote. A PDF for
another quote, or with lines the quote doesn't have, changes nothing.

**Files:**
- Create: `Sources/QuotePilotUI/App/AppModel+Acceptance.swift`
- Create: `Sources/QuotePilotUI/Screens/AcceptanceReviewView.swift`
- Modify: `Sources/QuotePilotUI/App/Dialogs.swift` (the `.acceptance` dialog)
- Modify: `Sources/QuotePilotUI/App/AppModel.swift` (stored `choosingFile`)
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (drop target, file chooser, toolbar Read Reply)
- Modify: `Sources/QuotePilotUI/App/Commands.swift` (⌘O)
- Modify: `Sources/QuotePilotUI/Screens/QuoteEditorView.swift` (Record Acceptance… button)
- Modify: `Tests/QuotePilotUITests/UIFixture.swift` (`fill`, `flattened`)
- Test: `Tests/QuotePilotUITests/AcceptanceTests.swift`

**Interfaces:**
- Consumes:
  - PDF: `ReturnedQuoteReader.read(_:)`, `ReturnedQuoteReader.quoteNumber(inMetadataOf:)` (Task 2),
    `ReturnedQuoteError`;
  - core: `Quote.proposal(from:today:)`, `AcceptanceProposal`, `Library.recordAcceptance` (sent
    quotes only, Task 1), `draftNextInvoice`;
  - `Dialog`, `DialogPanel` and `DialogOverlay` (Task 3).
- Produces:
  - `AcceptanceReview` (with `Line`) and `AcceptanceReviewView`; `Dialog.acceptance(AcceptanceReview)`.
  - `AppModel.readReturnedQuote(at:)`, `AppModel.startHandTicking(_:fileName:)` and
    `AppModel.confirmAcceptance(_:)`.
  - `FileChoice` (`.returnedQuote` for now), `AppModel.choosingFile` and `AppModel.fileChosen(_:)`.
  - Test helpers: `UIFixture.fill(_:ticking:acceptAll:name:date:)` and
    `UIFixture.flattened(_:keepingKeywords:)`.

- [ ] **Step 1: Test helpers for returned PDFs (`UIFixture.swift`)**

Add `import PDFKit` and `import QuotePilotPDF` to the top of the file, then inside `enum UIFixture`:

```swift
    /// Fills a quote PDF's form the way a client's PDF app would, then saves it.
    static func fill(_ data: Data, ticking codes: [String] = [], acceptAll: Bool = false,
                     name: String = "", date: String = "") -> Data {
        let document = PDFDocument(data: data)!
        for index in 0..<document.pageCount {
            for widget in document.page(at: index)!.annotations {
                switch widget.fieldName.flatMap({ QuoteFormFields.parse($0) })?.part {
                case .line(let code)? where codes.contains(code): widget.buttonWidgetState = .onState
                case .all? where acceptAll: widget.buttonWidgetState = .onState
                case .name?: widget.widgetStringValue = name
                case .date?: widget.widgetStringValue = date
                default: break
                }
            }
        }
        return document.dataRepresentation()!
    }

    /// Redraws page 1 into a new PDF, the way printing to PDF does: the form is gone. Keeps Quote
    /// Pilot's keywords when asked, as most PDF apps do.
    static func flattened(_ data: Data, keepingKeywords: Bool) -> Data {
        let document = PDFDocument(data: data)!
        let page = document.page(at: 0)!
        let keywords = document.documentAttributes?[PDFDocumentAttribute.keywordsAttribute]
        let info: [CFString: Any]? = keepingKeywords ? [kCGPDFContextKeywords: keywords as Any] : nil
        let flat = NSMutableData()
        var box = page.bounds(for: .mediaBox)
        let context = CGContext(consumer: CGDataConsumer(data: flat as CFMutableData)!, mediaBox: &box,
                                info as CFDictionary?)!
        context.beginPDFPage(nil)
        page.draw(with: .mediaBox, to: context)
        context.endPDFPage()
        context.closePDF()
        return flat as Data
    }
```

- [ ] **Step 2: Write the failing tests**

`Tests/QuotePilotUITests/AcceptanceTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct AcceptanceTests {
    /// The sample's sent quote Q-0002 (01 Menu board design $450, 02 Printing 2 × $85), as the
    /// client sends it back.
    func returned(_ model: AppModel, ticking codes: [String], acceptAll: Bool = false) throws -> URL {
        let quote = try #require(model.library.quote(number: "Q-0002"))
        let data = model.pdf(try #require(model.quoteContent(quote.id)))
        return try UIFixture.file("Q-0002 returned.pdf",
                                  UIFixture.fill(data, ticking: codes, acceptAll: acceptAll, name: "Alex Sample", date: "16/10/2026"))
    }

    func review(_ model: AppModel) throws -> AcceptanceReview {
        guard case .acceptance(let review) = model.dialog else {
            Issue.record("Expected the acceptance review, found \(String(describing: model.dialog))")
            throw CancellationError()
        }
        return review
    }

    @Test func aReturnedPDFOpensTheReviewAndChangesNothingYet() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: ["01"]))
        let review = try review(model)
        #expect(review.accepted == ["01"])
        #expect(review.declined == ["02"])
        #expect(review.clientName == "Alex Sample")
        #expect(review.clientDate == "16/10/2026")
        #expect(review.source == .returnedPDF)
        #expect(review.fileName == "Q-0002 returned.pdf")
        #expect(review.canBeConfirmed)
        #expect(model.library.quote(number: "Q-0002")?.stage == .sent)
        #expect(model.openQuoteID == review.quoteID)
    }

    @Test func confirmingRecordsItAndOpensTheDeposit() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: [], acceptAll: true))
        model.confirmAcceptance(try review(model))
        let quote = try #require(model.library.quote(number: "Q-0002"))
        #expect(quote.stage == .accepted)
        #expect(quote.acceptance?.fileName == "Q-0002 returned.pdf")
        let deposit = try #require(model.library.invoices(forQuote: quote.id).first)
        #expect(deposit.kind == .deposit)
        #expect(deposit.amount == Money(dollars: 310))
        #expect(model.dialog == nil)
        #expect(model.section == .invoices)
        #expect(model.selectedInvoiceID == deposit.id)
    }

    @Test func aChangedTickIsWhatGetsRecorded() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: ["01", "02"]))
        var review = try review(model)
        review.lines[1].accepted = false
        model.confirmAcceptance(review)
        let quote = try #require(model.library.quote(number: "Q-0002"))
        #expect(quote.lines.map(\.decision) == [.accepted, .declined])
    }

    @Test func aPDFForAnotherQuoteChangesNothing() throws {
        let sample = try UIFixture.sampleModel()
        let url = try returned(sample, ticking: ["01"])
        let other = try UIFixture.model()
        other.readReturnedQuote(at: url)
        #expect(other.dialog == nil)
        #expect(other.message?.title == "No Such Quote")
        #expect(other.library.quotes.isEmpty)
    }

    @Test func linesTheQuoteNoLongerHasBlockConfirming() throws {
        let model = try UIFixture.sampleModel()
        let url = try returned(model, ticking: ["01", "02"])
        var quote = try #require(model.library.quote(number: "Q-0002"))
        quote.lines.removeLast()
        model.updateQuote(quote)
        model.readReturnedQuote(at: url)
        let review = try review(model)
        #expect(!review.canBeConfirmed)
        model.confirmAcceptance(review)
        #expect(model.library.quote(number: "Q-0002")?.stage == .sent)
    }

    @Test func aFlattenedPDFOffersHandTicking() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0002"))
        let data = model.pdf(try #require(model.quoteContent(quote.id)))
        let url = try UIFixture.file("Q-0002 printed.pdf", UIFixture.flattened(data, keepingKeywords: true))
        model.readReturnedQuote(at: url)
        let box = try #require(model.message)
        #expect(box.title == "No Tick Boxes")
        model.respond(try #require(box.choices.first { $0.title == "Tick by Hand" }))
        let review = try review(model)
        #expect(review.source == .byHand)
        #expect(review.accepted.isEmpty)
        #expect(review.quoteID == quote.id)
    }

    @Test func aFlattenedPDFWithNoNumberJustSaysSo() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0002"))
        let data = model.pdf(try #require(model.quoteContent(quote.id)))
        model.readReturnedQuote(at: try UIFixture.file("scan.pdf", UIFixture.flattened(data, keepingKeywords: false)))
        #expect(model.message?.title == "No Tick Boxes")
        #expect(model.message?.choices.count == 1)
        #expect(model.dialog == nil)
    }

    @Test func nothingTickedAsksBeforeRecordingADecline() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: []))
        model.confirmAcceptance(try review(model))
        #expect(model.library.quote(number: "Q-0002")?.stage == .sent)
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first { $0.title == "Record as Declined" }))
        #expect(model.library.quote(number: "Q-0002")?.stage == .declined)
        #expect(model.library.invoices.count == 3)
    }

    @Test func handTickingStartsUntickedAndOnlyForSentQuotes() throws {
        let model = try UIFixture.sampleModel()
        let sent = try #require(model.library.quote(number: "Q-0002"))
        model.startHandTicking(sent.id)
        let review = try review(model)
        #expect(review.source == .byHand)
        #expect(review.accepted.isEmpty)
        model.dialog = nil
        let draft = try #require(model.library.quote(number: "Q-0004"))
        model.startHandTicking(draft.id)
        #expect(model.dialog == nil)
        #expect(model.message?.text == LibraryError.notSent.message)
    }

    @Test func theReviewDraws() throws {
        let model = try UIFixture.sampleModel()
        model.readReturnedQuote(at: try returned(model, ticking: ["01"]))
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "acceptance-review")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 3: Run them to watch them fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter AcceptanceTests`
Expected: build failure, `cannot find type 'AcceptanceReview' in scope`.

- [ ] **Step 4: Write `AppModel+Acceptance.swift`**

```swift
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
        let expired = quote.status(on: today) == .expired
        let proposal = AcceptanceProposal(accepted: [], declined: quote.lineCodes, clientName: "", clientDate: "",
                                          problems: expired ? [.expired(validUntil: quote.validUntil)] : [])
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

    /// The open panel's answer.
    public func fileChosen(_ result: Result<URL, Error>) {
        let choice = choosingFile
        choosingFile = nil
        switch result {
        case .failure(let error):
            show(error, title: "Couldn't open that file")
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
```

In `AppModel.swift`, add the stored property beside `dialog`:

```swift
    /// What the open panel is choosing a file for, while it's showing.
    public var choosingFile: FileChoice?
```

- [ ] **Step 5: The dialog (`Dialogs.swift` and `AcceptanceReviewView.swift`)**

Add the case to `enum Dialog`:

```swift
    /// Check what the client accepted, then confirm.
    case acceptance(AcceptanceReview)
```

and to the `switch` in `DialogOverlay`:

```swift
            case .acceptance(let review):
                AcceptanceReviewView(model: model, review: review)
```

`Sources/QuotePilotUI/Screens/AcceptanceReviewView.swift`:

```swift
import QuotePilotCore
import SwiftUI

/// Every line as the PDF reported it (or unticked, by hand). Change any tick, check the client's
/// name and date, then confirm.
struct AcceptanceReviewView: View {
    let model: AppModel
    @State private var review: AcceptanceReview

    init(model: AppModel, review: AcceptanceReview) {
        self.model = model
        _review = State(initialValue: review)
    }

    var body: some View {
        let quote = model.library.quote(review.quoteID)
        let accepted = Totals(subtotal: review.lines.filter(\.accepted).reduce(.zero) { $0 + $1.amount },
                              taxed: quote?.taxed ?? false).total
        DialogPanel(title: "Record Acceptance - \(quote?.number ?? "")", icon: .quote, width: 600) {
            VStack(alignment: .leading, spacing: 10) {
                Text(review.source == .returnedPDF
                     ? "From \(review.fileName ?? "the returned PDF"). Check the ticks and change any that are wrong, then confirm."
                     : "Tick the lines the client accepted, then confirm.")
                    .font(Win95.body)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(review.problems.enumerated()), id: \.offset) { _, problem in
                    NoteBanner(problem.isBlocking ? problem.message + " Nothing will change." : problem.message, warning: true)
                }
                GroupBox("Lines") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Accept all", isOn: acceptAll)
                            .toggleStyle(.win95)
                        EtchedLine()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach($review.lines) { $line in
                                    HStack {
                                        Toggle("\(line.code)  \(line.title.isEmpty ? "(untitled)" : line.title)", isOn: $line.accepted)
                                            .toggleStyle(.win95)
                                        Spacer()
                                        Text(model.money(line.amount))
                                            .font(Win95.money)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                }
                HStack(spacing: 6) {
                    Text("Accepted:").font(Win95.label)
                    Text(model.money(accepted)).font(Win95.money)
                    Text("of \(model.money(quote?.totals.total ?? .zero))").font(Win95.body)
                }
                Win95FieldRow("Client's name:", labelWidth: 110) {
                    Win95TextField("Client's name", text: $review.clientName)
                }
                Win95FieldRow("Date:", labelWidth: 110) {
                    Win95TextField("Date the client signed", text: $review.clientDate)
                }
                Text(planNote(quote, accepted: accepted))
                    .font(Win95.small)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Confirm") { model.confirmAcceptance(review) }
                        .buttonStyle(.win95Default)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!review.canBeConfirmed)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .foregroundStyle(Win95.text)
        }
        .groupBoxStyle(.win95)
    }

    private var acceptAll: Binding<Bool> {
        Binding(get: { review.lines.allSatisfy(\.accepted) },
                set: { value in
                    for index in review.lines.indices { review.lines[index].accepted = value }
                })
    }

    private func planNote(_ quote: Quote?, accepted: Money) -> String {
        guard accepted > .zero else { return "Nothing is ticked: confirming records that the client declined." }
        switch quote?.plan {
        case .fiftyFifty?:
            return "50/50: confirming also drafts the deposit invoice for \(model.money(accepted.percent(50))) and opens it."
        case .fullAmount?:
            return "Full amount: the invoice is drafted when you click Job Complete."
        case nil:
            return ""
        }
    }
}
```

- [ ] **Step 6: Drop, open panel, toolbar, menu and the editor button**

In `RootView.body`, add after the `.fileExporter(…) { … }` modifier:

```swift
        .fileImporter(isPresented: choosing, allowedContentTypes: model.choosingFile?.contentTypes ?? [.pdf]) { result in
            model.fileChosen(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            model.readReturnedQuote(at: pdf)
            return true
        }
```

and beside `exporting`:

```swift
    private var choosing: Binding<Bool> {
        Binding(get: { model.choosingFile != nil }, set: { if !$0 { model.choosingFile = nil } })
    }
```

In `Win95Toolbar`, replace the Read Reply button line with:

```swift
                tool("Read Reply", .folder, help: "Read a returned quote PDF, or drop one on the window (⌘O)") {
                    model.choosingFile = .returnedQuote
                }
```

In `QuotePilotCommands.body`, inside `CommandGroup(replacing: .newItem)` after New Client, add:

```swift
            Divider()
            Button("Read Returned Quote…") { model.choosingFile = .returnedQuote }
                .keyboardShortcut("o")
```

In `QuoteEditorView.header(_:)`, after the Send by Mail button, add:

```swift
            if quote.stage != .draft, model.library.invoices(forQuote: quoteID).isEmpty {
                Button("Record Acceptance…") { model.startHandTicking(quoteID) }
                    .buttonStyle(.win95)
                    .help("Tick the lines the client accepted, when they couldn't fill in the PDF")
            }
```

- [ ] **Step 7: Run the tests and look at the review**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter AcceptanceTests`
Expected: all ten tests pass. Look at `build/snapshots/acceptance-review.png`. It should show the
dialog over the quote editor, with line 01 ticked, "Accepted: $450.00 of $620.00", the client's
name and date, the 50/50 note ($225.00 deposit), and Confirm outlined.

- [ ] **Step 8: Run everything and commit**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests
git commit -m "Read returned quotes: the acceptance review, hand-ticking, and dropping a PDF on the window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The invoice editor, and invoicing from quotes

Invoices get an editor like the quote editor's: the form on the left and the live PDF on the right.
A draft can be edited; a sent or void one shows read-only with a note saying why. The quote editor
gains **Draft Invoice Now** and **Job Complete**. **New Invoice** (⇧⌘N) starts a one-off invoice.
Void, Delete Draft and Duplicate (one-off invoices only) round it out.

The line table moves into its own file so quotes and invoices share it. Each document's totals show
exactly as its PDF prints them.

**Files:**
- Create: `Sources/QuotePilotUI/App/AppModel+Invoices.swift`
- Create: `Sources/QuotePilotUI/Screens/LinesEditor.swift` (moved from `QuoteEditorView.swift` and
  made generic)
- Create: `Sources/QuotePilotUI/Screens/InvoiceEditorView.swift`
- Modify: `Sources/QuotePilotUI/App/AppModel.swift` (stored `openInvoiceID`; `openInvoice`;
  `exportableContent`)
- Modify: `Sources/QuotePilotUI/App/AppModel+Mail.swift` (`sendableDocument` uses `openInvoiceID`)
- Modify: `Sources/QuotePilotUI/Screens/QuoteEditorView.swift` (two-row header with the new
  actions; the shared line table)
- Modify: `Sources/QuotePilotUI/Screens/InvoicesView.swift` (show the editor when one is open)
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (toolbar New Invoice)
- Modify: `Sources/QuotePilotUI/App/AppModel.swift` (`go(to:)`: choosing Invoices again goes back to the
  list)
- Modify: `Sources/QuotePilotUI/App/Commands.swift` (⇧⌘N)
- Test: `Tests/QuotePilotUITests/InvoiceEditorTests.swift`

**Interfaces:**
- Consumes:
  - core: `Library.newInvoice`, `update(_ invoice:)` (Task 1 rules), `draftNextInvoice`,
    `completeJob`, `voidInvoice`, `deleteDraft(invoice:)`, `duplicateInvoice` and
    `nextInvoiceKind`;
  - PDF: `DocumentContent.totals`;
  - plan 2a: `CommitField`, `DayPicker`, `ClientPicker`, `SquareButton`, `LivePDFPreview`,
    `StatusLabel.cell`, `InvoiceKind.columnLabel`;
  - Task 3: `send`.
- Produces:
  - `AppModel.openInvoiceID`.
  - **Invoice actions:** `newInvoice(for:)`, `updateInvoice(_:)`, `invoiceBinding(_:)`,
    `draftInvoiceNow(forQuote:)`, `completeJob(_:)`, `voidInvoice(_:)` (asks first),
    `deleteDraftInvoice(_:)` (asks first) and `duplicateInvoice(_:)` (one-off only).
  - **Views:**
    - `LinesEditor(model:lines:showCodes:showDecision:editable:onAdd:footer:)` and
      `DocumentTotals(totals:)`;
    - `LineRow`, which gains `showCode:` and `editable:`;
    - `InvoiceEditorView(model:invoiceID:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/InvoiceEditorTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct InvoiceEditorTests {
    func invoice(_ model: AppModel, _ number: String) throws -> Invoice {
        try #require(model.library.invoices.first { $0.number == number })
    }

    @Test func aNewInvoiceOpensInTheEditor() throws {
        let model = try UIFixture.sampleModel()
        model.newInvoice()
        let id = try #require(model.openInvoiceID)
        #expect(model.section == .invoices)
        #expect(model.library.invoice(id)?.kind == .standalone)
        #expect(model.library.invoice(id)?.number == "INV-0004")
    }

    @Test func editingADraftSavesIt() throws {
        let model = try UIFixture.sampleModel()
        model.newInvoice()
        let id = try #require(model.openInvoiceID)
        model.invoiceBinding(id).wrappedValue.lines = [LineItem(title: "Extra page", rate: Money(dollars: 250))]
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.invoice(id)?.amount == Money(dollars: 250))
    }

    @Test func aSentInvoiceStaysAsItWas() throws {
        let model = try UIFixture.sampleModel()
        let care = try invoice(model, "INV-0002")
        model.invoiceBinding(care.id).wrappedValue.title = "Changed"
        #expect(model.library.invoice(care.id) == care)
        #expect(model.message?.text == LibraryError.notEditable.message)
    }

    @Test func draftInvoiceNowDraftsTheBalance() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0001"))
        model.draftInvoiceNow(forQuote: quote.id)
        let id = try #require(model.openInvoiceID)
        let final = try #require(model.library.invoice(id))
        #expect(final.kind == .final)
        #expect(final.amount == Money(dollars: 1935))
    }

    @Test func jobCompleteDraftsTheClosingInvoiceOnce() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0001"))
        model.completeJob(quote.id)
        #expect(model.library.quote(quote.id)?.completedOn == UIFixture.today)
        let count = model.library.invoices.count
        model.completeJob(quote.id)
        #expect(model.library.invoices.count == count)
        #expect(model.message?.title == "Job Complete")
    }

    @Test func voidingAsksFirst() throws {
        let model = try UIFixture.sampleModel()
        let care = try invoice(model, "INV-0002")
        model.voidInvoice(care.id)
        #expect(model.library.invoice(care.id)?.stage == .sent)
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first { $0.title == "Void" }))
        #expect(model.library.invoice(care.id)?.stage == .void)
    }

    @Test func onlyOneOffInvoicesCanBeDuplicated() throws {
        let model = try UIFixture.sampleModel()
        let deposit = try invoice(model, "INV-0001")
        model.duplicateInvoice(deposit.id)
        #expect(model.message?.title == "Can't Duplicate")
        model.message = nil
        let care = try invoice(model, "INV-0002")
        model.duplicateInvoice(care.id)
        let copy = try #require(model.openInvoiceID.flatMap { model.library.invoice($0) })
        #expect(copy.kind == .standalone)
        #expect(copy.stage == .draft)
        #expect(copy.amount == care.amount)
    }

    @Test func deletingADraftInvoiceAsksFirst() throws {
        let model = try UIFixture.sampleModel()
        model.newInvoice()
        let id = try #require(model.openInvoiceID)
        model.deleteDraftInvoice(id)
        model.respond(try #require(model.message?.choices.first { $0.title == "Delete" }))
        #expect(model.library.invoice(id) == nil)
        #expect(model.openInvoiceID == nil)
    }

    @Test func theInvoiceEditorDraws() throws {
        let model = try UIFixture.sampleModel()
        model.openInvoice(try invoice(model, "INV-0003").id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "invoice-editor")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theQuoteEditorShowsItsInvoiceActions() throws {
        let model = try UIFixture.sampleModel()
        model.openQuote(try #require(model.library.quote(number: "Q-0001")).id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quote-editor-actions")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter InvoiceEditorTests`
Expected: build failure, `value of type 'AppModel' has no member 'newInvoice'`.

- [ ] **Step 3: The open invoice (`AppModel.swift` and `AppModel+Mail.swift`)**

In `AppModel.swift`, add the stored property beside `openQuoteID`:

```swift
    /// The invoice open in the editor; nil shows the invoice list.
    public var openInvoiceID: UUID?
```

Change `openInvoice(_:)` to open the editor too:

```swift
    public func openInvoice(_ id: UUID) {
        section = .invoices
        selectedInvoiceID = id
        openInvoiceID = id
    }
```

In `exportableContent`, change the invoices case to:

```swift
        case .invoices: return (openInvoiceID ?? selectedInvoiceID).flatMap(invoiceContent)
```

In `AppModel+Mail.swift`, change the invoices case of `sendableDocument` to:

```swift
        case .invoices: return (openInvoiceID ?? selectedInvoiceID).map(MailDocument.invoice)
```

- [ ] **Step 4: Write `AppModel+Invoices.swift`**

```swift
import Foundation
import QuotePilotCore
import SwiftUI

extension AppModel {
    /// ⇧⌘N: a one-off invoice, for extra work or a monthly fee.
    public func newInvoice(for clientID: UUID? = nil) {
        var created: UUID?
        guard change("Couldn't start a new invoice", { library in
            created = library.newInvoice(on: today, clientID: clientID).id
        }), let created else { return }
        openInvoice(created)
    }

    public func updateInvoice(_ invoice: Invoice) {
        change("Couldn't save \(invoice.number)") { try $0.update(invoice) }
    }

    /// The editor's view of an invoice: it reads the stored invoice and writes through
    /// `updateInvoice`, so a refused edit shows the stored value again.
    public func invoiceBinding(_ id: UUID) -> Binding<Invoice> {
        Binding(
            get: {
                self.library.invoice(id)
                    ?? Invoice(id: id, number: "", kind: .standalone, issued: self.today, due: self.today)
            },
            set: { self.updateInvoice($0) })
    }

    /// "Draft Invoice Now": the next invoice the quote's plan calls for.
    public func draftInvoiceNow(forQuote id: UUID) {
        var created: UUID?
        guard change("Couldn't draft the invoice", { library in
            created = try library.draftNextInvoice(forQuote: id, on: today).id
        }), let created else { return }
        openInvoice(created)
    }

    /// "Job Complete": records the date and drafts the closing invoice, unless it exists already.
    public func completeJob(_ quoteID: UUID) {
        var created: UUID?
        let saved = change("Couldn't complete the job") { library in
            created = try library.completeJob(quote: quoteID, on: today)?.id
        }
        guard saved else { return }
        if let created {
            openInvoice(created)
        } else {
            show(title: "Job Complete", text: "The job is marked complete. Its closing invoice already exists.")
        }
    }

    public func voidInvoice(_ id: UUID) {
        guard let invoice = library.invoice(id) else { return }
        confirm(title: "Void Invoice",
                text: "Void \(invoice.number)? It stops counting as owed, and its number stays used.",
                confirm: "Void") {
            self.change("Couldn't void \(invoice.number)") { try $0.voidInvoice(id) }
        }
    }

    public func deleteDraftInvoice(_ id: UUID) {
        guard let invoice = library.invoice(id) else { return }
        guard invoice.stage == .draft else { return show(LibraryError.notDraft, title: "Can't Delete") }
        confirm(title: "Delete Draft",
                text: "Delete draft invoice \(invoice.number)? Its number won't be used again.",
                confirm: "Delete") {
            guard self.change("Couldn't delete \(invoice.number)", { try $0.deleteDraft(invoice: id) }) else { return }
            if self.openInvoiceID == id { self.openInvoiceID = nil }
            if self.selectedInvoiceID == id { self.selectedInvoiceID = nil }
        }
    }

    /// A fresh draft copy of a one-off invoice, for repeat work. Invoices from a quote are drafted from
    /// the quote instead.
    public func duplicateInvoice(_ id: UUID) {
        guard let invoice = library.invoice(id) else { return }
        guard invoice.kind == .standalone else {
            return show(title: "Can't Duplicate",
                        text: "Only one-off invoices can be duplicated. \(invoice.number) comes from a quote, so draft the next one from the quote instead.",
                        kind: .warning)
        }
        var created: UUID?
        guard change("Couldn't duplicate \(invoice.number)", { library in
            created = try library.duplicateInvoice(id, on: today).id
        }), let created else { return }
        openInvoice(created)
    }
}
```

- [ ] **Step 5: Write `LinesEditor.swift` and slim `QuoteEditorView.swift`**

Move `LineRow`, `SquareButton` and `SquareButtonStyle` from `QuoteEditorView.swift` into the new
file unchanged, except for `LineRow`'s changes below. Delete the old `LinesEditor` from
`QuoteEditorView.swift`. Then add:

```swift
import QuotePilotCore
import QuotePilotPDF
import SwiftUI

/// The line table quotes and invoices share. Each line has its wording, quantity, unit, rate and
/// amount, with buttons to move or remove it. Add Line sits below, then the document's own totals.
struct LinesEditor<Footer: View>: View {
    let model: AppModel
    @Binding var lines: [LineItem]
    /// Quotes show each line's ID; invoices don't.
    let showCodes: Bool
    /// Accepted quotes show what the client decided for each line.
    let showDecision: Bool
    /// Sent invoices show their lines without fields or buttons.
    let editable: Bool
    let onAdd: () -> Void
    let footer: Footer

    init(model: AppModel, lines: Binding<[LineItem]>, showCodes: Bool = true, showDecision: Bool = false,
         editable: Bool = true, onAdd: @escaping () -> Void, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self._lines = lines
        self.showCodes = showCodes
        self.showDecision = showDecision
        self.editable = editable
        self.onAdd = onAdd
        self.footer = footer()
    }

    var body: some View {
        let currency = model.currencyCode
        VStack(alignment: .leading, spacing: 4) {
            // Column widths: keep whatever plan 2a's QuoteEditorView settled on (its 980-pt fix trimmed
            // them, e.g. ID 24, Qty 48, Unit 72, Rate 92, Amount 88). Copy the current values from the
            // existing LinesEditor/LineRow rather than these placeholders, and put them in one shared
            // `LineColumns` enum used by both the header and LineRow so they can't drift.
            HStack(spacing: 4) {
                if showCodes { columnHead("ID", width: LineColumns.id) }
                columnHead("Item", width: nil)
                columnHead("Qty", width: LineColumns.quantity)
                columnHead("Unit", width: LineColumns.unit)
                columnHead("Rate", width: LineColumns.rate)
                columnHead("Amount", width: LineColumns.amount, trailing: true)
                if editable { Spacer().frame(width: LineColumns.buttons) }
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                LineRow(line: lineBinding(line.id), currency: currency, showCode: showCodes,
                        showDecision: showDecision, editable: editable,
                        canMoveUp: index > 0, canMoveDown: index < lines.count - 1,
                        move: { move(line.id, by: $0) }, remove: { remove(line) })
            }
            if lines.isEmpty {
                Text("No lines yet.")
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
            }
            HStack(alignment: .top) {
                if editable {
                    Button("Add Line", action: onAdd)
                        .buttonStyle(.win95)
                }
                Spacer()
                footer
            }
            .padding(.top, 4)
        }
        .disabled(!editable)
    }

    private func columnHead(_ title: String, width: CGFloat?, trailing: Bool = false) -> some View {
        Text(title)
            .font(Win95.label)
            .foregroundStyle(Win95.text)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    /// A line found by its identity, so a removed or moved line can never index past the end.
    private func lineBinding(_ id: UUID) -> Binding<LineItem> {
        Binding(
            get: { lines.first { $0.id == id } ?? LineItem(id: id, title: "", rate: .zero) },
            set: { line in
                var edited = lines
                guard let index = edited.firstIndex(where: { $0.id == id }) else { return }
                edited[index] = line
                lines = edited
            })
    }

    private func move(_ id: UUID, by offset: Int) {
        var edited = lines
        guard let index = edited.firstIndex(where: { $0.id == id }), edited.indices.contains(index + offset) else { return }
        edited.swapAt(index, index + offset)
        lines = edited
    }

    private func remove(_ line: LineItem) {
        let name = line.title.isEmpty ? (line.code.isEmpty ? "this line" : "line \(line.code)") : "\"\(line.title)\""
        model.confirm(title: "Remove Line", text: "Remove \(name)?", confirm: "Remove") {
            var edited = lines
            edited.removeAll { $0.id == line.id }
            lines = edited
        }
    }
}

/// A document's totals exactly as its PDF prints them.
struct DocumentTotals: View {
    let totals: [DocumentContent.TotalLine]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
            ForEach(Array(totals.enumerated()), id: \.offset) { _, line in
                GridRow {
                    Text(line.label)
                        .font(line.strong ? Win95.label : Win95.body)
                    Text(line.value)
                        .font(line.strong ? Win95.money.bold() : Win95.money)
                }
            }
        }
        .foregroundStyle(Win95.text)
    }
}
```

Change `LineRow` as follows:
- **New properties:** `let showCode: Bool` and `let editable: Bool`, after `currency`.
- **ID column:** wrap the ID `Text(line.code)…frame(width: 28…)` in `if showCode { … }`.
- **Buttons:** wrap the three `SquareButton`s in `if editable { … }`.
- **Detail row:** its spacer becomes `Spacer().frame(width: showCode ? 32 : 0)`.

Adding a line to a quote still goes through `Quote.addLine`, so drafts keep their IDs in order.

- [ ] **Step 6: The quote editor's header and table (`QuoteEditorView.swift`)**

Replace `header(_:)` with this two-row version. It keeps the earlier Send by Mail and Record
Acceptance buttons and adds the invoicing actions:

```swift
    private func header(_ quote: Quote) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button("All Quotes") { model.openQuoteID = nil }
                    .buttonStyle(.win95)
                    .help("Back to the list of quotes")
                PixelIconView(.quote, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quote \(quote.number)")
                        .font(Win95.title)
                        .foregroundStyle(Win95.text)
                    HStack(spacing: 8) {
                        StatusLabel.cell(quote.status(on: model.today), selected: false)
                        if let done = quote.completedOn {
                            Text("Job completed \(done.short)")
                                .font(Win95.body)
                                .foregroundStyle(Win95.text)
                        }
                    }
                }
                Spacer()
                Text(model.money(quote.totals.total))
                    .font(Win95.readout)
                    .foregroundStyle(Win95.text)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .frame(minWidth: 190, alignment: .trailing)
                    .win95Sunken()
                    .accessibilityLabel("Total \(model.money(quote.totals.total))")
            }
            .padding(8)
            HStack(spacing: 6) {
                Button("Send by Mail…") { model.send(.quote(quoteID)) }
                    .buttonStyle(.win95Default)
                    .help("Open a Mail draft with this quote attached (⌘S)")
                if quote.stage != .draft, model.library.invoices(forQuote: quoteID).isEmpty {
                    Button("Record Acceptance…") { model.startHandTicking(quoteID) }
                        .help("Tick the lines the client accepted, when they couldn't fill in the PDF")
                }
                if model.library.nextInvoiceKind(forQuote: quoteID) != nil {
                    Button("Draft Invoice Now") { model.draftInvoiceNow(forQuote: quoteID) }
                        .help("Draft the next invoice the payment plan calls for")
                    Button("Job Complete") { model.completeJob(quoteID) }
                        .help("Record the job as done and draft its final invoice")
                }
                Button("Duplicate") { model.duplicateQuote(quoteID) }
                if quote.stage == .draft {
                    Button("Delete Draft") { model.deleteDraftQuote(quoteID) }
                }
                Button("Save PDF…") { model.exportPDF() }
                Spacer()
            }
            .buttonStyle(.win95)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Win95.face)
        .overlay(alignment: .bottom) { EtchedLine() }
    }
```

In `form(_:)`, replace `LinesEditor(model: model, quote: quote)` with:

```swift
                LinesEditor(model: model, lines: quote.lines,
                            showDecision: current.stage == .accepted || current.stage == .declined,
                            onAdd: {
                                var edited = quote.wrappedValue
                                edited.addLine(LineItem(title: "", rate: .zero))
                                quote.wrappedValue = edited
                            }) {
                    DocumentTotals(totals: model.quoteContent(quoteID)?.totals ?? [])
                }
```

- [ ] **Step 7: Write `InvoiceEditorView.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// One invoice, laid out like the quote editor. Drafts can be edited; sent and void invoices are
/// records, shown read-only with a note saying why.
struct InvoiceEditorView: View {
    let model: AppModel
    let invoiceID: UUID

    var body: some View {
        let invoice = model.invoiceBinding(invoiceID)
        VStack(spacing: 0) {
            header(invoice.wrappedValue)
            // Same widths as plan 2a's QuoteEditorView after its 980-pt fix (form 500…640 with
            // layoutPriority(1), preview at least 220), so the editor fits the minimum window.
            HStack(alignment: .top, spacing: 8) {
                ScrollView {
                    form(invoice)
                        .padding(.trailing, 6)
                }
                .frame(minWidth: 500, idealWidth: 620, maxWidth: 640)
                .layoutPriority(1)
                GroupBox("Preview") {
                    LivePDFPreview(model: model, content: model.invoiceContent(invoiceID))
                }
                .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
        }
        .groupBoxStyle(.win95)
    }

    private func header(_ invoice: Invoice) -> some View {
        let status = invoice.status(on: model.today)
        let showOwing = invoice.stage == .sent
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button("All Invoices") { model.openInvoiceID = nil }
                    .buttonStyle(.win95)
                    .help("Back to the list of invoices")
                PixelIconView(.invoice, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invoice \(invoice.number)")
                        .font(Win95.title)
                        .foregroundStyle(Win95.text)
                    HStack(spacing: 8) {
                        StatusLabel.cell(status, selected: false)
                        Text(invoice.kind.columnLabel)
                            .font(Win95.body)
                            .foregroundStyle(Win95.text)
                    }
                }
                Spacer()
                Text(showOwing ? "Owing" : "Amount")
                    .font(Win95.label)
                    .foregroundStyle(Win95.text)
                Text(model.money(showOwing ? invoice.owing : invoice.amount))
                    .font(Win95.readout)
                    .foregroundStyle(status.isAlert ? Win95.overdue : Win95.text)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .frame(minWidth: 190, alignment: .trailing)
                    .win95Sunken()
            }
            .padding(8)
            HStack(spacing: 6) {
                if invoice.stage != .void {
                    Button("Send by Mail…") { model.send(.invoice(invoiceID)) }
                        .buttonStyle(.win95Default)
                        .help("Open a Mail draft with this invoice attached (⌘S)")
                }
                if invoice.stage == .sent, invoice.payments.isEmpty {
                    Button("Void…") { model.voidInvoice(invoiceID) }
                        .help("Cancel this invoice; its number stays used")
                }
                if invoice.stage == .draft {
                    Button("Delete Draft") { model.deleteDraftInvoice(invoiceID) }
                }
                if invoice.kind == .standalone {
                    Button("Duplicate") { model.duplicateInvoice(invoiceID) }
                        .help("A new draft with the same lines, for repeat work")
                }
                Button("Save PDF…") { model.exportPDF() }
                Spacer()
            }
            .buttonStyle(.win95)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Win95.face)
        .overlay(alignment: .bottom) { EtchedLine() }
    }

    private func form(_ invoice: Binding<Invoice>) -> some View {
        let current = invoice.wrappedValue
        let editable = current.stage == .draft
        let quote = current.quoteID.flatMap { model.library.quote($0) }
        return VStack(alignment: .leading, spacing: 10) {
            switch current.stage {
            case .sent:
                NoteBanner("This invoice has been sent, so it can't be changed. If something's wrong, void it and draft a new one.")
            case .void:
                NoteBanner("This invoice is void. It no longer counts as owed, and its number stays used.", warning: true)
            case .draft:
                EmptyView()
            }
            if let quote {
                HStack(spacing: 8) {
                    NoteBanner("Drafted from quote \(quote.number), as its \(current.kind.columnLabel.lowercased()) invoice.")
                    Button("Open Quote") { model.openQuote(quote.id) }
                        .buttonStyle(.win95)
                }
            }
            GroupBox("Invoice") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Client:") {
                        ClientPicker(clients: model.library.clients, selection: invoice.clientID)
                            .disabled(quote != nil)
                    }
                    Win95FieldRow("Title:") {
                        Win95TextField("Title", text: invoice.title, prompt: "e.g. Website care, October")
                    }
                    Win95FieldRow("Issued:") { DayPicker(label: "Issued", day: invoice.issued) }
                    Win95FieldRow("Due:") { DayPicker(label: "Due", day: invoice.due) }
                    if model.library.brand.gstRegistered || current.taxed {
                        Win95FieldRow("GST:") { Toggle("Add GST (10%)", isOn: invoice.taxed).toggleStyle(.win95) }
                    }
                }
            }
            .disabled(!editable)
            GroupBox("Lines") {
                LinesEditor(model: model, lines: invoice.lines, showCodes: false, editable: editable,
                            onAdd: {
                                var edited = invoice.wrappedValue
                                edited.lines.append(LineItem(title: "", rate: .zero))
                                invoice.wrappedValue = edited
                            }) {
                    DocumentTotals(totals: model.invoiceContent(invoiceID)?.totals ?? [])
                }
            }
            GroupBox("Terms") {
                Win95TextEditor("Terms", text: invoice.terms)
                    .frame(height: 60)
            }
            .disabled(!editable)
        }
    }
}
```

- [ ] **Step 8: The invoice list opens the editor (`InvoicesView.swift`)**

- Rename the current `body` to a private `list` property, then add:

  ```swift
      var body: some View {
          if let id = model.openInvoiceID, model.library.invoice(id) != nil {
              // A fresh editor per invoice, so Duplicate never shows the previous invoice's state.
              InvoiceEditorView(model: model, invoiceID: id)
                  .id(id)
          } else {
              list
          }
      }
  ```

- Give the list's `DetailsList` `onOpen: { model.openInvoice($0) }`.
- A draft isn't owed until it's sent: in `InvoiceRow.init`, make `owing` zero unless
  `invoice.stage == .sent` (it matches the dashboard, which counts only sent invoices).
- Keep plan 2a's `InvoicesView.layout(width:)` and its column set. The editor replaces the list only
  when an invoice is open.
- Replace its `NoteBanner` text with: "Double-click an invoice to open it. New Invoice (⇧⌘N) starts
  a one-off invoice; invoices for a job come from its quote."
- Add a toolbar row above the list, as the quote list has:

```swift
                HStack(spacing: 6) {
                    Button("New Invoice") { model.newInvoice() }
                        .buttonStyle(.win95)
                    Button("Open") { if let id = model.selectedInvoiceID { model.openInvoice(id) } }
                        .buttonStyle(.win95)
                        .disabled(model.selectedInvoiceID == nil)
                    Spacer()
                }
```

- [ ] **Step 9: Toolbar, tree and menu (`RootView.swift`, `Commands.swift`)**

In `Win95Toolbar`, replace the New Invoice button line with:

```swift
                tool("New Invoice", .invoice, help: "Start a one-off invoice (⇧⌘N)") { model.newInvoice() }
```

In `AppModel.go(to:)` (plan 2a Task 6's one rule for switching sections, used by the tree and the Go
menu), add beside the Quotes line:

```swift
        if section == .invoices, self.section == .invoices { openInvoiceID = nil }
```

In `QuotePilotCommands`, inside `CommandGroup(replacing: .newItem)` after New Quote, add:

```swift
            Button("New Invoice") { model.newInvoice() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
```

- [ ] **Step 10: Run the tests and look at both editors**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter InvoiceEditorTests`
Expected: all ten tests pass.

Look at `build/snapshots/invoice-editor.png`. INV-0003 should show as part paid, with Owing
$135.00, the sent note, read-only lines (no buttons), and the "Total due" rows as the PDF prints them.

Look at `quote-editor-actions.png`. Q-0001's action row should show Send by Mail…, Draft Invoice
Now, Job Complete, Duplicate and Save PDF…, with no Record Acceptance (it has invoices).

- [ ] **Step 11: Run everything and commit**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test`
Expected: everything passes, plan 2a's quote editor tests included.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests
git commit -m "The invoice editor, Draft Invoice Now, Job Complete, void, delete and duplicate

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Payments and receipts

**Record Payment…** opens a dialog with the date (today), the amount (what's owing), the method and a
note. A payment must be more than $0 and no more than what's owing. Recording one offers to send a
receipt. The invoice editor lists its payments; each can be removed, after a question, and **Send
Receipt…** appears once a payment exists. The toolbar's Payment button works on the open or selected
invoice.

**Files:**
- Create: `Sources/QuotePilotUI/Screens/PaymentDialog.swift`
- Modify: `Sources/QuotePilotUI/App/AppModel+Invoices.swift` (payment actions)
- Modify: `Sources/QuotePilotUI/App/Dialogs.swift` (the `.payment` dialog)
- Modify: `Sources/QuotePilotUI/Screens/InvoiceEditorView.swift` (Payments box; header buttons)
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (toolbar Payment)
- Modify: `Sources/QuotePilotCore/Invoicing.swift` (removing the last payment clears the receipt)
- Test: `Tests/QuotePilotUITests/PaymentTests.swift`

**Interfaces:**
- Consumes:
  - core: `Library.recordPayment` and `removePayment` (Task 1 checks), `PaymentMethod`;
  - plan 2a: `FieldParser.money`, `DayPicker`, `Win95RadioGroup`, `Win95Progress`, `SquareButton`;
  - Task 3: `send(.receipt(_:))`, `DialogPanel`.
- Produces:
  - `PaymentEntry(invoiceID:date:amount:method:note:)` and `Dialog.payment(PaymentEntry)`.
  - `AppModel.payableInvoiceID`, `startPayment(_:)`, `recordPayment(_:)` and
    `removePayment(_:from:)`.
  - `PaymentDialog` and `PaymentsBox`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/PaymentTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct PaymentTests {
    /// INV-0003: hosting and support, $195, $60 paid, $135 owing.
    func hosting(_ model: AppModel) throws -> Invoice {
        try #require(model.library.invoices.first { $0.number == "INV-0003" })
    }

    func entry(_ model: AppModel) throws -> PaymentEntry {
        guard case .payment(let entry) = model.dialog else {
            Issue.record("Expected the payment dialog, found \(String(describing: model.dialog))")
            throw CancellationError()
        }
        return entry
    }

    @Test func recordingAPaymentLowersWhatsOwing() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        model.startPayment(invoice.id)
        var entry = try entry(model)
        #expect(entry.amount == "$135.00")
        #expect(entry.date == UIFixture.today)
        entry.method = .card
        entry.note = "Paid at the office"
        model.recordPayment(entry)
        let paid = try #require(model.library.invoice(invoice.id))
        #expect(paid.owing == .zero)
        #expect(paid.payments.last?.method == .card)
        #expect(paid.payments.last?.note == "Paid at the office")
        #expect(model.dialog == nil)
        #expect(model.message?.title == "Payment Recorded")
    }

    @Test func theReceiptOfferOpensAReceiptDraft() throws {
        let mail = FakeMail()
        let model = try UIFixture.sampleModel(mail: mail)
        let invoice = try hosting(model)
        model.startPayment(invoice.id)
        model.recordPayment(try entry(model))
        model.respond(try #require(model.message?.choices.first { $0.title == "Send Receipt" }))
        #expect(mail.drafts.first?.subject == "Receipt for invoice INV-0003")
    }

    @Test func aPaymentOverWhatsOwingIsRefused() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        model.startPayment(invoice.id)
        var entry = try entry(model)
        entry.amount = "500"
        model.recordPayment(entry)
        #expect(model.message?.text == LibraryError.paymentMoreThanOwing(Money(dollars: 135)).message)
        #expect(model.library.invoice(invoice.id)?.payments.count == 1)
        if case .payment = model.dialog {} else { Issue.record("The dialog should stay open to fix the amount") }
    }

    @Test func aHalfTypedAmountIsRefused() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        model.startPayment(invoice.id)
        var entry = try entry(model)
        entry.amount = "12.3.4"
        model.recordPayment(entry)
        #expect(model.message?.title == "Amount")
        #expect(model.library.invoice(invoice.id)?.payments.count == 1)
    }

    @Test func onlySentInvoicesWithMoneyOwingTakePayments() throws {
        let model = try UIFixture.sampleModel()
        let deposit = try #require(model.library.invoices.first { $0.number == "INV-0001" })
        model.startPayment(deposit.id)
        #expect(model.dialog == nil)
        #expect(model.message?.title == "Nothing Owing")
        model.message = nil
        model.newInvoice()
        model.startPayment(try #require(model.openInvoiceID))
        #expect(model.dialog == nil)
        #expect(model.message?.text == LibraryError.notSent.message)
    }

    @Test func removingAPaymentAsksFirst() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        let payment = try #require(invoice.payments.first)
        model.removePayment(payment.id, from: invoice.id)
        #expect(model.library.invoice(invoice.id)?.payments.count == 1)
        model.respond(try #require(model.message?.choices.first { $0.title == "Remove" }))
        #expect(model.library.invoice(invoice.id)?.payments.isEmpty == true)
    }

    @Test func thePaymentDialogDraws() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        model.openInvoice(invoice.id)
        model.startPayment(invoice.id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "payment-dialog")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter PaymentTests`
Expected: build failure, `cannot find type 'PaymentEntry' in scope`.

- [ ] **Step 3: The payment actions (`AppModel+Invoices.swift`)**

Add at the top of the file, after the imports:

```swift
/// What the payment dialog holds while you type.
public struct PaymentEntry: Equatable {
    public var invoiceID: UUID
    public var date: Day
    /// As typed; read with `FieldParser.money` when you press Record.
    public var amount: String
    public var method: PaymentMethod
    public var note: String
}
```

and inside the extension:

```swift
    /// The invoice the toolbar's Payment button records against: the open or selected invoice.
    public var payableInvoiceID: UUID? {
        guard section == .invoices, let id = openInvoiceID ?? selectedInvoiceID,
              let invoice = library.invoice(id), invoice.stage == .sent, invoice.owing > .zero
        else { return nil }
        return id
    }

    /// Opens the payment dialog with today's date and what's owing.
    public func startPayment(_ invoiceID: UUID) {
        guard let invoice = library.invoice(invoiceID) else { return }
        switch invoice.stage {
        case .draft: return show(LibraryError.notSent, title: "Can't Record a Payment")
        case .void: return show(LibraryError.isVoid, title: "Can't Record a Payment")
        case .sent: break
        }
        guard invoice.owing > .zero else {
            return show(title: "Nothing Owing", text: "\(invoice.number) is paid in full.")
        }
        dialog = .payment(PaymentEntry(invoiceID: invoiceID, date: today, amount: money(invoice.owing),
                                       method: .bankTransfer, note: ""))
    }

    /// Records the dialog's payment, then offers a receipt. A refused amount leaves the dialog open.
    public func recordPayment(_ entry: PaymentEntry) {
        guard let amount = FieldParser.money(entry.amount) else {
            return show(title: "Amount", text: "Type the amount paid, like 540 or $540.00.", kind: .warning)
        }
        let payment = Payment(date: entry.date, amount: amount, method: entry.method,
                              note: entry.note.trimmingCharacters(in: .whitespacesAndNewlines))
        guard change("Couldn't record the payment", { try $0.recordPayment(payment, toInvoice: entry.invoiceID) }),
              let invoice = library.invoice(entry.invoiceID)
        else { return }
        dialog = nil
        message = MessageBox(kind: .question, title: "Payment Recorded",
                             text: "Recorded \(money(amount)) for \(invoice.number). Send a receipt by Mail?",
                             choices: [MessageBox.Choice("Send Receipt", isDefault: true) { self.send(.receipt(entry.invoiceID)) },
                                       MessageBox.Choice("Not Now", isCancel: true)])
    }

    public func removePayment(_ paymentID: UUID, from invoiceID: UUID) {
        guard let invoice = library.invoice(invoiceID),
              let payment = invoice.payments.first(where: { $0.id == paymentID }) else { return }
        confirm(title: "Remove Payment",
                text: "Remove the \(money(payment.amount)) payment of \(payment.date.long) from \(invoice.number)?",
                confirm: "Remove") {
            self.change("Couldn't remove the payment") { try $0.removePayment(paymentID, fromInvoice: invoiceID) }
        }
    }
```

- [ ] **Step 4: The dialog (`Dialogs.swift`, `PaymentDialog.swift`)**

Add to `enum Dialog`:

```swift
    /// Record a payment against an invoice.
    case payment(PaymentEntry)
```

and to the `switch` in `DialogOverlay`:

```swift
            case .payment(let entry):
                PaymentDialog(model: model, entry: entry)
```

`Sources/QuotePilotUI/Screens/PaymentDialog.swift`:

```swift
import QuotePilotCore
import SwiftUI

/// Record a payment: the date, the amount, how it was paid and a note.
struct PaymentDialog: View {
    let model: AppModel
    @State private var entry: PaymentEntry

    init(model: AppModel, entry: PaymentEntry) {
        self.model = model
        _entry = State(initialValue: entry)
    }

    var body: some View {
        let invoice = model.library.invoice(entry.invoiceID)
        let client = model.library.client(invoice?.clientID)?.name ?? "The client"
        DialogPanel(title: "Record Payment - \(invoice?.number ?? "")", icon: .payment) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(client) owes \(model.money(invoice?.owing ?? .zero)) on \(invoice?.number ?? "this invoice").")
                    .font(Win95.body)
                Win95FieldRow("Date:", labelWidth: 70) {
                    DayPicker(label: "Payment date", day: $entry.date)
                }
                Win95FieldRow("Amount:", labelWidth: 70) {
                    Win95TextField("Amount", text: $entry.amount)
                        .frame(width: 140)
                }
                Win95FieldRow("Method:", labelWidth: 70) {
                    Win95RadioGroup(selection: $entry.method, options: PaymentMethod.allCases.map { ($0, $0.label) })
                }
                Win95FieldRow("Note:", labelWidth: 70) {
                    Win95TextField("Note", text: $entry.note, prompt: "Optional, e.g. a reference")
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Record") { model.recordPayment(entry) }
                        .buttonStyle(.win95Default)
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .foregroundStyle(Win95.text)
        }
    }
}

/// An invoice's payments, what's paid so far, and the buttons that go with them.
struct PaymentsBox: View {
    let model: AppModel
    let invoice: Invoice

    var body: some View {
        let share = invoice.amount.cents > 0 ? Double(invoice.paid.cents) / Double(invoice.amount.cents) : 0
        GroupBox("Payments") {
            VStack(alignment: .leading, spacing: 6) {
                if invoice.payments.isEmpty {
                    Text("No payments recorded yet.")
                }
                ForEach(invoice.payments) { payment in
                    HStack(spacing: 8) {
                        Text(payment.date.short)
                            .frame(width: 100, alignment: .leading)
                        Text(payment.method.label)
                            .frame(width: 110, alignment: .leading)
                        Text(payment.note)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(model.money(payment.amount))
                            .font(Win95.money)
                        SquareButton(PixelGlyph.cross,
                                     label: "Remove the \(model.money(payment.amount)) payment of \(payment.date.short)") {
                            model.removePayment(payment.id, from: invoice.id)
                        }
                    }
                }
                EtchedLine()
                HStack(spacing: 8) {
                    Text("Paid \(model.money(invoice.paid)) of \(model.money(invoice.amount))")
                    Spacer()
                    Win95Progress(fraction: share)
                        .frame(width: 160)
                }
                HStack(spacing: 6) {
                    if invoice.stage == .sent, invoice.owing > .zero {
                        Button("Record Payment…") { model.startPayment(invoice.id) }
                            .buttonStyle(.win95)
                    }
                    if !invoice.payments.isEmpty {
                        Button("Send Receipt…") { model.send(.receipt(invoice.id)) }
                            .buttonStyle(.win95)
                    }
                    if let sent = invoice.receiptSentAt {
                        Text("Receipt sent \(Day(sent).short)")
                    }
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}
```

- [ ] **Step 5: Show payments in the editor, and the toolbar button**

In `InvoiceEditorView.form(_:)`, add between the Lines and Terms group boxes:

```swift
            if current.stage != .draft {
                PaymentsBox(model: model, invoice: current)
            }
```

In `InvoiceEditorView.header(_:)`, add after the Send by Mail button:

```swift
                if invoice.stage == .sent, invoice.owing > .zero {
                    Button("Record Payment…") { model.startPayment(invoiceID) }
                }
                if !invoice.payments.isEmpty {
                    Button("Send Receipt…") { model.send(.receipt(invoiceID)) }
                }
```

In `Win95Toolbar`, replace the Payment button line with:

```swift
                tool("Payment", .payment, help: "Record a payment on the open or selected invoice",
                     enabled: model.payableInvoiceID != nil) {
                    if let id = model.payableInvoiceID { model.startPayment(id) }
                }
```

In `Sources/QuotePilotCore/Invoicing.swift`'s `removePayment(_:fromInvoice:)`, after removing the
payment, add:

```swift
        // No payments left means no receipt stands either.
        if invoices[index].payments.isEmpty { invoices[index].receiptSentAt = nil }
```

and add to `PaymentTests`:

```swift
    @Test func removingTheLastPaymentClearsTheReceipt() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        model.change("test") { try $0.markReceiptSent(invoice: invoice.id) }
        let payment = try #require(invoice.payments.first)
        model.removePayment(payment.id, from: invoice.id)
        model.respond(try #require(model.message?.choices.first { $0.title == "Remove" }))
        #expect(model.library.invoice(invoice.id)?.receiptSentAt == nil)
    }
```

- [ ] **Step 6: Run the tests and look at the dialog**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter PaymentTests`
Expected: all eight tests pass. Look at `build/snapshots/payment-dialog.png`. It should show the
dialog over INV-0003's editor: "Acme Test Co owes $135.00 on INV-0003.", the date, $135.00 in the
amount field, Bank transfer chosen, and Record outlined.

- [ ] **Step 7: Run everything and commit**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test`
Expected: everything passes.

```bash
git add Sources Tests
git commit -m "Record payments, remove them, and send receipts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: ⌘F: find in every list

A "Find:" field above the Quotes, Invoices, Clients and Activity lists filters as you type. It
matches every word anywhere in the row's text (number, client, title, status), ignoring case and
accents. ⌘F puts the cursor in the current list's field. Each section remembers its own search.

**Files:**
- Create: `Sources/QuotePilotUI/Screens/FindField.swift`
- Modify: `Sources/QuotePilotUI/App/AppModel.swift` (stored `findText`, `findRequest`; `find()`)
- Modify: `Sources/QuotePilotUI/Screens/QuotesView.swift`, `InvoicesView.swift`, `ClientsView.swift`
  and `ActivityView.swift` (a Find field and filtered rows)
- Modify: `Sources/QuotePilotUI/App/Commands.swift` (⌘F)
- Test: `Tests/QuotePilotUITests/FindTests.swift`

**Interfaces:**
- Consumes: the four list screens from plan 2a, and `InvoiceRow`, `QuoteRow` and `ClientSummary`.
- Produces:
  - `Find.matches(_ query:_ fields:) -> Bool` and `FindField(text:request:)`.
  - `AppModel.findText: [AppSection: String]`, `findRequest: Int`, `find()` and
    `findBinding(_ section:)`.
  - Static row builders, each applying the section's search:
    - `QuoteListView.visibleRows(_:)`;
    - `InvoicesView.visibleRows(_:)`;
    - `ClientsView.visibleClients(_:)`;
    - `ActivityView.visibleEntries(_:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/FindTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct FindTests {
    @Test func everyWordHasToMatchSomewhere() {
        let fields = ["Q-0002", "Example Bakery", "Menu boards", "Sent"]
        #expect(Find.matches("", fields))
        #expect(Find.matches("bakery", fields))
        #expect(Find.matches("BAKERY menu", fields))
        #expect(Find.matches("q-0002", fields))
        #expect(!Find.matches("bakery logo", fields))
        #expect(Find.matches("cafe", ["Northside Café"]))
    }

    @Test func eachListFiltersBySearch() throws {
        let model = try UIFixture.sampleModel()
        model.findText[.quotes] = "bakery"
        #expect(QuoteListView.visibleRows(model).map(\.number) == ["Q-0002", "Q-0004"])
        model.findText[.invoices] = "overdue"
        #expect(InvoicesView.visibleRows(model).map(\.number) == ["INV-0002"])
        model.findText[.clients] = "acme"
        #expect(ClientsView.visibleClients(model).map(\.name) == ["Acme Test Co"])
        model.findText[.activity] = "INV-0003"
        #expect(!ActivityView.visibleEntries(model).isEmpty)
        #expect(ActivityView.visibleEntries(model).allSatisfy { $0.number == "INV-0003" || $0.message.contains("INV-0003") })
    }

    @Test func commandFFocusesTheField() throws {
        let model = try UIFixture.sampleModel()
        model.find()
        model.find()
        #expect(model.findRequest == 2)
    }

    @Test func aFilteredListDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .quotes
        model.findText[.quotes] = "bakery"
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quotes-find")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter FindTests`
Expected: build failure, `cannot find 'Find' in scope`.

- [ ] **Step 3: Write `FindField.swift`**

```swift
import SwiftUI

enum Find {
    /// True when every word of `query` appears somewhere in `fields`, ignoring case and accents.
    /// An empty query matches everything.
    static func matches(_ query: String, _ fields: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = fields.joined(separator: " ")
        return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// "Find:" and a sunken field above a list. ⌘F (a new `request` number) puts the cursor in it.
struct FindField: View {
    @Binding var text: String
    let request: Int
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("Find:")
                .font(Win95.body)
                .foregroundStyle(Win95.text)
            TextField("Find", text: $text, prompt: Text("Number, client, title…"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(Win95.body)
                .foregroundStyle(Win95.text)
                .focused($focused)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .background(Win95.field)
                .overlay(Bevel(.sunken))
                .overlay(focused ? FocusRect().padding(3) : nil)
                .frame(maxWidth: 260)
                .accessibilityLabel("Find")
            if !text.isEmpty {
                Button("Clear") { text = "" }
                    .buttonStyle(.win95)
            }
        }
        .onChange(of: request) { _, _ in focused = true }
    }
}
```

- [ ] **Step 4: The model's search state (`AppModel.swift`)**

Add beside the other stored properties:

```swift
    /// Each list's search text, kept while you move between sections.
    public var findText: [AppSection: String] = [:]
    /// Bumped by ⌘F; the current list's Find field takes the cursor.
    public var findRequest = 0
```

and the methods:

```swift
    /// ⌘F
    public func find() {
        findRequest += 1
    }

    public func findBinding(_ section: AppSection) -> Binding<String> {
        Binding(get: { self.findText[section, default: ""] }, set: { self.findText[section] = $0 })
    }
```

- [ ] **Step 5: Filter the four lists**

The pattern is the same in each list. Add a static builder that applies the section's search. Use
it for the rows. Put `FindField(text: model.findBinding(<section>), request: model.findRequest)` at
the right of the list's button row, or on a row of its own above the list when there's no button
row. When the search hides every row, the empty text says so.

`QuotesView.swift` (`QuoteListView`):

```swift
    /// The quotes the list shows: all of them, or those matching the search.
    static func visibleRows(_ model: AppModel) -> [QuoteRow] {
        let query = model.findText[.quotes, default: ""]
        return model.library.quotes
            .map { QuoteRow($0, library: model.library, today: model.today) }
            .filter { Find.matches(query, [$0.number, $0.client, $0.title, $0.status.label]) }
    }
```

In `body`, use `let rows = Self.visibleRows(model)`, add the `FindField` before the count text, and
change `emptyText:` to:

```swift
                        emptyText: model.findText[.quotes, default: ""].isEmpty
                            ? "No quotes yet. Press New Quote (⌘N) to write one."
                            : "No quotes match \"\(model.findText[.quotes, default: ""])\".",
```

`InvoicesView.swift`:

```swift
    static func visibleRows(_ model: AppModel) -> [InvoiceRow] {
        let query = model.findText[.invoices, default: ""]
        return model.library.invoices
            .map { InvoiceRow($0, library: model.library, today: model.today) }
            .filter { Find.matches(query, [$0.number, $0.client, $0.kind, $0.status.listLabel]) }
    }
```

Use it in `list` and add the `FindField` to the button row (after Open, before the `Spacer`).

`ClientsView.swift`:

```swift
    static func visibleClients(_ model: AppModel) -> [Client] {
        let query = model.findText[.clients, default: ""]
        return model.library.clients.filter {
            Find.matches(query, [$0.name, $0.contactName, $0.email, $0.phone])
        }
    }
```

Pass it to the `DetailsList`, and add the `FindField` after New Client.

`ActivityView.swift`:

```swift
    static func visibleEntries(_ model: AppModel) -> [ActivityEntry] {
        let query = model.findText[.activity, default: ""]
        return model.library.activity.filter { Find.matches(query, [$0.number ?? "", $0.message]) }
    }
```

Wrap the list in a `VStack(alignment: .leading, spacing: 6)` with an `HStack` holding the `FindField`
and a `Spacer` above it, and pass `Self.visibleEntries(model)` as the rows.

- [ ] **Step 6: ⌘F (`Commands.swift`)**

Add a group after the Go menu:

```swift
        CommandGroup(after: .textEditing) {
            Button("Find…") { model.find() }
                .keyboardShortcut("f")
        }
```

- [ ] **Step 7: Run the tests and look at the list**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter FindTests`
Expected: all four tests pass. `build/snapshots/quotes-find.png` should show "bakery" in the Find
field, with Q-0002 and Q-0004 only.

- [ ] **Step 8: Run everything and commit**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests
git commit -m "Find in every list with ⌘F

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The File menu: import, the tax-time export, Back Up To…, Restore Backup…

The File menu gains four items:
- **Import from Invoice Generator…** reads the old tool's backup file. It then shows what came in,
  plus the importer's notes, such as payments to record by hand. The old logo becomes the brand logo
  if there isn't one yet.
- **Export Payments for Tax Time…** asks which financial year, then saves a CSV.
- **Back Up To…** saves a copy of the library anywhere.
- **Restore Backup…** lists the daily backups and restores one, after a question. The current library
  is kept beside it.

All three saves use the one save panel, which now handles PDF, CSV and JSON.

**Files:**
- Create: `Sources/QuotePilotUI/App/AppModel+Files.swift`
- Create: `Sources/QuotePilotUI/Screens/FileDialogs.swift` (import report, tax year, restore list)
- Modify: `Sources/QuotePilotUI/App/AppModel.swift` (`PDFExport` → `FileExport` with a content
  type; `copyAsset` becomes internal; `restoreLatestBackup` uses `restore(from:)`)
- Modify: `Sources/QuotePilotUI/Screens/PDFPreview.swift` (`PDFFile` → `ExportFile`)
- Modify: `Sources/QuotePilotUI/App/AppModel+Acceptance.swift` (`FileChoice.legacyBackup`)
- Modify: `Sources/QuotePilotUI/App/Dialogs.swift` (three dialogs)
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (the save panel's content type)
- Modify: `Sources/QuotePilotUI/App/Commands.swift` (the four items)
- Modify: `Tests/QuotePilotUITests/AppModelTests.swift` (renamed export type, if it names it)
- Test: `Tests/QuotePilotUITests/FileMenuTests.swift`

**Interfaces:**
- Consumes:
  - core: `LegacyImport.importBackup(_:into:today:)`, `ImportReport`, `Library.paymentsCSV(for:)`,
    `FinancialYear`, `LibraryStore.backups()` and `restore(from:now:)`;
  - PDF: `Logo(url:)`.
- Produces:
  - `FileExport(data:fileName:contentType:)` and `ExportFile`; `FileChoice.legacyBackup`.
  - **Dialogs:** `.importReport(ImportReport)`, `.taxExport` and `.restore`.
  - **AppModel:**
    - `importLegacyBackup(at:)` and `taxYears`;
    - `exportPayments(for:)` and `exportBackupCopy()`;
    - `askToRestore(_:)` and `restore(from:)`.
  - Views: `ImportReportView`, `TaxExportView` and `RestoreView`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/FileMenuTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct FileMenuTests {
    /// A made-up backup in Invoice Generator's format, with no logo.
    static let legacyBackup = Data(#"""
    {
      "app": "invoice-quote-maker",
      "settings": { "logo": "", "logoHeight": 56, "accent": "#0B6B66", "paper": "A4" },
      "docs": {
        "a1": { "id": "a1", "type": "quote", "number": "Q-0101", "issued": "2026-10-04", "due": "2026-11-03",
                "reference": "Shop fit-out", "from": { "name": "Sample Studio", "details": "" },
                "to": { "name": "Northside Example Cafe", "details": "" },
                "items": [ { "title": "Design", "detail": "", "qty": 1, "unit": "unit", "rate": 500 } ],
                "tax": { "mode": "none", "rate": 10, "label": "GST" }, "discount": { "value": 0, "kind": "pct" },
                "paid": 0, "summary": "", "payment": "", "notes": "" },
        "b2": { "id": "b2", "type": "invoice", "number": "INV-0101", "issued": "2026-10-06", "due": "2026-10-20",
                "reference": "", "from": { "name": "Sample Studio", "details": "" },
                "to": { "name": "Northside Example Cafe", "details": "" },
                "items": [ { "title": "Hosting", "detail": "", "qty": 1, "unit": "unit", "rate": 30 } ],
                "tax": { "mode": "none", "rate": 10, "label": "GST" }, "discount": { "value": 0, "kind": "pct" },
                "paid": 10, "summary": "", "payment": "", "notes": "" }
      },
      "currentId": "a1"
    }
    """#.utf8)

    @Test func importingABackupAddsItsDocumentsAndShowsTheReport() throws {
        let model = try UIFixture.sampleModel()
        model.importLegacyBackup(at: try UIFixture.file("invoices-backup.json", Self.legacyBackup))
        #expect(model.library.quote(number: "Q-0101") != nil)
        #expect(model.library.invoices.contains { $0.number == "INV-0101" })
        guard case .importReport(let report) = model.dialog else {
            Issue.record("Expected the import report")
            return
        }
        #expect(report.addedQuotes == ["Q-0101"])
        #expect(report.notes.contains { $0.contains("Record it as a payment") })
    }

    @Test func aFileThatIsntABackupChangesNothing() throws {
        let model = try UIFixture.sampleModel()
        let before = model.library.quotes.count
        model.importLegacyBackup(at: try UIFixture.file("notes.json", Data(#"{"hello":1}"#.utf8)))
        #expect(model.library.quotes.count == before)
        #expect(model.message?.text == LegacyImportError.notABackup.message)
    }

    @Test func theTaxExportSavesACSVForTheChosenYear() throws {
        let model = try UIFixture.sampleModel()
        let year = FinancialYear(containing: UIFixture.today)
        #expect(model.taxYears.first == year)
        model.exportPayments(for: year)
        let export = try #require(model.pendingExport)
        #expect(export.contentType == .commaSeparatedText)
        #expect(export.fileName == "Payments FY 2026-27.csv")
        let csv = String(decoding: export.data, as: UTF8.self)
        #expect(csv.hasPrefix("Date,Client,Invoice,Amount,Method,Note"))
        #expect(csv.contains("INV-0001"))
        #expect(model.dialog == nil)
    }

    @Test func backUpToSavesTheLibraryFile() throws {
        let model = try UIFixture.sampleModel()
        model.exportBackupCopy()
        let export = try #require(model.pendingExport)
        #expect(export.contentType == .json)
        #expect(export.fileName == "Quote Pilot backup 2026-10-15.json")
        #expect(export.data == (try Data(contentsOf: model.store.libraryURL)))
    }

    @Test func restoringAChosenBackupAsksFirst() throws {
        let model = try UIFixture.sampleModel()
        let backup = try #require(model.store.backups().first)
        model.newQuote()
        #expect(model.library.quotes.count == 5)
        model.askToRestore(backup)
        #expect(model.library.quotes.count == 5)
        model.respond(try #require(model.message?.choices.first { $0.title == "Restore" }))
        #expect(model.library.quotes.count == 4)
        #expect(model.message?.title == "Backup Restored")
    }

    @Test func theFileDialogsDraw() throws {
        let model = try UIFixture.sampleModel()
        var report = ImportReport()
        report.addedQuotes = ["Q-0101"]
        report.addedInvoices = ["INV-0101"]
        report.notes = ["INV-0101: the old tool showed $10.00 already paid. Record it as a payment with the date it arrived."]
        model.dialog = .importReport(report)
        #expect(Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "import-report")
            .map(Snapshot.hasContent) == true)
        model.dialog = .taxExport
        #expect(Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "tax-export")
            .map(Snapshot.hasContent) == true)
        model.dialog = .restore
        #expect(Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "restore")
            .map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter FileMenuTests`
Expected: build failure, `value of type 'AppModel' has no member 'importLegacyBackup'`.

- [ ] **Step 3: One save panel for every kind of file (`AppModel.swift`, `PDFPreview.swift`, `RootView.swift`)**

- In `AppModel.swift`, rename `PDFExport` to `FileExport` and give it a content type:

  ```swift
  /// A file waiting for the save panel: a PDF, the tax-time CSV, or a copy of the library.
  public struct FileExport {
      public var data: Data
      public var fileName: String
      public var contentType: UTType = .pdf
  }
  ```

  Add `import UniformTypeIdentifiers`, and change `pendingExport`'s type to `FileExport?`.
  `exportPDF()` builds `FileExport(data: pdf(content), fileName: content.fileName)`.
- In `PDFPreview.swift`, rename `PDFFile` to `ExportFile`. Its
  `readableContentTypes` becomes `[.pdf, .commaSeparatedText, .json]`.
- In `RootView`'s `.fileExporter`, use `ExportFile(data: $0.data)` and
  `contentType: model.pendingExport?.contentType ?? .pdf`.
- Update any test that names `PDFExport`.
- Make `copyAsset(_:prefix:)` in `AppModel.swift` internal (drop `private`), so `AppModel+Files.swift`
  can save an imported logo.

- [ ] **Step 4: One restore path (`AppModel.swift`)**

Replace `restoreLatestBackup()` with a general `restore(from:)`, and keep the old name as the
unreadable screen's shortcut:

```swift
    /// Puts the newest backup back (the unreadable-library screen's button).
    public func restoreLatestBackup() {
        guard let backup = latestBackup else {
            show(title: "No Backup", text: "There's no backup to restore yet.", kind: .warning)
            return
        }
        restore(from: backup)
    }

    /// Replaces the library with a backup. `LibraryStore` keeps the file it replaces beside it.
    public func restore(from backup: URL) {
        do {
            library = try store.restore(from: backup, now: now())
        } catch {
            show(error, title: "Couldn't restore the backup")
            return
        }
        loadState = .ready
        lastSaved = now()
        openQuoteID = nil
        openInvoiceID = nil
        // Keep plan 2a's guard: a failed Activity note (or backup) message stays visible, with a
        // sentence saying the restore itself worked, instead of being replaced by the success box.
        // Move plan 2a's existing restoreLatestBackup body here rather than retyping it.
        guard change("Couldn't note the restore in Activity", { $0.log("Restored the backup \(backup.lastPathComponent)") }),
              message == nil
        else {
            message?.text += " The backup itself was restored."
            return
        }
        show(title: "Backup Restored",
             text: "Quote Pilot restored \(backup.lastPathComponent). The library it replaced is kept in the same folder, named library-replaced-….json.")
    }
```

- [ ] **Step 5: Write `AppModel+Files.swift`**

```swift
import Foundation
import QuotePilotCore
import QuotePilotPDF
import UniformTypeIdentifiers

extension AppModel {
    // MARK: Import from Invoice Generator

    public func importLegacyBackup(at url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            return show(LegacyImportError.notABackup, title: "Can't Import That File")
        }
        var report: ImportReport?
        let saved = change("Can't Import That File") { library in
            report = try LegacyImport.importBackup(data, into: &library, today: today)
        }
        guard saved, var report else { return }
        if let logo = report.logoData, library.brand.logoFile == nil, !useImportedLogo(logo) {
            report.notes.append("The old tool's logo couldn't be read. Add your logo on the Brand page.")
        }
        dialog = .importReport(report)
    }

    /// Saves the old tool's logo into Assets as the brand logo. False when it isn't a usable image.
    private func useImportedLogo(_ data: Data) -> Bool {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF]
        let ext: String
        if data.starts(with: png) { ext = "png" } else if data.starts(with: jpeg) { ext = "jpg" } else { return false }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("imported-logo-\(UUID().uuidString).\(ext)")
        guard (try? data.write(to: temporary)) != nil, Logo(url: temporary) != nil,
              let name = copyAsset(temporary, prefix: "logo")
        else { return false }
        return change("Couldn't use the imported logo") { $0.brand.logoFile = name }
    }

    // MARK: Tax time

    /// Financial years with payments, plus this one, newest first.
    public var taxYears: [FinancialYear] {
        var years = Set(library.invoices.filter { $0.stage == .sent }.flatMap(\.payments).map { FinancialYear(containing: $0.date) })
        years.insert(FinancialYear(containing: today))
        return years.sorted { $0.startYear > $1.startYear }
    }

    public func exportPayments(for year: FinancialYear) {
        dialog = nil
        let name = "Payments FY \(year.startYear)-\(String(format: "%02d", (year.startYear + 1) % 100)).csv"
        pendingExport = FileExport(data: Data(library.paymentsCSV(for: year).utf8), fileName: name,
                                   contentType: .commaSeparatedText)
    }

    // MARK: Backups

    /// "Back Up To…": a copy of the library file, saved wherever you choose.
    public func exportBackupCopy() {
        guard let data = try? Data(contentsOf: store.libraryURL) else {
            return show(title: "Nothing to Back Up", text: "There's nothing saved yet. Make a change first.")
        }
        pendingExport = FileExport(data: data, fileName: "Quote Pilot backup \(today.iso).json", contentType: .json)
    }

    /// Asks before restoring a backup over the library.
    public func askToRestore(_ backup: URL) {
        confirm(title: "Restore Backup",
                text: "Replace the library with \(backup.lastPathComponent)? The library it replaces is kept in the same folder.",
                confirm: "Restore") {
            self.dialog = nil
            self.restore(from: backup)
        }
    }
}
```

Add `legacyBackup` to `FileChoice` in `AppModel+Acceptance.swift`:

```swift
public enum FileChoice: Equatable {
    case returnedQuote
    case legacyBackup

    var contentTypes: [UTType] {
        switch self {
        case .returnedQuote: return [.pdf]
        case .legacyBackup: return [.json]
        }
    }
}
```

and handle it in `fileChosen(_:)`:

```swift
            case .legacyBackup?: importLegacyBackup(at: url)
```

- [ ] **Step 6: The dialogs (`Dialogs.swift`, `FileDialogs.swift`)**

Add to `enum Dialog`:

```swift
    /// What an import brought in, and what to do by hand.
    case importReport(ImportReport)
    /// Choose the financial year for the payments CSV.
    case taxExport
    /// Choose a daily backup to restore.
    case restore
```

and to `DialogOverlay`'s `switch`:

```swift
            case .importReport(let report):
                ImportReportView(model: model, report: report)
            case .taxExport:
                TaxExportView(model: model)
            case .restore:
                RestoreView(model: model)
```

`Sources/QuotePilotUI/Screens/FileDialogs.swift`:

```swift
import QuotePilotCore
import SwiftUI

/// What came in from Invoice Generator, and anything to finish by hand.
struct ImportReportView: View {
    let model: AppModel
    let report: ImportReport

    var body: some View {
        DialogPanel(title: "Import from Invoice Generator", icon: .folder, width: 520) {
            VStack(alignment: .leading, spacing: 10) {
                Text(report.summary)
                    .fixedSize(horizontal: false, vertical: true)
                if !report.addedClients.isEmpty {
                    Text("New clients: \(report.addedClients.joined(separator: ", ")).")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !report.notes.isEmpty {
                    Text("To finish by hand:").font(Win95.label)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                                NoteBanner(note)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                HStack {
                    Spacer()
                    Button("OK") { model.dialog = nil }
                        .buttonStyle(.win95Default)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}

/// Which financial year's payments to export.
struct TaxExportView: View {
    let model: AppModel
    @State private var year: FinancialYear?

    var body: some View {
        let years = model.taxYears
        DialogPanel(title: "Export Payments for Tax Time", icon: .payment) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quote Pilot saves a spreadsheet (CSV) of every payment received in the year: date, client, invoice, amount, method and note.")
                    .fixedSize(horizontal: false, vertical: true)
                Win95RadioGroup(selection: Binding(get: { year ?? years.first }, set: { year = $0 }),
                                options: years.map { (Optional($0), $0.label) })
                HStack(spacing: 8) {
                    Spacer()
                    Button("Export…") {
                        if let chosen = year ?? years.first { model.exportPayments(for: chosen) }
                    }
                    .buttonStyle(.win95Default)
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}

/// The daily backups, newest first; restore one.
struct RestoreView: View {
    let model: AppModel
    @State private var selection: URL?

    var body: some View {
        let backups = model.store.backups()
        DialogPanel(title: "Restore Backup", icon: .folder, width: 480) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quote Pilot backs up the library once a day and keeps the last 30. Restoring replaces the library with the one you choose; the current one is kept beside it.")
                    .fixedSize(horizontal: false, vertical: true)
                DetailsList(backups, id: \.self, columns: [
                    .text("Backup", width: .flexible(min: 160)) { RestoreView.label($0) },
                ], selection: $selection, emptyText: "No backups yet.",
                onOpen: { model.askToRestore($0) })
                .frame(height: 220)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Restore…") { if let selection { model.askToRestore(selection) } }
                        .buttonStyle(.win95Default)
                        .disabled(selection == nil)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }

    /// "library-2026-10-15.json" → "15 Oct 2026".
    static func label(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("library-"), let day = Day(iso: String(name.dropFirst("library-".count))) else { return name }
        return day.short
    }
}
```

`Win95RadioGroup` needs a `Hashable` value. `FinancialYear` is `Hashable`, so `FinancialYear?` is too.

- [ ] **Step 7: The File menu (`Commands.swift`)**

Add a group after the save items:

```swift
        CommandGroup(after: .saveItem) {
            Button("Import from Invoice Generator…") { model.choosingFile = .legacyBackup }
            Button("Export Payments for Tax Time…") { model.dialog = .taxExport }
            Divider()
            Button("Back Up To…") { model.exportBackupCopy() }
            Button("Restore Backup…") { model.dialog = .restore }
        }
```

- [ ] **Step 8: Run the tests and look at the dialogs**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter FileMenuTests`
Expected: all six tests pass. Check the snapshots:
- `import-report.png` shows the summary and the payment note;
- `tax-export.png` shows FY 2026–27 chosen;
- `restore.png` shows today's backup as "15 Oct 2026".

- [ ] **Step 9: Run everything and commit**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests
git commit -m "File menu: import from Invoice Generator, tax-time CSV, Back Up To and Restore Backup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: An app icon, the README, and the finished app

The app gets a Dock icon drawn from its own pixel art: the quote icon on teal. The binary renders it
itself, so the icon never drifts from the code. The README then describes the whole app, the final
build is made, and every snapshot is regenerated.

**Files:**
- Create: `Sources/QuotePilotUI/App/AppIcon.swift`
- Modify: `Sources/QuotePilotUI/Win95/PixelIcon.swift` (draw pixels without anti-aliasing, so any
  size is crisp and seamless)
- Modify: `Sources/QuotePilotApp/QuotePilotApp.swift` (`--make-iconset <folder>`)
- Modify: `build.sh` (make `AppIcon.icns` and bundle it)
- Modify: `Resources/Info.plist` (`CFBundleIconFile`)
- Modify: `README.md`
- Test: `Tests/QuotePilotUITests/AppIconTests.swift`

**Interfaces:**
- Consumes: `PixelIconView`, `Win95` (plan 2a), and `iconutil` (in macOS).
- Produces: `AppIconView(size:)`, `AppIcon.writeIconset(to:)` and `build/Quote Pilot.app` with its
  icon.

- [ ] **Step 1: Write the failing test**

`Tests/QuotePilotUITests/AppIconTests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import QuotePilotUI

@MainActor
@Suite struct AppIconTests {
    @Test func theIconsetHasEverySizeMacOSAsksFor() throws {
        let folder = UIFixture.makeFolder().appendingPathComponent("AppIcon.iconset")
        try AppIcon.writeIconset(to: folder)
        let expected = ["icon_16x16.png": 16, "icon_16x16@2x.png": 32, "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
                        "icon_128x128.png": 128, "icon_128x128@2x.png": 256, "icon_256x256.png": 256,
                        "icon_256x256@2x.png": 512, "icon_512x512.png": 512, "icon_512x512@2x.png": 1024]
        for (name, pixels) in expected {
            let image = try #require(NSBitmapImageRep(data: try Data(contentsOf: folder.appendingPathComponent(name))), "\(name)")
            #expect(image.pixelsWide == pixels, "\(name)")
            #expect(image.pixelsHigh == pixels, "\(name)")
        }
    }
}
```

- [ ] **Step 2: Run it to watch it fail**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter AppIconTests`
Expected: build failure, `cannot find 'AppIcon' in scope`.

- [ ] **Step 3: Crisp pixels at any size (`PixelIcon.swift`), then `AppIcon.swift`**

The icon is drawn at sizes that aren't multiples of 16. Anti-aliased pixel squares then show faint
seams. In `PixelIconView.body`, give the fill a style:

```swift
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(color), style: FillStyle(antialiased: false))
```

Then write `AppIcon.swift`:

```swift
import AppKit
import SwiftUI

/// The Dock icon: the quote icon's pixel art, large, on a teal tile with a raised edge.
public struct AppIconView: View {
    let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        let tile = size * 0.82
        ZStack {
            RoundedRectangle(cornerRadius: tile * 0.2)
                .fill(Win95.desktop)
                .frame(width: tile, height: tile)
                .overlay(
                    RoundedRectangle(cornerRadius: tile * 0.2)
                        .strokeBorder(Win95.highlight.opacity(0.6), lineWidth: max(1, size / 64))
                )
            PixelIconView(.quote, size: tile * 0.75)
        }
        .frame(width: size, height: size)
    }
}

public enum AppIcon {
    /// Writes an `.iconset` folder for `iconutil`: every size macOS asks for, drawn by `AppIconView`.
    @MainActor
    public static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let renderer = ImageRenderer(content: AppIconView(size: CGFloat(pixels)))
                renderer.scale = 1
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try png.write(to: folder.appendingPathComponent(name))
            }
        }
    }
}
```

- [ ] **Step 4: `--make-iconset` (`QuotePilotApp.swift`), `build.sh` and `Info.plist`**

In `QuotePilotApp.init()`, add first:

```swift
        // build.sh runs the binary with `--make-iconset <folder>` to draw the Dock icon, then quits.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--make-iconset"), arguments.indices.contains(flag + 1) {
            do {
                try AppIcon.writeIconset(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Couldn't draw the icon: \(error)\n".utf8))
                exit(1)
            }
        }
```

In `build.sh`, after the `cp Resources/Info.plist …` line, add:

```bash
# The Dock icon, drawn by the app's own pixel-art code.
"$binary" --make-iconset build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
```

In `Resources/Info.plist`, add inside the `<dict>`:

```xml
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
```

Then run: `./build.sh`
Expected: `Built build/Quote Pilot.app`, and `build/Quote Pilot.app/Contents/Resources/AppIcon.icns`
exists. Look at `build/AppIcon.iconset/icon_256x256.png` with Read: a teal tile with the
page-and-tick pixel icon.

- [ ] **Step 5: The README**

Replace the **Status** paragraph with:

```markdown
**Status:** the whole first version works. It covers quotes with a tick-box PDF, reading the
returned PDF, invoices (deposit and balance, or full amount), payments, receipts, Mail drafts, a
dashboard, and backups. It's built and tested on macOS 26 with Apple's Command Line Tools.
```

Replace the sections `## The Mac app` and `## Coming next` with:

```markdown
## The Mac app

A Windows 95-style window: a navy title bar, bevelled buttons and pixel icons, built to be read at a
glance.

- **Dashboard:** what you're waiting to be paid, what's overdue, what's come in this financial year
  and what's quoted, in big numbers, with the lists behind them.
- **Quotes:** an editor with a live preview of the PDF the client will tick. **Send by Mail** opens a
  Mail draft with the PDF attached, and you press Send. Quote Pilot then asks whether you sent it.
- **Returned quotes:** drop the client's PDF anywhere on the window, or use File → Read Returned
  Quote…. Check the ticks and confirm. A 50/50 quote then drafts its deposit invoice. If the
  client's app lost the ticks, tick the lines by hand.
- **Invoices:** deposits and balances from quotes (**Draft Invoice Now**, **Job Complete**), one-off
  invoices, payments, receipts, and voiding.
- **Clients**, **Brand** (logo, heading font, colour, wording and terms) and **Activity**, a log of
  what happened: quotes started and sent, Mail drafts, acceptances, invoices, payments and restores.
  ⌘F finds anything in a list.
- **File menu:** import from the old Invoice Generator, export the year's payments for tax time, back
  up anywhere, or restore a daily backup.
- Every change saves as you make it, with a daily backup. If the library file is ever damaged,
  Quote Pilot won't save over it and offers the latest backup instead. Every mailed PDF is also kept
  in `~/Documents/Quote Pilot/<year>/`.
```

Two lines in `## Built and tested so far` are stale now that the app exists. Change them:
- The intro sentence ("Today you can try the quote, invoice and receipt PDFs with the `qp` tool;
  everything else runs once the app's screens arrive.") becomes "Everything below runs in the Mac
  app; the `qp` tool can also make sample PDFs and read a returned quote from the terminal."
- The `qp` bullet ("a small command-line tool for trying the PDFs before the app exists") becomes
  "a small command-line tool for trying the PDFs and a sample library from the terminal."

- [ ] **Step 6: Everything, every snapshot, and the build**

Run: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk QP_SNAPSHOTS="$PWD/build/snapshots" swift test`
Expected: every test passes, and `build/snapshots/` holds plan 2a's pictures plus these:
- `email-prompt`, `acceptance-review`;
- `invoice-editor`, `quote-editor-actions`, `payment-dialog`;
- `quotes-find`, `import-report`, `tax-export` and `restore`.

Run: `./build.sh`
Expected: `Built build/Quote Pilot.app`.

Launch it against a fresh demo library and quit it, as plan 2a Task 6 Step 10 does. It should stay
up with no crash.

- [ ] **Step 7: Commit**

```bash
git add README.md build.sh Resources Sources Tests
git commit -m "App icon from the pixel art, and the README for the finished app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

The controller then walks through the real app with the demo library:
1. Send a quote (Mail opens a draft; answer Not Yet).
2. Drop a ticked PDF on the window.
3. Confirm, and see the deposit open.
4. Record a payment.
5. Find with ⌘F.
6. Export the tax CSV.
7. Restore a backup.

It reports anything that doesn't behave as the README says.
