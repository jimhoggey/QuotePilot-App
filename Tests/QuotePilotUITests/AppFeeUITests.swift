import AppKit
import Foundation
import QuotePilotCore
import SwiftUI
import Testing
@testable import QuotePilotUI

/// Brand → Settings' Quote Pilot fee: a checkbox, a percentage, and two lines of figures.
@MainActor
@Suite struct AppFeeUITests {
    /// A model on 15 Oct 2026 with $750 received this month and $120 on 30 Sep. Made-up amounts.
    func model(fee: AppFee = AppFee()) throws -> AppModel {
        var library = Library()
        library.brand.appFee = fee
        let client = Client(name: "Sample Client Pty Ltd")
        library.addClient(client)
        for (day, dollars) in [(UIFixture.today, 750), (Day(year: 2026, month: 9, day: 30), 120)] {
            var invoice = library.newInvoice(on: day, clientID: client.id)
            invoice.lines = [LineItem(title: "Sample work", rate: Money(dollars: dollars))]
            try library.update(invoice)
            try library.markSent(invoice: invoice.id)
            try library.recordPayment(Payment(date: day, amount: Money(dollars: dollars)), toInvoice: invoice.id)
        }
        return try UIFixture.model(library)
    }

    @Test func theFiguresForThisMonthAndLast() throws {
        let model = try model()
        #expect(model.appFeeLines == [
            "Received this month: $750.00 · Fee at 3%: $22.50",
            "Last month: received $120.00 · fee $3.60",
        ])
    }

    @Test func aDecimalPercentage() throws {
        let model = try model(fee: AppFee(percent: Decimal(string: "2.5")!))
        #expect(model.appFeeLines == [
            "Received this month: $750.00 · Fee at 2.5%: $18.75",
            "Last month: received $120.00 · fee $3.00",
        ])
    }

    @Test func zeroAndOneHundredPercent() throws {
        #expect(try model(fee: AppFee(percent: 0)).appFeeLines.first == "Received this month: $750.00 · Fee at 0%: $0.00")
        #expect(try model(fee: AppFee(percent: 100)).appFeeLines.first == "Received this month: $750.00 · Fee at 100%: $750.00")
    }

    @Test func turningItOffHidesTheFigures() throws {
        let model = try model()
        var brand = model.library.brand
        brand.appFee.calculates = false
        model.updateBrand(brand)
        #expect(model.appFeeLines.isEmpty)
        #expect(model.library.brand.appFee.percent == 3, "the percentage is kept for when it's back on")

        brand.appFee.calculates = true
        model.updateBrand(brand)
        #expect(model.appFeeLines.count == 2)
    }

    @Test func thePercentageFieldTakes0To100WithUpToTwoDecimals() {
        #expect(FieldParser.percent("3") == 3)
        #expect(FieldParser.percent("2.5") == Decimal(string: "2.5"))
        #expect(FieldParser.percent(" 2.5 % ") == Decimal(string: "2.5"))
        #expect(FieldParser.percent("0") == 0)
        #expect(FieldParser.percent("100") == 100)
        #expect(FieldParser.percent("0.25") == Decimal(string: "0.25"))
        for bad in ["", "%", "-1", "100.01", "101", "2.555", "abc", "1e2", "2,5", ".5", "3.", "\u{0663}"] {
            #expect(FieldParser.percent(bad) == nil, "\"\(bad)\" should be refused")
        }
        #expect(FieldParser.percentText(3) == "3")
        #expect(FieldParser.percentText(Decimal(string: "2.5")!) == "2.5")
    }

    @Test func aPercentageIsSavedAndKeptInsideTheLimits() throws {
        let model = try model()
        var brand = model.library.brand
        brand.appFee.percent = Decimal(string: "2.5")!
        model.updateBrand(brand)
        #expect(model.library.brand.appFee.percent == Decimal(string: "2.5"))
        // Reopened from disk, it's the same.
        let reopened = AppModel(store: model.store, now: model.now, mail: FakeMail(), sentFolder: UIFixture.makeFolder())
        #expect(reopened.library.brand.appFee.percent == Decimal(string: "2.5"))

        brand.appFee.percent = 150
        model.updateBrand(brand)
        #expect(model.library.brand.appFee.percent == 100)
        #expect(model.message == nil)
    }

    @Test func theSettingsTabDrawsWithTheFee() throws {
        let model = try model()
        model.section = .brand
        let rep = Snapshot.render(BrandView(model: model, tab: .settings).background(Win95.face),
                                  size: CGSize(width: 778, height: 492), name: "brand-settings-fee")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
