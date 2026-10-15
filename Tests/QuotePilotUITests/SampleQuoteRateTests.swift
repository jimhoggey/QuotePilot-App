import Foundation
import PDFKit
import Testing
import QuotePilotCore
import QuotePilotPDF
@testable import QuotePilotUI

/// The Brand page's sample quote charges its "Planning meeting, 2 hrs" line at the brand's hourly rate.
@MainActor
@Suite struct SampleQuoteRateTests {
    private func hoursLine(_ model: AppModel) throws -> DocumentContent.Row {
        let row = try #require(model.sampleContent().rows.first)
        #expect(row.title == "Planning meeting")
        #expect(row.quantity == "2 hrs")
        return row
    }

    @Test func withAnHourlyRateTheHoursLineAndTheTotalFollowIt() throws {
        let model = try UIFixture.sampleModel()
        model.brandBinding.wrappedValue.hourlyRate = Money(dollars: 95)
        let row = try hoursLine(model)
        #expect(row.rate == "$95.00")
        #expect(row.amount == "$190.00")
        // $190 + Design $600 + Build $1,200.
        #expect(model.sampleContent().amount == "$1,990.00")
    }

    @Test func withNoHourlyRateItStaysAtNinetyDollars() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.library.brand.hourlyRate == nil)
        let row = try hoursLine(model)
        #expect(row.rate == "$90.00")
        #expect(row.amount == "$180.00")
        #expect(model.sampleContent().amount == "$1,980.00")
    }

    /// $0 on Brand is no rate at all, as everywhere else the rate is used.
    @Test func aRateOfZeroIsNoRate() throws {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.hourlyRate = .zero
        model.updateBrand(brand)
        #expect(model.library.brand.hourlyRate == .zero)
        let row = try hoursLine(model)
        #expect(row.rate == "$90.00")
        #expect(model.sampleContent().amount == "$1,980.00")
    }

    /// Changing the rate on Brand changes the sample, and clearing it puts the sample back at $90.
    @Test func changingTheRateRedrawsTheSample() throws {
        let model = try UIFixture.sampleModel()
        model.brandBinding.wrappedValue.hourlyRate = Money(dollars: 120, cents: 50)
        #expect(try hoursLine(model).amount == "$241.00")
        #expect(model.sampleContent().amount == "$2,041.00")
        model.brandBinding.wrappedValue.hourlyRate = nil
        #expect(try hoursLine(model).amount == "$180.00")
    }

    /// What the preview draws is the PDF of that content: its text carries the rate and the total.
    @Test func thePreviewPDFShowsTheRate() throws {
        let model = try UIFixture.sampleModel()
        model.brandBinding.wrappedValue.hourlyRate = Money(dollars: 95)
        let document = try #require(PDFDocument(data: model.pdf(model.sampleContent())))
        let text = document.page(at: 0)?.string ?? ""
        #expect(text.contains("Planning meeting"))
        #expect(text.contains("$95.00"))
        #expect(text.contains("$190.00"))
        #expect(text.contains("$1,990.00"))
        #expect(!text.contains("$90.00"))
    }

    /// With GST on, the total still follows the rate: the sample is taxed like any quote.
    @Test func theTotalWithGSTFollowsTheRateToo() throws {
        var library = try SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date())
        library.brand.gstRegistered = true
        library.brand.hourlyRate = Money(dollars: 100)
        let model = try UIFixture.model(library)
        // ($200 + $600 + $1,200) plus 10% GST.
        #expect(model.sampleContent().amount == "$2,200.00")
    }
}
