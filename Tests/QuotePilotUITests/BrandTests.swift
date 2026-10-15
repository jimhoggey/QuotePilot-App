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

    /// Day counts past a year would put a due date where `Day` can't go, and the library would no
    /// longer open; whatever reaches the model is kept within 0 to 365.
    @Test func dayCountsAreKeptWithinAYear() throws {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.paymentDueDays = 9_999
        brand.quoteValidDays = -3
        model.updateBrand(brand)
        #expect(model.library.brand.paymentDueDays == 365)
        #expect(model.library.brand.quoteValidDays == 0)
        #expect(model.message == nil)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.paymentDueDays == 365)
        #expect(saved.brand.quoteValidDays == 0)
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
