# Quote Pilot, plan 1 of 2: core rules and PDFs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Quote Pilot's tested foundation: the money and document rules (quotes, acceptance,
50/50 and full-amount invoicing, payments, dashboard figures, saving, import from the old HTML tool) and
the PDFs (quote with a fillable tick-box form, invoices, receipts, and reading a returned quote), plus a
small `qp` command for trying it all before the app's screens exist.

**Architecture:** One Swift package. `QuotePilotCore` is pure Swift with no UI and holds every rule.
`QuotePilotPDF` draws documents with Core Text, adds the form with PDFKit and reads it back.
`qp` is a command-line tool over both. Plan 2 adds the SwiftUI app on top of the same two libraries.

**Tech Stack:** Swift 6.4 (Command Line Tools 27.0, no Xcode), Swift Testing, Foundation, Core Text,
Core Graphics, PDFKit, AppKit (fonts and colours only). No third-party packages.

**Spec:** `docs/superpowers/specs/2026-10-15-quote-pilot-design.md`

## Global Constraints

- macOS 14 and later. `// swift-tools-version: 6.0`. `QuotePilotCore` and its tests use Swift 6 language
  mode; `QuotePilotPDF`, `qp` and the PDF tests use `.swiftLanguageMode(.v5)` (PDFKit and AppKit types
  aren't `Sendable`).
- No third-party dependencies.
- Money is whole cents (`Money`, an `Int`), never `Double`. Display is Australian: `$1,500.00`.
  Quantities are `Decimal`. Every line rounds half up to the cent.
- Document dates are `Day` (year, month, day, no time zone). Moments (sent at, recorded at) are `Date`.
- Numbers are `Q-0001` and `INV-0001` (four digits), one past the highest ever used, and **never reused**,
  even after a draft is deleted.
- Line IDs (`code`) are `"01"`, `"02"`, … They follow line order while a quote is a draft and are frozen
  once it's sent.
- Form field names: `quotepilot_<quote number>_all`, `quotepilot_<quote number>_line_<code>`,
  `quotepilot_<quote number>_name`, `quotepilot_<quote number>_date` (underscores, because PDF reserves
  '.' for field hierarchy). Every tick box starts **off**.
- PDFs: A4 (595.28 × 841.89 pt), 46 pt margins, ink `#1F2A44`, default accent `#0B6B66`, heading font
  from the brand's font file (system semibold if none), body in the system font.
- GST is off by default (`Brand.gstRegistered = false`). When a document is taxed: 10% on top, invoice
  title "Tax invoice", and the ABN printed.
- 50/50: deposit = 50% of the accepted total, rounded half up; the final invoice subtracts the deposit
  invoice, so the two always add up to the accepted total exactly.
- **The repo is public:** all sample and test data is made up (for example "Sample Client Pty Ltd").
  No real client names, prices, bank details or ABNs.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

The five inputs most likely to bite someone using this, each pinned by a test in the task named:

1. **A 50/50 split of an odd-cent total** (e.g. $1,500.01): the deposit and final invoices must add up
   to the accepted total exactly. Task 4, `oddCentsSplitAddsUpExactly`.
2. **A returned PDF from a quote that was edited after sending** (lines added or removed): the
   proposal must name the missing and unknown lines, and nothing is recorded until confirmed. Task 3,
   `proposalFlagsLinesTheClientNeverSaw`.
3. **Due-date and financial-year edges:** an invoice due today isn't overdue, the next day it's 1 day
   late; a payment on 30 June and one on 1 July land in different financial years. Task 4,
   `overdueStartsTheDayAfterDue`; Task 5, `financialYearEdges`.
4. **An unreadable or newer-format library file:** Quote Pilot must never write over it. Task 6,
   `refusesToOverwriteAnUnreadableLibrary`.
5. **Long quotes:** 40 lines with long details must flow onto several pages, with each line's tick
   box on the same page as the line. Task 9, `longQuoteKeepsEachTickBoxWithItsLine`.

---

## File structure

```
Package.swift
Sources/QuotePilotCore/
  QuotePilotCore.swift     module overview comment
  Money.swift              whole-cent money, rounding, parsing, AUD formatting
  Day.swift                calendar day without time zones
  LineItem.swift           LineItem, Unit, LineDecision, Totals
  Models.swift             Brand, email templates, Client, PaymentPlan, Quote, Acceptance,
                           Invoice, Payment, Deduction, ActivityEntry
  Library.swift            the whole library: numbering, lookups, adding, deleting, activity log
  QuoteLifecycle.swift     quote status, line IDs, sending, returned-form proposal, acceptance
  Invoicing.swift          invoice status, drafting deposit/final/full, job complete, payments,
                           void, receipts, duplicates
  Dashboard.swift          FinancialYear, dashboard figures, tax-time CSV
  LibraryStore.swift       load, safe save, daily backups, restore
  LegacyImport.swift       import from Invoice Generator.html's backup JSON
Sources/QuotePilotPDF/
  PDFStyle.swift           colours, fonts, logo
  PageWriter.swift         paged drawing with Core Text from the top of the page down
  DocumentContent.swift    render-ready content, built from a quote, invoice or receipt
  DocumentRenderer.swift   draws content to PDF data and adds the quote form
  QuoteFormFields.swift    form field names, shared by the renderer and the reader
  ReturnedQuoteReader.swift  reads ticks, name and date out of a returned PDF
Sources/qp/main.swift      `qp samples <folder>` and `qp read <pdf>`
Tests/QuotePilotCoreTests/ MoneyTests, DayTests, ModelTests, Fixtures, QuoteLifecycleTests,
                           InvoicingTests, DashboardTests, LibraryStoreTests, LegacyImportTests
Tests/QuotePilotPDFTests/  RendererTests, FormRoundTripTests
README.md, LICENSE
```

---

### Task 1: Working toolchain, package skeleton, `Money` and `Day`

**Files:**
- Create: `Package.swift`
- Create: `Sources/QuotePilotCore/QuotePilotCore.swift`
- Create: `Sources/QuotePilotCore/Money.swift`
- Create: `Sources/QuotePilotCore/Day.swift`
- Test: `Tests/QuotePilotCoreTests/MoneyTests.swift`
- Test: `Tests/QuotePilotCoreTests/DayTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Money(cents:)`, `Money(dollars:cents:)`, `Money.zero`, `+ - += -= <`
  - `times(_: Decimal) -> Money`, `percent(_: Int) -> Money`
  - `formatted(currencyCode:) -> String`, `plain: String`, `Money(parsing: String)?`
  - Codable as an integer of cents
  - `Day(year:month:day:)`, `Day(_: Date, timeZone:)`, `Day.today()`, `Day(iso:)?`
  - `iso`, `long`, `short`, `adding(days:) -> Day`, `days(since:) -> Int`
  - Comparable; Codable as `"2026-10-15"`

- [ ] **Step 1: Confirm the repaired toolchain**

The user installed Command Line Tools for Xcode 27.0 on 15 Oct 2026 (Swift 6.4). With it, SwiftPM's
build system doesn't find the Swift Testing macro plugin on its own (`plugin for module 'TestingMacros'
not found`), so `Package.swift` points the compiler at
`/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` when that folder exists.
That fix was proven in a scratch package before this plan ran.

Run: `swift --version && swift package --version`
Expected: `Apple Swift version 6.4` and `Swift Package Manager - Swift 6.4…`, with **no**
`dyld … Symbol not found` error. If it's back, stop and tell the user.

- [ ] **Step 2: Write `Package.swift` (core only for now)**

```swift
// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Command Line Tools 27.0 install the Swift Testing macro plugin in a folder SwiftPM's build system
// doesn't search. Point the compiler at it when it's there; Xcode users don't need this.
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])]
    : []

let package = Package(
    name: "QuotePilot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuotePilotCore", targets: ["QuotePilotCore"]),
    ],
    targets: [
        .target(name: "QuotePilotCore"),
        .testTarget(name: "QuotePilotCoreTests", dependencies: ["QuotePilotCore"],
                    swiftSettings: testSettings),
    ]
)
```

`Sources/QuotePilotCore/QuotePilotCore.swift`:

```swift
// QuotePilotCore holds every business rule in Quote Pilot: money, dates, quotes, acceptance,
// invoices, payments, dashboard figures, saving and importing. It has no UI and no PDF code,
// so all of it can be tested directly.
```

- [ ] **Step 3: Write the failing tests**

`Tests/QuotePilotCoreTests/MoneyTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct MoneyTests {
    @Test func formatsAustralianDollars() {
        #expect(Money(dollars: 1500).formatted() == "$1,500.00")
        #expect(Money(cents: 5).formatted() == "$0.05")
    }

    @Test func multipliesByAQuantityAndRoundsHalfUp() {
        #expect(Money(dollars: 40).times(1.5) == Money(dollars: 60))
        #expect(Money(cents: 333).times(0.5) == Money(cents: 167))   // 166.5 → 167
        #expect(Money(cents: 101).times(0.25) == Money(cents: 25))   // 25.25 → 25
    }

    @Test func percentagesRoundHalfUp() {
        #expect(Money(cents: 150_001).percent(50) == Money(cents: 75_001))  // 75,000.5 → 75,001
        #expect(Money(dollars: 1500).percent(10) == Money(dollars: 150))
    }

    @Test func parsesWhatPeopleType() {
        #expect(Money(parsing: "1500") == Money(dollars: 1500))
        #expect(Money(parsing: "$1,500.50") == Money(cents: 150_050))
        #expect(Money(parsing: "12.345") == Money(cents: 1235))
        #expect(Money(parsing: "") == nil)
        #expect(Money(parsing: "abc") == nil)
    }

    @Test func plainTextForSpreadsheets() {
        #expect(Money(cents: 75_000).plain == "750.00")
        #expect(Money(cents: 5).plain == "0.05")
        #expect(Money(cents: -1250).plain == "-12.50")
    }

    @Test func addsAndSubtracts() {
        var total = Money(dollars: 10)
        total += Money(cents: 50)
        total -= Money(dollars: 1)
        #expect(total == Money(cents: 950))
        #expect(Money(dollars: 1) < Money(dollars: 2))
    }

    @Test func encodesAsWholeCents() throws {
        let data = try JSONEncoder().encode([Money(cents: 1234)])
        #expect(String(decoding: data, as: UTF8.self) == "[1234]")
        #expect(try JSONDecoder().decode([Money].self, from: data) == [Money(cents: 1234)])
    }
}
```

`Tests/QuotePilotCoreTests/DayTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct DayTests {
    @Test func isoRoundTrip() {
        let day = Day(year: 2026, month: 10, day: 5)
        #expect(day.iso == "2026-10-05")
        #expect(Day(iso: "2026-10-05") == day)
        #expect(Day(iso: "2026-02-31") == nil)
        #expect(Day(iso: "nope") == nil)
    }

    @Test func addsDaysAcrossMonthAndYearEnds() {
        #expect(Day(year: 2026, month: 12, day: 25).adding(days: 14) == Day(year: 2027, month: 1, day: 8))
        #expect(Day(year: 2028, month: 2, day: 28).adding(days: 1) == Day(year: 2028, month: 2, day: 29))
    }

    @Test func countsDaysBetween() {
        let start = Day(year: 2026, month: 10, day: 15)
        #expect(Day(year: 2026, month: 11, day: 1).days(since: start) == 17)
        #expect(start.days(since: start) == 0)
    }

    @Test func ordersByDate() {
        #expect(Day(year: 2026, month: 6, day: 30) < Day(year: 2026, month: 7, day: 1))
    }

    @Test func theDayOfAMomentDependsOnTheTimeZone() {
        // 14 Oct 2026 14:30 UTC is already 15 Oct in Brisbane (UTC+10).
        let moment = Date(timeIntervalSince1970: 1_791_988_200)
        #expect(Day(moment, timeZone: .gmt) == Day(year: 2026, month: 10, day: 14))
        #expect(Day(moment, timeZone: TimeZone(identifier: "Australia/Brisbane")!) == Day(year: 2026, month: 10, day: 15))
    }

    @Test func readableFormats() {
        #expect(Day(year: 2026, month: 10, day: 15).long == "15 October 2026")
        #expect(Day(year: 2026, month: 10, day: 15).short == "15 Oct 2026")
    }

    @Test func encodesAsISOText() throws {
        let data = try JSONEncoder().encode([Day(year: 2026, month: 10, day: 15)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-10-15\"]")
        #expect(try JSONDecoder().decode([Day].self, from: data) == [Day(year: 2026, month: 10, day: 15)])
    }
}
```

- [ ] **Step 4: Run the tests to watch them fail**

Run: `swift test`
Expected: a build failure, `cannot find 'Money' in scope` and `cannot find 'Day' in scope`.

- [ ] **Step 5: Write `Money.swift`**

```swift
import Foundation

/// An amount of money in whole cents. Amounts never pass through floating point.
public struct Money: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var cents: Int

    public init(cents: Int) {
        self.cents = cents
    }

    /// `Money(dollars: 1500)` or `Money(dollars: 12, cents: 50)`.
    public init(dollars: Int, cents: Int = 0) {
        self.cents = dollars * 100 + cents
    }

    /// Reads what someone types into an amount field: "1500", "$1,500.50", "12.345" (rounds to the cent).
    public init?(parsing text: String) {
        let cleaned = text.filter { "0123456789.-".contains($0) }
        guard !cleaned.isEmpty,
              let dollars = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        self = Money(cents: 100).times(dollars)
    }

    public static let zero = Money(cents: 0)

    public static func + (a: Money, b: Money) -> Money { Money(cents: a.cents + b.cents) }
    public static func - (a: Money, b: Money) -> Money { Money(cents: a.cents - b.cents) }
    public static func += (a: inout Money, b: Money) { a.cents += b.cents }
    public static func -= (a: inout Money, b: Money) { a.cents -= b.cents }
    public static func < (a: Money, b: Money) -> Bool { a.cents < b.cents }

    /// This amount times a quantity (1.5 hours, say), rounded half up to the nearest cent.
    public func times(_ quantity: Decimal) -> Money {
        var exact = Decimal(cents) * quantity
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 0, .plain)
        return Money(cents: NSDecimalNumber(decimal: rounded).intValue)
    }

    /// A whole-number percentage of this amount, rounded half up to the nearest cent.
    public func percent(_ percent: Int) -> Money {
        times(Decimal(percent) / 100)
    }

    /// "$1,500.00", Australian style.
    public func formatted(currencyCode: String = "AUD") -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currencyCode).locale(Locale(identifier: "en_AU")))
    }

    /// "1500.00": no symbol and no thousands separators, for CSV files.
    public var plain: String {
        let sign = cents < 0 ? "-" : ""
        let whole = abs(cents)
        return "\(sign)\(whole / 100)." + String(format: "%02d", whole % 100)
    }

    public var description: String { formatted() }

    public init(from decoder: Decoder) throws {
        cents = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(cents)
    }
}
```

- [ ] **Step 6: Write `Day.swift`**

```swift
import Foundation

/// A calendar day with no time and no time zone: issue dates, due dates, payment dates.
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day a moment falls on in a time zone (this Mac's by default).
    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static func today() -> Day { Day(Date()) }

    /// "2026-10-15". Returns nil for text that isn't a real date.
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let candidate = Day(year: parts[0], month: parts[1], day: parts[2])
        // 2026-02-31 would roll over to March; reject it.
        guard Day(candidate.midnightUTC, timeZone: .gmt) == candidate else { return nil }
        self = candidate
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    /// "15 October 2026"
    public var long: String { format("d MMMM yyyy") }

    /// "15 Oct 2026"
    public var short: String { format("d MMM yyyy") }

    public func adding(days: Int) -> Day {
        Day(Day.utc.date(byAdding: .day, value: days, to: midnightUTC)!, timeZone: .gmt)
    }

    /// Whole days from `other` to this day; positive when this day is later.
    public func days(since other: Day) -> Int {
        Day.utc.dateComponents([.day], from: other.midnightUTC, to: midnightUTC).day!
    }

    public static func < (a: Day, b: Day) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(iso: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not a date: \(text)"))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    var midnightUTC: Date {
        Day.utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func format(_ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = .gmt
        formatter.dateFormat = pattern
        return formatter.string(from: midnightUTC)
    }
}
```

- [ ] **Step 7: Run the tests to watch them pass**

Run: `swift test`
Expected: `Test run with 14 tests passed`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "Add the package with Money and Day

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: The data model, the library and numbering

**Files:**
- Create: `Sources/QuotePilotCore/LineItem.swift`
- Create: `Sources/QuotePilotCore/Models.swift`
- Create: `Sources/QuotePilotCore/Library.swift`
- Test: `Tests/QuotePilotCoreTests/ModelTests.swift`

**Interfaces:**
- Consumes: `Money`, `Day` (Task 1).
- Produces:
  - **Lines and totals:**
    - `Unit { hours, days, units }` with `describe(_: Decimal) -> String` ("2 hrs", "1 day", "3")
    - `LineDecision { accepted, declined }`
    - `LineItem(id:code:title:detail:quantity:unit:rate:decision:)` with `amount: Money`
    - `[LineItem].subtotal`
    - `Totals(subtotal:taxed:)` with `subtotal`, `gst`, `total`
  - **Brand and clients:**
    - `EmailTemplate.filled(_: [String: String]) -> (subject: String, body: String)`
    - `EmailTemplates.standard`
    - `Brand()` with its fields
    - `Client(name:…)` with `greetingName`
  - **Quotes:**
    - `PaymentPlan { fiftyFifty, fullAmount }` with `depositPercent`, `summary`
    - `QuoteStage { draft, sent, accepted, declined }`
    - `AcceptanceSource`, `Acceptance`
    - `Quote` with `totals`, `acceptedLines`, `acceptedTotals`
  - **Invoices and payments:**
    - `InvoiceKind { deposit, final, full, standalone }`
    - `InvoiceStage { draft, sent, void }`
    - `PaymentMethod` with `label`
    - `Payment`, `Deduction`
    - `Invoice` with `lineTotals`, `amount`, `paid`, `owing`
  - **Library:**
    - `ActivityEntry`
    - `DocumentKind { quote, invoice }`
    - `LibraryError` (all cases used by later tasks)
    - `Library` with `nextNumber(_:)`, `takeNumber(_:)`
    - lookups: `client(_:)`, `quote(_:)`, `quote(number:)`, `invoice(_:)`, `quoteIndex(_:)`,
      `invoiceIndex(_:)`
    - activity: `log(_:number:at:)`
    - creating and editing: `addClient(_:)`, `newQuote(on:clientID:)`, `newInvoice(on:clientID:)`,
      `update(_: Quote)`, `update(_: Invoice)`, `deleteDraft(quote:)`, `deleteDraft(invoice:)`
    - JSON: `Library.makeEncoder()`, `Library.makeDecoder()`

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotCoreTests/ModelTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct ModelTests {
    let today = Day(year: 2026, month: 10, day: 15)

    @Test func unitsDescribeQuantities() {
        #expect(Unit.hours.describe(2) == "2 hrs")
        #expect(Unit.hours.describe(1) == "1 hr")
        #expect(Unit.hours.describe(1.5) == "1.5 hrs")
        #expect(Unit.days.describe(1) == "1 day")
        #expect(Unit.units.describe(3) == "3")
    }

    @Test func lineAmountsAndTotals() {
        let lines = [
            LineItem(title: "Discovery", quantity: 1.5, unit: .hours, rate: Money(dollars: 40)),
            LineItem(title: "Build", rate: Money(dollars: 1000)),
        ]
        #expect(lines[0].amount == Money(dollars: 60))
        #expect(lines.subtotal == Money(dollars: 1060))
        #expect(Totals(subtotal: lines.subtotal, taxed: false).total == Money(dollars: 1060))
        let taxed = Totals(subtotal: lines.subtotal, taxed: true)
        #expect(taxed.gst == Money(dollars: 106))
        #expect(taxed.total == Money(dollars: 1166))
    }

    @Test func emailTemplatesFillPlaceholders() {
        let template = EmailTemplate(subject: "Quote {number}", body: "Hi {contact}, {amount} from {business}")
        let filled = template.filled(["number": "Q-0003", "contact": "Sam", "amount": "$500.00", "business": "Sample Studio"])
        #expect(filled.subject == "Quote Q-0003")
        #expect(filled.body == "Hi Sam, $500.00 from Sample Studio")
    }

    @Test func clientGreetingUsesTheContactsFirstName() {
        #expect(Client(name: "Sample Client Pty Ltd", contactName: "Sam Example").greetingName == "Sam")
        #expect(Client(name: "Sample Client Pty Ltd").greetingName == "Sample Client Pty Ltd")
    }

    @Test func numbersCountUpAndAreNeverReused() throws {
        var library = Library()
        #expect(library.nextNumber(.quote) == "Q-0001")
        #expect(library.nextNumber(.invoice) == "INV-0001")
        _ = library.newQuote(on: today)
        let second = library.newQuote(on: today)
        try library.deleteDraft(quote: second.id)
        #expect(library.nextNumber(.quote) == "Q-0003")
        library.usedNumbers.append("Q-0041")
        #expect(library.nextNumber(.quote) == "Q-0042")
        #expect(library.nextNumber(.invoice) == "INV-0001")
    }

    @Test func newDocumentsTakeTheBrandsDefaults() {
        var library = Library()
        library.brand.quoteValidDays = 30
        library.brand.paymentDueDays = 14
        let quote = library.newQuote(on: today)
        #expect(quote.validUntil == today.adding(days: 30))
        #expect(quote.stage == .draft)
        #expect(quote.terms == library.brand.quoteTerms)
        let invoice = library.newInvoice(on: today)
        #expect(invoice.due == today.adding(days: 14))
        #expect(invoice.kind == .standalone)
        #expect(library.activity.first?.message == "Started invoice INV-0001")
    }

    @Test func invoiceAmounts() {
        var invoice = Invoice(number: "INV-0001", kind: .deposit, issued: today, due: today.adding(days: 14),
                              lines: [LineItem(title: "Build", rate: Money(dollars: 1500))])
        invoice.depositPercent = 50
        #expect(invoice.amount == Money(dollars: 750))

        var closing = Invoice(number: "INV-0002", kind: .final, issued: today, due: today.adding(days: 14),
                              lines: [LineItem(title: "Build", rate: Money(dollars: 1500))])
        closing.deductions = [Deduction(label: "Less deposit", invoiceNumber: "INV-0001", amount: Money(dollars: 750))]
        #expect(closing.amount == Money(dollars: 750))
        closing.payments = [Payment(date: today, amount: Money(dollars: 500))]
        #expect(closing.paid == Money(dollars: 500))
        #expect(closing.owing == Money(dollars: 250))
    }

    @Test func onlyDraftsCanBeDeleted() throws {
        var library = Library()
        let quote = library.newQuote(on: today)
        var sent = quote
        sent.stage = .sent
        try library.update(sent)
        #expect(throws: LibraryError.notDraft) { try library.deleteDraft(quote: quote.id) }
    }

    @Test func libraryRoundTripsThroughJSON() throws {
        var library = Library()
        library.addClient(Client(name: "Sample Client Pty Ltd", email: "accounts@example.com"))
        var quote = library.newQuote(on: today, clientID: library.clients[0].id)
        quote.lines = [LineItem(code: "01", title: "Discovery", quantity: 2, unit: .hours, rate: Money(dollars: 40))]
        try library.update(quote)
        _ = library.newInvoice(on: today)

        let first = try Library.makeEncoder().encode(library)
        let decoded = try Library.makeDecoder().decode(Library.self, from: first)
        let second = try Library.makeEncoder().encode(decoded)
        #expect(first == second)
        #expect(decoded.quotes[0].lines[0].amount == Money(dollars: 80))
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter ModelTests`
Expected: build failure, `cannot find 'Unit' in scope` (and the other new types).

- [ ] **Step 3: Write `LineItem.swift`**

```swift
import Foundation

public enum Unit: String, Codable, CaseIterable, Sendable {
    case hours, days, units

    /// "2 hrs", "1 day", "1.5 hrs"; plain units print as a bare number ("3").
    public func describe(_ quantity: Decimal) -> String {
        let number = quantity.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_AU")))
        switch self {
        case .hours: return quantity == 1 ? "\(number) hr" : "\(number) hrs"
        case .days: return quantity == 1 ? "\(number) day" : "\(number) days"
        case .units: return number
        }
    }
}

public enum LineDecision: String, Codable, Sendable {
    case accepted, declined
}

/// One line on a quote or invoice.
public struct LineItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// The line ID a client sees on a quote: "01", "02", …
    public var code: String
    public var title: String
    public var detail: String
    public var quantity: Decimal
    public var unit: Unit
    public var rate: Money
    /// Quotes only: what the client decided.
    public var decision: LineDecision?

    public init(id: UUID = UUID(), code: String = "", title: String, detail: String = "",
                quantity: Decimal = 1, unit: Unit = .units, rate: Money, decision: LineDecision? = nil) {
        self.id = id
        self.code = code
        self.title = title
        self.detail = detail
        self.quantity = quantity
        self.unit = unit
        self.rate = rate
        self.decision = decision
    }

    public var amount: Money { rate.times(quantity) }
}

extension Array where Element == LineItem {
    public var subtotal: Money { reduce(.zero) { $0 + $1.amount } }
}

/// Subtotal, GST and total. GST is 10% on top, and only when the document is taxed.
public struct Totals: Equatable, Sendable {
    public static let gstPercent = 10

    public var subtotal: Money
    public var gst: Money
    public var total: Money

    public init(subtotal: Money, taxed: Bool) {
        self.subtotal = subtotal
        gst = taxed ? subtotal.percent(Totals.gstPercent) : .zero
        total = subtotal + gst
    }
}
```

- [ ] **Step 4: Write `Models.swift`**

```swift
import Foundation

// MARK: - Brand

public struct EmailTemplate: Codable, Hashable, Sendable {
    public var subject: String
    public var body: String

    public init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }

    /// Replaces `{key}` placeholders: client, contact, number, amount, due, business.
    public func filled(_ values: [String: String]) -> (subject: String, body: String) {
        func fill(_ text: String) -> String {
            values.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
        }
        return (fill(subject), fill(body))
    }
}

public struct EmailTemplates: Codable, Hashable, Sendable {
    public var quote: EmailTemplate
    public var invoice: EmailTemplate
    public var receipt: EmailTemplate

    public static let standard = EmailTemplates(
        quote: EmailTemplate(
            subject: "Quote {number} from {business}",
            body: """
            Hi {contact},

            Attached is quote {number}. Tick the lines you'd like to go ahead with, or tick Accept all, \
            add your name and the date, then save the PDF and send it back to me.

            Thanks,
            {business}
            """),
        invoice: EmailTemplate(
            subject: "Invoice {number} from {business}",
            body: """
            Hi {contact},

            Attached is invoice {number} for {amount}, due {due}. Payment details are on the invoice.

            Thanks,
            {business}
            """),
        receipt: EmailTemplate(
            subject: "Receipt for invoice {number}",
            body: """
            Hi {contact},

            Thanks for your payment. Attached is your receipt for invoice {number}.

            Thanks,
            {business}
            """)
    )
}

/// The one business identity on every document.
public struct Brand: Codable, Hashable, Sendable {
    public var businessName = ""
    /// Address, email, phone, website: one per line, printed under the business name.
    public var details = ""
    /// Printed on tax invoices.
    public var abn = ""
    /// Bank, BSB and account, or PayID.
    public var paymentDetails = ""
    public var accentHex = "#0B6B66"
    /// File names inside the library's Assets folder.
    public var logoFile: String?
    public var headingFontFile: String?
    public var quoteTerms = "Prices are fixed for the work listed. Work starts once this quote is accepted."
    public var invoiceTerms = "Please use the invoice number as your payment reference."
    public var emails = EmailTemplates.standard
    public var gstRegistered = false
    public var currencyCode = "AUD"
    public var paymentDueDays = 14
    public var quoteValidDays = 30

    public init() {}
}

// MARK: - Clients

public struct Client: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var contactName: String
    public var email: String
    public var phone: String
    public var address: String
    public var notes: String

    public init(id: UUID = UUID(), name: String, contactName: String = "", email: String = "",
                phone: String = "", address: String = "", notes: String = "") {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.address = address
        self.notes = notes
    }

    /// Who "Hi …" is addressed to: the contact's first name, or the business name.
    public var greetingName: String {
        let first = contactName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? name : first
    }
}

// MARK: - Quotes

public enum PaymentPlan: String, Codable, CaseIterable, Sendable {
    case fiftyFifty, fullAmount

    public var depositPercent: Int? { self == .fiftyFifty ? 50 : nil }

    public var summary: String {
        switch self {
        case .fiftyFifty: return "50% when the quote is accepted, 50% on completion"
        case .fullAmount: return "Full amount on completion"
        }
    }
}

public enum QuoteStage: String, Codable, Sendable {
    case draft, sent, accepted, declined
}

public enum AcceptanceSource: String, Codable, Sendable {
    case returnedPDF, byHand
}

/// What the client decided, and how Quote Pilot learned it.
public struct Acceptance: Codable, Hashable, Sendable {
    public var recordedAt: Date
    public var source: AcceptanceSource
    public var fileName: String?
    public var clientName: String
    public var clientDate: String
    public var accepted: [String]
    public var declined: [String]

    public init(recordedAt: Date = Date(), source: AcceptanceSource, fileName: String? = nil,
                clientName: String = "", clientDate: String = "", accepted: [String], declined: [String]) {
        self.recordedAt = recordedAt
        self.source = source
        self.fileName = fileName
        self.clientName = clientName
        self.clientDate = clientDate
        self.accepted = accepted
        self.declined = declined
    }
}

public struct Quote: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var number: String
    public var clientID: UUID?
    /// Shown as the reference, e.g. "Website rebuild, phase 1".
    public var title: String
    public var issued: Day
    public var validUntil: Day
    public var plan: PaymentPlan
    public var taxed: Bool
    public var lines: [LineItem]
    /// The highest line number ever given out on this quote, so a sent quote never reuses a line ID.
    public var lastLineNumber: Int
    /// Plain text; lines starting with "- " print as dot points.
    public var summary: String
    public var terms: String
    public var stage: QuoteStage
    public var sentAt: Date?
    public var acceptance: Acceptance?
    public var completedOn: Day?

    public init(id: UUID = UUID(), number: String, clientID: UUID? = nil, title: String = "",
                issued: Day, validUntil: Day, plan: PaymentPlan = .fiftyFifty, taxed: Bool = false,
                lines: [LineItem] = [], summary: String = "", terms: String = "", stage: QuoteStage = .draft) {
        self.id = id
        self.number = number
        self.clientID = clientID
        self.title = title
        self.issued = issued
        self.validUntil = validUntil
        self.plan = plan
        self.taxed = taxed
        self.lines = lines
        self.lastLineNumber = lines.compactMap { Int($0.code) }.max() ?? 0
        self.summary = summary
        self.terms = terms
        self.stage = stage
    }

    public var totals: Totals { Totals(subtotal: lines.subtotal, taxed: taxed) }
    public var acceptedLines: [LineItem] { lines.filter { $0.decision == .accepted } }
    public var acceptedTotals: Totals { Totals(subtotal: acceptedLines.subtotal, taxed: taxed) }
}

// MARK: - Invoices

public enum InvoiceKind: String, Codable, Sendable {
    case deposit, final, full, standalone
}

public enum InvoiceStage: String, Codable, Sendable {
    case draft, sent, void
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable {
    case bankTransfer, cash, card, other

    public var label: String {
        switch self {
        case .bankTransfer: return "Bank transfer"
        case .cash: return "Cash"
        case .card: return "Card"
        case .other: return "Other"
        }
    }
}

public struct Payment: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Day
    public var amount: Money
    public var method: PaymentMethod
    public var note: String

    public init(id: UUID = UUID(), date: Day, amount: Money, method: PaymentMethod = .bankTransfer, note: String = "") {
        self.id = id
        self.date = date
        self.amount = amount
        self.method = method
        self.note = note
    }
}

/// An earlier invoice that a final invoice subtracts: "Less deposit, INV-0004".
public struct Deduction: Codable, Hashable, Sendable {
    public var label: String
    public var invoiceNumber: String
    public var amount: Money

    public init(label: String, invoiceNumber: String, amount: Money) {
        self.label = label
        self.invoiceNumber = invoiceNumber
        self.amount = amount
    }
}

public struct Invoice: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var number: String
    public var clientID: UUID?
    public var quoteID: UUID?
    public var kind: InvoiceKind
    public var title: String
    public var issued: Day
    public var due: Day
    public var taxed: Bool
    public var lines: [LineItem]
    /// Deposit invoices bill this percentage of the lines' total.
    public var depositPercent: Int?
    public var deductions: [Deduction]
    public var terms: String
    public var stage: InvoiceStage
    public var sentAt: Date?
    public var payments: [Payment]
    public var receiptSentAt: Date?

    public init(id: UUID = UUID(), number: String, clientID: UUID? = nil, quoteID: UUID? = nil,
                kind: InvoiceKind, title: String = "", issued: Day, due: Day, taxed: Bool = false,
                lines: [LineItem] = [], terms: String = "", stage: InvoiceStage = .draft) {
        self.id = id
        self.number = number
        self.clientID = clientID
        self.quoteID = quoteID
        self.kind = kind
        self.title = title
        self.issued = issued
        self.due = due
        self.taxed = taxed
        self.lines = lines
        self.depositPercent = nil
        self.deductions = []
        self.terms = terms
        self.stage = stage
        self.payments = []
    }

    /// The lines' totals, before any deposit share or deduction.
    public var lineTotals: Totals { Totals(subtotal: lines.subtotal, taxed: taxed) }

    /// What this invoice asks the client to pay altogether.
    public var amount: Money {
        let base = lineTotals.total
        if let percent = depositPercent { return base.percent(percent) }
        return deductions.reduce(base) { $0 - $1.amount }
    }

    public var paid: Money { payments.reduce(.zero) { $0 + $1.amount } }
    public var owing: Money { amount - paid }
}

// MARK: - Activity

public struct ActivityEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var at: Date
    /// The quote or invoice number it's about, if any.
    public var number: String?
    public var message: String

    public init(id: UUID = UUID(), at: Date, number: String?, message: String) {
        self.id = id
        self.at = at
        self.number = number
        self.message = message
    }
}
```

- [ ] **Step 5: Write `Library.swift`**

```swift
import Foundation

public enum DocumentKind: Sendable {
    case quote, invoice

    var prefix: String { self == .quote ? "Q-" : "INV-" }
}

public enum LibraryError: Error, Equatable, Sendable {
    case notFound
    case notDraft
    case notSent
    case notAccepted
    case nothingAccepted
    case nothingLeftToInvoice
    case alreadyInvoiced
    case isVoid
    case hasPayments
    case unknownLineCodes([String])
}

/// Everything Quote Pilot knows, saved as one file.
public struct Library: Codable, Sendable {
    public static let currentFormat = 1

    public var format: Int
    public var brand: Brand
    public var clients: [Client]
    public var quotes: [Quote]
    public var invoices: [Invoice]
    /// Newest first.
    public var activity: [ActivityEntry]
    /// Every number ever issued, so deleting a draft never frees its number.
    public var usedNumbers: [String]

    public init(brand: Brand = Brand()) {
        format = Library.currentFormat
        self.brand = brand
        clients = []
        quotes = []
        invoices = []
        activity = []
        usedNumbers = []
    }

    // MARK: Numbering

    /// One past the highest number ever used with that prefix: "Q-0007".
    public func nextNumber(_ kind: DocumentKind) -> String {
        let prefix = kind.prefix
        let highest = usedNumbers
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count)) }
            .max() ?? 0
        return prefix + String(format: "%04d", highest + 1)
    }

    public mutating func takeNumber(_ kind: DocumentKind) -> String {
        let number = nextNumber(kind)
        usedNumbers.append(number)
        return number
    }

    // MARK: Lookups

    public func client(_ id: UUID?) -> Client? { clients.first { $0.id == id } }
    public func quote(_ id: UUID) -> Quote? { quotes.first { $0.id == id } }
    public func invoice(_ id: UUID) -> Invoice? { invoices.first { $0.id == id } }

    public func quote(number: String) -> Quote? {
        quotes.first { $0.number.caseInsensitiveCompare(number) == .orderedSame }
    }

    func quoteIndex(_ id: UUID) throws -> Int {
        guard let index = quotes.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        return index
    }

    func invoiceIndex(_ id: UUID) throws -> Int {
        guard let index = invoices.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        return index
    }

    // MARK: Activity

    public mutating func log(_ message: String, number: String? = nil, at time: Date = Date()) {
        activity.insert(ActivityEntry(at: time, number: number, message: message), at: 0)
    }

    // MARK: Creating and editing

    public mutating func addClient(_ client: Client) {
        clients.append(client)
        log("Added client \(client.name)")
    }

    @discardableResult
    public mutating func newQuote(on day: Day, clientID: UUID? = nil) -> Quote {
        let quote = Quote(number: takeNumber(.quote), clientID: clientID, issued: day,
                          validUntil: day.adding(days: brand.quoteValidDays),
                          taxed: brand.gstRegistered, terms: brand.quoteTerms)
        quotes.append(quote)
        log("Started quote \(quote.number)", number: quote.number)
        return quote
    }

    /// A standalone invoice: extra hourly work, a monthly fee.
    @discardableResult
    public mutating func newInvoice(on day: Day, clientID: UUID? = nil) -> Invoice {
        let invoice = Invoice(number: takeNumber(.invoice), clientID: clientID, kind: .standalone,
                              issued: day, due: day.adding(days: brand.paymentDueDays),
                              taxed: brand.gstRegistered, terms: brand.invoiceTerms)
        invoices.append(invoice)
        log("Started invoice \(invoice.number)", number: invoice.number)
        return invoice
    }

    public mutating func update(_ quote: Quote) throws {
        let index = try quoteIndex(quote.id)
        quotes[index] = quote
    }

    public mutating func update(_ invoice: Invoice) throws {
        let index = try invoiceIndex(invoice.id)
        invoices[index] = invoice
    }

    public mutating func deleteDraft(quote id: UUID) throws {
        let index = try quoteIndex(id)
        guard quotes[index].stage == .draft else { throw LibraryError.notDraft }
        let number = quotes.remove(at: index).number
        log("Deleted draft quote \(number)", number: number)
    }

    public mutating func deleteDraft(invoice id: UUID) throws {
        let index = try invoiceIndex(id)
        guard invoices[index].stage == .draft else { throw LibraryError.notDraft }
        let number = invoices.remove(at: index).number
        log("Deleted draft invoice \(number)", number: number)
    }

    // MARK: JSON

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 6: Run the tests to watch them pass**

Run: `swift test`
Expected: all tests pass (14 from Task 1 plus 9 here).

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "Add quotes, invoices, clients, the brand and numbering

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Quote lifecycle: status, line IDs, sending, reading a returned form, acceptance

**Files:**
- Create: `Sources/QuotePilotCore/QuoteLifecycle.swift`
- Test: `Tests/QuotePilotCoreTests/Fixtures.swift`
- Test: `Tests/QuotePilotCoreTests/QuoteLifecycleTests.swift`

**Interfaces:**
- Consumes: `Quote`, `Library`, `Acceptance`, `LibraryError`, `Day` (Tasks 1–2).
- Produces:
  - **Status:** `QuoteStatus { draft, sent, expired, declined, accepted(partly:) }` with `label`;
    `Quote.status(on: Day) -> QuoteStatus`
  - **Line IDs:** `Quote.lineCodes`, `Quote.renumberLinesIfDraft()`, `Quote.nextLineCode()`,
    `Quote.addLine(_:)`
  - **Reading a returned form:**
    - `ReturnedForm(quoteNumber:acceptAll:ticked:unticked:clientName:clientDate:)`
    - `AcceptanceProblem` with `message`
    - `AcceptanceProposal`
    - `Quote.proposal(from: ReturnedForm, today: Day) -> AcceptanceProposal`
  - **Library:** `markSent(quote:at:)`, `recordAcceptance(_:forQuote:)`
  - **Helpers:** `lineList(_: [String]) -> String` (internal: "line 03", "lines 01, 02")
  - **Test fixture:** `Fixture.today`, `Fixture.libraryWithQuote(stage:plan:)`,
    `Fixture.acceptedLibrary(plan:)` (lines 01 Discovery 2 hrs × $40, 02 Build $1,000, 03 Extra
    screens $420; accepted 01 and 02 = $1,080)

- [ ] **Step 1: Write the shared test fixture**

`Tests/QuotePilotCoreTests/Fixtures.swift`:

```swift
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
```

- [ ] **Step 2: Write the failing tests**

`Tests/QuotePilotCoreTests/QuoteLifecycleTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct QuoteLifecycleTests {
    let today = Fixture.today

    @Test func statusFollowsStageAndDates() {
        let (library, id) = Fixture.libraryWithQuote(stage: .draft)
        var quote = library.quote(id)!
        #expect(quote.status(on: today) == .draft)
        quote.stage = .sent
        #expect(quote.status(on: quote.validUntil) == .sent)
        #expect(quote.status(on: quote.validUntil.adding(days: 1)) == .expired)
        quote.stage = .accepted
        quote.lines[2].decision = .declined
        #expect(quote.status(on: today) == .accepted(partly: true))
        #expect(QuoteStatus.accepted(partly: true).label == "Accepted, partly")
        quote.stage = .declined
        #expect(quote.status(on: today) == .declined)
    }

    @Test func lineIDsFollowTheOrderOnlyWhileDraft() {
        let (library, id) = Fixture.libraryWithQuote(stage: .draft)
        var quote = library.quote(id)!
        quote.lines.swapAt(0, 2)
        quote.renumberLinesIfDraft()
        #expect(quote.lines.map(\.title) == ["Extra screens", "Build", "Discovery"])
        #expect(quote.lineCodes == ["01", "02", "03"])
        quote.stage = .sent
        quote.lines.swapAt(0, 2)
        quote.renumberLinesIfDraft()
        #expect(quote.lineCodes == ["03", "02", "01"])
        #expect(quote.nextLineCode() == "04")
    }

    @Test func aSentQuoteNeverReusesALineID() {
        let (library, id) = Fixture.libraryWithQuote()
        var quote = library.quote(id)!
        quote.lines.remove(at: 2)
        quote.addLine(LineItem(title: "Training session", rate: Money(dollars: 200)))
        #expect(quote.lineCodes == ["01", "02", "04"])
    }

    @Test func markingSentRecordsTheTimeAndLogs() throws {
        var (library, id) = Fixture.libraryWithQuote(stage: .draft)
        let moment = Date(timeIntervalSince1970: 1_792_000_000)
        try library.markSent(quote: id, at: moment)
        let quote = library.quote(id)!
        #expect(quote.stage == .sent)
        #expect(quote.sentAt == moment)
        #expect(library.activity.first?.message == "Marked quote Q-0001 as sent")
    }

    @Test func acceptAllAcceptsEveryLine() {
        let (library, id) = Fixture.libraryWithQuote()
        let form = ReturnedForm(quoteNumber: "Q-0001", acceptAll: true, ticked: [], unticked: ["01", "02", "03"])
        let proposal = library.quote(id)!.proposal(from: form, today: today)
        #expect(proposal.accepted == ["01", "02", "03"])
        #expect(proposal.declined == [])
        #expect(proposal.problems == [])
    }

    @Test func tickedLinesAreAcceptedAndTheRestDeclined() {
        let (library, id) = Fixture.libraryWithQuote()
        let form = ReturnedForm(quoteNumber: "q-0001", acceptAll: false, ticked: ["01", "03"], unticked: ["02"],
                                clientName: "Sam Example", clientDate: "16/10/2026")
        let proposal = library.quote(id)!.proposal(from: form, today: today)
        #expect(proposal.accepted == ["01", "03"])
        #expect(proposal.declined == ["02"])
        #expect(proposal.clientName == "Sam Example")
        #expect(proposal.clientDate == "16/10/2026")
        #expect(proposal.problems == [])
    }

    @Test func nothingTickedIsFlagged() {
        let (library, id) = Fixture.libraryWithQuote()
        let form = ReturnedForm(quoteNumber: "Q-0001", acceptAll: false, ticked: [], unticked: ["01", "02", "03"])
        let proposal = library.quote(id)!.proposal(from: form, today: today)
        #expect(proposal.accepted == [])
        #expect(proposal.declined == ["01", "02", "03"])
        #expect(proposal.problems == [.nothingTicked])
    }

    @Test func proposalFlagsLinesTheClientNeverSaw() {
        // The client's PDF had 01–03. Since then 03 was removed and 04 added.
        let (library, id) = Fixture.libraryWithQuote()
        var quote = library.quote(id)!
        quote.lines.remove(at: 2)
        quote.addLine(LineItem(title: "Training session", rate: Money(dollars: 200)))
        let form = ReturnedForm(quoteNumber: "Q-0001", acceptAll: false, ticked: ["01", "03"], unticked: ["02"])
        let proposal = quote.proposal(from: form, today: today)
        #expect(proposal.accepted == ["01"])
        #expect(proposal.declined == ["02", "04"])
        #expect(proposal.problems == [.unknownLines(["03"]), .missingLines(["04"])])
        #expect(AcceptanceProblem.missingLines(["04"]).message
                == "Line 04 wasn't on the PDF the client saw, so it's marked declined.")
    }

    @Test func wrongQuoteAndExpiryAreFlagged() {
        let (library, id) = Fixture.libraryWithQuote()
        let quote = library.quote(id)!
        let form = ReturnedForm(quoteNumber: "Q-0009", acceptAll: true, ticked: [], unticked: quote.lineCodes)
        let proposal = quote.proposal(from: form, today: quote.validUntil.adding(days: 3))
        #expect(proposal.problems == [.wrongQuote(found: "Q-0009", expected: "Q-0001"),
                                      .expired(validUntil: quote.validUntil)])
        #expect(AcceptanceProblem.wrongQuote(found: "Q-0009", expected: "Q-0001").message
                == "This PDF is for quote Q-0009, not Q-0001.")
    }

    @Test func recordingAcceptanceSetsDecisionsAndLogs() throws {
        var (library, id) = Fixture.libraryWithQuote()
        try library.recordAcceptance(Acceptance(source: .returnedPDF, fileName: "Q-0001 signed.pdf",
                                                clientName: "Sam Example", accepted: ["01", "02"], declined: ["03"]),
                                     forQuote: id)
        let quote = library.quote(id)!
        #expect(quote.stage == .accepted)
        #expect(quote.lines.map(\.decision) == [.accepted, .accepted, .declined])
        #expect(quote.acceptedTotals.total == Money(dollars: 1080))
        #expect(quote.acceptance?.clientName == "Sam Example")
        #expect(library.activity.first?.message
                == "Recorded acceptance of Q-0001 from Q-0001 signed.pdf: accepted lines 01, 02; declined line 03")
    }

    @Test func decliningEverythingDeclinesTheQuote() throws {
        var (library, id) = Fixture.libraryWithQuote()
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: [], declined: ["01", "02", "03"]), forQuote: id)
        #expect(library.quote(id)!.stage == .declined)
        #expect(library.activity.first?.message == "Recorded acceptance of Q-0001 by hand: all lines declined")
    }

    @Test func unknownLineIDsChangeNothing() {
        var (library, id) = Fixture.libraryWithQuote()
        #expect(throws: LibraryError.unknownLineCodes(["09"])) {
            try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["09"], declined: []), forQuote: id)
        }
        #expect(library.quote(id)!.stage == .sent)
        #expect(library.quote(id)!.lines.allSatisfy { $0.decision == nil })
    }
}
```

- [ ] **Step 3: Run them to watch them fail**

Run: `swift test --filter QuoteLifecycleTests`
Expected: build failure, `value of type 'Quote' has no member 'addLine'` (and the other new names).

- [ ] **Step 4: Write `QuoteLifecycle.swift`**

```swift
import Foundation

public enum QuoteStatus: Equatable, Sendable {
    case draft, sent, expired, declined
    case accepted(partly: Bool)

    public var label: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .expired: return "Expired"
        case .declined: return "Declined"
        case .accepted(let partly): return partly ? "Accepted, partly" : "Accepted"
        }
    }
}

extension Quote {
    public func status(on today: Day) -> QuoteStatus {
        switch stage {
        case .draft: return .draft
        case .sent: return today > validUntil ? .expired : .sent
        case .accepted: return .accepted(partly: lines.contains { $0.decision == .declined })
        case .declined: return .declined
        }
    }

    public var lineCodes: [String] { lines.map(\.code) }

    /// While a quote is a draft, line IDs follow the order of the lines. Once sent they never change,
    /// because the client's ticks refer to them.
    public mutating func renumberLinesIfDraft() {
        guard stage == .draft else { return }
        for index in lines.indices {
            lines[index].code = String(format: "%02d", index + 1)
        }
        lastLineNumber = lines.count
    }

    /// The ID the next new line gets: one past the highest ever given out on this quote.
    public func nextLineCode() -> String {
        String(format: "%02d", lastLineNumber + 1)
    }

    /// Adds a line with a fresh ID. Drafts then renumber to keep IDs in order.
    public mutating func addLine(_ line: LineItem) {
        var line = line
        line.code = nextLineCode()
        lastLineNumber += 1
        lines.append(line)
        renumberLinesIfDraft()
    }
}

/// What a returned quote said: read from the PDF form by QuotePilotPDF, or ticked by hand.
public struct ReturnedForm: Equatable, Sendable {
    public var quoteNumber: String
    public var acceptAll: Bool
    public var ticked: [String]
    public var unticked: [String]
    public var clientName: String
    public var clientDate: String

    public init(quoteNumber: String, acceptAll: Bool, ticked: [String], unticked: [String],
                clientName: String = "", clientDate: String = "") {
        self.quoteNumber = quoteNumber
        self.acceptAll = acceptAll
        self.ticked = ticked
        self.unticked = unticked
        self.clientName = clientName
        self.clientDate = clientDate
    }
}

public enum AcceptanceProblem: Equatable, Sendable {
    case wrongQuote(found: String, expected: String)
    /// On the PDF, but no longer on the quote.
    case unknownLines([String])
    /// On the quote, but not on the PDF the client saw.
    case missingLines([String])
    case nothingTicked
    case expired(validUntil: Day)

    public var message: String {
        switch self {
        case .wrongQuote(let found, let expected):
            return "This PDF is for quote \(found), not \(expected)."
        case .unknownLines(let codes):
            return "The PDF has \(lineList(codes)) that this quote no longer has."
        case .missingLines(let codes):
            let verb = codes.count == 1 ? "wasn't" : "weren't"
            return "\(lineList(codes).capitalizedFirst) \(verb) on the PDF the client saw, so it's marked declined."
        case .nothingTicked:
            return "Nothing is ticked. Either the client declined everything, or their PDF app didn't keep the ticks."
        case .expired(let validUntil):
            return "This quote expired on \(validUntil.long)."
        }
    }
}

/// What Quote Pilot thinks the client decided. Nothing changes until it's confirmed.
public struct AcceptanceProposal: Equatable, Sendable {
    public var accepted: [String]
    public var declined: [String]
    public var clientName: String
    public var clientDate: String
    public var problems: [AcceptanceProblem]
}

extension Quote {
    public func proposal(from form: ReturnedForm, today: Day) -> AcceptanceProposal {
        var problems: [AcceptanceProblem] = []
        if form.quoteNumber.caseInsensitiveCompare(number) != .orderedSame {
            problems.append(.wrongQuote(found: form.quoteNumber, expected: number))
        }
        let codes = lineCodes
        let onForm = form.ticked + form.unticked
        let unknown = onForm.filter { !codes.contains($0) }.sorted()
        if !unknown.isEmpty { problems.append(.unknownLines(unknown)) }
        let missing = codes.filter { !onForm.contains($0) }
        if !missing.isEmpty { problems.append(.missingLines(missing)) }
        if !form.acceptAll && form.ticked.isEmpty { problems.append(.nothingTicked) }
        if status(on: today) == .expired { problems.append(.expired(validUntil: validUntil)) }

        let accepted = form.acceptAll ? codes : codes.filter { form.ticked.contains($0) }
        return AcceptanceProposal(accepted: accepted,
                                  declined: codes.filter { !accepted.contains($0) },
                                  clientName: form.clientName,
                                  clientDate: form.clientDate,
                                  problems: problems)
    }
}

extension Library {
    public mutating func markSent(quote id: UUID, at time: Date = Date()) throws {
        let index = try quoteIndex(id)
        if quotes[index].stage == .draft {
            quotes[index].renumberLinesIfDraft()
            quotes[index].stage = .sent
        }
        quotes[index].sentAt = time
        log("Marked quote \(quotes[index].number) as sent", number: quotes[index].number, at: time)
    }

    /// Records what the client decided. Refused once the quote has invoices, so totals already
    /// billed can't shift underneath them.
    public mutating func recordAcceptance(_ acceptance: Acceptance, forQuote id: UUID) throws {
        let index = try quoteIndex(id)
        guard !invoices.contains(where: { $0.quoteID == id && $0.stage != .void }) else {
            throw LibraryError.alreadyInvoiced
        }
        let codes = quotes[index].lineCodes
        let unknown = (acceptance.accepted + acceptance.declined).filter { !codes.contains($0) }
        guard unknown.isEmpty else { throw LibraryError.unknownLineCodes(unknown) }

        for line in quotes[index].lines.indices {
            let code = quotes[index].lines[line].code
            quotes[index].lines[line].decision = acceptance.accepted.contains(code) ? .accepted : .declined
        }
        quotes[index].acceptance = acceptance
        quotes[index].stage = acceptance.accepted.isEmpty ? .declined : .accepted

        let number = quotes[index].number
        let how = acceptance.source == .returnedPDF ? "from \(acceptance.fileName ?? "the returned PDF")" : "by hand"
        var outcome = acceptance.accepted.isEmpty ? "all lines declined" : "accepted \(lineList(acceptance.accepted))"
        if !acceptance.accepted.isEmpty && !acceptance.declined.isEmpty {
            outcome += "; declined \(lineList(acceptance.declined))"
        }
        log("Recorded acceptance of \(number) \(how): \(outcome)", number: number, at: acceptance.recordedAt)
    }
}

/// "line 03" or "lines 01, 02".
func lineList(_ codes: [String]) -> String {
    (codes.count == 1 ? "line " : "lines ") + codes.joined(separator: ", ")
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
```

- [ ] **Step 5: Run the tests to watch them pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "Add quote status, line IDs, returned-form proposals and acceptance

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Invoicing: deposit, final and full invoices, job complete, payments, void, duplicates

**Files:**
- Create: `Sources/QuotePilotCore/Invoicing.swift`
- Test: `Tests/QuotePilotCoreTests/InvoicingTests.swift`

**Interfaces:**
- Consumes: `Library`, `Quote`, `Invoice`, `Payment`, `Deduction`, `LibraryError`, `Fixture` (Tasks 1–3).
- Produces:
  - **Status:** `InvoiceStatus { draft, sent, partPaid, paid, void, overdue(daysLate:) }` with
    `label`; `Invoice.status(on: Day) -> InvoiceStatus`
  - **Labels:** `InvoiceKind.label` ("deposit invoice", "final invoice", "invoice")
  - **Invoices from quotes:**
    - `Library.invoices(forQuote:) -> [Invoice]` (void excluded)
    - `invoicedAmount(forQuote:) -> Money`
    - `nextInvoiceKind(forQuote:) -> InvoiceKind?`
    - `draftNextInvoice(forQuote:on:) throws -> Invoice`
    - `completeJob(quote:on:) throws -> Invoice?`
  - **Sending and payments:**
    - `markSent(invoice:at:)`
    - `recordPayment(_:toInvoice:)`
    - `removePayment(_:fromInvoice:)`
    - `voidInvoice(_:)`
    - `markReceiptSent(invoice:at:)`
  - **Copies:** `duplicateInvoice(_:on:) throws -> Invoice`, `duplicateQuote(_:on:) throws -> Quote`

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotCoreTests/InvoicingTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct InvoicingTests {
    let today = Fixture.today

    @Test func fiftyFiftyDraftsADepositThenTheBalance() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(deposit.kind == .deposit)
        #expect(deposit.number == "INV-0001")
        #expect(deposit.lines.map(\.title) == ["Discovery", "Build"])
        #expect(deposit.lines.allSatisfy { $0.decision == nil })
        #expect(deposit.amount == Money(dollars: 540))
        #expect(deposit.due == today.adding(days: 14))
        #expect(library.activity.first?.message == "Drafted deposit invoice INV-0001 for $540.00 from quote Q-0001")

        let closing = try library.draftNextInvoice(forQuote: id, on: today.adding(days: 20))
        #expect(closing.kind == .final)
        #expect(closing.deductions == [Deduction(label: "Less deposit", invoiceNumber: "INV-0001", amount: Money(dollars: 540))])
        #expect(closing.amount == Money(dollars: 540))
        #expect(library.invoicedAmount(forQuote: id) == Money(dollars: 1080))
        #expect(throws: LibraryError.nothingLeftToInvoice) { try library.draftNextInvoice(forQuote: id, on: today) }
    }

    @Test func oddCentsSplitAddsUpExactly() throws {
        var (library, id) = Fixture.libraryWithQuote()
        var quote = library.quote(id)!
        quote.lines[1].rate = Money(cents: 99_921)   // accepted: $80 + $999.21 = $1,079.21
        try library.update(quote)
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: ["03"]), forQuote: id)
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        let closing = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(deposit.amount == Money(cents: 53_961))   // 53,960.5 rounds up
        #expect(closing.amount == Money(cents: 53_960))
        #expect(deposit.amount + closing.amount == Money(cents: 107_921))
    }

    @Test func fullAmountIsInvoicedOnceAtCompletion() throws {
        var (library, id) = Fixture.acceptedLibrary(plan: .fullAmount)
        let invoice = try library.completeJob(quote: id, on: today)
        #expect(invoice?.kind == .full)
        #expect(invoice?.amount == Money(dollars: 1080))
        #expect(library.quote(id)!.completedOn == today)
        let again = try library.completeJob(quote: id, on: today)
        #expect(again == nil)
        #expect(library.nextInvoiceKind(forQuote: id) == nil)
    }

    @Test func completingAFiftyFiftyJobWithoutADepositBillsEverything() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let closing = try library.completeJob(quote: id, on: today)
        #expect(closing?.kind == .final)
        #expect(closing?.deductions == [])
        #expect(closing?.amount == Money(dollars: 1080))
    }

    @Test func completingAfterTheDepositBillsTheBalance() throws {
        var (library, id) = Fixture.acceptedLibrary()
        try library.draftNextInvoice(forQuote: id, on: today)
        let closing = try library.completeJob(quote: id, on: today)
        #expect(closing?.amount == Money(dollars: 540))
    }

    @Test func onlyAcceptedQuotesCanBeInvoiced() {
        var (library, id) = Fixture.libraryWithQuote()
        #expect(throws: LibraryError.notAccepted) { try library.draftNextInvoice(forQuote: id, on: today) }
        #expect(library.nextInvoiceKind(forQuote: id) == nil)
    }

    @Test func acceptanceCantChangeOnceInvoiced() throws {
        var (library, id) = Fixture.acceptedLibrary()
        try library.draftNextInvoice(forQuote: id, on: today)
        #expect(throws: LibraryError.alreadyInvoiced) {
            try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: ["02", "03"]), forQuote: id)
        }
    }

    @Test func aVoidedDepositCanBeDraftedAgain() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        try library.voidInvoice(deposit.id)
        #expect(library.invoice(deposit.id)!.status(on: today) == .void)
        #expect(library.nextInvoiceKind(forQuote: id) == .deposit)
        let again = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(again.number == "INV-0002")
    }

    @Test func overdueStartsTheDayAfterDue() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.invoice(deposit.id)!.status(on: today) == .draft)
        try library.markSent(invoice: deposit.id)
        let sent = library.invoice(deposit.id)!
        #expect(sent.status(on: sent.due) == .sent)
        #expect(sent.status(on: sent.due.adding(days: 1)) == .overdue(daysLate: 1))
        #expect(InvoiceStatus.overdue(daysLate: 1).label == "Overdue, 1 day")
        #expect(InvoiceStatus.overdue(daysLate: 5).label == "Overdue, 5 days")
    }

    @Test func paymentsMoveAnInvoiceToPartPaidThenPaid() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(throws: LibraryError.notSent) {
            try library.recordPayment(Payment(date: today, amount: Money(dollars: 100)), toInvoice: deposit.id)
        }
        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 200)), toInvoice: deposit.id)
        #expect(library.invoice(deposit.id)!.status(on: today) == .partPaid)
        #expect(library.activity.first?.message == "Recorded $200.00 paid on 15 October 2026 by bank transfer for INV-0001")
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 340), method: .cash), toInvoice: deposit.id)
        #expect(library.invoice(deposit.id)!.status(on: today.adding(days: 60)) == .paid)
        #expect(throws: LibraryError.hasPayments) { try library.voidInvoice(deposit.id) }
    }

    @Test func removingAPaymentUndoesIt() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        let payment = Payment(date: today, amount: Money(dollars: 540))
        try library.recordPayment(payment, toInvoice: deposit.id)
        try library.removePayment(payment.id, fromInvoice: deposit.id)
        #expect(library.invoice(deposit.id)!.owing == Money(dollars: 540))
        #expect(library.activity.first?.message == "Removed the $540.00 payment of 15 October 2026 from INV-0001")
    }

    @Test func duplicatingAnInvoiceMakesAFreshDraft() throws {
        var library = Library()
        var monthly = library.newInvoice(on: today)
        monthly.lines = [LineItem(title: "Hosting and upkeep, October", rate: Money(dollars: 30))]
        try library.update(monthly)
        try library.markSent(invoice: monthly.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 30)), toInvoice: monthly.id)
        let next = try library.duplicateInvoice(monthly.id, on: today.adding(days: 31))
        #expect(next.number == "INV-0002")
        #expect(next.stage == .draft)
        #expect(next.payments.isEmpty)
        #expect(next.issued == today.adding(days: 31))
        #expect(next.lines.map(\.title) == ["Hosting and upkeep, October"])
        #expect(next.lines[0].id != monthly.lines[0].id)
    }

    @Test func duplicatingAQuoteClearsTheClientsDecisions() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let copy = try library.duplicateQuote(id, on: today)
        #expect(copy.number == "Q-0002")
        #expect(copy.stage == .draft)
        #expect(copy.acceptance == nil)
        #expect(copy.lines.allSatisfy { $0.decision == nil })
        #expect(copy.lineCodes == ["01", "02", "03"])
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter InvoicingTests`
Expected: build failure, `value of type 'Library' has no member 'draftNextInvoice'`.

- [ ] **Step 3: Write `Invoicing.swift`**

```swift
import Foundation

public enum InvoiceStatus: Equatable, Sendable {
    case draft, sent, partPaid, paid, void
    case overdue(daysLate: Int)

    public var label: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .partPaid: return "Part paid"
        case .paid: return "Paid"
        case .void: return "Void"
        case .overdue(let days): return days == 1 ? "Overdue, 1 day" : "Overdue, \(days) days"
        }
    }
}

extension Invoice {
    /// Overdue starts the day after the due date, and only while money is still owing.
    public func status(on today: Day) -> InvoiceStatus {
        switch stage {
        case .draft: return .draft
        case .void: return .void
        case .sent:
            if owing <= .zero { return .paid }
            if today > due { return .overdue(daysLate: today.days(since: due)) }
            return paid > .zero ? .partPaid : .sent
        }
    }
}

extension InvoiceKind {
    public var label: String {
        switch self {
        case .deposit: return "deposit invoice"
        case .final: return "final invoice"
        case .full, .standalone: return "invoice"
        }
    }
}

extension LineItem {
    /// The same line with a new identity and no client decision, for copies and invoices.
    var freshCopy: LineItem {
        var copy = self
        copy.id = UUID()
        copy.decision = nil
        return copy
    }
}

extension Library {
    /// A quote's invoices that still count (void ones don't).
    public func invoices(forQuote id: UUID) -> [Invoice] {
        invoices.filter { $0.quoteID == id && $0.stage != .void }
    }

    public func invoicedAmount(forQuote id: UUID) -> Money {
        invoices(forQuote: id).reduce(.zero) { $0 + $1.amount }
    }

    /// The invoice the quote's plan calls for next, or nil when nothing is left to invoice.
    public func nextInvoiceKind(forQuote id: UUID) -> InvoiceKind? {
        guard let found = quote(id), found.stage == .accepted, !found.acceptedLines.isEmpty else { return nil }
        let kinds = invoices(forQuote: id).map(\.kind)
        switch found.plan {
        case .fiftyFifty:
            if kinds.contains(.final) { return nil }
            return kinds.contains(.deposit) ? .final : .deposit
        case .fullAmount:
            return kinds.contains(.full) ? nil : .full
        }
    }

    /// "Draft invoice now": the deposit if there isn't one yet, otherwise the closing invoice.
    @discardableResult
    public mutating func draftNextInvoice(forQuote id: UUID, on day: Day) throws -> Invoice {
        let found = try acceptedQuote(id)
        guard let kind = nextInvoiceKind(forQuote: id) else { throw LibraryError.nothingLeftToInvoice }
        return draftInvoice(kind, for: found, on: day)
    }

    /// "Job complete": records the date, then drafts the closing invoice unless it already exists.
    /// For 50/50 without a deposit invoice, the final invoice simply bills the whole accepted total.
    @discardableResult
    public mutating func completeJob(quote id: UUID, on day: Day) throws -> Invoice? {
        let found = try acceptedQuote(id)
        let index = try quoteIndex(id)
        quotes[index].completedOn = day
        log("Marked the job for \(found.number) complete", number: found.number)
        let closing: InvoiceKind = found.plan == .fiftyFifty ? .final : .full
        guard !invoices(forQuote: id).contains(where: { $0.kind == closing }) else { return nil }
        return draftInvoice(closing, for: found, on: day)
    }

    private func acceptedQuote(_ id: UUID) throws -> Quote {
        guard let found = quote(id) else { throw LibraryError.notFound }
        guard found.stage == .accepted else { throw LibraryError.notAccepted }
        guard !found.acceptedLines.isEmpty else { throw LibraryError.nothingAccepted }
        return found
    }

    private mutating func draftInvoice(_ kind: InvoiceKind, for quote: Quote, on day: Day) -> Invoice {
        var invoice = Invoice(number: takeNumber(.invoice), clientID: quote.clientID, quoteID: quote.id,
                              kind: kind, title: quote.title, issued: day,
                              due: day.adding(days: brand.paymentDueDays), taxed: quote.taxed,
                              lines: quote.acceptedLines.map(\.freshCopy), terms: brand.invoiceTerms)
        if kind == .deposit {
            invoice.depositPercent = quote.plan.depositPercent ?? 50
        }
        if kind == .final {
            invoice.deductions = invoices(forQuote: quote.id)
                .filter { $0.kind == .deposit }
                .map { Deduction(label: "Less deposit", invoiceNumber: $0.number, amount: $0.amount) }
        }
        invoices.append(invoice)
        log("Drafted \(kind.label) \(invoice.number) for \(invoice.amount.formatted()) from quote \(quote.number)",
            number: invoice.number)
        return invoice
    }

    // MARK: Sending and payments

    public mutating func markSent(invoice id: UUID, at time: Date = Date()) throws {
        let index = try invoiceIndex(id)
        guard invoices[index].stage != .void else { throw LibraryError.isVoid }
        invoices[index].stage = .sent
        invoices[index].sentAt = time
        log("Marked invoice \(invoices[index].number) as sent", number: invoices[index].number, at: time)
    }

    public mutating func recordPayment(_ payment: Payment, toInvoice id: UUID) throws {
        let index = try invoiceIndex(id)
        switch invoices[index].stage {
        case .void: throw LibraryError.isVoid
        case .draft: throw LibraryError.notSent
        case .sent: break
        }
        invoices[index].payments.append(payment)
        let number = invoices[index].number
        log("Recorded \(payment.amount.formatted()) paid on \(payment.date.long) by \(payment.method.label.lowercased()) for \(number)",
            number: number)
    }

    public mutating func removePayment(_ paymentID: UUID, fromInvoice id: UUID) throws {
        let index = try invoiceIndex(id)
        guard let position = invoices[index].payments.firstIndex(where: { $0.id == paymentID }) else {
            throw LibraryError.notFound
        }
        let removed = invoices[index].payments.remove(at: position)
        let number = invoices[index].number
        log("Removed the \(removed.amount.formatted()) payment of \(removed.date.long) from \(number)", number: number)
    }

    /// Cancels a sent invoice and keeps its number used. Drafts are deleted instead; an invoice
    /// with payments must have them removed first.
    public mutating func voidInvoice(_ id: UUID) throws {
        let index = try invoiceIndex(id)
        switch invoices[index].stage {
        case .void: throw LibraryError.isVoid
        case .draft: throw LibraryError.notSent
        case .sent: break
        }
        guard invoices[index].payments.isEmpty else { throw LibraryError.hasPayments }
        invoices[index].stage = .void
        log("Voided invoice \(invoices[index].number)", number: invoices[index].number)
    }

    public mutating func markReceiptSent(invoice id: UUID, at time: Date = Date()) throws {
        let index = try invoiceIndex(id)
        invoices[index].receiptSentAt = time
        log("Marked the receipt for \(invoices[index].number) as sent", number: invoices[index].number, at: time)
    }

    // MARK: Copies

    /// A fresh draft dated `day`: for repeat work such as a monthly fee.
    @discardableResult
    public mutating func duplicateInvoice(_ id: UUID, on day: Day) throws -> Invoice {
        guard let original = invoice(id) else { throw LibraryError.notFound }
        let copy = Invoice(number: takeNumber(.invoice), clientID: original.clientID, kind: .standalone,
                           title: original.title, issued: day, due: day.adding(days: brand.paymentDueDays),
                           taxed: original.taxed, lines: original.lines.map(\.freshCopy), terms: original.terms)
        invoices.append(copy)
        log("Copied invoice \(original.number) to \(copy.number)", number: copy.number)
        return copy
    }

    @discardableResult
    public mutating func duplicateQuote(_ id: UUID, on day: Day) throws -> Quote {
        guard let original = quote(id) else { throw LibraryError.notFound }
        var copy = Quote(number: takeNumber(.quote), clientID: original.clientID, title: original.title,
                         issued: day, validUntil: day.adding(days: brand.quoteValidDays), plan: original.plan,
                         taxed: original.taxed, summary: original.summary, terms: original.terms)
        for line in original.lines {
            copy.addLine(line.freshCopy)
        }
        quotes.append(copy)
        log("Copied quote \(original.number) to \(copy.number)", number: copy.number)
        return copy
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Add invoicing: 50/50 and full plans, job complete, payments, void, copies

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Dashboard figures, financial years and the tax-time CSV

**Files:**
- Create: `Sources/QuotePilotCore/Dashboard.swift`
- Test: `Tests/QuotePilotCoreTests/DashboardTests.swift`

**Interfaces:**
- Consumes: `Library`, `Invoice.owing`, `invoicedAmount(forQuote:)`, `Fixture` (Tasks 1–4).
- Produces:
  - **Financial years:** `FinancialYear(startYear:)`, `FinancialYear(containing:)`, with `start`,
    `end`, `contains(_:)` and `label` ("FY 2026–27")
  - **Dashboard:** `Dashboard(library:today:)` with:
    - `waiting: [Dashboard.Owing]` (overdue first, most days late first), `waitingTotal`,
      `overdueTotal`
    - `receivedThisMonth`, `receivedThisYear`, `invoicedThisYear`
    - `openQuotes: [Dashboard.OpenQuote]`, `openQuotesTotal`
    - `toInvoice: [Dashboard.ToInvoice]`
  - **CSV:** `Library.paymentsCSV(for: FinancialYear) -> String`; internal `csvField(_:)`

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotCoreTests/DashboardTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct DashboardTests {
    let today = Day(year: 2026, month: 10, day: 15)

    @Test func financialYearEdges() {
        #expect(FinancialYear(containing: Day(year: 2027, month: 6, day: 30)) == FinancialYear(startYear: 2026))
        #expect(FinancialYear(containing: Day(year: 2027, month: 7, day: 1)) == FinancialYear(startYear: 2027))
        #expect(FinancialYear(startYear: 2026).label == "FY 2026–27")
        #expect(FinancialYear(startYear: 2026).contains(Day(year: 2026, month: 7, day: 1)))
        #expect(!FinancialYear(startYear: 2026).contains(Day(year: 2026, month: 6, day: 30)))
    }

    /// A made-up, busy library on 15 Oct 2026:
    /// - Q-0001 accepted 50/50 ($1,080). Deposit INV-0001 ($540) issued 15 Sep, paid 20 Sep.
    /// - INV-0002 $300, issued 15 Sep, due 29 Sep, $100 paid 10 Oct: 16 days late, $200 owing.
    /// - INV-0003 $90, issued 14 Oct, due 28 Oct, unpaid.
    /// - INV-0004 $500 draft (doesn't count).
    /// - INV-0005 $60, issued and paid 20 Jun 2026 (last financial year).
    /// - Q-0002 sent for $250, valid until 14 Nov.
    func busyLibrary() throws -> Library {
        var (library, quoteID) = Fixture.acceptedLibrary()
        let clientID = library.clients[0].id
        let deposit = try library.draftNextInvoice(forQuote: quoteID, on: Day(year: 2026, month: 9, day: 15))
        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: Day(year: 2026, month: 9, day: 20), amount: Money(dollars: 540)),
                                  toInvoice: deposit.id)

        func standalone(_ dollars: Int, issued: Day, send: Bool = true) throws -> Invoice {
            var invoice = library.newInvoice(on: issued, clientID: clientID)
            invoice.lines = [LineItem(title: "Extra work", rate: Money(dollars: dollars))]
            try library.update(invoice)
            if send { try library.markSent(invoice: invoice.id) }
            return invoice
        }

        let late = try standalone(300, issued: Day(year: 2026, month: 9, day: 15))
        try library.recordPayment(Payment(date: Day(year: 2026, month: 10, day: 10), amount: Money(dollars: 100)),
                                  toInvoice: late.id)
        _ = try standalone(90, issued: Day(year: 2026, month: 10, day: 14))
        _ = try standalone(500, issued: today, send: false)
        let old = try standalone(60, issued: Day(year: 2026, month: 6, day: 20))
        try library.recordPayment(Payment(date: Day(year: 2026, month: 6, day: 20), amount: Money(dollars: 60)),
                                  toInvoice: old.id)

        var second = library.newQuote(on: today, clientID: clientID)
        second.addLine(LineItem(title: "Phase 2 planning", rate: Money(dollars: 250)))
        try library.update(second)
        try library.markSent(quote: second.id)
        return library
    }

    @Test func waitingToBePaidPutsOverdueFirst() throws {
        let dashboard = Dashboard(library: try busyLibrary(), today: today)
        #expect(dashboard.waiting.map(\.number) == ["INV-0002", "INV-0003"])
        #expect(dashboard.waiting[0].daysLate == 16)
        #expect(dashboard.waiting[0].owing == Money(dollars: 200))
        #expect(dashboard.waiting[1].daysLate == 0)
        #expect(dashboard.waitingTotal == Money(dollars: 290))
        #expect(dashboard.overdueTotal == Money(dollars: 200))
    }

    @Test func receivedAndInvoicedFollowTheCalendar() throws {
        let dashboard = Dashboard(library: try busyLibrary(), today: today)
        #expect(dashboard.financialYear.label == "FY 2026–27")
        #expect(dashboard.receivedThisMonth == Money(dollars: 100))
        #expect(dashboard.receivedThisYear == Money(dollars: 640))
        #expect(dashboard.invoicedThisYear == Money(dollars: 930))
    }

    @Test func quotesAndJobsStillToInvoice() throws {
        let dashboard = Dashboard(library: try busyLibrary(), today: today)
        #expect(dashboard.openQuotes.map(\.number) == ["Q-0002"])
        #expect(dashboard.openQuotesTotal == Money(dollars: 250))
        #expect(dashboard.toInvoice.map(\.number) == ["Q-0001"])
        #expect(dashboard.toInvoice[0].remaining == Money(dollars: 540))
    }

    @Test func expiredQuotesAreShownButNotTotalled() throws {
        let dashboard = Dashboard(library: try busyLibrary(), today: Day(year: 2026, month: 11, day: 20))
        #expect(dashboard.openQuotes.first?.expired == true)
        #expect(dashboard.openQuotesTotal == .zero)
    }

    @Test func taxTimeCSVListsThisYearsPayments() throws {
        let csv = try busyLibrary().paymentsCSV(for: FinancialYear(startYear: 2026))
        #expect(csv == """
        Date,Client,Invoice,Amount,Method,Note
        2026-09-20,Sample Client Pty Ltd,INV-0001,540.00,Bank transfer,
        2026-10-10,Sample Client Pty Ltd,INV-0002,100.00,Bank transfer,

        """)
    }

    @Test func csvFieldsWithCommasOrQuotesAreQuoted() {
        #expect(csvField("Plain") == "Plain")
        #expect(csvField("Smith, Jones") == "\"Smith, Jones\"")
        #expect(csvField("The \"best\" job") == "\"The \"\"best\"\" job\"")
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter DashboardTests`
Expected: build failure, `cannot find 'FinancialYear' in scope`.

- [ ] **Step 3: Write `Dashboard.swift`**

```swift
import Foundation

/// An Australian financial year: 1 July to 30 June.
public struct FinancialYear: Hashable, Sendable {
    public let startYear: Int

    public init(startYear: Int) {
        self.startYear = startYear
    }

    public init(containing day: Day) {
        startYear = day.month >= 7 ? day.year : day.year - 1
    }

    public var start: Day { Day(year: startYear, month: 7, day: 1) }
    public var end: Day { Day(year: startYear + 1, month: 6, day: 30) }

    public func contains(_ day: Day) -> Bool { start <= day && day <= end }

    /// "FY 2026–27"
    public var label: String { "FY \(startYear)–" + String(format: "%02d", (startYear + 1) % 100) }
}

/// The main screen's figures, worked out from the library for one day.
public struct Dashboard: Equatable, Sendable {
    public struct Owing: Equatable, Sendable {
        public var invoiceID: UUID
        public var number: String
        public var client: String
        public var owing: Money
        public var due: Day
        /// 0 when not overdue yet.
        public var daysLate: Int
    }

    public struct OpenQuote: Equatable, Sendable {
        public var quoteID: UUID
        public var number: String
        public var client: String
        public var total: Money
        public var validUntil: Day
        public var expired: Bool
    }

    public struct ToInvoice: Equatable, Sendable {
        public var quoteID: UUID
        public var number: String
        public var client: String
        public var accepted: Money
        public var invoiced: Money
        public var remaining: Money { accepted - invoiced }
    }

    public var today: Day
    public var financialYear: FinancialYear
    public var waiting: [Owing]
    public var waitingTotal: Money
    public var overdueTotal: Money
    public var receivedThisMonth: Money
    public var receivedThisYear: Money
    public var invoicedThisYear: Money
    public var openQuotes: [OpenQuote]
    /// Open quotes that haven't expired.
    public var openQuotesTotal: Money
    public var toInvoice: [ToInvoice]

    public init(library: Library, today: Day) {
        self.today = today
        let year = FinancialYear(containing: today)
        financialYear = year
        func clientName(_ id: UUID?) -> String { library.client(id)?.name ?? "No client" }
        func sum(_ amounts: [Money]) -> Money { amounts.reduce(.zero, +) }

        let sent = library.invoices.filter { $0.stage == .sent }

        waiting = sent
            .filter { $0.owing > .zero }
            .map { Owing(invoiceID: $0.id, number: $0.number, client: clientName($0.clientID), owing: $0.owing,
                         due: $0.due, daysLate: max(0, today.days(since: $0.due))) }
            .sorted { a, b in
                if a.daysLate != b.daysLate { return a.daysLate > b.daysLate }
                return a.due < b.due
            }
        waitingTotal = sum(waiting.map(\.owing))
        overdueTotal = sum(waiting.filter { $0.daysLate > 0 }.map(\.owing))

        let payments = sent.flatMap(\.payments)
        receivedThisMonth = sum(payments.filter { $0.date.year == today.year && $0.date.month == today.month }.map(\.amount))
        receivedThisYear = sum(payments.filter { year.contains($0.date) }.map(\.amount))
        invoicedThisYear = sum(sent.filter { year.contains($0.issued) }.map(\.amount))

        openQuotes = library.quotes
            .filter { $0.stage == .sent }
            .map { OpenQuote(quoteID: $0.id, number: $0.number, client: clientName($0.clientID),
                             total: $0.totals.total, validUntil: $0.validUntil, expired: today > $0.validUntil) }
            .sorted { $0.validUntil < $1.validUntil }
        openQuotesTotal = sum(openQuotes.filter { !$0.expired }.map(\.total))

        toInvoice = library.quotes
            .filter { $0.stage == .accepted }
            .map { ToInvoice(quoteID: $0.id, number: $0.number, client: clientName($0.clientID),
                             accepted: $0.acceptedTotals.total, invoiced: library.invoicedAmount(forQuote: $0.id)) }
            .filter { $0.remaining > .zero }
            .sorted { $0.number < $1.number }
    }
}

extension Library {
    /// Payments received in a financial year, oldest first, for tax time.
    public func paymentsCSV(for year: FinancialYear) -> String {
        let pairs = invoices
            .filter { $0.stage == .sent }
            .flatMap { invoice in invoice.payments.filter { year.contains($0.date) }.map { (invoice, $0) } }
            .sorted { a, b in a.1.date == b.1.date ? a.0.number < b.0.number : a.1.date < b.1.date }
        let rows = pairs.map { pair -> String in
            let (invoice, payment) = pair
            return [payment.date.iso, client(invoice.clientID)?.name ?? "", invoice.number,
                    payment.amount.plain, payment.method.label, payment.note]
                .map(csvField)
                .joined(separator: ",")
        }
        return (["Date,Client,Invoice,Amount,Method,Note"] + rows).joined(separator: "\n") + "\n"
    }
}

/// Quotes a CSV field when it holds a comma, a quote mark or a line break.
func csvField(_ text: String) -> String {
    guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Add dashboard figures, financial years and the tax-time CSV

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Saving safely, daily backups and restore

**Files:**
- Create: `Sources/QuotePilotCore/LibraryStore.swift`
- Test: `Tests/QuotePilotCoreTests/LibraryStoreTests.swift`

**Interfaces:**
- Consumes: `Library`, `Library.makeEncoder()/makeDecoder()`, `Day`, `Fixture` (Tasks 1–3).
- Produces:
  - **Setup:** `LibraryStore(folder:)`, `LibraryStore.defaultFolder` (`~/Library/Application Support/Quote Pilot`)
  - **Locations:** `libraryURL`, `backupsFolder`, `assetsFolder`
  - **Loading:** `load() -> LibraryStore.LoadResult` (`.loaded`, `.fresh`, `.unreadable(reason:)`)
  - **Saving:** `save(_:) throws` (`StoreError.wouldOverwriteUnreadableLibrary`)
  - **Backups:** `backUpIfDue(today:) throws -> URL?`, `backups() -> [URL]` (newest first),
    `restore(from:now:) throws -> Library`, `exportCopy(to:) throws`

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotCoreTests/LibraryStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct LibraryStoreTests {
    func tempStore() -> LibraryStore {
        LibraryStore(folder: FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotePilotTests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func aMissingLibraryStartsFresh() {
        guard case .fresh(let library) = tempStore().load() else {
            Issue.record("expected a fresh library")
            return
        }
        #expect(library.quotes.isEmpty)
    }

    @Test func savesAndLoadsTheSameLibrary() throws {
        let store = tempStore()
        let (library, _) = Fixture.acceptedLibrary()
        try store.save(library)
        guard case .loaded(let loaded) = store.load() else {
            Issue.record("expected the saved library")
            return
        }
        #expect(try Library.makeEncoder().encode(loaded) == Library.makeEncoder().encode(library))
    }

    @Test func refusesToOverwriteAnUnreadableLibrary() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: store.libraryURL)
        guard case .unreadable = store.load() else {
            Issue.record("expected unreadable")
            return
        }
        #expect(throws: LibraryStore.StoreError.wouldOverwriteUnreadableLibrary) { try store.save(Library()) }
        #expect(try Data(contentsOf: store.libraryURL) == garbage)
    }

    @Test func aNewerFormatIsLeftAlone() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Data(#"{"format": 99}"#.utf8).write(to: store.libraryURL)
        guard case .unreadable(let reason) = store.load() else {
            Issue.record("expected unreadable")
            return
        }
        #expect(reason.contains("newer version"))
    }

    @Test func backsUpOnceADayAndKeepsThirty() throws {
        let store = tempStore()
        try store.save(Library())
        try FileManager.default.createDirectory(at: store.backupsFolder, withIntermediateDirectories: true)
        for day in 1...31 {
            let name = String(format: "library-2026-08-%02d.json", day)
            try Data("{}".utf8).write(to: store.backupsFolder.appendingPathComponent(name))
        }
        let made = try store.backUpIfDue(today: Day(year: 2026, month: 10, day: 15))
        #expect(made?.lastPathComponent == "library-2026-10-15.json")
        #expect(try store.backUpIfDue(today: Day(year: 2026, month: 10, day: 15)) == nil)
        let kept = store.backups().map(\.lastPathComponent)
        #expect(kept.count == 30)
        #expect(kept.first == "library-2026-10-15.json")
        #expect(!kept.contains("library-2026-08-01.json"))
        #expect(!kept.contains("library-2026-08-02.json"))
    }

    @Test func restoringKeepsTheFileItReplaces() throws {
        let store = tempStore()
        var older = Library()
        older.brand.businessName = "Sample Studio"
        try store.save(older)
        try store.backUpIfDue(today: Day(year: 2026, month: 10, day: 14))
        var newer = older
        newer.brand.businessName = "Renamed Studio"
        try store.save(newer)

        let restored = try store.restore(from: store.backups()[0])
        #expect(restored.brand.businessName == "Sample Studio")
        let names = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
        #expect(names.contains { $0.hasPrefix("library-replaced-") })
    }

    @Test func exportsACopyAnywhere() throws {
        let store = tempStore()
        try store.save(Library())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("QuotePilot-copy-\(UUID().uuidString).json")
        try store.exportCopy(to: destination)
        #expect(try Data(contentsOf: destination) == Data(contentsOf: store.libraryURL))
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter LibraryStoreTests`
Expected: build failure, `cannot find 'LibraryStore' in scope`.

- [ ] **Step 3: Write `LibraryStore.swift`**

```swift
import Foundation

/// Where the library lives and how it's kept safe.
public struct LibraryStore: Sendable {
    public enum LoadResult: Sendable {
        case loaded(Library)
        /// No library yet: start with an empty one.
        case fresh(Library)
        /// The file is there but can't be used. It is left exactly as it is.
        case unreadable(reason: String)
    }

    public enum StoreError: Error, Equatable, Sendable {
        case wouldOverwriteUnreadableLibrary
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// `~/Library/Application Support/Quote Pilot`
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quote Pilot", isDirectory: true)
    }

    public var libraryURL: URL { folder.appendingPathComponent("library.json") }
    public var backupsFolder: URL { folder.appendingPathComponent("Backups", isDirectory: true) }
    /// The brand's logo and font files.
    public var assetsFolder: URL { folder.appendingPathComponent("Assets", isDirectory: true) }

    private struct FormatProbe: Decodable {
        var format: Int
    }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return .fresh(Library()) }
        do {
            let data = try Data(contentsOf: libraryURL)
            let probe = try JSONDecoder().decode(FormatProbe.self, from: data)
            guard probe.format <= Library.currentFormat else {
                return .unreadable(reason: "It was saved by a newer version of Quote Pilot (library format \(probe.format)).")
            }
            return .loaded(try Library.makeDecoder().decode(Library.self, from: data))
        } catch {
            return .unreadable(reason: "The library file couldn't be read (\(error.localizedDescription)).")
        }
    }

    /// Writes a temporary file and swaps it in, so a crash can't leave half a library. Refuses to
    /// replace a library file it can't read: that file needs restoring, not overwriting.
    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: libraryURL.path), case .unreadable = load() {
            throw StoreError.wouldOverwriteUnreadableLibrary
        }
        try Library.makeEncoder().encode(library).write(to: libraryURL, options: .atomic)
    }

    /// Copies the library into Backups/ at most once a day, keeping the newest 30.
    @discardableResult
    public func backUpIfDue(today: Day) throws -> URL? {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return nil }
        try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let target = backupsFolder.appendingPathComponent("library-\(today.iso).json")
        guard !FileManager.default.fileExists(atPath: target.path) else { return nil }
        try FileManager.default.copyItem(at: libraryURL, to: target)
        for old in backups().dropFirst(30) {
            try FileManager.default.removeItem(at: old)
        }
        return target
    }

    /// Backups, newest first.
    public func backups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("library-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Replaces the library with a backup once the backup is known to read. The file being
    /// replaced is kept beside it as `library-replaced-<time>.json`.
    @discardableResult
    public func restore(from backup: URL, now: Date = Date()) throws -> Library {
        let library = try Library.makeDecoder().decode(Library.self, from: Data(contentsOf: backup))
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            try FileManager.default.moveItem(at: libraryURL,
                                             to: folder.appendingPathComponent("library-replaced-\(stamp).json"))
        }
        try save(library)
        return library
    }

    /// "File → Back up to…": a copy wherever the user picks.
    public func exportCopy(to destination: URL) throws {
        try Data(contentsOf: libraryURL).write(to: destination, options: .atomic)
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Save the library safely, with daily backups and restore

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Import from the old Invoice Generator

**Files:**
- Create: `Sources/QuotePilotCore/LegacyImport.swift`
- Test: `Tests/QuotePilotCoreTests/LegacyImportTests.swift`

**Interfaces:**
- Consumes: `Library`, `Quote`, `Invoice`, `Client`, `LineItem`, `Payment`, `Money`, `Day` (Tasks 1–2).
- Produces: `LegacyImport.importBackup(_ data: Data, into: inout Library, today: Day) throws -> ImportReport`;
  `ImportReport` (`addedQuotes`, `addedInvoices`, `skipped`, `addedClients`, `notes`, `logoData`,
  `summary`); `LegacyImportError.notABackup`.

The old tool's backup is `{ settings: { logo }, docs: { <id>: doc } }`. Each doc has `type`
(`"invoice"` or `"quote"`), `number`, `issued`, `due` (ISO dates), `reference`,
`from`/`to` `{ name, details }`, `items` `[{ title, detail, qty, unit ("hr" | "day" | "unit"), rate }]`,
`tax { mode ("none" | "add" | "incl") }`, `discount { value }`, `paid`, `summary`, `payment`,
`notes`. Rates and `paid` are dollars as JSON numbers.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotCoreTests/LegacyImportTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct LegacyImportTests {
    let today = Day(year: 2026, month: 10, day: 15)

    /// Made-up backup in the old tool's format.
    let backup = Data(#"""
    {
      "app": "invoice-quote-maker",
      "settings": { "logo": "data:image/png;base64,iVBORw0KGgo=", "logoHeight": 56, "accent": "#0B6B66", "paper": "A4" },
      "docs": {
        "a1": { "id": "a1", "type": "quote", "number": "Q-0001", "issued": "2026-10-04", "due": "2026-11-03",
                "reference": "Booking app, phase 1",
                "from": { "name": "Sample Studio", "details": "hello@example.com" },
                "to": { "name": "Sample Client Pty Ltd", "details": "1 Example St\nExampleton" },
                "items": [ { "title": "Discovery", "detail": "Walkthrough", "qty": 2, "unit": "hr", "rate": 40 },
                           { "title": "Build (50% deposit)", "detail": "", "qty": 1, "unit": "unit", "rate": 750 } ],
                "tax": { "mode": "none", "rate": 10, "label": "GST" }, "discount": { "value": 0, "kind": "pct" },
                "paid": 0, "summary": "- Walkthrough\n- Scope", "payment": "PayID: hello@example.com",
                "notes": "Quote terms" },
        "b2": { "id": "b2", "type": "invoice", "number": "INV-0001", "issued": "2026-10-06", "due": "2026-10-20",
                "reference": "", "from": { "name": "Sample Studio", "details": "" },
                "to": { "name": "sample client pty ltd", "details": "" },
                "items": [ { "title": "Hosting, October", "detail": "", "qty": 1, "unit": "unit", "rate": 30 } ],
                "tax": { "mode": "none", "rate": 10, "label": "GST" }, "discount": { "value": 5, "kind": "pct" },
                "paid": 10, "summary": "", "payment": "", "notes": "" }
      },
      "currentId": "a1"
    }
    """#.utf8)

    @Test func importsQuotesInvoicesAndClients() throws {
        var library = Library()
        let report = try LegacyImport.importBackup(backup, into: &library, today: today)
        #expect(report.addedQuotes == ["Q-0001"])
        #expect(report.addedInvoices == ["INV-0001"])
        #expect(report.addedClients == ["Sample Client Pty Ltd"])
        #expect(report.notes == ["INV-0001: its discount wasn't imported; add it as a line if needed."])

        let quote = try #require(library.quote(number: "Q-0001"))
        #expect(quote.stage == .sent)
        #expect(quote.title == "Booking app, phase 1")
        #expect(quote.lineCodes == ["01", "02"])
        #expect(quote.lines.map(\.amount) == [Money(dollars: 80), Money(dollars: 750)])
        #expect(quote.lines[0].unit == .hours)
        #expect(quote.summary == "- Walkthrough\n- Scope")
        #expect(quote.nextLineCode() == "03")
        #expect(library.client(quote.clientID)?.address == "1 Example St\nExampleton")

        let invoice = try #require(library.invoices.first)
        #expect(invoice.clientID == quote.clientID)
        #expect(invoice.kind == .standalone)
        #expect(invoice.payments.map(\.amount) == [Money(dollars: 10)])
        #expect(invoice.payments.first?.note == "Imported: already paid")

        #expect(library.brand.businessName == "Sample Studio")
        #expect(library.brand.paymentDetails == "PayID: hello@example.com")
        #expect(report.logoData == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(library.nextNumber(.quote) == "Q-0002")
        #expect(library.nextNumber(.invoice) == "INV-0002")
        #expect(library.activity.first?.message == "Imported 1 quote and 1 invoice from Invoice Generator.")
    }

    @Test func importingTwiceSkipsWhatsAlreadyThere() throws {
        var library = Library()
        _ = try LegacyImport.importBackup(backup, into: &library, today: today)
        let again = try LegacyImport.importBackup(backup, into: &library, today: today)
        #expect(again.addedQuotes.isEmpty)
        #expect(again.addedInvoices.isEmpty)
        #expect(again.skipped == ["Q-0001", "INV-0001"])
        #expect(library.quotes.count == 1)
        #expect(library.clients.count == 1)
    }

    @Test func anExistingLogoIsKept() throws {
        var library = Library()
        library.brand.logoFile = "logo.png"
        let report = try LegacyImport.importBackup(backup, into: &library, today: today)
        #expect(report.logoData == nil)
    }

    @Test func otherFilesAreRejected() {
        var library = Library()
        #expect(throws: LegacyImportError.notABackup) {
            try LegacyImport.importBackup(Data("[1, 2, 3]".utf8), into: &library, today: today)
        }
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter LegacyImportTests`
Expected: build failure, `cannot find 'LegacyImport' in scope`.

- [ ] **Step 3: Write `LegacyImport.swift`**

```swift
import Foundation

public struct ImportReport: Equatable, Sendable {
    public var addedQuotes: [String] = []
    public var addedInvoices: [String] = []
    /// Numbers that were already in the library.
    public var skipped: [String] = []
    public var addedClients: [String] = []
    /// Things that didn't carry over exactly.
    public var notes: [String] = []
    /// The old tool's logo, for the app to save as the brand logo (only when there isn't one yet).
    public var logoData: Data?

    public init() {}

    public var summary: String {
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        var text = "Imported \(count(addedQuotes.count, "quote")) and \(count(addedInvoices.count, "invoice")) from Invoice Generator"
        if !skipped.isEmpty { text += "; skipped \(skipped.joined(separator: ", ")), already here" }
        return text + "."
    }
}

public enum LegacyImportError: Error, Equatable, Sendable {
    case notABackup
}

/// Reads the JSON that Invoice Generator.html's "Back up to file" button writes.
public enum LegacyImport {
    struct Backup: Decodable {
        struct Settings: Decodable { var logo: String? }
        struct Party: Decodable { var name: String?; var details: String? }
        struct Item: Decodable {
            var title: String?
            var detail: String?
            var qty: Double?
            var unit: String?
            var rate: Double?
        }
        struct Tax: Decodable { var mode: String? }
        struct Discount: Decodable { var value: Double? }
        struct Doc: Decodable {
            var type: String?
            var number: String?
            var issued: String?
            var due: String?
            var reference: String?
            var from: Party?
            var to: Party?
            var items: [Item]?
            var tax: Tax?
            var discount: Discount?
            var paid: Double?
            var summary: String?
            var payment: String?
            var notes: String?
        }
        var settings: Settings?
        var docs: [String: Doc]
    }

    public static func importBackup(_ data: Data, into library: inout Library, today: Day) throws -> ImportReport {
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data) else {
            throw LegacyImportError.notABackup
        }
        var report = ImportReport()
        // Oldest first, so clients and brand details come from the earliest document.
        let docs = backup.docs.values.sorted {
            ($0.issued ?? "", $0.number ?? "") < ($1.issued ?? "", $1.number ?? "")
        }

        for doc in docs {
            guard let number = doc.number?.trimmingCharacters(in: .whitespaces), !number.isEmpty else {
                report.notes.append("Skipped a document with no number.")
                continue
            }
            if library.usedNumbers.contains(number) {
                report.skipped.append(number)
                continue
            }
            let clientID = client(for: doc.to, in: &library, report: &report)
            let issued = doc.issued.flatMap(Day.init(iso:)) ?? today
            let due = doc.due.flatMap(Day.init(iso:)) ?? issued.adding(days: library.brand.paymentDueDays)
            let taxed = doc.tax?.mode == "add"
            if doc.tax?.mode == "incl" {
                report.notes.append("\(number): prices included GST in the old tool; imported as entered, without GST.")
            }
            if let discount = doc.discount?.value, discount > 0 {
                report.notes.append("\(number): its discount wasn't imported; add it as a line if needed.")
            }
            let lines = (doc.items ?? []).enumerated().map { index, item in
                LineItem(code: String(format: "%02d", index + 1), title: item.title ?? "", detail: item.detail ?? "",
                         quantity: Decimal(item.qty ?? 1), unit: unit(item.unit), rate: dollars(item.rate ?? 0))
            }

            if doc.type == "quote" {
                library.quotes.append(Quote(number: number, clientID: clientID, title: doc.reference ?? "",
                                            issued: issued, validUntil: due, plan: .fiftyFifty, taxed: taxed,
                                            lines: lines, summary: doc.summary ?? "", terms: doc.notes ?? "",
                                            stage: .sent))
                report.addedQuotes.append(number)
            } else {
                var invoice = Invoice(number: number, clientID: clientID, kind: .standalone,
                                      title: doc.reference ?? "", issued: issued, due: due, taxed: taxed,
                                      lines: lines, terms: doc.notes ?? "", stage: .sent)
                if let paid = doc.paid, paid > 0 {
                    invoice.payments = [Payment(date: issued, amount: dollars(paid), method: .other,
                                                note: "Imported: already paid")]
                }
                library.invoices.append(invoice)
                report.addedInvoices.append(number)
            }
            library.usedNumbers.append(number)
            adoptBrandDetails(from: doc, into: &library.brand)
        }

        if library.brand.logoFile == nil, let logo = backup.settings?.logo {
            report.logoData = dataFromDataURL(logo)
        }
        library.log(report.summary)
        return report
    }

    static func client(for party: Backup.Party?, in library: inout Library, report: inout ImportReport) -> UUID? {
        let name = party?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        if let existing = library.clients.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.id
        }
        let client = Client(name: name, address: party?.details ?? "")
        library.addClient(client)
        report.addedClients.append(name)
        return client.id
    }

    static func adoptBrandDetails(from doc: Backup.Doc, into brand: inout Brand) {
        if brand.businessName.isEmpty, let name = doc.from?.name, !name.isEmpty {
            brand.businessName = name
            brand.details = doc.from?.details ?? ""
        }
        if brand.paymentDetails.isEmpty, let payment = doc.payment, !payment.isEmpty {
            brand.paymentDetails = payment
        }
    }

    static func unit(_ text: String?) -> Unit {
        switch text {
        case "hr": return .hours
        case "day": return .days
        default: return .units
        }
    }

    static func dollars(_ value: Double) -> Money {
        Money(cents: 100).times(Decimal(value))
    }

    /// The bytes inside `data:image/png;base64,....`
    static func dataFromDataURL(_ text: String) -> Data? {
        guard text.hasPrefix("data:"), let comma = text.firstIndex(of: ","),
              text[..<comma].hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(text[text.index(after: comma)...]))
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Import documents from the old Invoice Generator backup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Drawing quotes, invoices and receipts as PDFs

**Files:**
- Modify: `Package.swift` (add the `QuotePilotPDF` library and its tests)
- Create: `Sources/QuotePilotPDF/PDFStyle.swift`
- Create: `Sources/QuotePilotPDF/PageWriter.swift`
- Create: `Sources/QuotePilotPDF/QuoteFormFields.swift`
- Create: `Sources/QuotePilotPDF/DocumentContent.swift`
- Create: `Sources/QuotePilotPDF/DocumentRenderer.swift`
- Test: `Tests/QuotePilotPDFTests/Sample.swift`
- Test: `Tests/QuotePilotPDFTests/RendererTests.swift`

**Interfaces:**
- Consumes: `Quote`, `Invoice`, `Client`, `Brand`, `LineItem`, `Money`, `Day`, `Unit.describe` (Tasks 1–4).
- Produces:
  - **Style:** `PDFStyle(accentHex:headingFontURL:logo:)`, `PDFStyle(brand:assetsFolder:)`,
    `PDFStyle.color(hex:)`; `Logo(url:)` (PNG, JPG or PDF)
  - **Content:**
    - `DocumentContent.quote(_:client:brand:)`
    - `DocumentContent.invoice(_:client:brand:quoteNumber:)`
    - `DocumentContent.receipt(_:client:brand:)`
    - fields `title`, `number`, `amount`, `amountNote`, `totals: [TotalLine]`, `fileName`,
      `formQuoteNumber`
  - **Drawing:** `DocumentRenderer.render(_: DocumentContent, style: PDFStyle) -> Data` (quotes get
    the tick-box form)
  - **Form field names:** `QuoteFormFields.acceptAll(_:)`, `.line(_:_:)`, `.name(_:)`, `.date(_:)`,
    `.parse(_:) -> (quote: String, part: QuoteFormFields.Part)?`
  - **Internal:** `PageWriter` (used by tests to flatten a PDF)

- [ ] **Step 1: Add the PDF library to `Package.swift`**

```swift
// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Command Line Tools 27.0 install the Swift Testing macro plugin in a folder SwiftPM's build system
// doesn't search. Point the compiler at it when it's there; Xcode users don't need this.
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])]
    : []

let package = Package(
    name: "QuotePilot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuotePilotCore", targets: ["QuotePilotCore"]),
        .library(name: "QuotePilotPDF", targets: ["QuotePilotPDF"]),
    ],
    targets: [
        .target(name: "QuotePilotCore"),
        .target(name: "QuotePilotPDF", dependencies: ["QuotePilotCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "QuotePilotCoreTests", dependencies: ["QuotePilotCore"],
                    swiftSettings: testSettings),
        .testTarget(name: "QuotePilotPDFTests", dependencies: ["QuotePilotCore", "QuotePilotPDF"],
                    swiftSettings: testSettings + [.swiftLanguageMode(.v5)]),
    ]
)
```

- [ ] **Step 2: Write the sample data and the failing tests**

`Tests/QuotePilotPDFTests/Sample.swift`:

```swift
import Foundation
import PDFKit
import QuotePilotCore
@testable import QuotePilotPDF

/// Made-up documents for the PDF tests. Never real clients: this repo is public.
enum Sample {
    static let today = Day(year: 2026, month: 10, day: 15)

    static var brand: Brand {
        var brand = Brand()
        brand.businessName = "Sample Studio"
        brand.details = "hello@example.com\n0400 000 000"
        brand.paymentDetails = "BSB 000-000, account 00000000"
        brand.abn = "00 000 000 000"
        return brand
    }

    static let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example",
                               email: "sam@example.com", address: "1 Example St")

    /// Q-0001: 01 Discovery (2 hrs × $40), 02 Build ($1,000), 03 Extra screens ($420), plus any
    /// number of long extra lines ("Item 004", "Item 005", …).
    static func quote(extraLines: Int = 0) -> Quote {
        var quote = Quote(number: "Q-0001", clientID: client.id, title: "Booking app, phase 1",
                          issued: today, validUntil: today.adding(days: 30))
        quote.summary = "What's included:\n- A walkthrough of the current process\n- The agreed screens"
        quote.terms = "Prices are fixed for the work listed."
        quote.addLine(LineItem(title: "Discovery", detail: "Walkthrough of the current process",
                               quantity: 2, unit: .hours, rate: Money(dollars: 40)))
        quote.addLine(LineItem(title: "Build", rate: Money(dollars: 1000)))
        quote.addLine(LineItem(title: "Extra screens", rate: Money(dollars: 420)))
        for n in 0..<extraLines {
            quote.addLine(LineItem(title: "Item " + String(format: "%03d", n + 4),
                                   detail: String(repeating: "A longer description that wraps onto more lines. ", count: 3),
                                   rate: Money(dollars: 10)))
        }
        return quote
    }

    static func invoice(_ kind: InvoiceKind, taxed: Bool = false) -> Invoice {
        Invoice(number: "INV-0001", clientID: client.id, kind: kind, issued: today, due: today.adding(days: 14),
                taxed: taxed, lines: Array(quote().lines.prefix(2)), stage: .sent)
    }

    static func pdf(_ content: DocumentContent, style: PDFStyle = PDFStyle()) -> PDFDocument {
        PDFDocument(data: DocumentRenderer.render(content, style: style))!
    }

    static func text(_ document: PDFDocument) -> String {
        (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }
}
```

`Tests/QuotePilotPDFTests/RendererTests.swift`:

```swift
import AppKit
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

@Suite struct RendererTests {
    @Test func aQuoteShowsEverythingTheClientNeeds() {
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        #expect(content.fileName == "Q-0001 Sample Client Pty Ltd.pdf")
        #expect(content.amount == "$1,500.00")
        #expect(content.formQuoteNumber == "Q-0001")
        let document = Sample.pdf(content)
        #expect(document.pageCount == 1)
        let text = Sample.text(document)
        for expected in ["Quote", "Q-0001", "Sample Studio", "Sample Client Pty Ltd", "Discovery", "2 hrs",
                         "$1,500.00", "Accept all", "Accepted by", "Work summary", "Payment plan",
                         "50% when the quote is accepted"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
        #expect(!text.contains("ABN"))
    }

    @Test func aDepositInvoiceBillsTheShare() {
        var invoice = Sample.invoice(.deposit)
        invoice.depositPercent = 50
        let content = DocumentContent.invoice(invoice, client: Sample.client, brand: Sample.brand, quoteNumber: "Q-0001")
        #expect(content.title == "Invoice")
        #expect(content.amount == "$540.00")
        #expect(content.totals.map(\.label) == ["Accepted total", "Deposit (50%)"])
        let text = Sample.text(Sample.pdf(content))
        #expect(text.contains("Deposit (50%)"))
        #expect(text.contains("BSB 000-000"))
        #expect(text.contains("Due 29 October 2026"))
    }

    @Test func aFinalInvoiceSubtractsTheDeposit() {
        var invoice = Sample.invoice(.final)
        invoice.deductions = [Deduction(label: "Less deposit", invoiceNumber: "INV-0000", amount: Money(dollars: 540))]
        let content = DocumentContent.invoice(invoice, client: Sample.client, brand: Sample.brand, quoteNumber: "Q-0001")
        #expect(content.totals.map(\.label) == ["Accepted total", "Less deposit, INV-0000", "Balance (AUD)"])
        #expect(content.amount == "$540.00")
    }

    @Test func taxedInvoicesAreTaxInvoicesWithTheABN() {
        let content = DocumentContent.invoice(Sample.invoice(.standalone, taxed: true), client: Sample.client,
                                              brand: Sample.brand, quoteNumber: nil)
        #expect(content.title == "Tax invoice")
        #expect(content.totals.map(\.label) == ["Subtotal", "GST (10%)", "Total (AUD)"])
        #expect(content.amount == "$1,188.00")
        #expect(Sample.text(Sample.pdf(content)).contains("ABN 00 000 000 000"))
    }

    @Test func aReceiptListsThePayments() {
        var invoice = Sample.invoice(.standalone)
        invoice.payments = [Payment(date: Sample.today.adding(days: 2), amount: Money(dollars: 1080))]
        let content = DocumentContent.receipt(invoice, client: Sample.client, brand: Sample.brand)
        #expect(content.title == "Receipt")
        #expect(content.amountNote == "Paid in full. Thank you.")
        #expect(content.fileName == "Receipt INV-0001 Sample Client Pty Ltd.pdf")
        #expect(Sample.text(Sample.pdf(content)).contains("Paid 17 Oct 2026, bank transfer"))
    }

    @Test func invoicesHaveNoForm() {
        let document = Sample.pdf(DocumentContent.invoice(Sample.invoice(.standalone), client: Sample.client,
                                                          brand: Sample.brand, quoteNumber: nil))
        let widgets = (0..<document.pageCount).flatMap { document.page(at: $0)!.annotations }
        #expect(widgets.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/System/Library/Fonts/Supplemental/Georgia.ttf")))
    func theBrandsHeadingFontIsEmbedded() {
        let style = PDFStyle(headingFontURL: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Georgia.ttf"))
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        let data = DocumentRenderer.render(content, style: style)
        #expect(String(decoding: data, as: UTF8.self).contains("Georgia"))
    }

    @Test func aLogoIsDrawn() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("logo-\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: 120, height: 40), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: url)
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        let plain = DocumentRenderer.render(content, style: PDFStyle())
        let branded = DocumentRenderer.render(content, style: PDFStyle(logo: Logo(url: url)))
        #expect(Logo(url: url) != nil)
        #expect(branded.count > plain.count)
    }

    @Test func coloursComeFromHex() {
        #expect(PDFStyle.color(hex: "#0B6B66")?.components == [11.0 / 255, 107.0 / 255, 102.0 / 255, 1])
        #expect(PDFStyle.color(hex: "nope") == nil)
    }
}
```

- [ ] **Step 3: Run them to watch them fail**

Run: `swift test --filter RendererTests`
Expected: build failure, `cannot find 'DocumentContent' in scope`.

- [ ] **Step 4: Write `PDFStyle.swift`**

```swift
import AppKit
import CoreText
import ImageIO
import QuotePilotCore

/// Colours, fonts and logo for documents.
public struct PDFStyle {
    public static let ink = CGColor(srgbRed: 0x1F / 255, green: 0x2A / 255, blue: 0x44 / 255, alpha: 1)
    public static let muted = CGColor(srgbRed: 0x5E / 255, green: 0x67 / 255, blue: 0x7C / 255, alpha: 1)
    public static let rule = CGColor(srgbRed: 0xDD / 255, green: 0xE2 / 255, blue: 0xEA / 255, alpha: 1)

    public var accent: CGColor
    public var headingFontURL: URL?
    public var logo: Logo?

    public init(accentHex: String = "#0B6B66", headingFontURL: URL? = nil, logo: Logo? = nil) {
        accent = PDFStyle.color(hex: accentHex) ?? PDFStyle.color(hex: "#0B6B66")!
        self.headingFontURL = headingFontURL
        self.logo = logo
    }

    /// The brand's look, with its logo and font files found in the library's Assets folder.
    public init(brand: Brand, assetsFolder: URL?) {
        let fontURL = brand.headingFontFile.flatMap { name in assetsFolder?.appendingPathComponent(name) }
        let logo = brand.logoFile.flatMap { name in assetsFolder.flatMap { Logo(url: $0.appendingPathComponent(name)) } }
        self.init(accentHex: brand.accentHex, headingFontURL: fontURL, logo: logo)
    }

    /// "#0B6B66" → an sRGB colour, or nil if it isn't six hex digits.
    public static func color(hex: String) -> CGColor? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    /// The brand's heading font, or the system font in semibold when there's none or it won't load.
    func heading(_ size: CGFloat) -> CTFont {
        if let url = headingFontURL,
           let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first {
            return CTFontCreateWithFontDescriptor(first, size, nil)
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold) as CTFont
    }

    func body(_ size: CGFloat, weight: NSFont.Weight = .regular) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: weight) as CTFont
    }
}

/// A logo from a PNG or JPG (bitmap) or a PDF (stays sharp at any size).
public enum Logo {
    case bitmap(CGImage)
    case vector(CGPDFPage)

    public init?(url: URL) {
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
            self = .vector(page)
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            self = .bitmap(image)
        }
    }

    var size: CGSize {
        switch self {
        case .bitmap(let image): return CGSize(width: image.width, height: image.height)
        case .vector(let page): return page.getBoxRect(.cropBox).size
        }
    }

    /// Draws inside `rect` (PDF coordinates), keeping its shape, against the left edge.
    func draw(in rect: CGRect, context: CGContext) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawn = CGRect(x: rect.minX, y: rect.minY + (rect.height - size.height * scale) / 2,
                           width: size.width * scale, height: size.height * scale)
        switch self {
        case .bitmap(let image):
            context.draw(image, in: drawn)
        case .vector(let page):
            let box = page.getBoxRect(.cropBox)
            context.saveGState()
            context.translateBy(x: drawn.minX, y: drawn.minY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            context.restoreGState()
        }
    }
}
```

- [ ] **Step 5: Write `PageWriter.swift`**

```swift
import AppKit
import CoreText

/// Draws A4 pages from the top down with Core Text, starting a new page when space runs out.
final class PageWriter {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 46

    let context: CGContext
    private(set) var pageIndex = -1
    /// Distance from the top of the page to where the next thing goes.
    var y: CGFloat = 0
    /// Runs at the top of every page after the first, e.g. to repeat the table header.
    var onNewPage: ((PageWriter) -> Void)?

    init(context: CGContext) {
        self.context = context
    }

    var left: CGFloat { Self.margin }
    var width: CGFloat { Self.pageSize.width - 2 * Self.margin }
    var right: CGFloat { left + width }
    var bottom: CGFloat { Self.pageSize.height - Self.margin }

    func newPage() {
        if pageIndex >= 0 { context.endPDFPage() }
        context.beginPDFPage(nil)
        context.textMatrix = .identity
        pageIndex += 1
        y = Self.margin
        if pageIndex > 0 { onNewPage?(self) }
    }

    func finish() {
        if pageIndex >= 0 { context.endPDFPage() }
        context.closePDF()
    }

    /// Starts a new page unless `height` more points fit on this one.
    func ensureSpace(_ height: CGFloat) {
        if y + height > bottom { newPage() }
    }

    /// A rectangle measured from the top-left of the page, in PDF coordinates (origin bottom-left).
    func pdfRect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: Self.pageSize.height - top - height, width: width, height: height)
    }

    // MARK: Text

    static func text(_ string: String, _ font: CTFont, _ color: CGColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
    }

    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0 else { return 0 }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(size.height)
    }

    static func width(of text: NSAttributedString) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil))
    }

    static func lineHeight(_ font: CTFont) -> CGFloat {
        ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// Wrapped, left-aligned text with its top at `top`. Returns the height it took.
    @discardableResult
    func draw(_ text: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let height = Self.height(of: text, width: width)
        guard height > 0 else { return 0 }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: pdfRect(x: x, top: top, width: width, height: height + 2), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
        return height
    }

    /// One line of text ending at `right`, with its top at `top`.
    func drawRight(_ text: NSAttributedString, right: CGFloat, top: CGFloat) {
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
        context.textPosition = CGPoint(x: right - lineWidth, y: Self.pageSize.height - top - ascent)
        CTLineDraw(line, context)
    }

    func rule(top: CGFloat, x: CGFloat, width: CGFloat, color: CGColor, thickness: CGFloat = 0.75) {
        context.setFillColor(color)
        context.fill(pdfRect(x: x, top: top, width: width, height: thickness))
    }
}
```

- [ ] **Step 6: Write `QuoteFormFields.swift`**

```swift
import Foundation

/// Names of the form fields on a quote PDF. Every name carries the quote number, so a returned PDF
/// says which quote it answers.
public enum QuoteFormFields {
    static let prefix = "quotepilot."

    public enum Part: Equatable {
        case all, name, date
        case line(String)
    }

    public static func acceptAll(_ quote: String) -> String { "\(prefix)\(quote).all" }
    public static func line(_ quote: String, _ code: String) -> String { "\(prefix)\(quote).line.\(code)" }
    public static func name(_ quote: String) -> String { "\(prefix)\(quote).name" }
    public static func date(_ quote: String) -> String { "\(prefix)\(quote).date" }

    /// Splits a field name into its quote number and part; nil for fields that aren't Quote Pilot's.
    public static func parse(_ field: String) -> (quote: String, part: Part)? {
        guard field.hasPrefix(prefix) else { return nil }
        let rest = String(field.dropFirst(prefix.count))
        if let range = rest.range(of: ".line.", options: .backwards) {
            let quote = String(rest[..<range.lowerBound])
            let code = String(rest[range.upperBound...])
            return quote.isEmpty || code.isEmpty ? nil : (quote, .line(code))
        }
        let endings: [(String, Part)] = [(".all", .all), (".name", .name), (".date", .date)]
        for (ending, part) in endings where rest.hasSuffix(ending) {
            let quote = String(rest.dropLast(ending.count))
            return quote.isEmpty ? nil : (quote, part)
        }
        return nil
    }
}
```

- [ ] **Step 7: Write `DocumentContent.swift`**

```swift
import Foundation
import QuotePilotCore

/// Everything a document's pages show, already worded and formatted.
public struct DocumentContent: Equatable {
    public struct Meta: Equatable {
        public var label: String
        public var value: String
    }

    public struct Row: Equatable {
        public var code: String
        public var title: String
        public var detail: String
        public var quantity: String
        public var rate: String
        public var amount: String
    }

    public struct TotalLine: Equatable {
        public var label: String
        public var value: String
        public var strong: Bool
    }

    public struct Section: Equatable {
        public var heading: String
        /// Lines starting with "- " print as dot points.
        public var text: String
    }

    public var title: String
    public var number: String
    public var fromName: String
    public var fromDetails: String
    public var toLabel: String
    public var toName: String
    public var toDetails: String
    public var meta: [Meta]
    public var amountLabel: String
    public var amount: String
    public var amountNote: String
    /// Quotes show each line's ID.
    public var showCodes: Bool
    public var rows: [Row]
    public var totals: [TotalLine]
    public var sections: [Section]
    /// Quotes only: draw the tick-box form for this quote number.
    public var formQuoteNumber: String?
    public var fileName: String
}

extension DocumentContent {
    public static func quote(_ quote: Quote, client: Client?, brand: Brand) -> DocumentContent {
        let currency = brand.currencyCode
        let totals = quote.totals
        var totalLines: [TotalLine] = []
        if quote.taxed {
            totalLines.append(TotalLine(label: "Subtotal", value: totals.subtotal.formatted(currencyCode: currency), strong: false))
            totalLines.append(TotalLine(label: "GST (10%)", value: totals.gst.formatted(currencyCode: currency), strong: false))
        }
        totalLines.append(TotalLine(label: "Total (\(currency))", value: totals.total.formatted(currencyCode: currency), strong: true))

        var meta = [Meta(label: "Quote no.", value: quote.number),
                    Meta(label: "Issued", value: quote.issued.long),
                    Meta(label: "Valid until", value: quote.validUntil.long)]
        if !quote.title.trimmed.isEmpty { meta.append(Meta(label: "Reference", value: quote.title)) }

        var sections: [Section] = []
        if !quote.summary.trimmed.isEmpty { sections.append(Section(heading: "Work summary", text: quote.summary)) }
        sections.append(Section(heading: "Payment plan",
                                text: "\(quote.plan.summary). You're only invoiced for the lines you accept."))
        if !quote.terms.trimmed.isEmpty { sections.append(Section(heading: "Terms", text: quote.terms)) }

        return DocumentContent(
            title: "Quote", number: quote.number,
            fromName: brand.businessName, fromDetails: fromDetails(brand, taxed: quote.taxed),
            toLabel: "Prepared for", toName: client?.name ?? "", toDetails: clientDetails(client),
            meta: meta,
            amountLabel: "Quote total (\(currency))",
            amount: totals.total.formatted(currencyCode: currency),
            amountNote: "Valid until \(quote.validUntil.long)",
            showCodes: true,
            rows: quote.lines.map { row($0, currency) },
            totals: totalLines,
            sections: sections,
            formQuoteNumber: quote.number,
            fileName: fileName(quote.number, client))
    }

    public static func invoice(_ invoice: Invoice, client: Client?, brand: Brand, quoteNumber: String?) -> DocumentContent {
        let currency = brand.currencyCode
        func money(_ amount: Money) -> String { amount.formatted(currencyCode: currency) }
        let lineTotals = invoice.lineTotals

        var totals: [TotalLine] = []
        if invoice.taxed {
            totals.append(TotalLine(label: "Subtotal", value: money(lineTotals.subtotal), strong: false))
            totals.append(TotalLine(label: "GST (10%)", value: money(lineTotals.gst), strong: false))
        }
        switch invoice.kind {
        case .deposit:
            totals.append(TotalLine(label: "Accepted total", value: money(lineTotals.total), strong: false))
            totals.append(TotalLine(label: "Deposit (\(invoice.depositPercent ?? 50)%)", value: money(invoice.amount), strong: true))
        case .final where !invoice.deductions.isEmpty:
            totals.append(TotalLine(label: "Accepted total", value: money(lineTotals.total), strong: false))
            for deduction in invoice.deductions {
                totals.append(TotalLine(label: "\(deduction.label), \(deduction.invoiceNumber)",
                                        value: "−" + money(deduction.amount), strong: false))
            }
            totals.append(TotalLine(label: "Balance (\(currency))", value: money(invoice.amount), strong: true))
        default:
            totals.append(TotalLine(label: "Total (\(currency))", value: money(invoice.amount), strong: true))
        }
        if invoice.paid > .zero {
            totals.append(TotalLine(label: "Paid", value: "−" + money(invoice.paid), strong: false))
            totals.append(TotalLine(label: "Amount due (\(currency))", value: money(invoice.owing), strong: true))
        }

        var meta = [Meta(label: "Invoice no.", value: invoice.number),
                    Meta(label: "Issued", value: invoice.issued.long),
                    Meta(label: "Due", value: invoice.due.long)]
        if let quoteNumber { meta.append(Meta(label: "Quote", value: quoteNumber)) }
        if !invoice.title.trimmed.isEmpty { meta.append(Meta(label: "Reference", value: invoice.title)) }

        var sections: [Section] = []
        if !brand.paymentDetails.trimmed.isEmpty { sections.append(Section(heading: "Payment details", text: brand.paymentDetails)) }
        if !invoice.terms.trimmed.isEmpty { sections.append(Section(heading: "Terms", text: invoice.terms)) }

        let paidUp = invoice.paid > .zero && invoice.owing <= .zero
        return DocumentContent(
            title: invoice.taxed ? "Tax invoice" : "Invoice", number: invoice.number,
            fromName: brand.businessName, fromDetails: fromDetails(brand, taxed: invoice.taxed),
            toLabel: "Billed to", toName: client?.name ?? "", toDetails: clientDetails(client),
            meta: meta,
            amountLabel: paidUp ? "Paid in full" : "Amount due (\(currency))",
            amount: money(paidUp ? invoice.amount : invoice.owing),
            amountNote: paidUp ? "Thank you" : "Due \(invoice.due.long)",
            showCodes: false,
            rows: invoice.lines.map { row($0, currency) },
            totals: totals,
            sections: sections,
            formQuoteNumber: nil,
            fileName: fileName(invoice.number, client))
    }

    public static func receipt(_ invoice: Invoice, client: Client?, brand: Brand) -> DocumentContent {
        let currency = brand.currencyCode
        func money(_ amount: Money) -> String { amount.formatted(currencyCode: currency) }

        var totals = [TotalLine(label: "Invoice total", value: money(invoice.amount), strong: false)]
        for payment in invoice.payments.sorted(by: { $0.date < $1.date }) {
            totals.append(TotalLine(label: "Paid \(payment.date.short), \(payment.method.label.lowercased())",
                                    value: money(payment.amount), strong: false))
        }
        let owing = max(invoice.owing, .zero)
        totals.append(TotalLine(label: owing > .zero ? "Still owing (\(currency))" : "Balance (\(currency))",
                                value: money(owing), strong: true))

        var meta = [Meta(label: "Receipt for", value: invoice.number)]
        if let latest = invoice.payments.map(\.date).max() { meta.append(Meta(label: "Date", value: latest.long)) }
        meta.append(Meta(label: "Invoice issued", value: invoice.issued.long))

        return DocumentContent(
            title: "Receipt", number: invoice.number,
            fromName: brand.businessName, fromDetails: fromDetails(brand, taxed: invoice.taxed),
            toLabel: "Received from", toName: client?.name ?? "", toDetails: clientDetails(client),
            meta: meta,
            amountLabel: "Total paid (\(currency))",
            amount: money(invoice.paid),
            amountNote: owing > .zero ? "\(money(owing)) still owing" : "Paid in full. Thank you.",
            showCodes: false,
            rows: invoice.lines.map { row($0, currency) },
            totals: totals,
            sections: [],
            formQuoteNumber: nil,
            fileName: fileName("Receipt \(invoice.number)", client))
    }

    static func row(_ line: LineItem, _ currency: String) -> Row {
        Row(code: line.code, title: line.title, detail: line.detail,
            quantity: line.unit.describe(line.quantity),
            rate: line.rate.formatted(currencyCode: currency),
            amount: line.amount.formatted(currencyCode: currency))
    }

    static func fromDetails(_ brand: Brand, taxed: Bool) -> String {
        var parts = [brand.details.trimmed].filter { !$0.isEmpty }
        if taxed && !brand.abn.trimmed.isEmpty { parts.append("ABN \(brand.abn.trimmed)") }
        return parts.joined(separator: "\n")
    }

    static func clientDetails(_ client: Client?) -> String {
        guard let client else { return "" }
        return [client.contactName, client.address, client.email]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// "Q-0001 Sample Client Pty Ltd.pdf", with characters Finder dislikes swapped for dashes.
    static func fileName(_ prefix: String, _ client: Client?) -> String {
        let name = [prefix, client?.name.trimmed ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".pdf"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
```

- [ ] **Step 8: Write `DocumentRenderer.swift`**

```swift
import AppKit
import CoreText
import PDFKit
import QuotePilotCore

public enum DocumentRenderer {
    /// Draws a document as PDF data. Quotes also get the tick-box form.
    public static func render(_ content: DocumentContent, style: PDFStyle) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: PageWriter.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "\(content.title) \(content.number)",
            kCGPDFContextCreator: "Quote Pilot",
            kCGPDFContextAuthor: content.fromName,
            kCGPDFContextKeywords: ["quotepilot", content.number],
        ]
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)!
        let writer = PageWriter(context: context)
        let layout = Layout(content: content, style: style, writer: writer)
        layout.drawAll()
        writer.finish()
        guard content.formQuoteNumber != nil else { return data as Data }
        return addForm(layout.fields, to: data as Data, content: content)
    }

    /// Adds the form widgets PDFKit-side, where the drawing recorded them.
    static func addForm(_ fields: [PlacedField], to data: Data, content: DocumentContent) -> Data {
        guard let document = PDFDocument(data: data) else { return data }
        let ink = NSColor(cgColor: PDFStyle.ink) ?? .black
        for field in fields {
            guard let page = document.page(at: field.page) else { continue }
            let widget = PDFAnnotation(bounds: field.rect, forType: .widget, withProperties: nil)
            widget.fieldName = field.name
            switch field.kind {
            case .checkbox:
                widget.widgetFieldType = .button
                widget.widgetControlType = .checkBoxControl
                widget.buttonWidgetState = .offState
                widget.backgroundColor = .white
                let border = PDFBorder()
                border.lineWidth = 1
                widget.border = border
                widget.color = ink
            case .text:
                widget.widgetFieldType = .text
                widget.backgroundColor = NSColor(white: 0.96, alpha: 1)
                widget.font = NSFont.systemFont(ofSize: 10)
                widget.fontColor = ink
            }
            page.addAnnotation(widget)
        }
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "\(content.title) \(content.number)",
            PDFDocumentAttribute.creatorAttribute: "Quote Pilot",
            PDFDocumentAttribute.authorAttribute: content.fromName,
            PDFDocumentAttribute.keywordsAttribute: ["quotepilot", content.number],
        ]
        return document.dataRepresentation() ?? data
    }
}

/// A form field the layout placed; PDFKit adds the real widget afterwards.
struct PlacedField: Equatable {
    enum Kind { case checkbox, text }
    var name: String
    var kind: Kind
    var page: Int
    var rect: CGRect
}

/// Lays out one document: header, parties, amount, line table, totals, form, sections.
final class Layout {
    let content: DocumentContent
    let style: PDFStyle
    let writer: PageWriter
    private(set) var fields: [PlacedField] = []
    private var inTable = false

    // Line-table columns, measured from the left of the page.
    private let tickX: CGFloat
    private let codeX: CGFloat
    private let descX: CGFloat
    private let descWidth: CGFloat
    private let qtyRight: CGFloat
    private let rateRight: CGFloat
    private let amountRight: CGFloat

    init(content: DocumentContent, style: PDFStyle, writer: PageWriter) {
        self.content = content
        self.style = style
        self.writer = writer
        tickX = writer.left
        codeX = writer.left + (content.formQuoteNumber != nil ? 22 : 0)
        descX = codeX + (content.showCodes ? 28 : 0)
        amountRight = writer.right
        rateRight = amountRight - 78
        qtyRight = rateRight - 72
        descWidth = qtyRight - 58 - descX
    }

    func drawAll() {
        writer.onNewPage = { [unowned self] _ in
            self.drawContinuationHeader()
            if self.inTable { self.drawTableHeader() }
        }
        writer.newPage()
        drawHeader()
        drawParties()
        drawAmount()
        drawAcceptAll()
        drawTable()
        drawTotals()
        drawAcceptedBy()
        drawSections()
    }

    private func label(_ text: String) -> NSAttributedString {
        PageWriter.text(text, style.body(7.5, weight: .medium), PDFStyle.muted)
    }

    private func addField(_ name: String, _ kind: PlacedField.Kind, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) {
        fields.append(PlacedField(name: name, kind: kind, page: writer.pageIndex,
                                  rect: writer.pdfRect(x: x, top: top, width: width, height: height)))
    }

    private func drawHeader() {
        let top = writer.y
        var leftY = top
        if let logo = style.logo {
            logo.draw(in: writer.pdfRect(x: writer.left, top: leftY, width: 180, height: 44), context: writer.context)
            leftY += 44 + 12
        }
        if !content.fromName.isEmpty {
            leftY += writer.draw(PageWriter.text(content.fromName, style.body(13, weight: .semibold), PDFStyle.ink),
                                 x: writer.left, top: leftY, width: 300) + 3
        }
        if !content.fromDetails.isEmpty {
            leftY += writer.draw(PageWriter.text(content.fromDetails, style.body(8.5), PDFStyle.muted),
                                 x: writer.left, top: leftY, width: 300)
        }
        let titleFont = style.heading(26)
        writer.drawRight(PageWriter.text(content.title, titleFont, PDFStyle.ink), right: writer.right, top: top)
        writer.y = max(leftY, top + PageWriter.lineHeight(titleFont)) + 28
    }

    private func drawParties() {
        let top = writer.y
        var leftY = top
        leftY += writer.draw(label(content.toLabel), x: writer.left, top: leftY, width: 240) + 2
        if !content.toName.isEmpty {
            leftY += writer.draw(PageWriter.text(content.toName, style.body(10.5, weight: .semibold), PDFStyle.ink),
                                 x: writer.left, top: leftY, width: 240) + 1
        }
        if !content.toDetails.isEmpty {
            leftY += writer.draw(PageWriter.text(content.toDetails, style.body(8.5), PDFStyle.muted),
                                 x: writer.left, top: leftY, width: 240)
        }
        let metaX = writer.right - 230
        var rightY = top
        for item in content.meta {
            writer.draw(label(item.label), x: metaX, top: rightY + 1.5, width: 74)
            let used = writer.draw(PageWriter.text(item.value, style.body(9.5), PDFStyle.ink), x: metaX + 76, top: rightY, width: 154)
            rightY += max(used, 12) + 3
        }
        writer.y = max(leftY, rightY) + 22
    }

    private func drawAmount() {
        writer.rule(top: writer.y, x: writer.left, width: writer.width, color: PDFStyle.rule)
        writer.y += 14
        writer.y += writer.draw(label(content.amountLabel), x: writer.left, top: writer.y, width: writer.width) + 2
        let amountFont = style.heading(30)
        let amount = PageWriter.text(content.amount, amountFont, style.accent)
        writer.draw(amount, x: writer.left, top: writer.y, width: writer.width)
        let noteFont = style.body(9.5)
        let noteX = writer.left + PageWriter.width(of: amount) + 14
        writer.draw(PageWriter.text(content.amountNote, noteFont, PDFStyle.muted), x: noteX,
                    top: writer.y + CTFontGetAscent(amountFont) - CTFontGetAscent(noteFont),
                    width: writer.right - noteX)
        writer.y += PageWriter.lineHeight(amountFont) + 20
    }

    private func drawAcceptAll() {
        guard let number = content.formQuoteNumber else { return }
        writer.ensureSpace(60)
        addField(QuoteFormFields.acceptAll(number), .checkbox, x: writer.left, top: writer.y, width: 12, height: 12)
        writer.draw(PageWriter.text("Accept all", style.body(10, weight: .semibold), PDFStyle.ink),
                    x: writer.left + 20, top: writer.y - 0.5, width: 200)
        writer.y += 16
        let instruction = "Tick the lines you'd like to go ahead with, or Accept all. Add your name and the date at the bottom, then save this PDF and send it back."
        writer.y += writer.draw(PageWriter.text(instruction, style.body(8.5), PDFStyle.muted),
                                x: writer.left + 20, top: writer.y, width: writer.width - 20) + 14
    }

    private func drawTableHeader() {
        let top = writer.y
        if content.showCodes { writer.draw(label("ID"), x: codeX, top: top, width: 26) }
        writer.draw(label("Description"), x: descX, top: top, width: descWidth)
        writer.drawRight(label("Qty"), right: qtyRight, top: top)
        writer.drawRight(label("Rate"), right: rateRight, top: top)
        writer.drawRight(label("Amount"), right: amountRight, top: top)
        writer.y += 13
        writer.rule(top: writer.y, x: writer.left, width: writer.width, color: PDFStyle.ink, thickness: 1)
        writer.y += 4
    }

    private func drawTable() {
        writer.ensureSpace(60)
        drawTableHeader()
        inTable = true
        for row in content.rows { drawRow(row) }
        inTable = false
    }

    private func drawRow(_ row: DocumentContent.Row) {
        let title = PageWriter.text(row.title, style.body(9.5, weight: .medium), PDFStyle.ink)
        let detail = PageWriter.text(row.detail, style.body(8.5), PDFStyle.muted)
        let titleHeight = PageWriter.height(of: title, width: descWidth)
        let detailHeight = row.detail.isEmpty ? 0 : PageWriter.height(of: detail, width: descWidth) + 2
        let rowHeight = max(titleHeight + detailHeight, 14) + 14
        writer.ensureSpace(rowHeight)

        let top = writer.y + 7
        if let number = content.formQuoteNumber {
            addField(QuoteFormFields.line(number, row.code), .checkbox, x: tickX, top: top, width: 12, height: 12)
        }
        let numberFont = style.body(9.5)
        if content.showCodes {
            writer.draw(PageWriter.text(row.code, numberFont, PDFStyle.muted), x: codeX, top: top, width: 26)
        }
        writer.draw(title, x: descX, top: top, width: descWidth)
        if !row.detail.isEmpty {
            writer.draw(detail, x: descX, top: top + titleHeight + 2, width: descWidth)
        }
        writer.drawRight(PageWriter.text(row.quantity, numberFont, PDFStyle.ink), right: qtyRight, top: top)
        writer.drawRight(PageWriter.text(row.rate, numberFont, PDFStyle.ink), right: rateRight, top: top)
        writer.drawRight(PageWriter.text(row.amount, style.body(9.5, weight: .medium), PDFStyle.ink), right: amountRight, top: top)
        writer.y += rowHeight
        writer.rule(top: writer.y - 1, x: writer.left, width: writer.width, color: PDFStyle.rule)
    }

    private func drawTotals() {
        let needed = content.totals.reduce(CGFloat(26)) { $0 + ($1.strong ? 23 : 15) }
        writer.ensureSpace(needed)
        writer.y += 10
        let x = writer.right - 250
        for total in content.totals {
            let font = total.strong ? style.body(10.5, weight: .semibold) : style.body(9.5)
            if total.strong {
                writer.rule(top: writer.y, x: x, width: 250, color: PDFStyle.ink, thickness: 1)
                writer.y += 5
            }
            writer.draw(PageWriter.text(total.label, font, PDFStyle.ink), x: x, top: writer.y, width: 170)
            writer.drawRight(PageWriter.text(total.value, font, PDFStyle.ink), right: writer.right, top: writer.y)
            writer.y += total.strong ? 18 : 15
        }
        writer.y += 16
    }

    private func drawAcceptedBy() {
        guard let number = content.formQuoteNumber else { return }
        writer.ensureSpace(70)
        writer.y += writer.draw(PageWriter.text("Accepted by", style.body(10, weight: .semibold), PDFStyle.ink),
                                x: writer.left, top: writer.y, width: 200) + 8
        let top = writer.y
        addField(QuoteFormFields.name(number), .text, x: writer.left, top: top, width: 240, height: 18)
        addField(QuoteFormFields.date(number), .text, x: writer.left + 260, top: top, width: 120, height: 18)
        writer.rule(top: top + 18, x: writer.left, width: 240, color: PDFStyle.muted)
        writer.rule(top: top + 18, x: writer.left + 260, width: 120, color: PDFStyle.muted)
        writer.draw(label("Name"), x: writer.left, top: top + 21, width: 100)
        writer.draw(label("Date"), x: writer.left + 260, top: top + 21, width: 100)
        writer.y = top + 43
    }

    private func drawSections() {
        for section in content.sections {
            writer.ensureSpace(40)
            writer.y += 6
            writer.y += writer.draw(PageWriter.text(section.heading, style.body(10, weight: .semibold), PDFStyle.ink),
                                    x: writer.left, top: writer.y, width: writer.width) + 4
            for paragraph in section.text.components(separatedBy: "\n") {
                let line = paragraph.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    writer.y += 5
                    continue
                }
                let isBullet = line.hasPrefix("- ") || line.hasPrefix("• ")
                let text = PageWriter.text(isBullet ? String(line.dropFirst(2)) : line, style.body(9), PDFStyle.ink)
                let indent: CGFloat = isBullet ? 12 : 0
                let height = PageWriter.height(of: text, width: writer.width - indent)
                writer.ensureSpace(height)
                if isBullet {
                    writer.draw(PageWriter.text("•", style.body(9), style.accent), x: writer.left + 2, top: writer.y, width: 10)
                }
                writer.draw(text, x: writer.left + indent, top: writer.y, width: writer.width - indent)
                writer.y += height + 2
            }
            writer.y += 10
        }
    }

    private func drawContinuationHeader() {
        writer.draw(PageWriter.text("\(content.title) \(content.number), continued", style.body(8.5), PDFStyle.muted),
                    x: writer.left, top: writer.y, width: writer.width)
        writer.y += 22
    }
}
```

- [ ] **Step 9: Run the tests to watch them pass**

Run: `swift test`
Expected: all tests pass, core and PDF.

- [ ] **Step 10: Look at the result**

Write a sample quote PDF from a scratch test or the `qp` tool in Task 10, render page 1 to PNG
with PDFKit, and check it against the spec's look: title top right, amount as the one big
accent-coloured number, tick boxes beside each line, "Accept all" above the table, "Accepted by"
fields below the totals. Fix spacing or overlaps before committing.

- [ ] **Step 11: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "Draw quotes, invoices and receipts as PDFs, with the quote tick-box form

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Reading a returned quote

**Files:**
- Create: `Sources/QuotePilotPDF/ReturnedQuoteReader.swift`
- Test: `Tests/QuotePilotPDFTests/FormRoundTripTests.swift`

**Interfaces:**
- Consumes: `QuoteFormFields`, `DocumentRenderer`, `PageWriter` (Task 8); `ReturnedForm`,
  `Quote.proposal(from:today:)` (Task 3); `Sample` (Task 8 tests).
- Produces: `ReturnedQuoteReader.read(_ data: Data) throws -> ReturnedForm`,
  `ReturnedQuoteReader.read(contentsOf: URL) throws -> ReturnedForm`;
  `ReturnedQuoteError { unreadable, noForm, severalQuotes([String]) }` with `message`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotPDFTests/FormRoundTripTests.swift`:

```swift
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

@Suite struct FormRoundTripTests {
    func quotePDF(extraLines: Int = 0) -> Data {
        DocumentRenderer.render(.quote(Sample.quote(extraLines: extraLines), client: Sample.client, brand: Sample.brand),
                                style: PDFStyle())
    }

    /// Fills the form the way a client's PDF app would, then saves.
    func fill(_ data: Data, ticking codes: [String] = [], acceptAll: Bool = false,
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

    @Test func anUntouchedQuoteReadsAsNothingTicked() throws {
        let form = try ReturnedQuoteReader.read(quotePDF())
        #expect(form == ReturnedForm(quoteNumber: "Q-0001", acceptAll: false, ticked: [], unticked: ["01", "02", "03"]))
    }

    @Test func ticksNameAndDateSurviveTheRoundTrip() throws {
        let form = try ReturnedQuoteReader.read(fill(quotePDF(), ticking: ["01", "03"], name: "Sam Example", date: "16/10/2026"))
        #expect(form.ticked == ["01", "03"])
        #expect(form.unticked == ["02"])
        #expect(form.clientName == "Sam Example")
        #expect(form.clientDate == "16/10/2026")
        let proposal = Sample.quote().proposal(from: form, today: Sample.today)
        #expect(proposal.accepted == ["01", "03"])
        #expect(proposal.declined == ["02"])
        #expect(proposal.problems == [])
    }

    @Test func acceptAllOnItsOwnAcceptsEverything() throws {
        let form = try ReturnedQuoteReader.read(fill(quotePDF(), acceptAll: true))
        #expect(form.acceptAll)
        #expect(Sample.quote().proposal(from: form, today: Sample.today).accepted == ["01", "02", "03"])
    }

    @Test func aFlattenedPDFHasNoForm() {
        // Drawing the page into a new PDF drops the form, the way printing to PDF does.
        let document = PDFDocument(data: quotePDF())!
        let flat = NSMutableData()
        var box = CGRect(origin: .zero, size: PageWriter.pageSize)
        let context = CGContext(consumer: CGDataConsumer(data: flat as CFMutableData)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        document.page(at: 0)!.draw(with: .mediaBox, to: context)
        context.endPDFPage()
        context.closePDF()
        #expect(throws: ReturnedQuoteError.noForm) { try ReturnedQuoteReader.read(flat as Data) }
    }

    @Test func somethingThatIsntAPDFIsUnreadable() {
        #expect(throws: ReturnedQuoteError.unreadable) { try ReturnedQuoteReader.read(Data("hello".utf8)) }
    }

    @Test func fieldNamesRoundTrip() {
        #expect(QuoteFormFields.line("Q-0007", "03") == "quotepilot.Q-0007.line.03")
        #expect(QuoteFormFields.parse("quotepilot.Q-0007.line.03")! == ("Q-0007", .line("03")))
        #expect(QuoteFormFields.parse("quotepilot.Q-0007.all")! == ("Q-0007", .all))
        #expect(QuoteFormFields.parse("quotepilot.Q-0007.name")! == ("Q-0007", .name))
        #expect(QuoteFormFields.parse("Check Box 1") == nil)
    }

    @Test func longQuoteKeepsEachTickBoxWithItsLine() throws {
        let document = PDFDocument(data: quotePDF(extraLines: 40))!
        #expect(document.pageCount >= 3)
        var pageOfLine: [String: Int] = [:]
        for index in 0..<document.pageCount {
            let page = document.page(at: index)!
            for widget in page.annotations {
                guard case .line(let code)? = widget.fieldName.flatMap({ QuoteFormFields.parse($0) })?.part else { continue }
                #expect(pageOfLine[code] == nil, "line \(code) has two tick boxes")
                pageOfLine[code] = index
                #expect(page.bounds(for: .mediaBox).contains(widget.bounds))
            }
        }
        let quote = Sample.quote(extraLines: 40)
        #expect(pageOfLine.count == quote.lines.count)
        for line in quote.lines {
            let page = try #require(pageOfLine[line.code])
            #expect(document.page(at: page)!.string?.contains(line.title) == true,
                    "\(line.title) isn't on page \(page + 1) with its tick box")
        }
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter FormRoundTripTests`
Expected: build failure, `cannot find 'ReturnedQuoteReader' in scope`.

- [ ] **Step 3: Write `ReturnedQuoteReader.swift`**

```swift
import Foundation
import PDFKit
import QuotePilotCore

public enum ReturnedQuoteError: Error, Equatable {
    case unreadable
    /// No Quote Pilot form fields: the client's app flattened the form, or it's a different PDF.
    case noForm
    case severalQuotes([String])

    public var message: String {
        switch self {
        case .unreadable:
            return "That file isn't a PDF Quote Pilot can open."
        case .noForm:
            return "This PDF has no tick boxes left. The client's app may have flattened it (printing to PDF does this). Tick the lines by hand instead."
        case .severalQuotes(let numbers):
            return "This PDF has tick boxes from more than one quote (\(numbers.joined(separator: ", "))). Tick the lines by hand instead."
        }
    }
}

/// Reads ticks, name and date out of a quote PDF the client sent back.
public enum ReturnedQuoteReader {
    public static func read(contentsOf url: URL) throws -> ReturnedForm {
        guard let data = try? Data(contentsOf: url) else { throw ReturnedQuoteError.unreadable }
        return try read(data)
    }

    public static func read(_ data: Data) throws -> ReturnedForm {
        guard let document = PDFDocument(data: data) else { throw ReturnedQuoteError.unreadable }
        var quotes = Set<String>()
        var acceptAll = false
        var ticked: [String] = []
        var unticked: [String] = []
        var name = ""
        var date = ""

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for widget in page.annotations where widget.type == "Widget" {
                guard let field = widget.fieldName, let parsed = QuoteFormFields.parse(field) else { continue }
                quotes.insert(parsed.quote)
                let isOn = widget.buttonWidgetState == .onState
                switch parsed.part {
                case .all:
                    acceptAll = acceptAll || isOn
                case .line(let code):
                    if isOn { ticked.append(code) } else { unticked.append(code) }
                case .name:
                    name = (widget.widgetStringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                case .date:
                    date = (widget.widgetStringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        guard let quote = quotes.first else { throw ReturnedQuoteError.noForm }
        guard quotes.count == 1 else { throw ReturnedQuoteError.severalQuotes(quotes.sorted()) }
        return ReturnedForm(quoteNumber: quote, acceptAll: acceptAll, ticked: ticked.sorted(),
                            unticked: unticked.sorted(), clientName: name, clientDate: date)
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Read ticks, name and date from a returned quote PDF

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The `qp` tool and the real-world Preview check

**Files:**
- Modify: `Package.swift` (add the `qp` executable)
- Create: `Sources/qp/main.swift`

**Interfaces:**
- Consumes: everything public in `QuotePilotCore` and `QuotePilotPDF`.
- Produces: `swift run qp samples <folder>` (writes a sample quote, deposit invoice, final invoice
  and receipt) and `swift run qp read <pdf>` (prints what a returned quote says, and what Quote
  Pilot would record against the sample quote).

- [ ] **Step 1: Add the executable to `Package.swift`**

Add to `products`:

```swift
        .executable(name: "qp", targets: ["qp"]),
```

Add to `targets`:

```swift
        .executableTarget(name: "qp", dependencies: ["QuotePilotCore", "QuotePilotPDF"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
```

- [ ] **Step 2: Write `Sources/qp/main.swift`**

```swift
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
```

- [ ] **Step 3: Build and write the samples**

Run: `swift build && swift run qp samples build/samples`
Expected: four paths printed:
- `Q-0001 Sample Client Pty Ltd.pdf`
- `INV-0001 Sample Client Pty Ltd.pdf`
- `Receipt INV-0001 Sample Client Pty Ltd.pdf`
- `INV-0002 Sample Client Pty Ltd.pdf`

`build/` is git-ignored.

- [ ] **Step 4: Check that an untouched quote reads back**

Run: `swift run qp read "build/samples/Q-0001 Sample Client Pty Ltd.pdf"`
Expected:
- `Accept all:  not ticked`, `Ticked:      none`, `Not ticked:  01, 02, 03`
- `Check:` line: "Nothing is ticked. …"

- [ ] **Step 5: Look at all four PDFs**

Render page 1 of each to PNG with a small PDFKit script in the scratchpad, and send them to the user.
Check the layout against the spec (section 7). Fix spacing or overlaps in `DocumentRenderer.swift`, then
run `swift test` again.

- [ ] **Step 6: The real-world check (needs the user, about two minutes)**

Ask the user to:
1. Open `build/samples/Q-0001 Sample Client Pty Ltd.pdf` in Preview.
2. Tick lines 01 and 03, type a name and a date.
3. Save (⌘S) and close it.

Then run: `swift run qp read "build/samples/Q-0001 Sample Client Pty Ltd.pdf"`
Expected:
- `Ticked:      01, 03` and the name and date they typed
- `Would record: accept 01, 03; decline 02`

If Preview didn't keep the ticks, stop and report exactly what came back. The spec's fallback
(hand-ticking) still works, but the user decides how to proceed.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources
git commit -m "Add the qp tool for sample PDFs and reading returned quotes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: README, licence and the public GitHub repo

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: the finished package (Tasks 1–10).
- Produces: the public repo `https://github.com/jimhoggey/QuotePilot-App` with `main` pushed.

- [ ] **Step 1: Write `README.md`**

````markdown
# Quote Pilot

A simple Mac app for the paperwork side of a one-person business: send a quote, let the client tick
the lines they want right on the PDF, invoice for what they accepted, and see at a glance what's been
paid and what's still owed.

**Status:** in progress. The core rules and the PDFs are built and tested. The app's screens come next.

## How it works

1. **Quote.** Every line gets an ID and a tick box, with an "Accept all" box at the top. The client
   ticks, adds their name and the date, saves the PDF and sends it back.
2. **Acceptance.** Drop the returned PDF into Quote Pilot and it reads the ticks. If the client's PDF
   app couldn't fill the form, tick the lines yourself.
3. **Invoices.** Choose a payment plan per quote: **50/50** (a deposit invoice when it's accepted, the
   balance when the job's done) or **full amount**. Only the accepted lines are billed.
4. **Payments.** Record each payment. The dashboard shows what's waiting to be paid, what's overdue, and
   what came in this month and this financial year (1 July to 30 June).
5. **Mail.** Quote Pilot opens a Mail draft with the PDF attached. You always press Send yourself.

Everything stays on your Mac, in `~/Library/Application Support/Quote Pilot`, with a daily backup.

## Building

Needs macOS 14 or later and Apple's Command Line Tools (Xcode isn't required).

```bash
swift build
swift test
swift run qp samples build/samples     # sample quote, invoices and receipt
swift run qp read "build/samples/Q-0001 Sample Client Pty Ltd.pdf"
```

## Licence

MIT. See `LICENSE`.
````

- [ ] **Step 2: Write `LICENSE`**

```
MIT License

Copyright (c) 2026 Fynn Projects

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Check nothing private is tracked**

Run: `git ls-files && git ls-files -z | xargs -0 grep -l -i -E "h[a]ppy|pl[u]mb|x[e]ro|servicem[a]te" ; echo "exit $?"`
(The brackets stop the pattern matching itself in this plan.)
Expected: the file list has no `CLAUDE.md`, `Invoice Generator.html`, PDFs or backups, and the grep
prints no file names (`exit 1` means nothing matched). Stop and fix anything that matches.

- [ ] **Step 4: Commit**

```bash
git add README.md LICENSE
git commit -m "Add the README and MIT licence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Create the public repo and push**

Run: `gh repo create jimhoggey/QuotePilot-App --public --source . --remote origin --description "A simple Mac app for quotes clients tick on the PDF, invoices, payments and what's still owed." --push`
Expected: `https://github.com/jimhoggey/QuotePilot-App` printed, and `main` pushed.

Then run: `gh repo view jimhoggey/QuotePilot-App --json visibility,url`
Expected: `"visibility":"PUBLIC"`.

---

## After plan 1

Plan 2 (the app) is written once this plan is done and the Preview check has passed, so it builds on
what the PDFs really do. It covers spec sections 6, 8 and 10's app side:
- the SwiftUI window and sidebar
- Brand (logo, font, colour, details, email wording)
- Clients
- the quote and invoice editors with live PDF preview
- drag-and-drop of returned PDFs and the acceptance review sheet
- Mail drafts via `NSSharingService` with the "Did you send it?" step
- payments, receipts and void
- the dashboard and tax-time export
- Activity
- import from Invoice Generator and backup/restore
- `build.sh` for `Quote Pilot.app`

## Self-review (done while writing)

- **Spec coverage:**
  - Sections 1–5 (data, money rules, statuses, dashboard figures) → Tasks 1–5.
  - Section 7 (PDFs, form names, reading back, invoices, receipts) → Tasks 8–9.
  - Section 9 (import) → Task 7. Section 10 (saving, backups, unreadable file, format version) →
    Task 6. Section 11 (testing, the real-world check) → every task, plus Task 10.
  - Section 12 (repo) → Task 11.
  - Sections 6 and 8 (screens and Mail) are deliberately plan 2.
- **Placeholders:** none. Every code step has the code.
- **Types:** names used across tasks match:
  - `Money`, `Day`, `LineItem.code`, `Quote.lastLineNumber`, `addLine`
  - `ReturnedForm`, `AcceptanceProposal`, `draftNextInvoice(forQuote:on:)`, `completeJob(quote:on:)`
  - `DocumentContent.quote/invoice/receipt`, `DocumentRenderer.render(_:style:)`,
    `QuoteFormFields.parse`, `ReturnedQuoteReader.read`
- **Review Focus:** each of the five has a named test in its owning task.

