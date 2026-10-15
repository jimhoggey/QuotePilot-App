# Quote Pilot, plan 2a: the Windows 95 app (shell, dashboard, clients, brand, quotes)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put a real, double-clickable `Quote Pilot.app` on top of plan 1's engine. It has a Windows 95
look and covers:
- the main window: navy title bar, toolbar, Explorer-style tree, status bar, message boxes and menus
  with shortcuts
- safe loading and saving, including the unreadable-library screen
- Dashboard, Clients and Brand
- the quote list and quote editor, with a live PDF preview

Mail, reading returned quotes, invoicing actions, payments, import and backup screens are plan 2b. So
are the shortcuts for them (⇧⌘N new invoice, ⌘S send, ⌘O read returned quote) and ⌘F filter. In
2a, the toolbar shows those buttons switched off, with a tooltip saying they arrive in the next build.

**Architecture:**
- **`QuotePilotUI`** (new library, Swift 5 mode) holds:
  - the Windows 95 kit: theme, bevels, controls, pixel icons and the details list;
  - `AppModel`, an `@Observable` on the main actor that is the only path from the screens to the
    library. Every change is applied to a copy, saved, and only then kept;
  - every screen.
- **`QuotePilotApp`** (new executable) is the thin `@main` app.
- **`build.sh`** wraps the release binary into `build/Quote Pilot.app`.
- **Core:** one task first makes the library file tolerant of future fields and gives every error a
  plain message.

**Tech Stack:** Swift 6.4 (Command Line Tools 27.0), SwiftUI (macOS 14+), Observation, AppKit (PDFView,
NSHostingView for snapshots), PDFKit, Swift Testing. No third-party packages.

**Spec:** `docs/superpowers/specs/2026-10-15-quote-pilot-design.md` (sections 6 and 10; section 15 is
the visual design).

## Global Constraints

- **Platform and packages:** macOS 14 and later. `QuotePilotUI`, `QuotePilotApp` and
  `QuotePilotUITests` use `.swiftLanguageMode(.v5)`. No third-party dependencies.
- **Palette:** exactly the spec §15 hex values, defined once in `Win95` (`Win95Theme.swift`), and
  never as raw hex in views:
  - face `#C0C0C0`, highlight `#FFFFFF`, light `#DFDFDF`, shadow `#808080`, dark `#000000`
  - title bar navy `#000080`, inactive title bar `#808080`, desktop teal `#008080`
  - selection navy `#000080` with white text, fields white, text black, tooltip `#FFFFE1`
  - overdue `#C00000`, paid `#007000`, warning yellow `#FFFF00`
- **Type:** the system font at 13 pt, semibold labels and bold titles, money in monospaced digits,
  and headline readouts at 28 pt monospaced. No pixel or bitmap font for text.
- **Appearance:** light only (`.preferredColorScheme(.light)`). No animation.
- **Meaning is never colour alone:** every status shows an icon plus a word.
- **Contrast:** at least 4.5:1 for all text, or 3:1 for 14 pt bold and larger (the window title on
  the grey inactive bar).
- **Icons:** pixel icons only (16×16 grids in `PixelIcon.swift`), never emoji, never SF Symbols in the
  chrome.
- **Keyboard and accessibility:**
  - Shortcuts: ⌘N new quote, ⌘P print or save PDF, ⌘1–⌘6 switch sections.
  - Every control is reachable by keyboard. Focused text fields and lists show the dotted focus
    rectangle.
  - Icon-only buttons have accessibility labels.
- **Changes and errors:**
  - Every library change goes through `AppModel.change(_:_:)`, which applies it to a copy, saves, and
    only then keeps it.
  - Every error is shown in a Windows 95 message box with the error's plain message. User input never
    crashes the app.
- **Data:**
  - Real data lives only in `~/Library/Application Support/Quote Pilot`. Tests use temporary folders
    and never touch the real folder.
  - All sample and test data is made up ("Sample Studio", "Sample Client Pty Ltd"); the repo is
    public.
- **Toolchain:** Command Line Tools 27.0, no Xcode. Test targets carry `testSettings` (the
  `-plugin-path …/host/plugins/testing` workaround).
- **Files and commits:**
  - Create and change files with Edit/Write, never shell redirects or `sed -i`.
  - Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A change the core refuses** (for example editing a rate after a deposit invoice exists): a
   message box explains it, and the library, the file on disk and the editor all keep the stored
   value. Task 5, `aRefusedChangeKeepsTheStoredValue`; Task 9, `theEditorRevertsARefusedEdit`.
2. **Half-typed or nonsense numbers** ("", "$", "abc", "1.2.3", a quantity of "1.") in amount,
   quantity and day fields are never committed and never crash. A field commits only on Return or
   leaving it, and otherwise beeps and puts the stored value back. Task 9, `FieldParserTests`.
3. **An unreadable library at launch** is never saved over. The app shows the unreadable screen and
   offers the latest backup. Task 5, `anUnreadableLibraryIsNeverSaved` and
   `restoringTheLatestBackupRecovers`.
4. **Long client names and titles** truncate with an ellipsis in lists and never push columns out of
   line. Task 4, `longTextTruncatesInsteadOfWidening`.
5. **Importing a file that isn't an image as the logo** (or isn't a font as the heading font) shows a
   message and leaves the brand unchanged. Task 5, `aNonImageLogoIsRefused`.

---

## File structure

```
Package.swift                         + QuotePilotUI, QuotePilotApp, QuotePilotUITests
Sources/QuotePilotCore/
  Models.swift, LineItem.swift, Library.swift   + tolerant decoding (Task 1)
  Messages.swift                      plain messages for LibraryError, StoreError, LegacyImportError
  Day.swift                           + date(in:) for date pickers
  SampleLibrary.swift                 a made-up business for trying the app (Task 7)
Sources/qp/main.swift                 + `qp demo <folder>` (Task 7)
Sources/QuotePilotUI/
  Win95/Win95Theme.swift              palette, fonts, Color(hex:)
  Win95/Bevel.swift                   bevel drawing, raised/sunken modifiers, focus rectangle
  Win95/Win95Controls.swift           button, toolbar button, text field, text editor, group box,
                                      checkbox, radio group, segmented progress, pixel glyphs
  Win95/PixelIcon.swift               16×16 icon grids, their view, status labels
  Win95/DetailsList.swift             Windows 95 "Details view" list: columns, sorting, selection, keys
  Win95/Win95Chrome.swift             title bar, window dragging, status panel, etched line, note
                                      banner, message box, property tabs
  App/AppSection.swift                the six sections
  App/AppModel.swift                  state, loading, the change path, actions, PDF rendering
  App/MessageBox.swift                message box model
  App/RootView.swift                  window layout, toolbar, tree, status bar, unreadable screen
  App/Commands.swift                  menus and shortcuts
  Screens/DashboardView.swift         readouts, the three lists, status cells
  Screens/ClientsView.swift
  Screens/BrandView.swift
  Screens/PDFPreview.swift            save-panel document, PDFView wrapper, live preview
  Screens/FieldParser.swift           reading typed amounts, quantities, days and colours
  Screens/QuotesView.swift            quote list
  Screens/QuoteEditorView.swift       quote editor, lines editor, commit-on-Return fields, pickers
  Screens/InvoicesView.swift          read-only invoice list with preview (editor comes in 2b)
  Screens/ActivityView.swift
Sources/QuotePilotApp/QuotePilotApp.swift   @main
Resources/Info.plist
build.sh
Tests/QuotePilotCoreTests/ToleranceAndMessagesTests.swift, SampleLibraryTests.swift
Tests/QuotePilotUITests/              Snapshot helper, UIFixture, and tests for the kit, icons, the
                                      details list, AppModel, the shell and each screen
```

---

### Task 1: Core: a library file that tolerates new fields, plain error messages, Day ↔ Date

The app starts saving real data in this plan. From now on, a field added in a later version must
not make older library files unreadable, and every error the screens show needs a plain sentence.

**Files:**
- Modify: `Sources/QuotePilotCore/Models.swift` (tolerant `init(from:)` for Brand, Client, Quote,
  Invoice)
- Modify: `Sources/QuotePilotCore/LineItem.swift` (tolerant `init(from:)` for LineItem)
- Modify: `Sources/QuotePilotCore/Library.swift` (tolerant `init(from:)` for Library, plus the
  decoding helper)
- Create: `Sources/QuotePilotCore/Messages.swift`
- Modify: `Sources/QuotePilotCore/Day.swift` (add `date(in:)`)
- Test: `Tests/QuotePilotCoreTests/ToleranceAndMessagesTests.swift`

**Interfaces:**
- Consumes: the existing core types. Encoding stays exactly as synthesized; only decoding becomes
  tolerant.
- Produces:
  - **Tolerant decoding:** missing non-essential keys fall back to defaults. Essential keys still
    throw when missing: Quote `id`, `number`, `issued`, `validUntil`; Invoice `id`, `number`, `kind`,
    `issued`, `due`; Client `id`, `name`; LineItem `id`.
  - **Messages:** `LibraryError.message`, `LibraryStore.StoreError.message`,
    `LegacyImportError.message`. All three conform to `LocalizedError`, so
    `error.localizedDescription` is the plain message.
  - **Dates:** `Day.date(in: TimeZone = .current) -> Date` (noon that day, for date pickers).

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotCoreTests/ToleranceAndMessagesTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct ToleranceAndMessagesTests {
    @Test func aBrandMissingNewerFieldsGetsDefaults() throws {
        let brand = try Library.makeDecoder().decode(Brand.self, from: Data(#"{"businessName":"Sample Studio"}"#.utf8))
        #expect(brand.businessName == "Sample Studio")
        #expect(brand.paymentDueDays == 14)
        #expect(brand.quoteValidDays == 30)
        #expect(brand.emails == .standard)
        #expect(brand.gstRegistered == false)
    }

    @Test func aQuoteMissingOptionalFieldsGetsDefaults() throws {
        let json = #"""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","number":"Q-0009","issued":"2026-10-15","validUntil":"2026-11-14",
         "lines":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","code":"01","title":"Build","rate":100000}]}
        """#
        let quote = try Library.makeDecoder().decode(Quote.self, from: Data(json.utf8))
        #expect(quote.stage == .draft)
        #expect(quote.plan == .fiftyFifty)
        #expect(quote.summary == "")
        #expect(quote.lastLineNumber == 1)
        #expect(quote.lines[0].quantity == 1)
        #expect(quote.lines[0].unit == .units)
        #expect(quote.lines[0].amount == Money(dollars: 1000))
    }

    @Test func aQuoteMissingItsNumberIsStillRejected() {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","issued":"2026-10-15","validUntil":"2026-11-14"}"#
        #expect(throws: DecodingError.self) { try Library.makeDecoder().decode(Quote.self, from: Data(json.utf8)) }
    }

    @Test func anInvoiceMissingOptionalFieldsGetsDefaults() throws {
        let json = #"""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","number":"INV-0003","kind":"standalone",
         "issued":"2026-10-15","due":"2026-10-29"}
        """#
        let invoice = try Library.makeDecoder().decode(Invoice.self, from: Data(json.utf8))
        #expect(invoice.stage == .draft)
        #expect(invoice.lines.isEmpty)
        #expect(invoice.payments.isEmpty)
        #expect(invoice.deductions.isEmpty)
    }

    @Test func aMinimalLibraryLoads() throws {
        let library = try Library.makeDecoder().decode(Library.self, from: Data(#"{"format":1}"#.utf8))
        #expect(library.quotes.isEmpty)
        #expect(library.usedNumbers.isEmpty)
        #expect(library.brand == Brand())
    }

    @Test func everythingSavedStillRoundTrips() throws {
        let (library, _) = Fixture.acceptedLibrary()
        let first = try Library.makeEncoder().encode(library)
        let second = try Library.makeEncoder().encode(try Library.makeDecoder().decode(Library.self, from: first))
        #expect(first == second)
    }

    @Test func everyErrorHasAPlainMessage() {
        let errors: [LibraryError] = [.notFound, .notDraft, .notSent, .notAccepted, .nothingAccepted,
                                      .nothingLeftToInvoice, .alreadyInvoiced, .isVoid, .hasPayments,
                                      .deductedByFinal("INV-0002"), .unknownLineCodes(["09"])]
        for error in errors {
            #expect(!error.message.isEmpty)
            #expect(error.localizedDescription == error.message)
        }
        #expect(LibraryError.deductedByFinal("INV-0002").message.contains("INV-0002"))
        #expect(LibraryError.unknownLineCodes(["09"]).message.contains("09"))
        #expect(LibraryStore.StoreError.wouldOverwriteUnreadableLibrary.localizedDescription.contains("library"))
        #expect(LegacyImportError.notABackup.localizedDescription.contains("backup"))
    }

    @Test func aDayBecomesNoonOnThatDay() {
        let day = Day(year: 2026, month: 10, day: 15)
        let zone = TimeZone(identifier: "Australia/Brisbane")!
        #expect(Day(day.date(in: zone), timeZone: zone) == day)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter ToleranceAndMessagesTests`
Expected: build failure, `value of type 'LibraryError' has no member 'message'` and
`value of type 'Day' has no member 'date'`.

- [ ] **Step 3: Add the decoding helper and Library's tolerant decoding (`Library.swift`)**

Add at the end of `Library.swift`:

```swift
extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when the file was saved before that field existed.
    func value<T: Decodable>(_ key: Key, or fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}

extension Library {
    enum CodingKeys: String, CodingKey {
        case format, brand, clients, quotes, invoices, activity, usedNumbers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.value(.format, or: Library.currentFormat)
        brand = try c.value(.brand, or: Brand())
        clients = try c.value(.clients, or: [])
        quotes = try c.value(.quotes, or: [])
        invoices = try c.value(.invoices, or: [])
        activity = try c.value(.activity, or: [])
        usedNumbers = try c.value(.usedNumbers, or: [])
    }
}
```

- [ ] **Step 4: Tolerant decoding for the models (`Models.swift`)**

Add at the end of `Models.swift`:

```swift
// MARK: - Tolerant decoding
// A field added in a later version must not make an older library unreadable, so every
// non-essential field falls back to its default when it's missing.

extension Brand {
    enum CodingKeys: String, CodingKey {
        case businessName, details, abn, paymentDetails, accentHex, logoFile, headingFontFile
        case quoteTerms, invoiceTerms, emails, gstRegistered, currencyCode, paymentDueDays, quoteValidDays
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Brand()
        businessName = try c.value(.businessName, or: d.businessName)
        details = try c.value(.details, or: d.details)
        abn = try c.value(.abn, or: d.abn)
        paymentDetails = try c.value(.paymentDetails, or: d.paymentDetails)
        accentHex = try c.value(.accentHex, or: d.accentHex)
        logoFile = try c.decodeIfPresent(String.self, forKey: .logoFile)
        headingFontFile = try c.decodeIfPresent(String.self, forKey: .headingFontFile)
        quoteTerms = try c.value(.quoteTerms, or: d.quoteTerms)
        invoiceTerms = try c.value(.invoiceTerms, or: d.invoiceTerms)
        emails = try c.value(.emails, or: d.emails)
        gstRegistered = try c.value(.gstRegistered, or: d.gstRegistered)
        currencyCode = try c.value(.currencyCode, or: d.currencyCode)
        paymentDueDays = try c.value(.paymentDueDays, or: d.paymentDueDays)
        quoteValidDays = try c.value(.quoteValidDays, or: d.quoteValidDays)
    }
}

extension Client {
    enum CodingKeys: String, CodingKey {
        case id, name, contactName, email, phone, address, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        contactName = try c.value(.contactName, or: "")
        email = try c.value(.email, or: "")
        phone = try c.value(.phone, or: "")
        address = try c.value(.address, or: "")
        notes = try c.value(.notes, or: "")
    }
}

extension Quote {
    enum CodingKeys: String, CodingKey {
        case id, number, clientID, title, issued, validUntil, plan, taxed, lines, lastLineNumber
        case summary, terms, stage, sentAt, acceptance, completedOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(String.self, forKey: .number)
        clientID = try c.decodeIfPresent(UUID.self, forKey: .clientID)
        title = try c.value(.title, or: "")
        issued = try c.decode(Day.self, forKey: .issued)
        validUntil = try c.decode(Day.self, forKey: .validUntil)
        plan = try c.value(.plan, or: .fiftyFifty)
        taxed = try c.value(.taxed, or: false)
        lines = try c.value(.lines, or: [])
        lastLineNumber = try c.value(.lastLineNumber, or: lines.compactMap { Int($0.code) }.max() ?? 0)
        summary = try c.value(.summary, or: "")
        terms = try c.value(.terms, or: "")
        stage = try c.value(.stage, or: .draft)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        acceptance = try c.decodeIfPresent(Acceptance.self, forKey: .acceptance)
        completedOn = try c.decodeIfPresent(Day.self, forKey: .completedOn)
    }
}

extension Invoice {
    enum CodingKeys: String, CodingKey {
        case id, number, clientID, quoteID, kind, title, issued, due, taxed, lines, depositPercent
        case deductions, terms, stage, sentAt, payments, receiptSentAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(String.self, forKey: .number)
        clientID = try c.decodeIfPresent(UUID.self, forKey: .clientID)
        quoteID = try c.decodeIfPresent(UUID.self, forKey: .quoteID)
        kind = try c.decode(InvoiceKind.self, forKey: .kind)
        title = try c.value(.title, or: "")
        issued = try c.decode(Day.self, forKey: .issued)
        due = try c.decode(Day.self, forKey: .due)
        taxed = try c.value(.taxed, or: false)
        lines = try c.value(.lines, or: [])
        depositPercent = try c.decodeIfPresent(Int.self, forKey: .depositPercent)
        deductions = try c.value(.deductions, or: [])
        terms = try c.value(.terms, or: "")
        stage = try c.value(.stage, or: .draft)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        payments = try c.value(.payments, or: [])
        receiptSentAt = try c.decodeIfPresent(Date.self, forKey: .receiptSentAt)
    }
}
```

- [ ] **Step 5: Tolerant decoding for line items (`LineItem.swift`)**

Add at the end of `LineItem.swift`:

```swift
extension LineItem {
    enum CodingKeys: String, CodingKey {
        case id, code, title, detail, quantity, unit, rate, decision
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = try c.value(.code, or: "")
        title = try c.value(.title, or: "")
        detail = try c.value(.detail, or: "")
        quantity = try c.value(.quantity, or: 1)
        unit = try c.value(.unit, or: .units)
        rate = try c.value(.rate, or: .zero)
        decision = try c.decodeIfPresent(LineDecision.self, forKey: .decision)
    }
}
```

- [ ] **Step 6: Plain messages (`Messages.swift`)**

```swift
import Foundation

// Every error the app can show, in a sentence that says what happened and what to do.

extension LibraryError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .notFound:
            return "That item no longer exists."
        case .notDraft:
            return "Only drafts can be deleted. A sent invoice can be voided instead."
        case .notSent:
            return "Mark it as sent first."
        case .notAccepted:
            return "This quote hasn't been accepted yet."
        case .nothingAccepted:
            return "The client didn't accept any lines, so there's nothing to invoice."
        case .nothingLeftToInvoice:
            return "Everything on this quote has already been invoiced."
        case .alreadyInvoiced:
            return "This quote already has invoices, so its prices, lines and payment plan are locked. Void its invoices first to change them."
        case .isVoid:
            return "This invoice is void."
        case .hasPayments:
            return "This invoice has payments recorded. Remove them before voiding it."
        case .deductedByFinal(let final):
            return "The final invoice \(final) subtracts this deposit. Void or delete \(final) first."
        case .unknownLineCodes(let codes):
            return "This quote has no \(lineList(codes))."
        }
    }
}

extension LibraryStore.StoreError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .wouldOverwriteUnreadableLibrary:
            return "The library file can't be read, so Quote Pilot won't save over it. Restore a backup first."
        case .wouldWriteUnreadableLibrary:
            return "That change would have made the library unreadable, so it wasn't saved."
        case .backupFromNewerVersion(let format):
            return "That backup was made by a newer version of Quote Pilot (library format \(format)). Update Quote Pilot to restore it."
        }
    }
}

extension LegacyImportError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .notABackup:
            return "That file isn't a backup from Invoice Generator. Use its Saved documents → Back up to file button."
        }
    }
}
```

If `LibraryStore.StoreError` has cases other than these three, the switch won't compile. Add a sentence
for each extra case in the same plain style, and list them in the report.

- [ ] **Step 7: Day to Date (`Day.swift`)**

Add inside `struct Day`, after `adding(days:)`:

```swift
    /// Noon on this day in a time zone, for date pickers. Noon keeps daylight-saving
    /// changes from moving the date.
    public func date(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
```

- [ ] **Step 8: Run all the tests**

Run: `swift test`
Expected: every test passes (the existing 142 plus 8 new).

- [ ] **Step 9: Commit**

```bash
git add Sources/QuotePilotCore Tests/QuotePilotCoreTests
git commit -m "Tolerate newer fields in the library file, and give every error a plain message

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The Windows 95 kit: theme, bevels and controls (with the first screenshot)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/QuotePilotUI/Win95/Win95Theme.swift`
- Create: `Sources/QuotePilotUI/Win95/Bevel.swift`
- Create: `Sources/QuotePilotUI/Win95/Win95Controls.swift`
- Test: `Tests/QuotePilotUITests/Snapshot.swift`
- Test: `Tests/QuotePilotUITests/KitTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure SwiftUI).
- Produces:
  - **Theme:** `Win95` colours and fonts; `Color(hex:)` (internal).
  - **Bevels:** `Bevel(_ kind: BevelKind)` with `.raised / .sunken / .pressed / .etched`; the modifiers
    `.win95Raised(padding:)` and `.win95Sunken(fill:padding:)`; `FocusRect`.
  - **Buttons:** `Win95ButtonStyle` (`.win95`, `.win95Default`) and `Win95ToolbarButtonStyle`.
  - **Text:** `Win95TextField(_ label:text:prompt:)`, `Win95TextEditor(text:)`, and
    `Win95FieldRow(_ label:labelWidth:content:)`.
  - **Containers and choices:** `Win95GroupBoxStyle` (`.win95`), `Win95CheckboxStyle` (`.win95`),
    `Win95RadioGroup(selection:options:)` and `Win95Progress(fraction:)`.
  - **Glyphs:** `PixelGlyph(_ rows:color:)` with `.tick`, `.up`, `.down`, `.cross`.
  - **Fonts** include `Win95.windowTitle` (14 pt bold) for title bars.
  - **Test helper:** `Snapshot.render(_:size:name:) -> NSBitmapImageRep?` and
    `Snapshot.hasContent(_:)`.

- [ ] **Step 1: Add the UI library and its tests to `Package.swift`**

Add to `targets` (keep everything that's there):

```swift
        .target(name: "QuotePilotUI", dependencies: ["QuotePilotCore", "QuotePilotPDF"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "QuotePilotUITests", dependencies: ["QuotePilotUI", "QuotePilotCore", "QuotePilotPDF"],
                    swiftSettings: testSettings + [.swiftLanguageMode(.v5)]),
```

- [ ] **Step 2: Write the snapshot helper and the failing kit tests**

`Tests/QuotePilotUITests/Snapshot.swift`:

```swift
import AppKit
import SwiftUI

/// Renders a SwiftUI view through AppKit in an off-screen window, so text fields and pickers draw
/// as they really do. When QP_SNAPSHOTS names a folder, it also saves a PNG there for people to
/// look at.
@MainActor
enum Snapshot {
    static func render<V: View>(_ view: V, size: CGSize, name: String) -> NSBitmapImageRep? {
        _ = NSApplication.shared
        // An off-screen window is never the key window; draw as if it were, so title bars are navy.
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .key))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let folder = ProcessInfo.processInfo.environment["QP_SNAPSHOTS"],
           let png = rep.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
        return rep
    }

    /// True when the picture has at least three distinct colours: something was drawn.
    static func hasContent(_ rep: NSBitmapImageRep) -> Bool {
        var seen = Set<UInt32>()
        let stepX = max(1, rep.pixelsWide / 60), stepY = max(1, rep.pixelsHigh / 60)
        for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = UInt32(color.redComponent * 255) << 16 | UInt32(color.greenComponent * 255) << 8 | UInt32(color.blueComponent * 255)
                seen.insert(key)
                if seen.count >= 3 { return true }
            }
        }
        return false
    }
}
```

`Tests/QuotePilotUITests/KitTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import QuotePilotUI

@MainActor
@Suite struct KitTests {
    @Test func paletteMatchesTheSpec() {
        func hex(_ color: Color) -> String {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                          Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
        }
        #expect(hex(Win95.face) == "#C0C0C0")
        #expect(hex(Win95.highlight) == "#FFFFFF")
        #expect(hex(Win95.light) == "#DFDFDF")
        #expect(hex(Win95.shadow) == "#808080")
        #expect(hex(Win95.dark) == "#000000")
        #expect(hex(Win95.titleBar) == "#000080")
        #expect(hex(Win95.inactiveTitleBar) == "#808080")
        #expect(hex(Win95.desktop) == "#008080")
        #expect(hex(Win95.selection) == "#000080")
        #expect(hex(Win95.field) == "#FFFFFF")
        #expect(hex(Win95.text) == "#000000")
        #expect(hex(Win95.tooltip) == "#FFFFE1")
        #expect(hex(Win95.overdue) == "#C00000")
        #expect(hex(Win95.paid) == "#007000")
        #expect(hex(Win95.warning) == "#FFFF00")
    }

    @Test func theKitDraws() {
        let rep = Snapshot.render(KitSampler(), size: CGSize(width: 640, height: 420), name: "kit")
        #expect(rep != nil)
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}

/// One of everything in the kit, for the screenshot.
struct KitSampler: View {
    @State private var name = "Sample Client Pty Ltd"
    @State private var notes = "Prefers email.\nPays on time."
    @State private var gst = false
    @State private var plan = "5050"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Buttons") {
                    HStack {
                        Button("OK") {}.buttonStyle(.win95Default)
                        Button("Cancel") {}.buttonStyle(.win95)
                        Button("Disabled") {}.buttonStyle(.win95).disabled(true)
                    }
                }
                GroupBox("Client") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95FieldRow("Name:") { Win95TextField("Name", text: $name) }
                        Win95FieldRow("Notes:") { Win95TextEditor(text: $notes).frame(height: 54) }
                    }
                }
                GroupBox("Progress") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95Progress(fraction: 0.5)
                        Win95Progress(fraction: 1)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Options") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Registered for GST", isOn: $gst).toggleStyle(.win95)
                        Win95RadioGroup(selection: $plan, options: [("5050", "50/50"), ("full", "Full amount")])
                    }
                }
                GroupBox("Wells") {
                    Text("$1,080.00").font(Win95.readout).padding(6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .win95Sunken()
                }
            }
        }
        .groupBoxStyle(.win95)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Win95.face)
    }
}
```

- [ ] **Step 3: Run them to watch them fail**

Run: `swift test --filter KitTests`
Expected: build failure, `cannot find 'Win95' in scope`.

- [ ] **Step 4: Write `Win95Theme.swift`**

```swift
import SwiftUI

/// The Windows 95 palette and type (spec §15). Views use these names, never raw hex.
public enum Win95 {
    // Faces and bevels
    public static let face = Color(hex: 0xC0C0C0)
    public static let highlight = Color(hex: 0xFFFFFF)
    public static let light = Color(hex: 0xDFDFDF)
    public static let shadow = Color(hex: 0x808080)
    public static let dark = Color(hex: 0x000000)

    // Areas
    public static let titleBar = Color(hex: 0x000080)
    public static let inactiveTitleBar = Color(hex: 0x808080)
    public static let desktop = Color(hex: 0x008080)
    public static let selection = Color(hex: 0x000080)
    public static let field = Color(hex: 0xFFFFFF)
    public static let text = Color(hex: 0x000000)
    public static let tooltip = Color(hex: 0xFFFFE1)

    // Meaning, always paired with a word or an icon
    public static let overdue = Color(hex: 0xC00000)
    public static let paid = Color(hex: 0x007000)
    public static let warning = Color(hex: 0xFFFF00)

    // Type
    public static let body = Font.system(size: 13)
    public static let label = Font.system(size: 13, weight: .semibold)
    public static let title = Font.system(size: 13, weight: .bold)
    /// Title bars. 14 pt bold counts as large text, so white stays readable on the grey
    /// inactive bar (3.9:1, above the 3:1 large-text minimum).
    public static let windowTitle = Font.system(size: 14, weight: .bold)
    public static let small = Font.system(size: 11)
    public static let money = Font.system(size: 13).monospacedDigit()
    public static let readout = Font.system(size: 28, design: .monospaced)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
```

- [ ] **Step 5: Write `Bevel.swift`**

```swift
import SwiftUI

public enum BevelKind {
    case raised, sunken, pressed, etched
}

/// The two-line Windows 95 bevel: an outer and an inner frame, each lit from the top left.
public struct Bevel: View {
    public var kind: BevelKind

    public init(_ kind: BevelKind) {
        self.kind = kind
    }

    public var body: some View {
        Canvas { context, size in
            let colors: (outerTL: Color, outerBR: Color, innerTL: Color, innerBR: Color)
            switch kind {
            case .raised: colors = (Win95.highlight, Win95.dark, Win95.light, Win95.shadow)
            case .sunken: colors = (Win95.shadow, Win95.highlight, Win95.dark, Win95.light)
            case .pressed: colors = (Win95.dark, Win95.highlight, Win95.shadow, Win95.light)
            case .etched: colors = (Win95.shadow, Win95.highlight, Win95.highlight, Win95.shadow)
            }
            func frame(inset: CGFloat, topLeft: Color, bottomRight: Color) {
                let w = size.width - inset * 2, h = size.height - inset * 2
                guard w > 2, h > 2 else { return }
                context.fill(Path(CGRect(x: inset, y: inset, width: w - 1, height: 1)), with: .color(topLeft))
                context.fill(Path(CGRect(x: inset, y: inset, width: 1, height: h - 1)), with: .color(topLeft))
                context.fill(Path(CGRect(x: inset, y: inset + h - 1, width: w, height: 1)), with: .color(bottomRight))
                context.fill(Path(CGRect(x: inset + w - 1, y: inset, width: 1, height: h)), with: .color(bottomRight))
            }
            frame(inset: 0, topLeft: colors.outerTL, bottomRight: colors.outerBR)
            frame(inset: 1, topLeft: colors.innerTL, bottomRight: colors.innerBR)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public extension View {
    /// A raised grey panel: bars, buttons, the window body.
    func win95Raised(padding: CGFloat = 2) -> some View {
        self.padding(padding).background(Win95.face).overlay(Bevel(.raised))
    }

    /// A sunken well: fields, lists, readouts.
    func win95Sunken(fill: Color = Win95.field, padding: CGFloat = 2) -> some View {
        self.padding(padding).background(fill).overlay(Bevel(.sunken))
    }
}

/// The dotted rectangle Windows 95 draws around the focused control.
public struct FocusRect: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [1, 1]))
            .foregroundStyle(Win95.dark)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 6: Write `Win95Controls.swift`**

```swift
import SwiftUI

// MARK: Buttons

public struct Win95ButtonStyle: ButtonStyle {
    /// The default button gets the heavy black outline, as in Windows 95.
    public var isDefault: Bool

    public init(isDefault: Bool = false) {
        self.isDefault = isDefault
    }

    public func makeBody(configuration: Configuration) -> some View {
        Win95ButtonBody(configuration: configuration, isDefault: isDefault)
    }
}

struct Win95ButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isDefault: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Win95.body)
            .foregroundStyle(isEnabled ? Win95.text : Win95.shadow)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(minWidth: 75, minHeight: 23)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .background(Win95.face)
            .overlay(Bevel(configuration.isPressed ? .pressed : .raised))
            .padding(isDefault ? 1 : 0)
            .overlay(isDefault ? Rectangle().strokeBorder(Win95.dark, lineWidth: 1) : nil)
            .contentShape(Rectangle())
    }
}

public extension ButtonStyle where Self == Win95ButtonStyle {
    static var win95: Win95ButtonStyle { Win95ButtonStyle() }
    static var win95Default: Win95ButtonStyle { Win95ButtonStyle(isDefault: true) }
}

/// The square toolbar button: an icon above a short label.
public struct Win95ToolbarButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Win95ToolbarButtonBody(configuration: configuration)
    }
}

struct Win95ToolbarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Win95.small)
            .foregroundStyle(isEnabled ? Win95.text : Win95.shadow)
            .opacity(isEnabled ? 1 : 0.6)
            .frame(width: 80, height: 58)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .background(Win95.face)
            .overlay(Bevel(configuration.isPressed ? .pressed : .raised))
            .contentShape(Rectangle())
    }
}

// MARK: Text

/// A sunken white text field with the dotted focus rectangle.
public struct Win95TextField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    public init(_ label: String, text: Binding<String>, prompt: String = "") {
        self.label = label
        self._text = text
        self.prompt = prompt
    }

    public var body: some View {
        TextField(label, text: $text, prompt: Text(prompt))
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
            .accessibilityLabel(label)
    }
}

/// A sunken multi-line editor.
public struct Win95TextEditor: View {
    @Binding var text: String

    public init(text: Binding<String>) {
        self._text = text
    }

    public var body: some View {
        TextEditor(text: $text)
            .font(Win95.body)
            .foregroundStyle(Win95.text)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Win95.field)
            .overlay(Bevel(.sunken))
    }
}

/// "Label:" on the left, the control on the right, as in Windows 95 dialogs.
public struct Win95FieldRow<Content: View>: View {
    let label: String
    let labelWidth: CGFloat
    let content: Content

    public init(_ label: String, labelWidth: CGFloat = 96, @ViewBuilder content: () -> Content) {
        self.label = label
        self.labelWidth = labelWidth
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(Win95.body)
                .foregroundStyle(Win95.text)
                .frame(width: labelWidth, alignment: .leading)
            content
        }
    }
}

// MARK: Group box

/// An etched frame with its title set into the top edge.
public struct Win95GroupBoxStyle: GroupBoxStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Bevel(.etched).padding(.top, 7))
            .overlay(alignment: .topLeading) {
                configuration.label
                    .font(Win95.label)
                    .foregroundStyle(Win95.text)
                    .padding(.horizontal, 3)
                    .background(Win95.face)
                    .padding(.leading, 8)
            }
    }
}

public extension GroupBoxStyle where Self == Win95GroupBoxStyle {
    static var win95: Win95GroupBoxStyle { Win95GroupBoxStyle() }
}

// MARK: Checkbox and radio

/// A sunken white square with a black tick.
public struct Win95CheckboxStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Win95.field
                    if configuration.isOn { PixelGlyph(PixelGlyph.tick).frame(width: 7, height: 7) }
                }
                .frame(width: 13, height: 13)
                .overlay(Bevel(.sunken))
                configuration.label
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

public extension ToggleStyle where Self == Win95CheckboxStyle {
    static var win95: Win95CheckboxStyle { Win95CheckboxStyle() }
}

/// A small glyph for controls (a tick, an arrow, a cross), drawn from rows where "k" is a pixel.
/// Give it a frame of one point per pixel (7×7 for the tick) so every pixel lands whole.
public struct PixelGlyph: View {
    public static let tick = ["......k", ".....kk", "k...kkk", "kk.kkk.", "kkkkk..", ".kkk...", "..k...."]
    public static let up = ["...k...", "..kkk..", ".kkkkk.", "kkkkkkk"]
    public static let down = ["kkkkkkk", ".kkkkk.", "..kkk..", "...k..."]
    public static let cross = ["kk...kk", ".kk.kk.", "..kkk..", ".kk.kk.", "kk...kk"]

    let rows: [String]
    let color: Color

    public init(_ rows: [String], color: Color = Win95.dark) {
        self.rows = rows
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            let columns = rows.map(\.count).max() ?? 1
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(max(rows.count, 1)))
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() where char == "k" {
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Round option buttons, one choice per row.
public struct Win95RadioGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    public init(selection: Binding<Value>, options: [(Value, String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.0
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Win95.field)
                            Circle().strokeBorder(Win95.shadow, lineWidth: 1)
                            if selection == option.0 {
                                Circle().fill(Win95.dark).frame(width: 5, height: 5)
                            }
                        }
                        .frame(width: 13, height: 13)
                        Text(option.1)
                            .font(Win95.body)
                            .foregroundStyle(Win95.text)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }
    }
}

// MARK: Progress

/// The chunky segmented Windows 95 progress bar.
public struct Win95Progress: View {
    let fraction: Double

    public init(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
    }

    public var body: some View {
        GeometryReader { geometry in
            let block: CGFloat = 8, gap: CGFloat = 2
            let count = max(0, Int((geometry.size.width - 4 + gap) / (block + gap)))
            let filled = Int((Double(count) * fraction).rounded())
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    Rectangle()
                        .fill(index < filled ? Win95.selection : Color.clear)
                        .frame(width: block)
                }
            }
            .padding(2)
        }
        .frame(height: 16)
        .background(Win95.field)
        .overlay(Bevel(.sunken))
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}
```

- [ ] **Step 7: Run the tests and look at the kit**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter KitTests`
Expected: both tests pass, and `build/snapshots/kit.png` exists (`build/` is git-ignored).

Look at `kit.png`. Check the bevels: highlight top-left, dark bottom-right on raised; the reverse on
sunken. Check the default button's black outline, the disabled button's grey text, the group-box
titles sitting in the etched line, the tick, the radio dot and the segmented bars. Fix anything
that's visibly wrong before committing, and say what you changed in the report. The controller sends
this picture to the user.

- [ ] **Step 8: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Package.swift Sources/QuotePilotUI Tests/QuotePilotUITests
git commit -m "Add the Windows 95 kit: theme, bevels and controls

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Pixel icons and status labels

**Files:**
- Create: `Sources/QuotePilotUI/Win95/PixelIcon.swift`
- Test: `Tests/QuotePilotUITests/IconTests.swift`

**Interfaces:**
- Consumes: `Win95` and `Color(hex:)` (Task 2); `QuoteStatus`, `InvoiceStatus` (core).
- Produces:
  - `PixelIcon`: the cases `quote, invoice, receipt, client, dashboard, activity, brand, mail, pdf,
    payment, warning, info, question, folder, tick, cross`, with `grid: [String]`, plus the static
    `PixelIcon.palette: [Character: Color]`.
  - `PixelIconView(_ icon:size:)`; the size defaults to 16, and 32 doubles every pixel.
  - `StatusLabel(_ icon:_ text:color:)`: an icon plus a word.
  - `QuoteStatus.icon` and `InvoiceStatus.icon`, plus `InvoiceStatus.listLabel` ("Overdue 5 d") and
    `InvoiceStatus.isAlert`.

The icon colours are the Windows 95 16-colour icon palette. It's a data table for pixels, not the UI
palette, so it's the one place where hex values appear outside `Win95`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/IconTests.swift`:

```swift
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@Suite struct IconTests {
    @Test func everyIconIsSixteenBySixteenInThePalette() {
        for icon in PixelIcon.allCases {
            #expect(icon.grid.count == 16, "\(icon) has \(icon.grid.count) rows")
            for (index, row) in icon.grid.enumerated() {
                #expect(row.count == 16, "\(icon) row \(index) has \(row.count) pixels")
                #expect(row.allSatisfy { $0 == "." || PixelIcon.palette[$0] != nil }, "\(icon) row \(index) uses a colour outside the palette")
            }
            #expect(icon.grid.joined().contains { $0 != "." }, "\(icon) is blank")
        }
    }

    @Test func everyIconLooksDifferent() {
        #expect(Set(PixelIcon.allCases.map(\.grid)).count == PixelIcon.allCases.count)
    }

    @Test func everyStatusHasAnIconAndAWord() {
        let quoteStatuses: [QuoteStatus] = [.draft, .sent, .expired, .declined, .accepted(partly: false), .accepted(partly: true)]
        for status in quoteStatuses {
            #expect(!status.label.isEmpty)
            _ = status.icon
        }
        let invoiceStatuses: [InvoiceStatus] = [.draft, .sent, .partPaid, .paid, .void, .overdue(daysLate: 5)]
        for status in invoiceStatuses {
            #expect(!status.listLabel.isEmpty)
            _ = status.icon
        }
        #expect(InvoiceStatus.overdue(daysLate: 5).listLabel == "Overdue 5 d")
        #expect(InvoiceStatus.overdue(daysLate: 5).isAlert)
        #expect(!InvoiceStatus.paid.isAlert)
        #expect(QuoteStatus.expired.icon == .warning)
        #expect(InvoiceStatus.paid.icon == .tick)
    }

    @MainActor @Test func theIconSheetDraws() {
        let rep = Snapshot.render(IconSheet(), size: CGSize(width: 640, height: 150), name: "icons")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}

/// Every icon at 16 and 32 points, for the screenshot.
struct IconSheet: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(72)), count: 8), spacing: 8) {
            ForEach(PixelIcon.allCases, id: \.self) { icon in
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        PixelIconView(icon)
                        PixelIconView(icon, size: 32)
                    }
                    Text(icon.rawValue).font(Win95.small).foregroundStyle(Win95.text)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Win95.face)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter IconTests`
Expected: build failure, `cannot find 'PixelIcon' in scope`.

- [ ] **Step 3: Write `PixelIcon.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// The app's icons, drawn from 16×16 grids (spec §15). Each character is one pixel; "." is
/// transparent and the rest are the Windows 95 icon colours in `palette`.
public enum PixelIcon: String, CaseIterable, Sendable {
    case quote, invoice, receipt, client, dashboard, activity, brand
    case mail, pdf, payment, warning, info, question, folder, tick, cross

    /// The Windows 95 16-colour icon palette.
    static let palette: [Character: Color] = [
        "k": Color(hex: 0x000000), "w": Color(hex: 0xFFFFFF), "s": Color(hex: 0xC0C0C0),
        "g": Color(hex: 0x808080), "n": Color(hex: 0x000080), "b": Color(hex: 0x0000FF),
        "t": Color(hex: 0x008080), "c": Color(hex: 0x00FFFF), "y": Color(hex: 0xFFFF00),
        "o": Color(hex: 0x808000), "m": Color(hex: 0x800000), "r": Color(hex: 0xFF0000),
        "G": Color(hex: 0x008000), "l": Color(hex: 0x00FF00), "p": Color(hex: 0x800080),
    ]

    public var grid: [String] {
        switch self {
        case .quote:
            // A page with a green tick.
            return ["..kkkkkkkkk.....",
                    "..kwwwwwwwkk....",
                    "..kwwwwwwwkwk...",
                    "..kwwwwwwwkkkk..",
                    "..kwwwwwwwwwwk..",
                    "..kwgggggggwwk..",
                    "..kwwwwwwwwwwk..",
                    "..kwgggggwwwwk..",
                    "..kwwwwwwwwGwk..",
                    "..kwwwwwwwGGwk..",
                    "..kwGwwwwGGwwk..",
                    "..kwGGwwGGwwwk..",
                    "..kwwGGGGwwwwk..",
                    "..kwwwGGwwwwwk..",
                    "..kwwwwwwwwwwk..",
                    "..kkkkkkkkkkkk.."]
        case .invoice:
            // A page with a dollar sign.
            return ["..kkkkkkkkk.....",
                    "..kwwwwwwwkk....",
                    "..kwwwwwwwkwk...",
                    "..kwwwwwwwkkkk..",
                    "..kwwwwwwwwwwk..",
                    "..kwwwwwGwwwwk..",
                    "..kwwwwGGGGwwk..",
                    "..kwwwGwGwwwwk..",
                    "..kwwwwGGGwwwk..",
                    "..kwwwwwGwGwwk..",
                    "..kwwwGGGGwwwk..",
                    "..kwwwwwGwwwwk..",
                    "..kwwwwwwwwwwk..",
                    "..kwggggggggwk..",
                    "..kwwwwwwwwwwk..",
                    "..kkkkkkkkkkkk.."]
        case .receipt:
            // A till slip with a torn bottom edge.
            return ["...kkkkkkkkkk...",
                    "...kwwwwwwwwk...",
                    "...kwggggggwk...",
                    "...kwwwwwwwwk...",
                    "...kwggggwwwk...",
                    "...kwwwwwwwwk...",
                    "...kwggwwggwk...",
                    "...kwwwwwwwwk...",
                    "...kwggwwggwk...",
                    "...kwwwwwwwwk...",
                    "...kwwwkkkkwk...",
                    "...kwwwwwwwwk...",
                    "...kwwwwGGGwk...",
                    "...kwwwwwwwwk...",
                    "...kwkwkwkwkk...",
                    "....k.k.k.k....."]
        case .client:
            // Head and shoulders.
            return ["................",
                    "......kkkk......",
                    ".....kyyyyk.....",
                    "....kyyyyyyk....",
                    "....kykyykyk....",
                    "....kyyyyyyk....",
                    "....kyykkyyk....",
                    ".....kyyyyk.....",
                    "......kkkk......",
                    "....kknnnnkk....",
                    "...knnnnnnnnk...",
                    "..knnnnnnnnnnk..",
                    "..knnnnnnnnnnk..",
                    "..knnnnnnnnnnk..",
                    "..knnnnnnnnnnk..",
                    "..kkkkkkkkkkkk.."]
        case .dashboard:
            // A bar chart.
            return ["................",
                    ".k..............",
                    ".k..............",
                    ".k......bb......",
                    ".k......bb......",
                    ".k......bb......",
                    ".k...GG.bb......",
                    ".k...GG.bb.tt...",
                    ".k...GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".knn.GG.bb.tt...",
                    ".kkkkkkkkkkkkkk.",
                    "................"]
        case .activity:
            // A clipboard with a list.
            return ["......kkkk......",
                    "..oooksssskooo..",
                    "..ookkkkkkkkoo..",
                    "..okwwwwwwwwko..",
                    "..okwkwggggwko..",
                    "..okwwwwwwwwko..",
                    "..okwkwggggwko..",
                    "..okwwwwwwwwko..",
                    "..okwkwgggwwko..",
                    "..okwwwwwwwwko..",
                    "..okwkwggggwko..",
                    "..okwwwwwwwwko..",
                    "..okwkwggwwwko..",
                    "..okwwwwwwwwko..",
                    "..okkkkkkkkkko..",
                    "..oooooooooooo.."]
        case .brand:
            // A paint palette.
            return ["................",
                    "................",
                    ".....kkkkkk.....",
                    "...kkooooookk...",
                    "..koorroobbook..",
                    ".kooorroobboook.",
                    "koooooooooollook",
                    "koo..oooooollook",
                    "koo..ooooooooook",
                    "kooooooyyooooook",
                    ".koooooyyoooook.",
                    "..kooooooooook..",
                    "...kkooooookk...",
                    ".....kkkkkk.....",
                    "................",
                    "................"]
        case .mail:
            // An envelope.
            return ["................",
                    "................",
                    "................",
                    "kkkkkkkkkkkkkkkk",
                    "kkwwwwwwwwwwwwkk",
                    "kwkwwwwwwwwwwkwk",
                    "kwwkwwwwwwwwkwwk",
                    "kwwwkwwwwwwkwwwk",
                    "kwwwwkwwwwkwwwwk",
                    "kwwwwwkwwkwwwwwk",
                    "kwwwwwwkkwwwwwwk",
                    "kwwwwwwwwwwwwwwk",
                    "kwwwwwwwwwwwwwwk",
                    "kkkkkkkkkkkkkkkk",
                    "................",
                    "................"]
        case .pdf:
            // A printer with a page coming out.
            return ["................",
                    "....kkkkkkkk....",
                    "....kwwwwwwk....",
                    "....kwggggwk....",
                    "....kwwwwwwk....",
                    "..kkkkkkkkkkkk..",
                    ".kssssssssssssk.",
                    ".kssssssssssGsk.",
                    ".kssssssssssssk.",
                    ".kggggggggggggk.",
                    ".kkkkkkkkkkkkkk.",
                    "...kwwwwwwwwk...",
                    "...kwggggggwk...",
                    "...kwwwwwwwwk...",
                    "...kkkkkkkkkk...",
                    "................"]
        case .payment:
            // A gold coin with a dollar sign.
            return ["................",
                    ".....kkkkkk.....",
                    "...kkyyyyyykk...",
                    "..kyyyyyyyyyyk..",
                    ".kyyyyykyyyyyyk.",
                    ".kyyyykkkkyyyyk.",
                    ".kyyykykyyyyyyk.",
                    ".kyyyykkkyyyyyk.",
                    ".kyyyyykykyyyyk.",
                    ".kyyykkkkyyyyyk.",
                    ".kyyyyykyyyyyyk.",
                    ".kyyyyyyyyyyyyk.",
                    "..kyyyyyyyyyyk..",
                    "...kkyyyyyykk...",
                    ".....kkkkkk.....",
                    "................"]
        case .warning:
            // A yellow triangle with an exclamation mark.
            return [".......kk.......",
                    "......kyyk......",
                    "......kyyk......",
                    ".....kyyyyk.....",
                    ".....kykkyk.....",
                    "....kyykkyyk....",
                    "....kyykkyyk....",
                    "...kyyykkyyyk...",
                    "...kyyykkyyyk...",
                    "..kyyyykkyyyyk..",
                    "..kyyyyyyyyyyk..",
                    ".kyyyyykkyyyyyk.",
                    ".kyyyyykkyyyyyk.",
                    "kyyyyyyyyyyyyyyk",
                    "kkkkkkkkkkkkkkkk",
                    "................"]
        case .info:
            // A blue circle with a white "i".
            return [".....kkkkkk.....",
                    "...kkbbbbbbkk...",
                    "..kbbbbwwbbbbk..",
                    ".kbbbbbwwbbbbbk.",
                    ".kbbbbbbbbbbbbk.",
                    "kbbbbbwwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    ".kbbbbbwwbbbbbk.",
                    ".kbbbbwwwwbbbbk.",
                    "..kbbbbbbbbbbk..",
                    "...kkbbbbbbkk...",
                    ".....kkkkkk.....",
                    "................"]
        case .question:
            // A blue circle with a white question mark.
            return [".....kkkkkk.....",
                    "...kkbbbbbbkk...",
                    "..kbbbbbbbbbbk..",
                    ".kbbbbwwwwbbbbk.",
                    ".kbbbwwbbwwbbbk.",
                    "kbbbbbbbbwwbbbbk",
                    "kbbbbbbbwwbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbwwbbbbbbk",
                    "kbbbbbbbbbbbbbbk",
                    ".kbbbbbwwbbbbbk.",
                    ".kbbbbbwwbbbbbk.",
                    "..kbbbbbbbbbbk..",
                    "...kkbbbbbbkk...",
                    ".....kkkkkk.....",
                    "................"]
        case .folder:
            // A yellow folder.
            return ["................",
                    "................",
                    ".kkkkk..........",
                    "kyyyyyk.........",
                    "kyyyyyykkkkkkkk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "kyyyyyyyyyyyyyk.",
                    "koooooooooooook.",
                    "kkkkkkkkkkkkkkk.",
                    "................",
                    "................"]
        case .tick:
            // A green tick.
            return ["................",
                    "................",
                    "................",
                    "............GG..",
                    "...........GGG..",
                    "..........GGG...",
                    ".........GGG....",
                    "..GG....GGG.....",
                    "..GGG..GGG......",
                    "...GGGGGG.......",
                    "....GGGG........",
                    ".....GG.........",
                    "................",
                    "................",
                    "................",
                    "................"]
        case .cross:
            // A red cross.
            return ["................",
                    "................",
                    "................",
                    "...rr......rr...",
                    "...rrr....rrr...",
                    "....rrr..rrr....",
                    ".....rrrrrr.....",
                    "......rrrr......",
                    ".....rrrrrr.....",
                    "....rrr..rrr....",
                    "...rrr....rrr...",
                    "...rr......rr...",
                    "................",
                    "................",
                    "................",
                    "................"]
        }
    }
}

/// Draws a pixel icon. At 16 points each grid pixel is one point; at 32, two. Icons always sit
/// beside a word, so VoiceOver skips them.
public struct PixelIconView: View {
    let icon: PixelIcon
    let size: CGFloat

    public init(_ icon: PixelIcon, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let cell = canvasSize.width / 16
            for (y, row) in icon.grid.enumerated() {
                for (x, char) in row.enumerated() {
                    guard let color = PixelIcon.palette[char] else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A status as Windows 95 lists show it: a small icon and a word, never colour alone.
public struct StatusLabel: View {
    let icon: PixelIcon
    let text: String
    let color: Color

    public init(_ icon: PixelIcon, _ text: String, color: Color = Win95.text) {
        self.icon = icon
        self.text = text
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            PixelIconView(icon)
            Text(text)
                .font(Win95.body)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension QuoteStatus {
    var icon: PixelIcon {
        switch self {
        case .draft: return .quote
        case .sent: return .mail
        case .expired: return .warning
        case .declined: return .cross
        case .accepted: return .tick
        }
    }
}

extension InvoiceStatus {
    var icon: PixelIcon {
        switch self {
        case .draft: return .invoice
        case .sent: return .mail
        case .partPaid: return .payment
        case .paid: return .tick
        case .void: return .cross
        case .overdue: return .warning
        }
    }

    /// The short form lists use: "Overdue 5 d".
    var listLabel: String {
        if case .overdue(let days) = self { return "Overdue \(days) d" }
        return label
    }

    var isAlert: Bool {
        if case .overdue = self { return true }
        return false
    }
}
```

- [ ] **Step 4: Run the tests and look at the icons**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter IconTests`
Expected: all four tests pass, and `build/snapshots/icons.png` shows all 16 icons at 16 and 32
points.

Look at `icons.png`. Every icon should read as what it's named: a page with a tick, a page with a
"$", a slip, a person, a chart, a clipboard, a palette, an envelope, a printer, a coin, a warning
triangle, an "i", a "?", a folder, a tick and a cross. Redraw any grid that doesn't, keeping it
16×16 in the palette, and say which ones you changed in the report.

- [ ] **Step 5: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI/Win95/PixelIcon.swift Tests/QuotePilotUITests/IconTests.swift
git commit -m "Add the pixel icons and status labels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The details list

The Windows 95 "Details view" every list in the app uses. It has raised headers you click to sort,
navy selection, arrow keys, Return or double-click to open, and a right-click menu. Every row stays
one line high, however long its text.

**Files:**
- Create: `Sources/QuotePilotUI/Win95/DetailsList.swift`
- Test: `Tests/QuotePilotUITests/DetailsListTests.swift`

**Interfaces:**
- Consumes: `Win95`, `Bevel`, `FocusRect`, `PixelGlyph` (Task 2); `Money`, `Day` (core).
- Produces:
  - `SortValue` (`.text`, `.number`, `.day`, plus `.money(_:)`), `ColumnWidth` (`.fixed`,
    `.flexible(min:)`) and `DetailsSort(column:ascending:)`.
  - `DetailsColumn<Row>` with `init(_:width:alignment:sortValue:cell:)`, where
    `cell: (Row, Bool) -> AnyView` and the flag means "selected". Helpers:
    `.text(_:width:alignment:monospaced:sortValue:_:)`, `.money(_:width:currencyCode:_:)` and
    `.day(_:width:_:)`.
  - `DetailsLayout.rowHeight` (20), `DetailsLayout.widths(_:total:)` and
    `DetailsLayout.sorted(_:by:ascending:)`.
  - `DetailsList(_ rows:id:columns:selection:sort:emptyText:onOpen:rowMenu:)`, where `id` is a key
    path, `selection` is a `Binding<ID?>`, `onOpen` takes `(ID) -> Void` and `rowMenu` takes
    `(ID) -> AnyView`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/DetailsListTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

private let october15 = Day(year: 2026, month: 10, day: 15)

struct SampleRow: Identifiable {
    var id: Int
    var name: String
    var total: Money = .zero
    var day: Day = october15
}

@MainActor
@Suite struct DetailsListTests {
    @Test func flexibleColumnsShareTheRoomAndKeepTheirMinimum() {
        #expect(DetailsLayout.widths([.fixed(100), .flexible(min: 50), .flexible(min: 50)], total: 400) == [100, 150, 150])
        #expect(DetailsLayout.widths([.fixed(300), .flexible(min: 80)], total: 320) == [300, 80])
    }

    @Test func moneySortsByValueNotByText() {
        let rows = [SampleRow(id: 1, name: "a", total: Money(dollars: 900)),
                    SampleRow(id: 2, name: "b", total: Money(dollars: 1000))]
        let column = DetailsColumn<SampleRow>.money("Total") { $0.total }
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: true).map(\.id) == [1, 2])
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: false).map(\.id) == [2, 1])
    }

    @Test func textSortIgnoresCaseAndPutsNumbersInOrder() {
        let rows = ["Q-0010", "q-0009", "Banana", "apple"].enumerated().map { SampleRow(id: $0.offset, name: $0.element) }
        let column = DetailsColumn<SampleRow>.text("Name", width: .flexible(min: 50)) { $0.name }
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: true).map(\.name) == ["apple", "Banana", "q-0009", "Q-0010"])
    }

    @Test func daysSortByDate() {
        let rows = [SampleRow(id: 1, name: "late", day: Day(year: 2026, month: 12, day: 1)),
                    SampleRow(id: 2, name: "early", day: Day(year: 2026, month: 2, day: 9))]
        let column = DetailsColumn<SampleRow>.day("Issued") { $0.day }
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: true).map(\.id) == [2, 1])
    }

    @Test func equalRowsKeepTheirOrder() {
        let rows = (0..<5).map { SampleRow(id: $0, name: "Same") }
        let column = DetailsColumn<SampleRow>.text("Name", width: .flexible(min: 50)) { $0.name }
        #expect(DetailsLayout.sorted(rows, by: column.sortValue, ascending: false).map(\.id) == [0, 1, 2, 3, 4])
    }

    @Test func longTextTruncatesInsteadOfWidening() {
        let long = String(repeating: "Very Long Client Name Pty Ltd ", count: 40)
        let columns: [DetailsColumn<SampleRow>] = [
            .text("Client", width: .flexible(min: 120)) { $0.name },
            .money("Total") { $0.total },
        ]
        let widths = DetailsLayout.widths(columns.map(\.width), total: 400)
        #expect(widths == [290, 110])
        let row = DetailsRowView(row: SampleRow(id: 1, name: long, total: Money(dollars: 5)), columns: columns,
                                 widths: widths, selected: false, showsFocus: false)
        let size = NSHostingView(rootView: row).fittingSize
        #expect(size.height == DetailsLayout.rowHeight)
        #expect(size.width <= 400)
    }

    @Test func theListDraws() {
        let rows = [SampleRow(id: 1, name: "Sample Client Pty Ltd", total: Money(dollars: 1935)),
                    SampleRow(id: 2, name: "Example Bakery", total: Money(dollars: 620)),
                    SampleRow(id: 3, name: String(repeating: "A very long client name ", count: 6), total: Money(dollars: 195))]
        let list = DetailsList(rows, id: \.id, columns: [
            .text("Client", width: .flexible(min: 120)) { $0.name },
            .day("Issued") { $0.day },
            .money("Total") { $0.total },
        ], selection: .constant(2), sort: DetailsSort(column: 2, ascending: false), emptyText: "Nothing here.")
        let rep = Snapshot.render(list.padding(8).background(Win95.face), size: CGSize(width: 520, height: 160), name: "details-list")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func anEmptyListSaysSo() {
        let list = DetailsList([SampleRow](), id: \.id, columns: [.text("Client", width: .flexible(min: 120)) { $0.name }],
                               selection: .constant(nil), emptyText: "No quotes yet. Press New Quote to write one.")
        let rep = Snapshot.render(list.padding(8).background(Win95.face), size: CGSize(width: 520, height: 160), name: "details-list-empty")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter DetailsListTests`
Expected: build failure, `cannot find 'DetailsLayout' in scope`.

- [ ] **Step 3: Write `DetailsList.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// What a column sorts by: text ignoring case with numbers in order ("Q-0009" before "Q-0010"),
/// whole numbers (money in cents), or days.
public enum SortValue: Comparable {
    case text(String)
    case number(Int)
    case day(Day)

    public static func money(_ amount: Money) -> SortValue { .number(amount.cents) }

    public static func < (a: SortValue, b: SortValue) -> Bool {
        switch (a, b) {
        case (.text(let x), .text(let y)): return x.localizedStandardCompare(y) == .orderedAscending
        case (.number(let x), .number(let y)): return x < y
        case (.day(let x), .day(let y)): return x < y
        default: return a.rank < b.rank
        }
    }

    private var rank: Int {
        switch self {
        case .text: return 0
        case .number: return 1
        case .day: return 2
        }
    }
}

public enum ColumnWidth: Equatable {
    case fixed(CGFloat)
    /// Shares the room the fixed columns leave, never narrower than `min`.
    case flexible(min: CGFloat)
}

public struct DetailsSort: Equatable {
    public var column: Int
    public var ascending: Bool

    public init(column: Int, ascending: Bool = true) {
        self.column = column
        self.ascending = ascending
    }
}

/// One column of a details list: its header, width, alignment, sort value and cell.
public struct DetailsColumn<Row> {
    public var title: String
    public var width: ColumnWidth
    public var alignment: Alignment
    public var sortValue: (Row) -> SortValue
    /// Draws a cell. The flag says whether the row is selected, which means white text on navy.
    public var cell: (Row, Bool) -> AnyView

    public init(_ title: String, width: ColumnWidth, alignment: Alignment = .leading,
                sortValue: @escaping (Row) -> SortValue, cell: @escaping (Row, Bool) -> AnyView) {
        self.title = title
        self.width = width
        self.alignment = alignment
        self.sortValue = sortValue
        self.cell = cell
    }

    /// A plain text column. Monospaced digits keep amounts lined up. Hovering shows the whole text,
    /// for cells cut short.
    public static func text(_ title: String, width: ColumnWidth, alignment: Alignment = .leading,
                            monospaced: Bool = false, sortValue: ((Row) -> SortValue)? = nil,
                            _ text: @escaping (Row) -> String) -> DetailsColumn {
        DetailsColumn(title, width: width, alignment: alignment,
                      sortValue: sortValue ?? { .text(text($0)) },
                      cell: { row, selected in
                          AnyView(Text(text(row))
                              .font(monospaced ? Win95.money : Win95.body)
                              .foregroundStyle(selected ? Win95.highlight : Win95.text)
                              .help(text(row)))
                      })
    }

    /// A right-aligned amount, sorted by value.
    public static func money(_ title: String, width: CGFloat = 110, currencyCode: String = "AUD",
                             _ amount: @escaping (Row) -> Money) -> DetailsColumn {
        .text(title, width: .fixed(width), alignment: .trailing, monospaced: true,
              sortValue: { .money(amount($0)) }, { amount($0).formatted(currencyCode: currencyCode) })
    }

    /// A day such as "15 Oct 2026", sorted by date.
    public static func day(_ title: String, width: CGFloat = 100, _ day: @escaping (Row) -> Day) -> DetailsColumn {
        .text(title, width: .fixed(width), sortValue: { .day(day($0)) }, { day($0).short })
    }
}

public enum DetailsLayout {
    public static let rowHeight: CGFloat = 20
    public static let headerHeight: CGFloat = 20

    /// Fixed columns keep their width; flexible ones share what's left, never below their minimum.
    public static func widths(_ columns: [ColumnWidth], total: CGFloat) -> [CGFloat] {
        var fixed: CGFloat = 0
        var flexibleCount = 0
        for column in columns {
            switch column {
            case .fixed(let width): fixed += width
            case .flexible: flexibleCount += 1
            }
        }
        let share = flexibleCount == 0 ? 0 : max(0, total - fixed) / CGFloat(flexibleCount)
        return columns.map { column in
            switch column {
            case .fixed(let width): return width
            case .flexible(let minimum): return max(minimum, share)
            }
        }
    }

    /// A stable sort: rows that compare equal keep their order.
    public static func sorted<Row>(_ rows: [Row], by value: (Row) -> SortValue, ascending: Bool) -> [Row] {
        rows.enumerated()
            .sorted { a, b in
                let x = value(a.element), y = value(b.element)
                if x < y { return ascending }
                if y < x { return !ascending }
                return a.offset < b.offset
            }
            .map(\.element)
    }
}

/// The Windows 95 "Details view".
public struct DetailsList<Row, ID: Hashable>: View {
    let rows: [Row]
    let id: KeyPath<Row, ID>
    let columns: [DetailsColumn<Row>]
    @Binding var selection: ID?
    let emptyText: String
    let onOpen: ((ID) -> Void)?
    let rowMenu: ((ID) -> AnyView)?
    @State private var sort: DetailsSort?
    @FocusState private var focused: Bool

    public init(_ rows: [Row], id: KeyPath<Row, ID>, columns: [DetailsColumn<Row>], selection: Binding<ID?>,
                sort: DetailsSort? = nil, emptyText: String,
                onOpen: ((ID) -> Void)? = nil, rowMenu: ((ID) -> AnyView)? = nil) {
        self.rows = rows
        self.id = id
        self.columns = columns
        self._selection = selection
        self.emptyText = emptyText
        self.onOpen = onOpen
        self.rowMenu = rowMenu
        self._sort = State(initialValue: sort)
    }

    private var orderedRows: [Row] {
        guard let sort, columns.indices.contains(sort.column) else { return rows }
        return DetailsLayout.sorted(rows, by: columns[sort.column].sortValue, ascending: sort.ascending)
    }

    public var body: some View {
        let ordered = orderedRows
        return GeometryReader { geometry in
            let widths = DetailsLayout.widths(columns.map(\.width), total: geometry.size.width - 4)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    header(widths)
                    if ordered.isEmpty {
                        emptyState
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(ordered, id: id) { row in
                                    rowView(row, widths: widths)
                                }
                            }
                        }
                    }
                }
                .padding(2)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.upArrow) { step(-1, ordered, proxy) }
                .onKeyPress(.downArrow) { step(1, ordered, proxy) }
                .onKeyPress(.return) { openSelection() }
            }
        }
        .background(Win95.field)
        .overlay(Bevel(.sunken))
        .clipped()
    }

    private func header(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { index in
                Button {
                    toggleSort(index)
                } label: {
                    HStack(spacing: 4) {
                        Text(columns[index].title)
                            .font(Win95.body)
                            .foregroundStyle(Win95.text)
                            .lineLimit(1)
                        if let sort, sort.column == index {
                            PixelGlyph(sort.ascending ? PixelGlyph.up : PixelGlyph.down)
                                .frame(width: 7, height: 4)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(width: widths[index], height: DetailsLayout.headerHeight, alignment: columns[index].alignment)
                    .background(Win95.face)
                    .overlay(Bevel(.raised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(headerLabel(index))
            }
            // The empty header to the right of the last column.
            Win95.face
                .frame(height: DetailsLayout.headerHeight)
                .overlay(Bevel(.raised))
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, widths: [CGFloat]) -> some View {
        let rowID = row[keyPath: id]
        let selected = rowID == selection
        let base = DetailsRowView(row: row, columns: columns, widths: widths, selected: selected,
                                  showsFocus: selected && focused)
            .id(rowID)
            .onTapGesture(count: 2) {
                selection = rowID
                onOpen?(rowID)
            }
            .simultaneousGesture(TapGesture().onEnded {
                selection = rowID
                focused = true
            })
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Open") { onOpen?(rowID) }
        if let rowMenu {
            base.contextMenu { rowMenu(rowID) }
        } else {
            base
        }
    }

    private var emptyState: some View {
        Text(emptyText)
            .font(Win95.label)
            .foregroundStyle(Win95.highlight)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Win95.desktop)
    }

    private func toggleSort(_ index: Int) {
        if let current = sort, current.column == index {
            sort = DetailsSort(column: index, ascending: !current.ascending)
        } else {
            sort = DetailsSort(column: index)
        }
    }

    private func headerLabel(_ index: Int) -> String {
        guard let sort, sort.column == index else { return "\(columns[index].title), sort" }
        return "\(columns[index].title), sorted \(sort.ascending ? "ascending" : "descending")"
    }

    private func step(_ delta: Int, _ ordered: [Row], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let ids = ordered.map { $0[keyPath: id] }
        guard !ids.isEmpty else { return .ignored }
        let current = selection.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ids.count - 1) } ?? (delta > 0 ? 0 : ids.count - 1)
        selection = ids[next]
        proxy.scrollTo(ids[next])
        return .handled
    }

    private func openSelection() -> KeyPress.Result {
        guard let selection, let onOpen else { return .ignored }
        onOpen(selection)
        return .handled
    }
}

/// One row: every cell one line high, cut short with "…" rather than wrapping or widening.
struct DetailsRowView<Row>: View {
    let row: Row
    let columns: [DetailsColumn<Row>]
    let widths: [CGFloat]
    let selected: Bool
    let showsFocus: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { index in
                columns[index].cell(row, selected)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .frame(width: widths[index], height: DetailsLayout.rowHeight, alignment: columns[index].alignment)
                    .clipped()
            }
        }
        .background(selected ? Win95.selection : Color.clear)
        .overlay(showsFocus ? FocusRect() : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Run the tests and look at the list**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter DetailsListTests`
Expected: all eight tests pass.

Look at `build/snapshots/details-list.png`. Check these:
- raised headers, with a sort arrow on Total;
- row 2 in navy with white text;
- amounts right-aligned in monospaced digits;
- the long name cut short with "…" on one line.

`details-list-empty.png` should show the teal empty state with white text.

- [ ] **Step 5: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI/Win95/DetailsList.swift Tests/QuotePilotUITests/DetailsListTests.swift
git commit -m "Add the Windows 95 details list: sortable columns, selection and keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The app model: loading, the change path, actions and message boxes

`AppModel` is the only route from the screens to the library. It loads safely, and it applies every
change to a copy and saves it before keeping it. It also backs up once a day and turns every error
into a message box.

**Files:**
- Create: `Sources/QuotePilotUI/App/AppSection.swift`
- Create: `Sources/QuotePilotUI/App/MessageBox.swift`
- Create: `Sources/QuotePilotUI/App/AppModel.swift`
- Test: `Tests/QuotePilotUITests/UIFixture.swift`
- Test: `Tests/QuotePilotUITests/AppModelTests.swift`

**Interfaces:**
- Consumes:
  - core: `LibraryStore` (`load`, `save`, `backUpIfDue`, `backups`, `restore`, `assetsFolder`),
    `Library`'s actions, `Dashboard`, and the plain messages from Task 1;
  - PDF: `Logo(url:)`, `PDFStyle(brand:assetsFolder:)`, `DocumentContent.quote/.invoice`,
    `DocumentRenderer.render`;
  - `PixelIcon` (Task 3).
- Produces:
  - `AppSection` (`.dashboard, .quotes, .invoices, .clients, .activity, .brand`) with `title`,
    `icon` and `shortcut: Character` ("1"…"6").
  - `MessageBox(kind:title:text:choices:)` with `Kind` (`.info, .question, .warning`) and
    `MessageBox.Choice(_ title:isDefault:isCancel:action:)`.
  - `PDFExport(data:fileName:)`.
  - `AppModel(store:now:)`, `@MainActor @Observable`. Its properties:
    - read-only: `store`, `library`, `loadState` (`.ready` or `.unreadable(reason:)`), `lastSaved`;
    - settable: `section`, `selectedQuoteID`, `openQuoteID`, `selectedInvoiceID`,
      `selectedClientID`, `message`, `pendingExport`.
  - **Change path:** `change(_ failureTitle:_ edit:) -> Bool` (discardable).
  - **Messages:** `show(_ error:title:)`, `show(title:text:kind:)`,
    `confirm(title:text:confirm:action:)` (Cancel is the default) and `respond(_:)`.
  - **Navigation:** `openQuote(_:)` and `openInvoice(_:)`.
  - **Quotes:** `newQuote(for:)`, `updateQuote(_:)`, `quoteBinding(_:)`, `duplicateQuote(_:)` and
    `deleteDraftQuote(_:)` (asks first).
  - **Clients:** `newClient()`, `updateClient(_:)` and `clientBinding(_:)`.
  - **Brand:** `updateBrand(_:)`, `brandBinding`, `importLogo(from:)`, `importHeadingFont(from:)`,
    `removeLogo()`, `removeHeadingFont()`, `logoURL` and `headingFontName`.
  - **Documents:** `quoteContent(_:)`, `invoiceContent(_:)`, `sampleContent()`, `pdf(_:)`,
    `exportableContent`, `canExportPDF` and `exportPDF()`.
  - **Backups:** `latestBackup` and `restoreLatestBackup()`.
  - **Figures:** `today`, `dashboard`, `currencyCode` and `money(_:)`.
  - Test helper `UIFixture`: `today`, `makeFolder()`, `invoicedLibrary()`, `model(_:folder:)` and
    `pngData()`.

- [ ] **Step 1: Write the test fixture and the failing tests**

`Tests/QuotePilotUITests/UIFixture.swift`:

```swift
import AppKit
import Foundation
import QuotePilotCore
@testable import QuotePilotUI

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

    /// A model on its own temporary folder, starting from `library` when one is given.
    @MainActor
    static func model(_ library: Library? = nil, folder: URL = makeFolder()) throws -> AppModel {
        let store = LibraryStore(folder: folder)
        if let library { try store.save(library) }
        return AppModel(store: store, now: { today.date() })
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
```

`Tests/QuotePilotUITests/AppModelTests.swift`:

```swift
import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct AppModelTests {
    @Test func aFreshLibraryStartsEmptyAndWritesNothingUntilTheFirstChange() throws {
        let model = try UIFixture.model()
        #expect(model.loadState == .ready)
        #expect(model.library.quotes.isEmpty)
        #expect(model.lastSaved == nil)
        #expect(!FileManager.default.fileExists(atPath: model.store.libraryURL.path))
    }

    @Test func aChangeIsSavedBeforeTheAppKeepsIt() throws {
        let model = try UIFixture.model()
        model.newQuote()
        #expect(model.library.quotes.map(\.number) == ["Q-0001"])
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("The new quote wasn't saved")
            return
        }
        #expect(saved.quotes.map(\.number) == ["Q-0001"])
        #expect(model.lastSaved != nil)
        #expect(model.section == .quotes)
        #expect(model.openQuoteID == saved.quotes[0].id)
    }

    @Test func aRefusedChangeKeepsTheStoredValue() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        let before = try Data(contentsOf: model.store.libraryURL)
        var edited = try #require(model.library.quote(quoteID))
        edited.lines[0].rate = Money(dollars: 999)
        model.updateQuote(edited)
        #expect(model.library.quote(quoteID)?.lines[0].rate == Money(dollars: 600))
        #expect(try Data(contentsOf: model.store.libraryURL) == before)
        #expect(model.message?.text == LibraryError.alreadyInvoiced.message)
    }

    @Test func anUnreadableLibraryIsNeverSaved() throws {
        let garbage = Data("not a library".utf8)
        let folder = try UIFixture.file("library.json", garbage).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        guard case .unreadable = model.loadState else {
            Issue.record("A damaged file should load as unreadable")
            return
        }
        model.newQuote()
        model.newClient()
        #expect(try Data(contentsOf: model.store.libraryURL) == garbage)
        #expect(model.library.quotes.isEmpty)
        #expect(model.message != nil)
    }

    @Test func restoringTheLatestBackupRecovers() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let folder = UIFixture.makeFolder()
        let store = LibraryStore(folder: folder)
        try store.save(library)
        try store.backUpIfDue(today: UIFixture.today)
        try Data("damaged".utf8).write(to: store.libraryURL)

        let model = try UIFixture.model(folder: folder)
        guard case .unreadable = model.loadState else {
            Issue.record("A damaged file should load as unreadable")
            return
        }
        model.restoreLatestBackup()
        #expect(model.loadState == .ready)
        #expect(model.library.quote(quoteID) != nil)
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("library-replaced-") }
        #expect(kept.count == 1)
        #expect(model.library.activity.first?.message.hasPrefix("Restored the backup") == true)
    }

    @Test func anExistingLibraryIsBackedUpOnLaunch() throws {
        let (library, _) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        #expect(model.store.backups().count == 1)
    }

    @Test func aNonImageLogoIsRefused() throws {
        let model = try UIFixture.model(Library())
        let fake = try UIFixture.file("logo.png", Data("this is not a picture".utf8))
        model.importLogo(from: fake)
        #expect(model.library.brand.logoFile == nil)
        #expect(model.message?.title == "Not an Image")
        let copied = (try? FileManager.default.contentsOfDirectory(atPath: model.store.assetsFolder.path)) ?? []
        #expect(copied.isEmpty)
    }

    @Test func aRealLogoIsCopiedIntoAssets() throws {
        let model = try UIFixture.model(Library())
        model.importLogo(from: try UIFixture.file("logo.png", UIFixture.pngData()))
        let name = try #require(model.library.brand.logoFile)
        #expect(name.hasPrefix("logo-") && name.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: model.store.assetsFolder.appendingPathComponent(name).path))
        #expect(model.logoURL?.lastPathComponent == name)
    }

    @Test func aNonFontIsRefused() throws {
        let model = try UIFixture.model(Library())
        model.importHeadingFont(from: try UIFixture.file("heading.ttf", Data("not a font".utf8)))
        #expect(model.library.brand.headingFontFile == nil)
        #expect(model.message?.title == "Not a Font")
    }

    @Test func deletingADraftAsksFirstWithCancelAsTheDefault() throws {
        let model = try UIFixture.model()
        model.newQuote()
        let id = try #require(model.openQuoteID)
        model.deleteDraftQuote(id)
        #expect(model.library.quote(id) != nil)
        let box = try #require(model.message)
        #expect(box.choices.first(where: \.isDefault)?.title == "Cancel")
        model.respond(try #require(box.choices.first { $0.title == "Delete" }))
        #expect(model.library.quote(id) == nil)
        #expect(model.openQuoteID == nil)
        #expect(model.message == nil)
    }

    @Test func savePDFNeedsAQuoteOrAnInvoice() throws {
        let model = try UIFixture.model()
        model.exportPDF()
        #expect(model.pendingExport == nil)
        #expect(model.message != nil)
        model.message = nil
        model.newQuote()
        #expect(model.canExportPDF)
        model.exportPDF()
        let export = try #require(model.pendingExport)
        #expect(export.fileName == "Q-0001.pdf")
        #expect(export.data.starts(with: Data("%PDF".utf8)))
    }

    @Test func theSampleQuoteUsesTheBrand() throws {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        let model = try UIFixture.model(library)
        let content = model.sampleContent()
        #expect(content.fromName == "Sample Studio")
        #expect(model.pdf(content).starts(with: Data("%PDF".utf8)))
    }

    @Test func sectionsAreInSidebarOrderWithShortcutsOneToSix() {
        #expect(AppSection.allCases.map(\.title) == ["Dashboard", "Quotes", "Invoices", "Clients", "Activity", "Brand"])
        #expect(AppSection.allCases.map(\.shortcut) == ["1", "2", "3", "4", "5", "6"])
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter AppModelTests`
Expected: build failure, `cannot find 'AppModel' in scope`.

- [ ] **Step 3: Write `AppSection.swift`**

```swift
import Foundation

/// The six places in the window's tree, in order.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard, quotes, invoices, clients, activity, brand

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .quotes: return "Quotes"
        case .invoices: return "Invoices"
        case .clients: return "Clients"
        case .activity: return "Activity"
        case .brand: return "Brand"
        }
    }

    public var icon: PixelIcon {
        switch self {
        case .dashboard: return .dashboard
        case .quotes: return .quote
        case .invoices: return .invoice
        case .clients: return .client
        case .activity: return .activity
        case .brand: return .brand
        }
    }

    /// ⌘1 to ⌘6, in tree order.
    public var shortcut: Character {
        Character(String(AppSection.allCases.firstIndex(of: self)! + 1))
    }
}
```

- [ ] **Step 4: Write `MessageBox.swift`**

```swift
import Foundation

/// A Windows 95 message box: a title, an icon, a sentence and its buttons.
public struct MessageBox: Identifiable {
    public enum Kind: Sendable {
        case info, question, warning
    }

    public struct Choice: Identifiable {
        public let id = UUID()
        public var title: String
        /// Return presses it; it gets the heavy black outline.
        public var isDefault: Bool
        /// Escape presses it.
        public var isCancel: Bool
        public var action: () -> Void

        public init(_ title: String, isDefault: Bool = false, isCancel: Bool = false, action: @escaping () -> Void = {}) {
            self.title = title
            self.isDefault = isDefault
            self.isCancel = isCancel
            self.action = action
        }
    }

    public let id = UUID()
    public var kind: Kind
    public var title: String
    public var text: String
    public var choices: [Choice]

    public init(kind: Kind, title: String, text: String,
                choices: [Choice] = [Choice("OK", isDefault: true, isCancel: true)]) {
        self.kind = kind
        self.title = title
        self.text = text
        self.choices = choices
    }
}
```

- [ ] **Step 5: Write `AppModel.swift`**

```swift
import CoreText
import Foundation
import Observation
import QuotePilotCore
import QuotePilotPDF
import SwiftUI

/// A PDF waiting for the save panel.
public struct PDFExport {
    public var data: Data
    public var fileName: String
}

/// The app's state, and the only way the screens change the library. Every change is made to a
/// copy and saved; the app keeps it only once the save has worked.
@MainActor
@Observable
public final class AppModel {
    public enum LoadState: Equatable {
        case ready
        /// The library file can't be read. Nothing is saved until a backup is restored.
        case unreadable(reason: String)
    }

    public let store: LibraryStore
    public private(set) var library: Library
    public private(set) var loadState: LoadState
    public private(set) var lastSaved: Date?

    public var section: AppSection = .dashboard
    public var selectedQuoteID: UUID?
    /// The quote open in the editor; nil shows the quote list.
    public var openQuoteID: UUID?
    public var selectedInvoiceID: UUID?
    public var selectedClientID: UUID?
    public var message: MessageBox?
    public var pendingExport: PDFExport?

    private let now: () -> Date
    @ObservationIgnored private var lastBackupDay: Day?

    public init(store: LibraryStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        var loadedExisting = false
        switch store.load() {
        case .loaded(let library):
            self.library = library
            loadState = .ready
            loadedExisting = true
        case .fresh(let library):
            self.library = library
            loadState = .ready
        case .unreadable(let reason):
            library = Library()
            loadState = .unreadable(reason: reason)
        }
        if loadedExisting { backUpIfDue() }
    }

    // MARK: Figures

    public var today: Day { Day(now()) }
    public var dashboard: Dashboard { Dashboard(library: library, today: today) }
    public var currencyCode: String { library.brand.currencyCode }

    public func money(_ amount: Money) -> String {
        amount.formatted(currencyCode: currencyCode)
    }

    // MARK: The change path

    /// Applies `edit` to a copy of the library and saves the copy; only then does the app keep it.
    /// When the edit or the save fails, nothing changes and a message box says why.
    @discardableResult
    public func change(_ failureTitle: String, _ edit: (inout Library) throws -> Void) -> Bool {
        guard loadState == .ready else {
            show(LibraryStore.StoreError.wouldOverwriteUnreadableLibrary, title: failureTitle)
            return false
        }
        var copy = library
        do {
            try edit(&copy)
            try store.save(copy)
        } catch {
            show(error, title: failureTitle)
            return false
        }
        library = copy
        lastSaved = now()
        backUpIfDue()
        return true
    }

    /// Today's backup, tried once a day.
    private func backUpIfDue() {
        let day = today
        guard lastBackupDay != day else { return }
        lastBackupDay = day
        do {
            try store.backUpIfDue(today: day)
        } catch {
            show(error, title: "Couldn't make today's backup")
        }
    }

    // MARK: Message boxes

    public func show(_ error: Error, title: String) {
        message = MessageBox(kind: .warning, title: title, text: error.localizedDescription)
    }

    public func show(title: String, text: String, kind: MessageBox.Kind = .info) {
        message = MessageBox(kind: kind, title: title, text: text)
    }

    /// Asks before something that can't be undone. Cancel is the default button.
    public func confirm(title: String, text: String, confirm: String, action: @escaping () -> Void) {
        message = MessageBox(kind: .question, title: title, text: text, choices: [
            MessageBox.Choice(confirm, action: action),
            MessageBox.Choice("Cancel", isDefault: true, isCancel: true),
        ])
    }

    public func respond(_ choice: MessageBox.Choice) {
        message = nil
        choice.action()
    }

    // MARK: Going places

    public func openQuote(_ id: UUID) {
        section = .quotes
        selectedQuoteID = id
        openQuoteID = id
    }

    public func openInvoice(_ id: UUID) {
        section = .invoices
        selectedInvoiceID = id
    }

    // MARK: Quotes

    public func newQuote(for clientID: UUID? = nil) {
        var created: UUID?
        change("Couldn't start a new quote") { library in
            created = library.newQuote(on: today, clientID: clientID).id
        }
        if let created { openQuote(created) }
    }

    public func updateQuote(_ quote: Quote) {
        change("Couldn't save \(quote.number)") { try $0.update(quote) }
    }

    /// The editor's view of a quote: it reads the stored quote and writes through `updateQuote`, so
    /// a refused edit shows the stored value again.
    public func quoteBinding(_ id: UUID) -> Binding<Quote> {
        Binding(
            get: { self.library.quote(id) ?? Quote(id: id, number: "", issued: self.today, validUntil: self.today) },
            set: { self.updateQuote($0) })
    }

    public func duplicateQuote(_ id: UUID) {
        var created: UUID?
        change("Couldn't duplicate the quote") { library in
            created = try library.duplicateQuote(id, on: today).id
        }
        if let created { openQuote(created) }
    }

    public func deleteDraftQuote(_ id: UUID) {
        guard let quote = library.quote(id) else { return }
        guard quote.stage == .draft else {
            show(title: "Can't Delete", text: "Only draft quotes can be deleted. \(quote.number) has been sent.", kind: .warning)
            return
        }
        confirm(title: "Delete Draft", text: "Delete draft quote \(quote.number)? Its number won't be used again.",
                confirm: "Delete") {
            guard self.change("Couldn't delete \(quote.number)", { try $0.deleteDraft(quote: id) }) else { return }
            if self.openQuoteID == id { self.openQuoteID = nil }
            if self.selectedQuoteID == id { self.selectedQuoteID = nil }
        }
    }

    // MARK: Clients

    public func newClient() {
        let client = Client(name: "New client")
        guard change("Couldn't add a client", { $0.addClient(client) }) else { return }
        section = .clients
        selectedClientID = client.id
    }

    public func updateClient(_ client: Client) {
        change("Couldn't save \(client.name)") { library in
            guard let index = library.clients.firstIndex(where: { $0.id == client.id }) else {
                throw LibraryError.notFound
            }
            library.clients[index] = client
        }
    }

    public func clientBinding(_ id: UUID) -> Binding<Client> {
        Binding(get: { self.library.client(id) ?? Client(id: id, name: "") }, set: { self.updateClient($0) })
    }

    // MARK: Brand

    public func updateBrand(_ brand: Brand) {
        change("Couldn't save the brand") { $0.brand = brand }
    }

    public var brandBinding: Binding<Brand> {
        Binding(get: { self.library.brand }, set: { self.updateBrand($0) })
    }

    public var logoURL: URL? {
        library.brand.logoFile.map { store.assetsFolder.appendingPathComponent($0) }
    }

    /// The heading font's name as people know it ("Avenir Next Demi Bold"), or nil.
    public var headingFontName: String? {
        guard let name = library.brand.headingFontFile,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(
                  store.assetsFolder.appendingPathComponent(name) as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first
        else { return nil }
        return CTFontDescriptorCopyAttribute(first, kCTFontDisplayNameAttribute) as? String
    }

    /// Copies a PNG, JPG or PDF into the library's Assets folder and makes it the logo.
    public func importLogo(from url: URL) {
        guard Logo(url: url) != nil else {
            show(title: "Not an Image",
                 text: "\(url.lastPathComponent) isn't an image Quote Pilot can use. Choose a PNG, JPG or PDF.",
                 kind: .warning)
            return
        }
        guard let name = copyAsset(url, prefix: "logo") else { return }
        change("Couldn't use that logo") { $0.brand.logoFile = name }
    }

    /// Copies a TTF or OTF into the Assets folder and makes it the heading font.
    public func importHeadingFont(from url: URL) {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        guard !descriptors.isEmpty else {
            show(title: "Not a Font",
                 text: "\(url.lastPathComponent) isn't a font Quote Pilot can use. Choose a TTF or OTF file.",
                 kind: .warning)
            return
        }
        guard let name = copyAsset(url, prefix: "heading-font") else { return }
        change("Couldn't use that font") { $0.brand.headingFontFile = name }
    }

    public func removeLogo() {
        change("Couldn't remove the logo") { $0.brand.logoFile = nil }
    }

    public func removeHeadingFont() {
        change("Couldn't remove the heading font") { $0.brand.headingFontFile = nil }
    }

    /// Copies a file into Assets under a fresh name ("logo-1A2B3C4D.png"), so a document already
    /// showing the old file never meets a half-copied one. Returns the new name.
    private func copyAsset(_ url: URL, prefix: String) -> String? {
        let name = "\(prefix)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.lowercased())"
        do {
            try FileManager.default.createDirectory(at: store.assetsFolder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: store.assetsFolder.appendingPathComponent(name))
            return name
        } catch {
            show(error, title: "Couldn't copy \(url.lastPathComponent)")
            return nil
        }
    }

    // MARK: Documents

    public func quoteContent(_ id: UUID) -> DocumentContent? {
        guard let quote = library.quote(id) else { return nil }
        return .quote(quote, client: library.client(quote.clientID), brand: library.brand)
    }

    public func invoiceContent(_ id: UUID) -> DocumentContent? {
        guard let invoice = library.invoice(id) else { return nil }
        let quoteNumber = invoice.quoteID.flatMap { library.quote($0)?.number }
        return .invoice(invoice, client: library.client(invoice.clientID), brand: library.brand, quoteNumber: quoteNumber)
    }

    /// A made-up quote in the current brand, for the Brand screen's preview.
    public func sampleContent() -> DocumentContent {
        let brand = library.brand
        var quote = Quote(number: "Q-0000", title: "Sample job", issued: today,
                          validUntil: today.adding(days: brand.quoteValidDays), taxed: brand.gstRegistered,
                          summary: "What's included:\n- A planning meeting\n- Design and build", terms: brand.quoteTerms)
        quote.addLine(LineItem(title: "Planning meeting", quantity: 2, unit: .hours, rate: Money(dollars: 90)))
        quote.addLine(LineItem(title: "Design", rate: Money(dollars: 600)))
        quote.addLine(LineItem(title: "Build", rate: Money(dollars: 1200)))
        let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example", email: "sam@example.com")
        return .quote(quote, client: client, brand: brand)
    }

    public func pdf(_ content: DocumentContent) -> Data {
        DocumentRenderer.render(content, style: PDFStyle(brand: library.brand, assetsFolder: store.assetsFolder))
    }

    /// What ⌘P saves: the open or selected quote on Quotes, the selected invoice on Invoices.
    public var exportableContent: DocumentContent? {
        switch section {
        case .quotes: return (openQuoteID ?? selectedQuoteID).flatMap(quoteContent)
        case .invoices: return selectedInvoiceID.flatMap(invoiceContent)
        default: return nil
        }
    }

    public var canExportPDF: Bool { exportableContent != nil }

    public func exportPDF() {
        guard let content = exportableContent else {
            show(title: "Save PDF", text: "Open or select a quote or an invoice first.")
            return
        }
        pendingExport = PDFExport(data: pdf(content), fileName: content.fileName)
    }

    // MARK: Backups

    public var latestBackup: URL? { store.backups().first }

    /// Puts the newest backup back. The file it replaces is kept beside it by `LibraryStore`.
    public func restoreLatestBackup() {
        guard let backup = latestBackup else {
            show(title: "No Backup", text: "There's no backup to restore yet.", kind: .warning)
            return
        }
        do {
            library = try store.restore(from: backup, now: now())
        } catch {
            show(error, title: "Couldn't restore the backup")
            return
        }
        loadState = .ready
        lastSaved = now()
        change("Couldn't note the restore in Activity") { $0.log("Restored the backup \(backup.lastPathComponent)") }
        show(title: "Backup Restored",
             text: "Quote Pilot restored \(backup.lastPathComponent). The file it couldn't read is kept in the same folder, named library-replaced-….json.")
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter AppModelTests`
Expected: all 13 tests pass.

- [ ] **Step 7: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI/App Tests/QuotePilotUITests/UIFixture.swift Tests/QuotePilotUITests/AppModelTests.swift
git commit -m "Add the app model: safe loading, the change path, actions and message boxes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The window: title bar, toolbar, tree, status bar, menus, and a real `Quote Pilot.app`

After this task the app opens as a real window. Sections still show a placeholder until Tasks 7–11
fill them in.

**Files:**
- Modify: `Package.swift` (the app target and product)
- Create: `Sources/QuotePilotUI/Win95/Win95Chrome.swift`
- Create: `Sources/QuotePilotUI/App/RootView.swift`
- Create: `Sources/QuotePilotUI/App/Commands.swift`
- Create: `Sources/QuotePilotUI/Screens/PDFPreview.swift` (the save-panel document for now; Task 9
  adds the preview)
- Create: `Sources/QuotePilotApp/QuotePilotApp.swift`
- Create: `Resources/Info.plist`
- Create: `build.sh`
- Test: `Tests/QuotePilotUITests/ShellTests.swift`

**Interfaces:**
- Consumes: the kit (Tasks 2–4) and `AppModel`, `AppSection`, `MessageBox` (Task 5).
- Produces:
  - **Chrome:**
    - `TitleBar(_ title:icon:height:leadingInset:)`, navy when the window is active and grey when
      it isn't;
    - `StatusPanel(_ text:)`, `EtchedLine()`, `NoteBanner(_ text:warning:)`, `MessageBoxView`;
    - `WindowDragArea`, which makes the drawn title bar move and zoom the window.
  - **Window:**
    - `RootView(model:)`, the whole window, and `QuotePilotCommands(model:)`, the menus;
    - `SectionPlaceholder(section:)`, which Tasks 7–11 replace one section at a time;
    - `StatusBarText.items(_:lastSaved:currencyCode:)`.
  - **Saving PDFs:** `PDFFile(data:)`, a `FileDocument` for the save panel.
  - **App:** the `QuotePilotApp` executable. `QP_LIBRARY_FOLDER` points it at another library
    folder. `./build.sh` makes `build/Quote Pilot.app`.

- [ ] **Step 1: Add the app to `Package.swift`**

Add to `products`:

```swift
        .executable(name: "QuotePilotApp", targets: ["QuotePilotApp"]),
```

Add to `targets`:

```swift
        .executableTarget(name: "QuotePilotApp", dependencies: ["QuotePilotUI", "QuotePilotCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/QuotePilotUITests/ShellTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct ShellTests {
    @Test func theStatusBarRepeatsTheKeyTotals() throws {
        var library = Library()
        var invoice = library.newInvoice(on: UIFixture.today.adding(days: -20))
        invoice.lines = [LineItem(title: "Monthly care", rate: Money(dollars: 150))]
        try library.update(invoice)
        try library.markSent(invoice: invoice.id)
        let dashboard = Dashboard(library: library, today: UIFixture.today)

        let items = StatusBarText.items(dashboard, lastSaved: nil, currencyCode: "AUD")
        #expect(items == ["Waiting: $150.00", "1 invoice overdue", "Received FY 2026–27: $0.00", "No changes yet"])

        let saved = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14, minute: 41))!
        #expect(StatusBarText.items(dashboard, lastSaved: saved, currencyCode: "AUD")[3].hasPrefix("Saved 2:41"))
    }

    @Test func theWindowDraws() throws {
        let model = try UIFixture.model(UIFixture.invoicedLibrary().library)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "window")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func aMessageBoxDraws() throws {
        let model = try UIFixture.model()
        model.confirm(title: "Delete Draft", text: "Delete draft quote Q-0001? Its number won't be used again.",
                      confirm: "Delete") {}
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "message-box")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theUnreadableScreenDraws() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "unreadable")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 3: Run them to watch them fail**

Run: `swift test --filter ShellTests`
Expected: build failure, `cannot find 'StatusBarText' in scope`.

- [ ] **Step 4: Write `Win95Chrome.swift`**

```swift
import AppKit
import SwiftUI

/// The navy title bar across the top of the window and of every message box. It turns grey when
/// the window isn't the active one, as in Windows 95.
public struct TitleBar: View {
    let title: String
    let icon: PixelIcon?
    let height: CGFloat
    let leadingInset: CGFloat
    @Environment(\.controlActiveState) private var activeState

    public init(_ title: String, icon: PixelIcon? = nil, height: CGFloat = 22, leadingInset: CGFloat = 0) {
        self.title = title
        self.icon = icon
        self.height = height
        self.leadingInset = leadingInset
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let icon { PixelIconView(icon) }
            Text(title)
                .font(Win95.windowTitle)
                .foregroundStyle(Win95.highlight)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4 + leadingInset)
        .padding(.trailing, 4)
        .frame(height: height)
        .background(activeState == .inactive ? Win95.inactiveTitleBar : Win95.titleBar)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Lets the drawn title bar move the window, and a double-click zoom it, like a real title bar.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// One sunken panel of the status bar.
public struct StatusPanel: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Win95.body)
            .foregroundStyle(Win95.text)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .overlay(Bevel(.sunken))
    }
}

/// The two-tone line Windows 95 draws between toolbars and panels.
public struct EtchedLine: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Win95.shadow.frame(height: 1)
            Win95.highlight.frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A note in a pale yellow box, or a warning in bright yellow, with its icon.
public struct NoteBanner: View {
    let text: String
    let warning: Bool

    public init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            PixelIconView(warning ? .warning : .info)
            Text(text)
                .font(Win95.body)
                .foregroundStyle(Win95.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(warning ? Win95.warning : Win95.tooltip)
        .overlay(Rectangle().strokeBorder(Win95.dark, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// A Windows 95 message box: navy title, a 32-point icon, the sentence, and bevelled buttons.
/// Return presses the default button and Escape the cancel one.
struct MessageBoxView: View {
    let box: MessageBox
    let respond: (MessageBox.Choice) -> Void

    private var icon: PixelIcon {
        switch box.kind {
        case .info: return .info
        case .question: return .question
        case .warning: return .warning
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(box.title)
                .padding(2)
            HStack(alignment: .top, spacing: 14) {
                PixelIconView(icon, size: 32)
                Text(box.text)
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380, alignment: .leading)
            }
            .padding(16)
            HStack(spacing: 8) {
                ForEach(box.choices) { choice in
                    Button(choice.title) { respond(choice) }
                        .buttonStyle(Win95ButtonStyle(isDefault: choice.isDefault))
                        .keyboardShortcut(shortcut(for: choice))
                }
            }
            .padding(.bottom, 14)
            // When one button is both default and cancel (a lone OK), Escape still needs a home.
            if let cancel = box.choices.first(where: { $0.isCancel && $0.isDefault }) {
                Button("") { respond(cancel) }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 320)
        .background(Win95.face)
        .overlay(Bevel(.raised))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(box.title)
    }

    private func shortcut(for choice: MessageBox.Choice) -> KeyboardShortcut? {
        if choice.isDefault { return .defaultAction }
        if choice.isCancel { return .cancelAction }
        return nil
    }
}
```

- [ ] **Step 5: Write `PDFPreview.swift` (the save-panel document)**

```swift
import SwiftUI
import UniformTypeIdentifiers

/// A PDF for the save panel.
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
```

- [ ] **Step 6: Write `RootView.swift`**

```swift
import AppKit
import QuotePilotCore
import SwiftUI

/// The whole window: title bar, toolbar, the section tree, the current section and the status bar,
/// or the unreadable-library screen. Message boxes sit on top.
public struct RootView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The macOS window buttons sit over the left end of this bar.
            TitleBar(windowTitle, icon: titleIcon, height: 28, leadingInset: 72)
                .overlay(WindowDragArea())
            switch model.loadState {
            case .ready:
                Win95Toolbar(model: model)
                HStack(spacing: 4) {
                    SectionTree(model: model)
                        .frame(width: 190)
                    sectionContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(4)
                StatusBar(model: model)
            case .unreadable(let reason):
                UnreadableLibraryView(model: model, reason: reason)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 980, minHeight: 620)
        .background(Win95.face)
        .preferredColorScheme(.light)
        .overlay { messageOverlay }
        .fileExporter(isPresented: exporting, document: model.pendingExport.map { PDFFile(data: $0.data) },
                      contentType: .pdf, defaultFilename: model.pendingExport?.fileName) { result in
            if case .failure(let error) = result {
                model.show(error, title: "Couldn't save the PDF")
            }
            model.pendingExport = nil
        }
    }

    private var windowTitle: String {
        if case .unreadable = model.loadState { return "Quote Pilot" }
        return "Quote Pilot - \(model.section.title)"
    }

    private var titleIcon: PixelIcon {
        if case .unreadable = model.loadState { return .warning }
        return model.section.icon
    }

    private var exporting: Binding<Bool> {
        Binding(get: { model.pendingExport != nil }, set: { if !$0 { model.pendingExport = nil } })
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.section {
        case .dashboard: SectionPlaceholder(section: .dashboard)
        case .quotes: SectionPlaceholder(section: .quotes)
        case .invoices: SectionPlaceholder(section: .invoices)
        case .clients: SectionPlaceholder(section: .clients)
        case .activity: SectionPlaceholder(section: .activity)
        case .brand: SectionPlaceholder(section: .brand)
        }
    }

    @ViewBuilder
    private var messageOverlay: some View {
        if let box = model.message {
            ZStack {
                // As with a Windows 95 message box, the window behind stays visible but can't be clicked.
                Color.white.opacity(0.001)
                MessageBoxView(box: box) { model.respond($0) }
            }
        }
    }
}

/// The toolbar: square buttons with a pixel icon over a short label. Buttons for plan 2b's work
/// are there but off, so the toolbar's shape doesn't change later.
struct Win95Toolbar: View {
    let model: AppModel
    private let later = "Arrives in the next build"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                tool("New Quote", .quote, help: "Start a new quote (⌘N)") { model.newQuote() }
                tool("New Invoice", .invoice, help: later, enabled: false) {}
                ToolbarSeparator()
                tool("Send", .mail, help: later, enabled: false) {}
                tool("Read Reply", .folder, help: later, enabled: false) {}
                tool("Payment", .payment, help: later, enabled: false) {}
                ToolbarSeparator()
                tool("Save PDF", .pdf, help: "Save the open quote or invoice as a PDF (⌘P)",
                     enabled: model.canExportPDF) { model.exportPDF() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            EtchedLine()
        }
        .background(Win95.face)
    }

    private func tool(_ title: String, _ icon: PixelIcon, help: String, enabled: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                PixelIconView(icon, size: 32)
                Text(title)
            }
        }
        .buttonStyle(Win95ToolbarButtonStyle())
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(help)
    }
}

struct ToolbarSeparator: View {
    var body: some View {
        HStack(spacing: 0) {
            Win95.shadow.frame(width: 1)
            Win95.highlight.frame(width: 1)
        }
        .frame(height: 50)
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}

/// The Explorer-style tree on the left: the business at the top, the six sections under it.
struct SectionTree: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                PixelIconView(.folder)
                Text(model.library.brand.businessName.isEmpty ? "Quote Pilot" : model.library.brand.businessName)
                    .font(Win95.label)
                    .foregroundStyle(Win95.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .frame(height: 22)
            ForEach(AppSection.allCases) { section in
                row(section, isLast: section == AppSection.allCases.last)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Win95.field)
        .overlay(Bevel(.sunken))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }

    private func row(_ section: AppSection, isLast: Bool) -> some View {
        let selected = model.section == section
        return HStack(spacing: 4) {
            TreeConnector(isLast: isLast)
                .frame(width: 16, height: 22)
            PixelIconView(section.icon)
            Text(section.title)
                .font(Win95.body)
                .foregroundStyle(selected ? Win95.highlight : Win95.text)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(selected ? Win95.selection : Color.clear)
                .overlay(selected && focused ? FocusRect() : nil)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            select(section)
            focused = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(section) }
    }

    private func select(_ section: AppSection) {
        // Choosing Quotes again from the editor goes back to the list.
        if section == .quotes, model.section == .quotes { model.openQuoteID = nil }
        model.section = section
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        let all = AppSection.allCases
        let index = all.firstIndex(of: model.section) ?? 0
        model.section = all[min(max(index + delta, 0), all.count - 1)]
        return .handled
    }
}

/// Explorer's dotted tree lines.
struct TreeConnector: View {
    let isLast: Bool

    var body: some View {
        Canvas { context, size in
            let x = (size.width / 2).rounded(.down) + 0.5
            let middle = (size.height / 2).rounded(.down) + 0.5
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: isLast ? middle : size.height))
            path.move(to: CGPoint(x: x, y: middle))
            path.addLine(to: CGPoint(x: size.width, y: middle))
            context.stroke(path, with: .color(Win95.shadow), style: StrokeStyle(lineWidth: 1, dash: [1, 1]))
        }
        .accessibilityHidden(true)
    }
}

/// What the status bar says, on every screen.
enum StatusBarText {
    static func items(_ dashboard: Dashboard, lastSaved: Date?, currencyCode: String) -> [String] {
        let overdue = dashboard.waiting.filter { $0.daysLate > 0 }.count
        let saved = lastSaved.map {
            "Saved " + $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_AU")))
        }
        return [
            "Waiting: \(dashboard.waitingTotal.formatted(currencyCode: currencyCode))",
            overdue == 1 ? "1 invoice overdue" : "\(overdue) invoices overdue",
            "Received \(dashboard.financialYear.label): \(dashboard.receivedThisYear.formatted(currencyCode: currencyCode))",
            saved ?? "No changes yet",
        ]
    }
}

struct StatusBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatusBarText.items(model.dashboard, lastSaved: model.lastSaved, currencyCode: model.currencyCode),
                    id: \.self) { item in
                StatusPanel(item)
            }
        }
        .padding(2)
        .background(Win95.face)
    }
}

/// Stands in for a section until its screen is built.
struct SectionPlaceholder: View {
    let section: AppSection

    var body: some View {
        Text("\(section.title) is on its way.")
            .font(Win95.label)
            .foregroundStyle(Win95.highlight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Win95.desktop)
            .overlay(Bevel(.sunken))
    }
}

/// Shown instead of the app when the library file can't be read. Nothing is saved from here; the
/// only way on is restoring a backup.
struct UnreadableLibraryView: View {
    let model: AppModel
    let reason: String

    var body: some View {
        ZStack {
            Win95.desktop
            VStack(spacing: 0) {
                TitleBar("Quote Pilot", icon: .warning)
                    .padding(2)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        PixelIconView(.warning, size: 32)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quote Pilot can't open your library.")
                                .font(Win95.label)
                            Text(reason)
                            Text("The file has been left exactly as it is, and Quote Pilot won't save over it.")
                            Text(model.store.libraryURL.path)
                                .font(Win95.small.monospaced())
                                .textSelection(.enabled)
                            if let backup = model.latestBackup {
                                Text("The latest backup is \(backup.lastPathComponent).")
                            } else {
                                Text("There are no backups to restore.")
                            }
                        }
                        .font(Win95.body)
                        .foregroundStyle(Win95.text)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Restore Latest Backup") { model.restoreLatestBackup() }
                            .buttonStyle(.win95Default)
                            .disabled(model.latestBackup == nil)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([model.store.libraryURL])
                        }
                        .buttonStyle(.win95)
                        Button("Quit") { NSApp.terminate(nil) }
                            .buttonStyle(.win95)
                    }
                }
                .padding(16)
            }
            .frame(width: 560)
            .background(Win95.face)
            .overlay(Bevel(.raised))
        }
    }
}
```

- [ ] **Step 7: Write `Commands.swift`**

```swift
import SwiftUI

/// The menu bar. Each command checks for itself whether it applies, and says so in a message box
/// when it doesn't.
public struct QuotePilotCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Quote") { model.newQuote() }
                .keyboardShortcut("n")
            Button("New Client") { model.newClient() }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        // Every change saves itself, so there's no Save.
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .printItem) {
            Button("Save PDF…") { model.exportPDF() }
                .keyboardShortcut("p")
        }
        CommandMenu("Go") {
            ForEach(AppSection.allCases) { section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(section.shortcut))
            }
        }
    }
}
```

- [ ] **Step 8: Write the app, its `Info.plist` and `build.sh`**

`Sources/QuotePilotApp/QuotePilotApp.swift`:

```swift
import AppKit
import QuotePilotCore
import QuotePilotUI
import SwiftUI

@main
struct QuotePilotApp: App {
    @State private var model: AppModel

    init() {
        // QP_LIBRARY_FOLDER points the app at another library, such as the one `qp demo` writes.
        let folder = ProcessInfo.processInfo.environment["QP_LIBRARY_FOLDER"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? LibraryStore.defaultFolder
        _model = State(initialValue: AppModel(store: LibraryStore(folder: folder)))
        // Started with `swift run`, the binary isn't inside an app bundle; make it a normal app anyway.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Quote Pilot", id: "main") {
            RootView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands { QuotePilotCommands(model: model) }
    }
}
```

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Quote Pilot</string>
    <key>CFBundleDisplayName</key>
    <string>Quote Pilot</string>
    <key>CFBundleIdentifier</key>
    <string>com.fynnprojects.quotepilot</string>
    <key>CFBundleExecutable</key>
    <string>Quote Pilot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.business</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

`build.sh`:

```bash
#!/bin/bash
# Builds "build/Quote Pilot.app" from the release binary. Run it from anywhere: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product QuotePilotApp
binary="$(swift build -c release --show-bin-path)/QuotePilotApp"
app="build/Quote Pilot.app"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Quote Pilot"
cp Resources/Info.plist "$app/Contents/Info.plist"
# An ad-hoc signature, so macOS runs the app on this Mac.
codesign --force --sign - "$app"
echo "Built $app"
```

Then make it executable: `chmod +x build.sh`.

- [ ] **Step 9: Run the tests and look at the window**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter ShellTests`
Expected: all four tests pass.

Look at `build/snapshots/window.png`. You should see:
- a navy title bar reading "Quote Pilot - Dashboard";
- a toolbar of square buttons with 32-point icons. New Quote and Save PDF are on; the four plan-2b
  buttons are greyed;
- a white sunken tree with dotted lines and Dashboard selected in navy;
- the teal placeholder;
- four sunken status panels ("Waiting: $0.00", …).

Also check `message-box.png` (a centred question box with Cancel outlined) and `unreadable.png` (the
teal screen with the warning box). Fix anything that's visibly wrong, and say what you changed in the
report. The controller sends `window.png` to the user.

- [ ] **Step 10: Build the app and open it once**

Run: `./build.sh`
Expected: `Built build/Quote Pilot.app`.

Run: `QP_LIBRARY_FOLDER="$(mktemp -d)" "build/Quote Pilot.app/Contents/MacOS/Quote Pilot" &`, wait
five seconds, then `kill %1`. A temporary empty library keeps the real folder untouched.
Expected: the process starts and stays up until it's killed, with no crash report in the output.

- [ ] **Step 11: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Package.swift build.sh Resources Sources/QuotePilotApp Sources/QuotePilotUI Tests/QuotePilotUITests/ShellTests.swift
git commit -m "Add the Windows 95 window, menus and Quote Pilot.app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The dashboard, plus a made-up sample business to try it with

The main screen has the four headline numbers in big sunken readouts, and three lists: what's owed,
quotes waiting on a reply, and what's still to invoice. To show it working, the core gains a made-up
sample business, and `qp demo <folder>` writes it as a library.

**Files:**
- Create: `Sources/QuotePilotCore/SampleLibrary.swift`
- Modify: `Sources/qp/main.swift` (the `demo` command)
- Create: `Sources/QuotePilotUI/Screens/DashboardView.swift`
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (show the dashboard)
- Modify: `Tests/QuotePilotUITests/UIFixture.swift` (`sampleModel()`)
- Test: `Tests/QuotePilotCoreTests/SampleLibraryTests.swift`
- Test: `Tests/QuotePilotUITests/DashboardTests.swift`

**Interfaces:**
- Consumes: `Dashboard` (core), `DetailsList` (Task 4), `AppModel` (Task 5), `RootView` (Task 6).
- Produces:
  - `SampleLibrary.make(today:now:) throws -> Library`.
  - `qp demo <folder>`.
  - `DashboardView(model:)`, `Readout`, and `DashboardView.overdueNote(_:)`.
  - `StatusLabel.cell(_ status: QuoteStatus, selected:)` and
    `StatusLabel.cell(_ status: InvoiceStatus, selected:)`, which return `AnyView` for list cells.
  - `UIFixture.sampleModel()`.

- [ ] **Step 1: Write the failing core test**

`Tests/QuotePilotCoreTests/SampleLibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct SampleLibraryTests {
    @Test func theSampleBusinessFillsEveryDashboardFigure() throws {
        let library = try SampleLibrary.make(today: Fixture.today)
        let dashboard = Dashboard(library: library, today: Fixture.today)
        #expect(dashboard.waitingTotal == Money(dollars: 285))
        #expect(dashboard.overdueTotal == Money(dollars: 150))
        #expect(dashboard.waiting.first?.daysLate == 5)
        #expect(dashboard.receivedThisMonth == Money(dollars: 1995))
        #expect(dashboard.receivedThisYear == Money(dollars: 1995))
        #expect(dashboard.invoicedThisYear == Money(dollars: 2280))
        #expect(dashboard.openQuotes.count == 2)
        #expect(dashboard.openQuotes.filter(\.expired).count == 1)
        #expect(dashboard.openQuotesTotal == Money(dollars: 620))
        #expect(dashboard.toInvoice.map(\.remaining) == [Money(dollars: 1935)])
        #expect(library.quotes.map { $0.status(on: Fixture.today) } == [.accepted(partly: true), .sent, .expired, .draft])
    }

    @Test func theSampleBusinessIsMadeUp() throws {
        let library = try SampleLibrary.make(today: Fixture.today)
        let text = String(decoding: try Library.makeEncoder().encode(library), as: UTF8.self)
        #expect(text.contains("example.com"))
        #expect(!text.localizedCaseInsensitiveContains("plumb"))
    }
}
```

- [ ] **Step 2: Run it to watch it fail**

Run: `swift test --filter SampleLibraryTests`
Expected: build failure, `cannot find 'SampleLibrary' in scope`.

- [ ] **Step 3: Write `SampleLibrary.swift`**

```swift
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
```

- [ ] **Step 4: Run the core test**

Run: `swift test --filter SampleLibraryTests`
Expected: both tests pass.

- [ ] **Step 5: Add `qp demo` (`Sources/qp/main.swift`)**

Change the header comment to:

```swift
// qp: try Quote Pilot's documents and app with made-up data.
//   qp samples <folder>   writes a sample quote, deposit invoice, final invoice and receipt
//   qp read <pdf>         reads a returned quote and shows what Quote Pilot would record
//   qp demo <folder>      writes a sample business's library, for opening with QP_LIBRARY_FOLDER
```

Add this function above `let arguments`:

```swift
func demo(into folder: URL) {
    let store = LibraryStore(folder: folder)
    guard folder.standardizedFileURL.path != LibraryStore.defaultFolder.standardizedFileURL.path else {
        print("qp demo never writes to the real library folder. Pick another folder.")
        exit(1)
    }
    guard !FileManager.default.fileExists(atPath: store.libraryURL.path) else {
        print("\(store.libraryURL.path) already exists, and qp demo never writes over a library.")
        exit(1)
    }
    do {
        try store.save(SampleLibrary.make(today: Day.today()))
        print("Wrote a sample library to \(store.libraryURL.path)")
        print("Open it with: QP_LIBRARY_FOLDER=\"\(folder.path)\" \"build/Quote Pilot.app/Contents/MacOS/Quote Pilot\"")
    } catch {
        print("Couldn't write the sample library: \(error.localizedDescription)")
        exit(1)
    }
}
```

In the `switch`, add before `default:`:

```swift
case ("demo", 2):
    demo(into: URL(fileURLWithPath: arguments[1], isDirectory: true))
```

and change the usage line to:

```swift
    print("usage: qp samples <folder>   |   qp read <returned quote.pdf>   |   qp demo <folder>")
```

Check it: `swift run qp demo "$(mktemp -d)/demo"` prints "Wrote a sample library to …". Running it a
second time on the same folder refuses.

- [ ] **Step 6: Write the failing UI tests**

Add to `UIFixture` in `Tests/QuotePilotUITests/UIFixture.swift`:

```swift
    /// A model holding the made-up sample business, on its own temporary folder.
    @MainActor
    static func sampleModel() throws -> AppModel {
        try model(SampleLibrary.make(today: today, now: today.date()))
    }
```

`Tests/QuotePilotUITests/DashboardTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct DashboardTests {
    @Test func theOverdueNoteNamesTheOldest() throws {
        let model = try UIFixture.sampleModel()
        #expect(DashboardView.overdueNote(model.dashboard) == "1 invoice, 5 days late")
        let empty = Dashboard(library: Library(), today: UIFixture.today)
        #expect(DashboardView.overdueNote(empty) == "Nothing overdue")
    }

    @Test func theDashboardDraws() throws {
        let model = try UIFixture.sampleModel()
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "dashboard")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func anEmptyDashboardDraws() throws {
        let model = try UIFixture.model()
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "dashboard-empty")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 7: Run them to watch them fail**

Run: `swift test --filter DashboardTests`
Expected: build failure, `cannot find 'DashboardView' in scope`.

- [ ] **Step 8: Write `DashboardView.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// The main screen: four big readouts, then what's owed, quotes waiting on a reply and what's still
/// to invoice. Double-click a row to open it.
struct DashboardView: View {
    let model: AppModel
    @State private var selectedInvoice: UUID?
    @State private var selectedQuote: UUID?
    @State private var selectedJob: UUID?

    var body: some View {
        let dashboard = model.dashboard
        let liveQuotes = dashboard.openQuotes.filter { !$0.expired }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Readout(title: "Waiting to be paid", value: model.money(dashboard.waitingTotal),
                        note: Self.count(dashboard.waiting.count, "invoice", "invoices"))
                Readout(title: "Overdue", value: model.money(dashboard.overdueTotal),
                        note: Self.overdueNote(dashboard), alert: dashboard.overdueTotal > .zero)
                Readout(title: "Received \(dashboard.financialYear.label)", value: model.money(dashboard.receivedThisYear),
                        note: "This month: \(model.money(dashboard.receivedThisMonth))")
                Readout(title: "Quotes out", value: model.money(dashboard.openQuotesTotal),
                        note: Self.count(liveQuotes, "quote", "quotes") + " waiting on a reply")
            }
            GroupBox("Waiting to be paid") {
                DetailsList(dashboard.waiting, id: \.invoiceID, columns: owingColumns, selection: $selectedInvoice,
                            emptyText: "Nothing waiting. Every sent invoice is paid.",
                            onOpen: { model.openInvoice($0) })
            }
            .frame(maxHeight: .infinity)
            HStack(alignment: .top, spacing: 8) {
                GroupBox("Quotes waiting on a reply") {
                    DetailsList(dashboard.openQuotes, id: \.quoteID, columns: quoteColumns, selection: $selectedQuote,
                                emptyText: "No quotes out.", onOpen: { model.openQuote($0) })
                }
                GroupBox("Still to invoice") {
                    DetailsList(dashboard.toInvoice, id: \.quoteID, columns: jobColumns, selection: $selectedJob,
                                emptyText: "Every accepted job is fully invoiced.", onOpen: { model.openQuote($0) })
                }
            }
            .frame(maxHeight: .infinity)
            Text("Invoiced \(dashboard.financialYear.label): \(model.money(dashboard.invoicedThisYear))")
                .font(Win95.body)
                .foregroundStyle(Win95.text)
        }
        .padding(8)
        .groupBoxStyle(.win95)
    }

    private var owingColumns: [DetailsColumn<Dashboard.Owing>] {
        [
            .text("Invoice", width: .fixed(90)) { $0.number },
            .text("Client", width: .flexible(min: 140)) { $0.client },
            .day("Due") { $0.due },
            DetailsColumn("Status", width: .fixed(140), sortValue: { .number($0.daysLate) }) { row, selected in
                StatusLabel.cell(model.library.invoice(row.invoiceID)?.status(on: model.today) ?? .sent, selected: selected)
            },
            .money("Owing", currencyCode: model.currencyCode) { $0.owing },
        ]
    }

    private var quoteColumns: [DetailsColumn<Dashboard.OpenQuote>] {
        [
            .text("Quote", width: .fixed(80)) { $0.number },
            .text("Client", width: .flexible(min: 120)) { $0.client },
            .day("Valid until") { $0.validUntil },
            DetailsColumn("Status", width: .fixed(100), sortValue: { .number($0.expired ? 1 : 0) }) { row, selected in
                StatusLabel.cell(row.expired ? QuoteStatus.expired : .sent, selected: selected)
            },
            .money("Total", currencyCode: model.currencyCode) { $0.total },
        ]
    }

    private var jobColumns: [DetailsColumn<Dashboard.ToInvoice>] {
        [
            .text("Quote", width: .fixed(80)) { $0.number },
            .text("Client", width: .flexible(min: 120)) { $0.client },
            DetailsColumn("Invoiced", width: .fixed(110), sortValue: { .number(Int(Self.share($0) * 1000)) }) { row, _ in
                AnyView(Win95Progress(fraction: Self.share(row))
                    .frame(height: 14)
                    .accessibilityLabel("Invoiced \(Int((Self.share(row) * 100).rounded())) percent"))
            },
            .money("Left to invoice", width: 120, currencyCode: model.currencyCode) { $0.remaining },
        ]
    }

    /// "1 invoice, 5 days late": how many are overdue, and the oldest.
    static func overdueNote(_ dashboard: Dashboard) -> String {
        let late = dashboard.waiting.filter { $0.daysLate > 0 }
        guard let oldest = late.map(\.daysLate).max() else { return "Nothing overdue" }
        return count(late.count, "invoice", "invoices") + ", " + count(oldest, "day", "days") + " late"
    }

    static func count(_ number: Int, _ one: String, _ many: String) -> String {
        "\(number) \(number == 1 ? one : many)"
    }

    /// How much of an accepted job is invoiced, from 0 to 1.
    static func share(_ job: Dashboard.ToInvoice) -> Double {
        job.accepted.cents > 0 ? Double(job.invoiced.cents) / Double(job.accepted.cents) : 0
    }
}

/// A headline number in a sunken white panel, 28 points, with a line of detail under it.
struct Readout: View {
    let title: String
    let value: String
    let note: String
    var alert = false

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(Win95.readout)
                    .foregroundStyle(alert ? Win95.overdue : Win95.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .win95Sunken()
                HStack(spacing: 4) {
                    if alert { PixelIconView(.warning) }
                    Text(note)
                        .font(Win95.body)
                        .foregroundStyle(Win95.text)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension StatusLabel {
    /// A quote's status in a list cell: white on a selected row, dark red once expired.
    static func cell(_ status: QuoteStatus, selected: Bool) -> AnyView {
        AnyView(StatusLabel(status.icon, status.label,
                            color: selected ? Win95.highlight : (status == .expired ? Win95.overdue : Win95.text)))
    }

    /// An invoice's status in a list cell: white on a selected row, dark red when overdue.
    static func cell(_ status: InvoiceStatus, selected: Bool) -> AnyView {
        AnyView(StatusLabel(status.icon, status.listLabel,
                            color: selected ? Win95.highlight : (status.isAlert ? Win95.overdue : Win95.text)))
    }
}
```

In `RootView.sectionContent`, replace `case .dashboard: SectionPlaceholder(section: .dashboard)` with:

```swift
        case .dashboard: DashboardView(model: model)
```

- [ ] **Step 9: Run the tests and look at the dashboard**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter DashboardTests`
Expected: all three tests pass.

Look at `build/snapshots/dashboard.png`. Check these:
- four readouts: $285.00, $150.00 in dark red with a warning icon and "1 invoice, 5 days late",
  $1,995.00, and $620.00;
- "Waiting to be paid" lists INV-0002 (Overdue 5 d, in red with a warning icon) and INV-0003 (Part
  paid);
- quotes out lists Q-0002 (Sent) and Q-0003 (Expired);
- still to invoice lists Q-0001 with a half-full segmented bar and $1,935.00 left.

Fix anything that's visibly wrong and say what in the report. The controller sends this picture to
the user.

- [ ] **Step 10: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Sources Tests
git commit -m "Add the dashboard, a made-up sample business and qp demo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Clients

**Files:**
- Create: `Sources/QuotePilotUI/Screens/ClientsView.swift`
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (show Clients)
- Test: `Tests/QuotePilotUITests/ClientsTests.swift`

**Interfaces:**
- Consumes: `AppModel.newClient()`, `clientBinding(_:)`, `newQuote(for:)`, `selectedClientID`
  (Task 5); `DetailsList` (Task 4); `NoteBanner` (Task 6); `UIFixture.sampleModel()` (Task 7).
- Produces: `ClientsView(model:)`, `ClientForm`, and `ClientSummary(library:clientID:)` with
  `quotes`, `invoiced`, `paid` and `owing`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/ClientsTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct ClientsTests {
    @Test func editingAClientSavesIt() throws {
        let model = try UIFixture.sampleModel()
        let id = try #require(model.library.clients.first { $0.name == "Example Bakery" }?.id)
        model.clientBinding(id).wrappedValue.email = "orders@example.com"
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.client(id)?.email == "orders@example.com")
    }

    @Test func aNewQuoteForAClientPicksThatClient() throws {
        let model = try UIFixture.sampleModel()
        let id = try #require(model.library.clients.first?.id)
        model.newQuote(for: id)
        let quoteID = try #require(model.openQuoteID)
        #expect(model.library.quote(quoteID)?.clientID == id)
    }

    @Test func theSummaryAddsUpTheClientsWork() throws {
        let model = try UIFixture.sampleModel()
        let bakery = try #require(model.library.clients.first { $0.name == "Example Bakery" }?.id)
        let summary = ClientSummary(library: model.library, clientID: bakery)
        #expect(summary.quotes == 2)
        #expect(summary.invoiced == Money(dollars: 150))
        #expect(summary.paid == .zero)
        #expect(summary.owing == Money(dollars: 150))
    }

    @Test func theClientsScreenDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .clients
        model.selectedClientID = model.library.clients.first?.id
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "clients")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter ClientsTests`
Expected: build failure, `cannot find 'ClientSummary' in scope`.

- [ ] **Step 3: Write `ClientsView.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// Clients: the list on the left, the selected client's details on the right.
struct ClientsView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button("New Client") { model.newClient() }
                        .buttonStyle(.win95)
                    Spacer()
                    Text(DashboardView.count(model.library.clients.count, "client", "clients"))
                        .font(Win95.body)
                        .foregroundStyle(Win95.text)
                }
                DetailsList(model.library.clients, id: \.id, columns: columns, selection: $model.selectedClientID,
                            sort: DetailsSort(column: 0), emptyText: "No clients yet. Press New Client to add one.")
            }
            .frame(minWidth: 360, maxWidth: .infinity)
            if let id = model.selectedClientID, model.library.client(id) != nil {
                ClientForm(model: model, clientID: id)
                    .frame(width: 440)
            } else {
                Text("Select a client to see their details.")
                    .font(Win95.label)
                    .foregroundStyle(Win95.highlight)
                    .frame(width: 440)
                    .frame(maxHeight: .infinity)
                    .background(Win95.desktop)
                    .overlay(Bevel(.sunken))
            }
        }
        .padding(8)
    }

    private var columns: [DetailsColumn<Client>] {
        [
            .text("Name", width: .flexible(min: 160)) { $0.name.isEmpty ? "(no name)" : $0.name },
            .text("Contact", width: .flexible(min: 110)) { $0.contactName },
            .text("Email", width: .flexible(min: 150)) { $0.email },
            .text("Quotes", width: .fixed(70), alignment: .trailing, monospaced: true,
                  sortValue: { client in .number(model.library.quotes.filter { $0.clientID == client.id }.count) }) { client in
                String(model.library.quotes.filter { $0.clientID == client.id }.count)
            },
        ]
    }
}

/// One client's details. Every change saves as you type.
struct ClientForm: View {
    let model: AppModel
    let clientID: UUID

    var body: some View {
        let client = model.clientBinding(clientID)
        let summary = ClientSummary(library: model.library, clientID: clientID)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Client") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95FieldRow("Business:") { Win95TextField("Business name", text: client.name) }
                        Win95FieldRow("Contact:") { Win95TextField("Contact name", text: client.contactName) }
                        Win95FieldRow("Email:") { Win95TextField("Email", text: client.email) }
                        if !client.wrappedValue.email.isEmpty, !client.wrappedValue.email.contains("@") {
                            NoteBanner("That doesn't look like an email address.", warning: true)
                        }
                        Win95FieldRow("Phone:") { Win95TextField("Phone", text: client.phone) }
                        Win95FieldRow("Address:") { Win95TextEditor(text: client.address).frame(height: 54) }
                    }
                }
                GroupBox("Notes") {
                    Win95TextEditor(text: client.notes)
                        .frame(height: 80)
                }
                GroupBox("Work") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win95FieldRow("Quotes:") { Text(String(summary.quotes)).font(Win95.money) }
                        Win95FieldRow("Invoiced:") { Text(model.money(summary.invoiced)).font(Win95.money) }
                        Win95FieldRow("Paid:") { Text(model.money(summary.paid)).font(Win95.money) }
                        Win95FieldRow("Owing:") { Text(model.money(summary.owing)).font(Win95.money) }
                        Button("New Quote for This Client") { model.newQuote(for: clientID) }
                            .buttonStyle(.win95)
                    }
                    .foregroundStyle(Win95.text)
                }
            }
            .padding(.trailing, 6)
        }
        .groupBoxStyle(.win95)
    }
}

/// What a client has been quoted, invoiced and paid. Draft and void invoices don't count.
struct ClientSummary: Equatable {
    var quotes: Int
    var invoiced: Money
    var paid: Money
    var owing: Money

    init(library: Library, clientID: UUID) {
        quotes = library.quotes.filter { $0.clientID == clientID }.count
        let sent = library.invoices.filter { $0.clientID == clientID && $0.stage == .sent }
        invoiced = sent.reduce(.zero) { $0 + $1.amount }
        paid = sent.reduce(.zero) { $0 + $1.paid }
        owing = sent.reduce(.zero) { $0 + max($1.owing, .zero) }
    }
}
```

In `RootView.sectionContent`, replace `case .clients: SectionPlaceholder(section: .clients)` with:

```swift
        case .clients: ClientsView(model: model)
```

- [ ] **Step 4: Run the tests and look at the screen**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter ClientsTests`
Expected: all four tests pass.

Look at `build/snapshots/clients.png`. The list should be sorted by name, and the selected client's
form should show sunken fields, the Notes box, and the Work figures.

- [ ] **Step 5: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests/ClientsTests.swift
git commit -m "Add the Clients screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Quotes: the list and the editor with a live PDF preview

**Files:**
- Create: `Sources/QuotePilotUI/Screens/FieldParser.swift`
- Create: `Sources/QuotePilotUI/Screens/QuotesView.swift`
- Create: `Sources/QuotePilotUI/Screens/QuoteEditorView.swift`
- Modify: `Sources/QuotePilotUI/Screens/PDFPreview.swift` (add the preview views)
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (show Quotes)
- Test: `Tests/QuotePilotUITests/FieldParserTests.swift`
- Test: `Tests/QuotePilotUITests/QuotesTests.swift`

**Interfaces:**
- Consumes:
  - from Task 5: `AppModel.quoteBinding(_:)`, `updateQuote`, `newQuote`, `openQuote`,
    `duplicateQuote`, `deleteDraftQuote`, `quoteContent`, `pdf`, `exportPDF`, `confirm`;
  - from Task 6: `NoteBanner`, `EtchedLine`;
  - from Task 7: `StatusLabel.cell`, `DashboardView.count`;
  - from Task 2: `PixelGlyph`.
- Produces:
  - **Parsing:** `FieldParser.money/quantity/days/hex(_:)` and `FieldParser.quantityText(_:)`.
  - **Fields:**
    - `CommitField(label:value:format:parse:alignment:commit:)`. It commits on Return or when you
      leave the field, puts the stored value back when the text doesn't parse, and beeps;
    - `DayPicker(label:day:)` and `ClientPicker(clients:selection:)`.
  - **Previews:** `PDFPreview(data:)`, `LivePDFPreview(model:content:)` and `PreviewKey`.
  - **Screens:** `QuotesView(model:)`, `QuoteListView`, `QuoteEditorView(model:quoteID:)`,
    `LinesEditor`, `LineRow` and `QuoteRow`.
  - **Small parts:** `SquareButton`, and `QuotePilotCore.Unit.label`.

`QuotePilotCore.Unit` clashes with Foundation's `Unit` class, so write it out in full in the UI
module.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/FieldParserTests.swift`:

```swift
import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@Suite struct FieldParserTests {
    @Test func moneyTakesWhatPeopleType() {
        #expect(FieldParser.money("1500") == Money(dollars: 1500))
        #expect(FieldParser.money("$1,500.50") == Money(dollars: 1500, cents: 50))
        #expect(FieldParser.money(" 90 ") == Money(dollars: 90))
        #expect(FieldParser.money("-20") == Money(dollars: -20))
    }

    @Test func moneyRefusesHalfTypedAndNonsense() {
        for text in ["", "$", "abc", "1.2.3", "$-", "12abc"] {
            #expect(FieldParser.money(text) == nil, "\(text)")
        }
    }

    @Test func quantityTakesUpToTwoDecimalPlaces() {
        #expect(FieldParser.quantity("1") == 1)
        #expect(FieldParser.quantity("1.5") == Decimal(string: "1.5"))
        #expect(FieldParser.quantity("0.25") == Decimal(string: "0.25"))
        #expect(FieldParser.quantity("0") == 0)
    }

    @Test func quantityRefusesHalfTypedAndNonsense() {
        for text in ["", "1.", ".5", "-1", "1.234", "1e3", "abc", "1,5", "100001"] {
            #expect(FieldParser.quantity(text) == nil, "\(text)")
        }
    }

    @Test func daysAreWholeNumbersUpToAYear() {
        #expect(FieldParser.days("14") == 14)
        #expect(FieldParser.days("0") == 0)
        for text in ["", "-1", "1.5", "366", "two"] {
            #expect(FieldParser.days(text) == nil, "\(text)")
        }
    }

    @Test func coloursAreSixHexDigits() {
        #expect(FieldParser.hex("0b6b66") == "#0B6B66")
        #expect(FieldParser.hex("#C00000") == "#C00000")
        for text in ["", "#12345", "zzzzzz", "#1234567", "##0B6B66"] {
            #expect(FieldParser.hex(text) == nil, "\(text)")
        }
    }

    @Test func quantitiesShowWithoutTrailingZeros() {
        #expect(FieldParser.quantityText(Decimal(string: "1.5")!) == "1.5")
        #expect(FieldParser.quantityText(2) == "2")
    }
}
```

`Tests/QuotePilotUITests/QuotesTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct QuotesTests {
    @Test func theEditorRevertsARefusedEdit() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        let quote = model.quoteBinding(quoteID)
        quote.wrappedValue.lines[0].rate = Money(dollars: 999)
        #expect(quote.wrappedValue.lines[0].rate == Money(dollars: 600))
        #expect(model.message?.text == LibraryError.alreadyInvoiced.message)
    }

    @Test func wordingStillChangesOnAnInvoicedQuote() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        model.quoteBinding(quoteID).wrappedValue.title = "Renamed job"
        #expect(model.library.quote(quoteID)?.title == "Renamed job")
        #expect(model.message == nil)
    }

    @Test func aDraftsLineIDsFollowTheOrderAfterAMove() throws {
        let model = try UIFixture.model()
        model.newQuote()
        let id = try #require(model.openQuoteID)
        let binding = model.quoteBinding(id)
        var quote = binding.wrappedValue
        quote.addLine(LineItem(title: "First", rate: Money(dollars: 100)))
        quote.addLine(LineItem(title: "Second", rate: Money(dollars: 200)))
        binding.wrappedValue = quote
        var moved = binding.wrappedValue
        moved.lines.swapAt(0, 1)
        binding.wrappedValue = moved
        #expect(binding.wrappedValue.lines.map(\.title) == ["Second", "First"])
        #expect(binding.wrappedValue.lines.map(\.code) == ["01", "02"])
    }

    @Test func listRowsShowClientStatusAndTotal() throws {
        let model = try UIFixture.sampleModel()
        let rows = model.library.quotes.map { QuoteRow($0, library: model.library, today: model.today) }
        #expect(rows.map(\.client) == ["Sample Client Pty Ltd", "Example Bakery", "Acme Test Co", "Example Bakery"])
        #expect(rows.map(\.status) == [.accepted(partly: true), .sent, .expired, .draft])
        #expect(rows[1].total == Money(dollars: 620))
    }

    @Test func theQuoteListDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .quotes
        model.selectedQuoteID = model.library.quotes[1].id
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quotes")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theQuoteEditorDraws() throws {
        let model = try UIFixture.sampleModel()
        model.openQuote(model.library.quotes[0].id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quote-editor")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter "FieldParserTests|QuotesTests"`
Expected: build failure, `cannot find 'FieldParser' in scope`.

- [ ] **Step 3: Write `FieldParser.swift`**

```swift
import Foundation
import QuotePilotCore

/// Reads what someone typed into a number field. Anything that isn't a whole, sensible value gives
/// nil, so half-typed or mistyped text never replaces what's stored.
enum FieldParser {
    /// "$1,500.50", "1500", "-20" (a discount line). Rounds to the cent.
    static func money(_ text: String) -> Money? {
        Money(parsing: text.trimmingCharacters(in: .whitespaces))
    }

    /// "1", "1.5", "0.25": zero or more, with at most two decimal places (what documents print).
    static func quantity(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              !parts[0].isEmpty,
              parts.allSatisfy({ part in part.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.count == 1 || (1...2).contains(parts[1].count),
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              value <= 100_000
        else { return nil }
        return value
    }

    /// A whole number of days from 0 to 365.
    static func days(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(trimmed), (0...365).contains(value)
        else { return nil }
        return value
    }

    /// "#0b6b66" or "0B6B66" → "#0B6B66".
    static func hex(_ text: String) -> String? {
        var digits = Substring(text.trimmingCharacters(in: .whitespaces))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.uppercased()
    }

    /// "1.5", "2": a quantity as a field shows it.
    static func quantityText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
```

- [ ] **Step 4: Add the previews to `PDFPreview.swift`**

Add `import AppKit`, `import PDFKit`, `import QuotePilotCore` and `import QuotePilotPDF` at the top,
then add:

```swift
/// PDF data in a PDFView on Windows 95 grey, the page fitted to the width.
struct PDFPreview: NSViewRepresentable {
    let data: Data?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor(Win95.shadow)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.shown != data else { return }
        context.coordinator.shown = data
        view.document = data.flatMap(PDFDocument.init(data:))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var shown: Data?
    }
}

/// What a preview shows. The brand counts too, because the logo, font and colour aren't in the
/// document's content.
struct PreviewKey: Equatable {
    var content: DocumentContent?
    var brand: Brand
}

/// A preview that redraws itself shortly after the document or the brand changes.
struct LivePDFPreview: View {
    let model: AppModel
    let content: DocumentContent?
    @State private var pdf: Data?

    var body: some View {
        PDFPreview(data: pdf)
            .overlay(Bevel(.sunken))
            .task(id: PreviewKey(content: content, brand: model.library.brand)) {
                // Wait for a pause in typing before redrawing, except the first time.
                if pdf != nil {
                    try? await Task.sleep(for: .milliseconds(300))
                    if Task.isCancelled { return }
                }
                pdf = content.map(model.pdf)
            }
    }
}
```

- [ ] **Step 5: Write `QuotesView.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// Quotes: the list, or the editor when a quote is open.
struct QuotesView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let id = model.openQuoteID, model.library.quote(id) != nil {
            QuoteEditorView(model: model, quoteID: id)
        } else {
            QuoteListView(model: model)
        }
    }
}

/// One quote as the list shows it.
struct QuoteRow: Identifiable {
    let id: UUID
    let number: String
    let client: String
    let title: String
    let issued: Day
    let status: QuoteStatus
    let total: Money

    init(_ quote: Quote, library: Library, today: Day) {
        id = quote.id
        number = quote.number
        client = library.client(quote.clientID)?.name ?? "No client"
        title = quote.title
        issued = quote.issued
        status = quote.status(on: today)
        total = quote.totals.total
    }
}

struct QuoteListView: View {
    @Bindable var model: AppModel

    var body: some View {
        let rows = model.library.quotes.map { QuoteRow($0, library: model.library, today: model.today) }
        let selected = model.selectedQuoteID.flatMap { model.library.quote($0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button("New Quote") { model.newQuote() }
                    .buttonStyle(.win95)
                Button("Open") { if let selected { model.openQuote(selected.id) } }
                    .buttonStyle(.win95)
                    .disabled(selected == nil)
                Button("Duplicate") { if let selected { model.duplicateQuote(selected.id) } }
                    .buttonStyle(.win95)
                    .disabled(selected == nil)
                Button("Delete Draft") { if let selected { model.deleteDraftQuote(selected.id) } }
                    .buttonStyle(.win95)
                    .disabled(selected?.stage != .draft)
                Spacer()
                Text(DashboardView.count(rows.count, "quote", "quotes"))
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
            }
            DetailsList(rows, id: \.id, columns: columns, selection: $model.selectedQuoteID,
                        sort: DetailsSort(column: 0, ascending: false),
                        emptyText: "No quotes yet. Press New Quote (⌘N) to write one.",
                        onOpen: { model.openQuote($0) },
                        rowMenu: { id in AnyView(menu(id)) })
        }
        .padding(8)
    }

    private var columns: [DetailsColumn<QuoteRow>] {
        [
            .text("Quote", width: .fixed(80)) { $0.number },
            .text("Client", width: .flexible(min: 140)) { $0.client },
            .text("Title", width: .flexible(min: 140)) { $0.title },
            .day("Issued") { $0.issued },
            DetailsColumn("Status", width: .fixed(150), sortValue: { .text($0.status.label) }) { row, selected in
                StatusLabel.cell(row.status, selected: selected)
            },
            .money("Total", currencyCode: model.currencyCode) { $0.total },
        ]
    }

    @ViewBuilder
    private func menu(_ id: UUID) -> some View {
        Button("Open") { model.openQuote(id) }
        Button("Duplicate") { model.duplicateQuote(id) }
        if model.library.quote(id)?.stage == .draft {
            Divider()
            Button("Delete Draft…") { model.deleteDraftQuote(id) }
        }
    }
}
```

- [ ] **Step 6: Write `QuoteEditorView.swift`**

```swift
import AppKit
import QuotePilotCore
import SwiftUI

/// One quote: the form on the left, its PDF on the right. Text saves as you type; amounts and
/// quantities save when you press Return or leave the field.
struct QuoteEditorView: View {
    let model: AppModel
    let quoteID: UUID

    var body: some View {
        let quote = model.quoteBinding(quoteID)
        let current = quote.wrappedValue
        VStack(spacing: 0) {
            header(current)
            HStack(alignment: .top, spacing: 8) {
                ScrollView {
                    form(quote)
                        .padding(.trailing, 6)
                }
                .frame(minWidth: 560, idealWidth: 620, maxWidth: 720)
                GroupBox("Preview") {
                    LivePDFPreview(model: model, content: model.quoteContent(quoteID))
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
        }
        .groupBoxStyle(.win95)
    }

    private func header(_ quote: Quote) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button("All Quotes") { model.openQuoteID = nil }
                .buttonStyle(.win95)
                .help("Back to the list of quotes")
            PixelIconView(.quote, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quote \(quote.number)")
                    .font(Win95.title)
                    .foregroundStyle(Win95.text)
                StatusLabel.cell(quote.status(on: model.today), selected: false)
            }
            Spacer()
            Button("Duplicate") { model.duplicateQuote(quoteID) }
                .buttonStyle(.win95)
            if quote.stage == .draft {
                Button("Delete Draft") { model.deleteDraftQuote(quoteID) }
                    .buttonStyle(.win95)
            }
            Button("Save PDF…") { model.exportPDF() }
                .buttonStyle(.win95)
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
        .background(Win95.face)
        .overlay(alignment: .bottom) { EtchedLine() }
    }

    private func form(_ quote: Binding<Quote>) -> some View {
        let current = quote.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            if current.stage != .draft {
                NoteBanner("This quote has been sent. Changes here change Quote Pilot's copy, not the PDF your client already has.")
            }
            GroupBox("Quote") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Client:") { ClientPicker(clients: model.library.clients, selection: quote.clientID) }
                    Win95FieldRow("Title:") {
                        Win95TextField("Title", text: quote.title, prompt: "e.g. Website rebuild, phase 1")
                    }
                    Win95FieldRow("Issued:") { DayPicker(label: "Issued", day: quote.issued) }
                    Win95FieldRow("Valid until:") { DayPicker(label: "Valid until", day: quote.validUntil) }
                    Win95FieldRow("Payment:") {
                        Win95RadioGroup(selection: quote.plan, options: PaymentPlan.allCases.map { ($0, $0.summary) })
                    }
                    if model.library.brand.gstRegistered || current.taxed {
                        Win95FieldRow("GST:") { Toggle("Add GST (10%)", isOn: quote.taxed).toggleStyle(.win95) }
                    }
                }
            }
            GroupBox("Lines") {
                LinesEditor(model: model, quote: quote)
            }
            GroupBox("Work summary") {
                VStack(alignment: .leading, spacing: 4) {
                    Win95TextEditor(text: quote.summary)
                        .frame(height: 90)
                    Text("Lines starting with \"- \" print as dot points.")
                        .font(Win95.small)
                        .foregroundStyle(Win95.text)
                }
            }
            GroupBox("Terms") {
                Win95TextEditor(text: quote.terms)
                    .frame(height: 60)
            }
        }
    }
}

/// The quote's lines, each with its ID, wording, quantity, unit, rate and amount, plus totals.
struct LinesEditor: View {
    let model: AppModel
    @Binding var quote: Quote

    var body: some View {
        let currency = model.currencyCode
        let showDecision = quote.stage == .accepted || quote.stage == .declined
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                columnHead("ID", width: 28)
                columnHead("Item", width: nil)
                columnHead("Qty", width: 56)
                columnHead("Unit", width: 80)
                columnHead("Rate", width: 96)
                columnHead("Amount", width: 96, trailing: true)
                Spacer().frame(width: 3 * 20 + 2 * 4)
            }
            ForEach(Array(quote.lines.enumerated()), id: \.element.id) { index, line in
                LineRow(line: lineBinding(line.id), currency: currency, showDecision: showDecision,
                        canMoveUp: index > 0, canMoveDown: index < quote.lines.count - 1,
                        move: { move(line.id, by: $0) }, remove: { remove(line) })
            }
            if quote.lines.isEmpty {
                Text("No lines yet. Add one for each piece of work the client can tick.")
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
            }
            HStack(alignment: .top) {
                Button("Add Line") { add() }
                    .buttonStyle(.win95)
                Spacer()
                totals(currency)
            }
            .padding(.top, 4)
        }
    }

    private func columnHead(_ title: String, width: CGFloat?, trailing: Bool = false) -> some View {
        Text(title)
            .font(Win95.label)
            .foregroundStyle(Win95.text)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func totals(_ currency: String) -> some View {
        let totals = quote.totals
        return Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
            if quote.taxed {
                GridRow {
                    Text("Subtotal")
                    Text(totals.subtotal.formatted(currencyCode: currency)).font(Win95.money)
                }
                GridRow {
                    Text("GST (10%)")
                    Text(totals.gst.formatted(currencyCode: currency)).font(Win95.money)
                }
            }
            GridRow {
                Text("Total").font(Win95.label)
                Text(totals.total.formatted(currencyCode: currency)).font(Win95.money.bold())
            }
        }
        .font(Win95.body)
        .foregroundStyle(Win95.text)
    }

    /// A line found by its identity, so a removed or moved line can never index past the end.
    private func lineBinding(_ id: UUID) -> Binding<LineItem> {
        Binding(
            get: { quote.lines.first { $0.id == id } ?? LineItem(id: id, title: "", rate: .zero) },
            set: { line in
                var edited = quote
                guard let index = edited.lines.firstIndex(where: { $0.id == id }) else { return }
                edited.lines[index] = line
                quote = edited
            })
    }

    private func add() {
        var edited = quote
        edited.addLine(LineItem(title: "", rate: .zero))
        quote = edited
    }

    private func move(_ id: UUID, by offset: Int) {
        var edited = quote
        guard let index = edited.lines.firstIndex(where: { $0.id == id }),
              edited.lines.indices.contains(index + offset)
        else { return }
        edited.lines.swapAt(index, index + offset)
        quote = edited
    }

    private func remove(_ line: LineItem) {
        let name = line.title.isEmpty ? "line \(line.code)" : "line \(line.code), \(line.title)"
        model.confirm(title: "Remove Line", text: "Remove \(name)?", confirm: "Remove") {
            var edited = quote
            edited.lines.removeAll { $0.id == line.id }
            quote = edited
        }
    }
}

struct LineRow: View {
    @Binding var line: LineItem
    let currency: String
    let showDecision: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(line.code)
                    .font(Win95.money)
                    .foregroundStyle(Win95.text)
                    .frame(width: 28, alignment: .leading)
                Win95TextField("Line \(line.code) item", text: $line.title, prompt: "What the work is")
                CommitField(label: "Line \(line.code) quantity", value: line.quantity,
                            format: FieldParser.quantityText, parse: FieldParser.quantity) { line.quantity = $0 }
                    .frame(width: 56)
                Picker("Line \(line.code) unit", selection: $line.unit) {
                    ForEach(QuotePilotCore.Unit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                CommitField(label: "Line \(line.code) rate", value: line.rate,
                            format: { $0.formatted(currencyCode: currency) }, parse: FieldParser.money) { line.rate = $0 }
                    .frame(width: 96)
                Text(line.amount.formatted(currencyCode: currency))
                    .font(Win95.money)
                    .foregroundStyle(Win95.text)
                    .lineLimit(1)
                    .frame(width: 96, alignment: .trailing)
                SquareButton(PixelGlyph.up, label: "Move line \(line.code) up") { move(-1) }
                    .disabled(!canMoveUp)
                SquareButton(PixelGlyph.down, label: "Move line \(line.code) down") { move(1) }
                    .disabled(!canMoveDown)
                SquareButton(PixelGlyph.cross, label: "Remove line \(line.code)", action: remove)
            }
            HStack(spacing: 4) {
                Spacer().frame(width: 32)
                Win95TextField("Line \(line.code) detail", text: $line.detail, prompt: "Detail (optional)")
                if showDecision, let decision = line.decision {
                    StatusLabel(decision == .accepted ? .tick : .cross, decision == .accepted ? "Accepted" : "Declined")
                        .frame(width: 110, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// A number field that only takes text `parse` accepts, when you press Return or leave the field.
/// Anything else beeps and puts the stored value back, so half-typed text never reaches the library.
struct CommitField<Value: Equatable>: View {
    let label: String
    let value: Value
    let format: (Value) -> String
    let parse: (String) -> Value?
    var alignment: TextAlignment = .trailing
    let commit: (Value) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(Win95.money)
            .foregroundStyle(Win95.text)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onSubmit(apply)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { apply() }
            }
            .onChange(of: value) { _, newValue in
                text = format(newValue)
            }
            .onAppear { text = format(value) }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(Win95.field)
            .overlay(Bevel(.sunken))
            .overlay(focused ? FocusRect().padding(3) : nil)
            .accessibilityLabel(label)
    }

    private func apply() {
        if let parsed = parse(text) {
            if parsed != value { commit(parsed) }
        } else if text != format(value) {
            NSSound.beep()
        }
        // The stored value: the new one once the commit lands (onChange), or the old one if refused.
        text = format(value)
    }
}

/// A date field for a `Day`.
struct DayPicker: View {
    let label: String
    @Binding var day: Day

    var body: some View {
        DatePicker(label, selection: Binding(get: { day.date() }, set: { day = Day($0) }), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(maxWidth: 160, alignment: .leading)
    }
}

/// Choose a client, or none. A native pop-up, so it works from the keyboard and with VoiceOver.
struct ClientPicker: View {
    let clients: [Client]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Client", selection: $selection) {
            Text("No client").tag(UUID?.none)
            ForEach(clients.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { client in
                Text(client.name).tag(Optional(client.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 300, alignment: .leading)
    }
}

/// A small square Windows 95 button showing a glyph, for line actions.
struct SquareButton: View {
    let glyph: [String]
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ glyph: [String], label: String, action: @escaping () -> Void) {
        self.glyph = glyph
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PixelGlyph(glyph, color: isEnabled ? Win95.dark : Win95.shadow)
                .frame(width: 7, height: CGFloat(glyph.count))
        }
        .buttonStyle(SquareButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

struct SquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .frame(width: 20, height: 20)
            .background(Win95.face)
            .overlay(Bevel(configuration.isPressed ? .pressed : .raised))
            .contentShape(Rectangle())
    }
}

extension QuotePilotCore.Unit {
    /// The unit as the picker names it.
    var label: String {
        switch self {
        case .hours: return "hours"
        case .days: return "days"
        case .units: return "units"
        }
    }
}
```

In `RootView.sectionContent`, replace `case .quotes: SectionPlaceholder(section: .quotes)` with:

```swift
        case .quotes: QuotesView(model: model)
```

- [ ] **Step 7: Run the tests and look at both screens**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter "FieldParserTests|QuotesTests"`
Expected: all 13 tests pass.

Look at `build/snapshots/quotes.png`: the list newest first, with icon-and-word statuses and Q-0003
"Expired" in red.

Look at `build/snapshots/quote-editor.png`. Check these:
- the header, with the big total of every line ($4,470.00);
- the sent-quote note;
- the form;
- line rows with up, down and remove buttons, and Accepted or Declined under each line.

The PDF preview fills in after a moment, so a snapshot may show it empty. Check the real preview in
Step 8.

- [ ] **Step 8: Try the editor in the real app**

Run `./build.sh`, then:

```bash
demo="$(mktemp -d)/demo"
swift run qp demo "$demo"
QP_LIBRARY_FOLDER="$demo" "build/Quote Pilot.app/Contents/MacOS/Quote Pilot"
```

Check these in the app:
- Open Q-0004. Type a title and see the PDF redraw within about a second.
- Type "abc" into a rate and press Return. It beeps and the old rate comes back.
- Change the rate on Q-0001 line 01, which already has a deposit invoice. A message box explains,
  and the old rate stays.

Quit the app, and report what you saw.

- [ ] **Step 9: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests
git commit -m "Add the quote list and the quote editor with a live PDF preview

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Brand, with property-sheet tabs and a live sample PDF

**Files:**
- Modify: `Sources/QuotePilotUI/Win95/Win95Chrome.swift` (add `PropertyTabs`, `TabEdge`)
- Create: `Sources/QuotePilotUI/Screens/BrandView.swift`
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (show Brand)
- Test: `Tests/QuotePilotUITests/BrandTests.swift`

**Interfaces:**
- Consumes:
  - from Task 5: `AppModel.brandBinding`, `importLogo`, `importHeadingFont`, `removeLogo`,
    `removeHeadingFont`, `logoURL`, `headingFontName`, `sampleContent()` and `show`;
  - from Task 9: `CommitField`, `FieldParser.days/hex` and `LivePDFPreview`;
  - from Task 6: `NoteBanner`;
  - from core: `PDFStyle.color(hex:)`.
- Produces: `PropertyTabs(selection:tabs:content:)`, `BrandView(model:tab:)` with
  `BrandView.Tab` (`.business, .look, .documents, .emails`), plus `LogoWell`, `AccentPicker` and
  `Swatch`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/BrandTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct BrandTests {
    @Test func editingTheBrandSavesIt() throws {
        let model = try UIFixture.sampleModel()
        model.brandBinding.wrappedValue.businessName = "Sample Studio Two"
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.businessName == "Sample Studio Two")
    }

    @Test func theBusinessTabDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .brand
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "brand")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theLookTabDraws() throws {
        let model = try UIFixture.sampleModel()
        let rep = Snapshot.render(BrandView(model: model, tab: .look).background(Win95.face),
                                  size: CGSize(width: 1000, height: 640), name: "brand-look")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter BrandTests`
Expected: build failure, `cannot find 'BrandView' in scope`.

- [ ] **Step 3: Add the tabs to `Win95Chrome.swift`**

```swift
/// Windows 95 property-sheet tabs. The selected tab is taller and joins the panel below it.
public struct PropertyTabs<Tab: Hashable, Content: View>: View {
    @Binding var selection: Tab
    let tabs: [(Tab, String)]
    let content: Content

    public init(selection: Binding<Tab>, tabs: [(Tab, String)], @ViewBuilder content: () -> Content) {
        self._selection = selection
        self.tabs = tabs
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                    tabButton(tab.0, title: tab.1)
                }
            }
            .padding(.leading, 2)
            .zIndex(1)
            content
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Win95.face)
                .overlay(Bevel(.raised))
        }
    }

    private func tabButton(_ tab: Tab, title: String) -> some View {
        let selected = tab == selection
        return Button {
            selection = tab
        } label: {
            Text(title)
                .font(Win95.body)
                .foregroundStyle(Win95.text)
                .padding(.horizontal, selected ? 12 : 10)
                .frame(height: selected ? 24 : 21)
                .background(Win95.face)
                .overlay(TabEdge())
                // The selected tab covers the panel's top edge beneath it, so the two join up.
                .offset(y: selected ? 2 : 0)
        }
        .buttonStyle(.plain)
        .zIndex(selected ? 1 : 0)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A tab's raised edges: left and top lit, right in shadow, and no bottom.
struct TabEdge: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            guard w > 4, h > 2 else { return }
            context.fill(Path(CGRect(x: 0, y: 2, width: 1, height: h - 2)), with: .color(Win95.highlight))
            context.fill(Path(CGRect(x: 1, y: 1, width: 1, height: 1)), with: .color(Win95.highlight))
            context.fill(Path(CGRect(x: 2, y: 0, width: w - 4, height: 1)), with: .color(Win95.highlight))
            context.fill(Path(CGRect(x: w - 2, y: 1, width: 1, height: 1)), with: .color(Win95.dark))
            context.fill(Path(CGRect(x: w - 1, y: 2, width: 1, height: h - 2)), with: .color(Win95.dark))
            context.fill(Path(CGRect(x: w - 2, y: 2, width: 1, height: h - 2)), with: .color(Win95.shadow))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4: Write `BrandView.swift`**

```swift
import AppKit
import QuotePilotCore
import QuotePilotPDF
import SwiftUI
import UniformTypeIdentifiers

/// Brand: everything documents carry about the business, on four tabs, beside a sample quote that
/// redraws as you change things.
struct BrandView: View {
    enum Tab: Hashable {
        case business, look, documents, emails
    }

    let model: AppModel
    @State private var tab: Tab

    init(model: AppModel, tab: Tab = .business) {
        self.model = model
        self._tab = State(initialValue: tab)
    }

    var body: some View {
        let brand = model.brandBinding
        HStack(alignment: .top, spacing: 8) {
            PropertyTabs(selection: $tab, tabs: [(.business, "Business"), (.look, "Look"),
                                                 (.documents, "Documents"), (.emails, "Emails")]) {
                ScrollView {
                    Group {
                        switch tab {
                        case .business: BusinessTab(brand: brand)
                        case .look: LookTab(model: model, brand: brand)
                        case .documents: DocumentsTab(brand: brand)
                        case .emails: EmailsTab(brand: brand)
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
            .frame(minWidth: 460, idealWidth: 520, maxWidth: 600)
            GroupBox("Sample quote") {
                LivePDFPreview(model: model, content: model.sampleContent())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .groupBoxStyle(.win95)
    }
}

struct BusinessTab: View {
    @Binding var brand: Brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Business") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Name:") { Win95TextField("Business name", text: $brand.businessName) }
                    Win95FieldRow("Details:") { Win95TextEditor(text: $brand.details).frame(height: 70) }
                    Text("Address, email, phone and website, one per line. They print under your name.")
                        .font(Win95.small)
                    Win95FieldRow("ABN:") { Win95TextField("ABN", text: $brand.abn) }
                }
            }
            GroupBox("Payment details") {
                VStack(alignment: .leading, spacing: 4) {
                    Win95TextEditor(text: $brand.paymentDetails)
                        .frame(height: 54)
                    Text("Bank, BSB and account, or PayID. Printed on invoices.")
                        .font(Win95.small)
                }
            }
            GroupBox("GST") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Registered for GST", isOn: $brand.gstRegistered)
                        .toggleStyle(.win95)
                    Text("Off: no GST anywhere. On: new quotes add 10% GST, and invoices say Tax invoice and show your ABN.")
                        .font(Win95.small)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(Win95.text)
    }
}

struct LookTab: View {
    let model: AppModel
    @Binding var brand: Brand
    @State private var choosingLogo = false
    @State private var choosingFont = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Logo") {
                HStack(alignment: .center, spacing: 10) {
                    LogoWell(url: model.logoURL)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(brand.logoFile == nil ? "No logo yet." : "Shown at the top of every document.")
                            .font(Win95.body)
                        HStack(spacing: 6) {
                            Button("Choose…") { choosingLogo = true }
                                .buttonStyle(.win95)
                            Button("Remove") { model.removeLogo() }
                                .buttonStyle(.win95)
                                .disabled(brand.logoFile == nil)
                        }
                        Text("PNG, JPG or PDF. A PDF logo stays sharp at any size.")
                            .font(Win95.small)
                    }
                }
                .fileImporter(isPresented: $choosingLogo, allowedContentTypes: [.png, .jpeg, .pdf]) { result in
                    use(result, model.importLogo)
                }
            }
            GroupBox("Heading font") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.headingFontName ?? "The system font (no heading font chosen).")
                        .font(Win95.body)
                    HStack(spacing: 6) {
                        Button("Choose…") { choosingFont = true }
                            .buttonStyle(.win95)
                        Button("Remove") { model.removeHeadingFont() }
                            .buttonStyle(.win95)
                            .disabled(brand.headingFontFile == nil)
                    }
                    Text("A TTF or OTF file, used for document titles and headings.")
                        .font(Win95.small)
                }
                .fileImporter(isPresented: $choosingFont, allowedContentTypes: [.font]) { result in
                    use(result, model.importHeadingFont)
                }
            }
            GroupBox("Accent colour") {
                AccentPicker(hex: $brand.accentHex)
            }
        }
        .foregroundStyle(Win95.text)
    }

    private func use(_ result: Result<URL, Error>, _ importFile: (URL) -> Void) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importFile(url)
        case .failure(let error):
            model.show(error, title: "Couldn't open that file")
        }
    }
}

/// The logo in a sunken well, or "No logo".
struct LogoWell: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text("No logo")
                    .font(Win95.small)
                    .foregroundStyle(Win95.text)
            }
        }
        .padding(4)
        .frame(width: 96, height: 64)
        .win95Sunken()
    }
}

/// The documents' accent colour: a hex field, its swatch, and a few ready-made choices.
struct AccentPicker: View {
    @Binding var hex: String
    /// Document colours, not window colours: these go on the client's PDFs.
    private static let presets = ["#0B6B66", "#1F2A44", "#7A1F2B", "#2E6B30", "#5B3F8C", "#B85C00"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Swatch(hex: hex)
                    .frame(width: 28, height: 22)
                CommitField(label: "Accent colour", value: hex, format: { $0 }, parse: FieldParser.hex,
                            alignment: .leading) { hex = $0 }
                    .frame(width: 100)
                Text("Six hex digits, like #0B6B66.")
                    .font(Win95.small)
            }
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button { hex = preset } label: {
                        Swatch(hex: preset)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(preset)")
                    .help(preset)
                }
            }
        }
    }
}

struct Swatch: View {
    let hex: String

    var body: some View {
        Rectangle()
            .fill(PDFStyle.color(hex: hex).map { Color(cgColor: $0) } ?? Win95.field)
            .overlay(Bevel(.sunken))
            .accessibilityHidden(true)
    }
}

struct DocumentsTab: View {
    @Binding var brand: Brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Quotes") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Valid for:") {
                        HStack(spacing: 6) {
                            CommitField(label: "Quotes are valid for, in days", value: brand.quoteValidDays,
                                        format: { String($0) }, parse: FieldParser.days) { brand.quoteValidDays = $0 }
                                .frame(width: 60)
                            Text("days")
                        }
                    }
                    Text("Terms printed on quotes:")
                    Win95TextEditor(text: $brand.quoteTerms)
                        .frame(height: 60)
                }
            }
            GroupBox("Invoices") {
                VStack(alignment: .leading, spacing: 6) {
                    Win95FieldRow("Payment due:") {
                        HStack(spacing: 6) {
                            CommitField(label: "Payment is due after, in days", value: brand.paymentDueDays,
                                        format: { String($0) }, parse: FieldParser.days) { brand.paymentDueDays = $0 }
                                .frame(width: 60)
                            Text("days")
                        }
                    }
                    Text("Terms printed on invoices:")
                    Win95TextEditor(text: $brand.invoiceTerms)
                        .frame(height: 60)
                }
            }
            GroupBox("Currency") {
                Text("Australian dollars (\(brand.currencyCode))")
            }
        }
        .font(Win95.body)
        .foregroundStyle(Win95.text)
    }
}

struct EmailsTab: View {
    @Binding var brand: Brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NoteBanner("Quote Pilot fills in {client}, {contact}, {number}, {amount}, {due} and {business}. Mail drafts arrive in the next build, and you always press Send yourself.")
            template("Quote email", $brand.emails.quote)
            template("Invoice email", $brand.emails.invoice)
            template("Receipt email", $brand.emails.receipt)
        }
    }

    private func template(_ title: String, _ template: Binding<EmailTemplate>) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                Win95FieldRow("Subject:", labelWidth: 64) {
                    Win95TextField("\(title) subject", text: template.subject)
                }
                Win95TextEditor(text: template.body)
                    .frame(height: 110)
            }
        }
    }
}
```

In `RootView.sectionContent`, replace `case .brand: SectionPlaceholder(section: .brand)` with:

```swift
        case .brand: BrandView(model: model)
```

- [ ] **Step 5: Run the tests and look at the tabs**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter BrandTests`
Expected: all three tests pass.

Look at `build/snapshots/brand.png` and `brand-look.png`. The selected tab should be raised and
joined to the panel, with group boxes inside. `brand-look.png` should show the logo well, the font
line, the accent swatch with its hex field, and six preset swatches.

- [ ] **Step 6: Try a logo in the real app**

With the demo library from Task 9 Step 8, open Brand → Look → Choose… and pick any PNG on this Mac.
The logo should appear in the well and on the sample quote. Then choose a text file renamed to `.png`:
a "Not an Image" message box should appear, and the logo shouldn't change. Report both.

- [ ] **Step 7: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests/BrandTests.swift
git commit -m "Add the Brand screen with property-sheet tabs and a live sample PDF

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Invoices (read-only for now) and Activity

The invoice editor, payments and receipts come in plan 2b. This task lists invoices with a preview,
so the sample business's invoices (and later real ones) can be seen and saved as PDFs. It also adds
the Activity log, and removes the last placeholders.

**Files:**
- Create: `Sources/QuotePilotUI/Screens/InvoicesView.swift`
- Create: `Sources/QuotePilotUI/Screens/ActivityView.swift`
- Modify: `Sources/QuotePilotUI/App/AppModel.swift` (add `openDocument(number:)`)
- Modify: `Sources/QuotePilotUI/App/RootView.swift` (show both; delete `SectionPlaceholder`)
- Test: `Tests/QuotePilotUITests/InvoicesAndActivityTests.swift`

**Interfaces:**
- Consumes: `AppModel.invoiceContent`, `selectedInvoiceID`, `openQuote`, `openInvoice` (Task 5);
  `LivePDFPreview` (Task 9); `StatusLabel.cell` (Task 7).
- Produces:
  - `InvoicesView(model:)` and `InvoiceRow`;
  - `ActivityView(model:)` and `ActivityView.when(_:)`;
  - `AppModel.openDocument(number:)`;
  - `InvoiceKind.columnLabel`.

- [ ] **Step 1: Write the failing tests**

`Tests/QuotePilotUITests/InvoicesAndActivityTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct InvoicesAndActivityTests {
    @Test func invoiceRowsShowKindStatusAndWhatsOwing() throws {
        let model = try UIFixture.sampleModel()
        let rows = model.library.invoices.map { InvoiceRow($0, library: model.library, today: model.today) }
        #expect(rows.map(\.number) == ["INV-0001", "INV-0002", "INV-0003"])
        #expect(rows.map(\.kind) == ["Deposit", "One-off", "One-off"])
        #expect(rows.map(\.status) == [.paid, .overdue(daysLate: 5), .partPaid])
        #expect(rows.map(\.owing) == [.zero, Money(dollars: 150), Money(dollars: 135)])
    }

    @Test func aVoidInvoiceOwesNothing() throws {
        var library = try SampleLibrary.make(today: UIFixture.today)
        let care = try #require(library.invoices.first { $0.number == "INV-0002" })
        try library.voidInvoice(care.id)
        let row = InvoiceRow(try #require(library.invoice(care.id)), library: library, today: UIFixture.today)
        #expect(row.status == .void)
        #expect(row.owing == .zero)
    }

    @Test func openingAnActivityEntryOpensItsDocument() throws {
        let model = try UIFixture.sampleModel()
        model.openDocument(number: "INV-0002")
        #expect(model.section == .invoices)
        #expect(model.selectedInvoiceID == model.library.invoices.first { $0.number == "INV-0002" }?.id)
        model.openDocument(number: "Q-0002")
        #expect(model.section == .quotes)
        #expect(model.openQuoteID == model.library.quote(number: "Q-0002")?.id)
    }

    @Test func theInvoicesScreenDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .invoices
        model.selectedInvoiceID = model.library.invoices[1].id
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "invoices")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theActivityScreenDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .activity
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "activity")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `swift test --filter InvoicesAndActivityTests`
Expected: build failure, `cannot find 'InvoiceRow' in scope`.

- [ ] **Step 3: Add `openDocument(number:)` to `AppModel` (under `// MARK: Going places`)**

```swift
    /// Opens the quote or invoice with this number, as Activity's double-click does.
    public func openDocument(number: String) {
        if let quote = library.quote(number: number) {
            openQuote(quote.id)
        } else if let invoice = library.invoices.first(where: { $0.number.caseInsensitiveCompare(number) == .orderedSame }) {
            openInvoice(invoice.id)
        }
    }
```

- [ ] **Step 4: Write `InvoicesView.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// Invoices: the list, with the selected invoice's PDF beside it. Editing arrives in plan 2b.
struct InvoicesView: View {
    @Bindable var model: AppModel

    var body: some View {
        let rows = model.library.invoices.map { InvoiceRow($0, library: model.library, today: model.today) }
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                NoteBanner("Invoices are drafted from accepted quotes. Drafting, sending and recording payments arrive in the next build.")
                DetailsList(rows, id: \.id, columns: columns, selection: $model.selectedInvoiceID,
                            sort: DetailsSort(column: 0, ascending: false),
                            emptyText: "No invoices yet.")
            }
            .frame(minWidth: 560, maxWidth: .infinity)
            GroupBox("Preview") {
                if let id = model.selectedInvoiceID, model.library.invoice(id) != nil {
                    LivePDFPreview(model: model, content: model.invoiceContent(id))
                } else {
                    Text("Select an invoice to see it.")
                        .font(Win95.label)
                        .foregroundStyle(Win95.highlight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Win95.desktop)
                        .overlay(Bevel(.sunken))
                }
            }
            .frame(minWidth: 320, maxWidth: 520, maxHeight: .infinity)
        }
        .padding(8)
        .groupBoxStyle(.win95)
    }

    private var columns: [DetailsColumn<InvoiceRow>] {
        [
            .text("Invoice", width: .fixed(80)) { $0.number },
            .text("Client", width: .flexible(min: 120)) { $0.client },
            .text("Kind", width: .fixed(76)) { $0.kind },
            .day("Due") { $0.due },
            DetailsColumn("Status", width: .fixed(130), sortValue: { .text($0.status.listLabel) }) { row, selected in
                StatusLabel.cell(row.status, selected: selected)
            },
            .money("Amount", width: 100, currencyCode: model.currencyCode) { $0.amount },
            .money("Owing", width: 100, currencyCode: model.currencyCode) { $0.owing },
        ]
    }
}

/// One invoice as the list shows it. A void invoice owes nothing.
struct InvoiceRow: Identifiable {
    let id: UUID
    let number: String
    let client: String
    let kind: String
    let due: Day
    let status: InvoiceStatus
    let amount: Money
    let owing: Money

    init(_ invoice: Invoice, library: Library, today: Day) {
        id = invoice.id
        number = invoice.number
        client = library.client(invoice.clientID)?.name ?? "No client"
        kind = invoice.kind.columnLabel
        due = invoice.due
        status = invoice.status(on: today)
        amount = invoice.amount
        owing = invoice.stage == .void ? .zero : max(invoice.owing, .zero)
    }
}

extension InvoiceKind {
    var columnLabel: String {
        switch self {
        case .deposit: return "Deposit"
        case .final: return "Final"
        case .full: return "Full"
        case .standalone: return "One-off"
        }
    }
}
```

- [ ] **Step 5: Write `ActivityView.swift`**

```swift
import QuotePilotCore
import SwiftUI

/// Everything that has happened, newest first. Double-click an entry to open its quote or invoice.
struct ActivityView: View {
    let model: AppModel
    @State private var selection: UUID?

    var body: some View {
        DetailsList(model.library.activity, id: \.id, columns: [
            .text("When", width: .fixed(180), sortValue: { .number(Int($0.at.timeIntervalSince1970)) }) { Self.when($0.at) },
            .text("Number", width: .fixed(90)) { $0.number ?? "" },
            .text("What happened", width: .flexible(min: 240)) { $0.message },
        ], selection: $selection, sort: DetailsSort(column: 0, ascending: false),
        emptyText: "Nothing has happened yet. Every change you make is noted here.",
        onOpen: { id in
            if let number = model.library.activity.first(where: { $0.id == id })?.number {
                model.openDocument(number: number)
            }
        })
        .padding(8)
    }

    /// "15 Oct 2026, 2:41 pm"
    static func when(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_AU")))
    }
}
```

In `RootView.sectionContent`, replace the last two placeholder lines with:

```swift
        case .invoices: InvoicesView(model: model)
        case .activity: ActivityView(model: model)
```

Then delete `SectionPlaceholder` from `RootView.swift`. No section uses it any more.

- [ ] **Step 6: Run the tests and look at both screens**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test --filter InvoicesAndActivityTests`
Expected: all five tests pass.

Look at `build/snapshots/invoices.png`. INV-0002 should be selected with "Overdue 5 d", and the
statuses should read Paid, Overdue 5 d and Part paid. Look at `activity.png`: the sample business's
history, newest first.

- [ ] **Step 7: Run all tests and commit**

Run: `swift test`
Expected: everything passes.

```bash
git add Sources/QuotePilotUI Tests/QuotePilotUITests/InvoicesAndActivityTests.swift
git commit -m "Add the invoice list with preview, and the Activity log

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: README, a final build, and a look at the real app

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: an up-to-date README, a fresh `build/Quote Pilot.app`, and a set of snapshot PNGs in
  `build/snapshots/` for the controller to send to the user.

- [ ] **Step 1: Update `README.md`**

Change the **Status** paragraph to:

```markdown
**Status:** in progress. The business rules, the PDFs and the first half of the Mac app are built and
tested. Mail drafts, reading returned quotes, invoicing, payments and backups on screen come next.
```

Replace the section `## Coming next: the Mac app` (heading and paragraph) with:

```markdown
## The Mac app

A Windows 95-style window: a navy title bar, bevelled buttons and pixel icons, built to be read at a
glance.

- **Dashboard:** what you're waiting to be paid, what's overdue, what's come in this financial year
  and what's quoted, in big numbers, with the lists behind them.
- **Quotes:** a list, and an editor with a live preview of the PDF the client will tick.
- **Clients**, **Brand** (logo, heading font, colour, wording and terms) and **Activity**, a log of
  every change.
- **Invoices** can be listed and saved as PDFs. Drafting, sending and payments come next.
- Every change saves as you make it, with a daily backup. If the library file is ever damaged,
  Quote Pilot won't save over it and offers the latest backup instead.

## Coming next

Mail drafts with the PDF attached (you always press Send yourself), dropping a returned quote onto the
window, ticking lines by hand, the invoice editor, payments and receipts, import from the old
Invoice Generator, and backup and restore on screen.
```

In `## Building`, replace the paragraph and code block with:

````markdown
`swift build` builds the libraries (`QuotePilotCore` for the rules, `QuotePilotPDF` for the PDFs and
`QuotePilotUI` for the screens), the app and the `qp` tool. `swift test` runs the tests, and
`./build.sh` makes `build/Quote Pilot.app`.

```bash
swift build
swift test
./build.sh                              # build/Quote Pilot.app
swift run qp samples build/samples      # sample quote, invoices and receipt
swift run qp read "build/samples/Q-0001 Sample Client Pty Ltd.pdf"
```

To try the app with a made-up business instead of your own library:

```bash
swift run qp demo /tmp/quote-pilot-demo
QP_LIBRARY_FOLDER=/tmp/quote-pilot-demo "build/Quote Pilot.app/Contents/MacOS/Quote Pilot"
```

Your real library lives in `~/Library/Application Support/Quote Pilot`, with daily backups in its
`Backups` folder.
````

- [ ] **Step 2: Run everything, make every snapshot, and build**

Run: `QP_SNAPSHOTS="$PWD/build/snapshots" swift test`
Expected: every test passes, and `build/snapshots/` holds these:
- `kit`, `icons`, `details-list`, `details-list-empty`;
- `window`, `message-box`, `unreadable`;
- `dashboard`, `dashboard-empty`, `clients`, `quotes`, `quote-editor`, `brand`, `brand-look`;
- `invoices` and `activity`.

Run: `./build.sh`
Expected: `Built build/Quote Pilot.app`.

- [ ] **Step 3: Walk through the real app with the demo library**

```bash
demo="$(mktemp -d)/demo"
swift run qp demo "$demo"
QP_LIBRARY_FOLDER="$demo" "build/Quote Pilot.app/Contents/MacOS/Quote Pilot"
```

Check each of these in the app:
- **Window:** it drags by the navy bar, and a double-click zooms it. The title bar turns grey when
  another app is in front.
- **Keyboard:**
  - ⌘1–⌘6 switch sections, and the arrow keys move through the tree.
  - ⌘N starts a quote and opens it. ⌘P on an open quote offers to save its PDF.
- **Lists:** clicking a header sorts by that column, and clicking again reverses it. Arrow keys move
  the selection; Return or a double-click opens.
- **Save and reload:** quit and reopen the app with the same folder. Everything you changed is still
  there, and `Backups/` holds today's backup.

Quit the app, and report each item as worked or not, with what you saw.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "README: the Mac app's first half, and how to try it with sample data

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
