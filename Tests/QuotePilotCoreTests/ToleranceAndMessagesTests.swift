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

    /// A library saved before the hourly rate existed has no such field; it loads with no rate, and a
    /// rate that is there round-trips.
    @Test func aBrandWithoutAnHourlyRateLoadsWithNone() throws {
        let old = try Library.makeDecoder().decode(Brand.self, from: Data(#"{"businessName":"Sample Studio"}"#.utf8))
        #expect(old.hourlyRate == nil)

        var brand = Brand()
        #expect(brand.hourlyRate == nil)
        brand.hourlyRate = Money(dollars: 95, cents: 50)
        let saved = try Library.makeEncoder().encode(brand)
        #expect(try Library.makeDecoder().decode(Brand.self, from: saved).hourlyRate == Money(dollars: 95, cents: 50))
        // With none set, nothing is written, so the file is as it was before the field existed.
        #expect(!String(decoding: try Library.makeEncoder().encode(Brand()), as: UTF8.self).contains("hourlyRate"))

        let library = try Library.makeDecoder().decode(
            Library.self, from: Data(#"{"format":1,"brand":{"businessName":"Sample Studio","quoteValidDays":20}}"#.utf8))
        #expect(library.brand.hourlyRate == nil)
        #expect(library.brand.quoteValidDays == 20)
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
                                      .deductedByFinal("INV-0002"), .unknownLineCodes(["09"]),
                                      .notEditable, .noPayments, .paymentNotPositive,
                                      .paymentMoreThanOwing(Money(dollars: 300))]
        for error in errors {
            #expect(!error.message.isEmpty)
            #expect(error.localizedDescription == error.message)
        }
        #expect(LibraryError.deductedByFinal("INV-0002").message.contains("INV-0002"))
        // A quote with invoices keeps its client too, so the message says so.
        #expect(LibraryError.alreadyInvoiced.message.contains("its client"))
        #expect(LibraryError.unknownLineCodes(["09"]).message.contains("09"))
        #expect(LibraryError.paymentMoreThanOwing(Money(dollars: 300)).message.contains("$300.00"))
        #expect(LibraryStore.StoreError.wouldOverwriteUnreadableLibrary.localizedDescription.contains("library"))
        #expect(LibraryStore.StoreError.backupHasProblems(["Q-0001 line 02 has a rate of $20,000,000.00, over the $10,000,000.00 limit."])
            .localizedDescription.contains("Q-0001 line 02"))
        #expect(LegacyImportError.notABackup.localizedDescription.contains("backup"))
    }

    @Test func aDayBecomesNoonOnThatDay() {
        let day = Day(year: 2026, month: 10, day: 15)
        let zone = TimeZone(identifier: "Australia/Brisbane")!
        #expect(Day(day.date(in: zone), timeZone: zone) == day)
    }
}
