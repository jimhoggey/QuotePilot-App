import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The padlock on Brand → Settings → Quote Pilot fee: a password, chosen once, that has to be typed
/// before the fee's tick, percentage, first name or email can change.
@MainActor
@Suite struct FeePasswordUITests {
    let password = "Sample pass 1"

    func lockedModel() throws -> AppModel {
        let model = try UIFixture.sampleModel()
        model.dialog = .feePassword(.choose)
        model.lockFeeSettings(password: password)
        return model
    }

    @Test func lockingGreysTheFeeAndSaysSoInActivity() throws {
        let model = try lockedModel()
        #expect(model.feeSettingsLocked)
        #expect(model.dialog == nil)
        #expect(model.library.activity.first?.message == "Locked the Quote Pilot fee's settings with a password")
        #expect(!model.library.activity.contains { $0.message.contains(password) })
    }

    /// Behind the password the fee stays as it is, though the rest of the brand still saves.
    @Test func theFeeKeepsItsSettingsUntilThePasswordIsTyped() throws {
        let model = try lockedModel()
        let fee = model.library.brand.appFee
        var brand = model.library.brand
        brand.appFee.calculates = false
        brand.appFee.percent = 1
        brand.appFee.email = "someone@example.com"
        brand.businessName = "Sample Studio Two"
        model.updateBrand(brand)
        #expect(model.library.brand.appFee == fee)
        #expect(model.library.brand.businessName == "Sample Studio Two")

        #expect(!model.unlockFeeSettings(password: "wrong"))
        #expect(model.feeSettingsLocked)
        #expect(model.unlockFeeSettings(password: password))
        #expect(!model.feeSettingsLocked)
        model.updateBrand(brand)
        #expect(model.library.brand.appFee.percent == 1)
        #expect(model.library.brand.appFee.email == "someone@example.com")
    }

    @Test func thePasswordComesOffOnlyOnceTyped() throws {
        let model = try lockedModel()
        model.removeFeePassword()
        #expect(model.library.brand.appFee.lock != nil, "not while locked")
        model.unlockFeeSettings(password: password)
        model.removeFeePassword()
        #expect(model.library.brand.appFee.lock == nil)
        #expect(!model.feeSettingsLocked)
        #expect(model.library.activity.first?.message == "Removed the password from the Quote Pilot fee's settings")
    }

    @Test func theLockSaysWhatItDoes() {
        #expect(FeeLockButton.help(hasPassword: false, locked: false).hasPrefix("Lock the fee's settings"))
        #expect(FeeLockButton.help(hasPassword: true, locked: true).hasPrefix("Locked."))
        #expect(FeeLockButton.help(hasPassword: true, locked: false).hasPrefix("Unlocked."))
    }

    /// Snapshots: brand-settings-fee-locked and fee-password (the box asking for it).
    @Test func theLockAndItsBoxDraw() throws {
        let model = try lockedModel()
        model.section = .brand
        let settings = Snapshot.render(BrandView(model: model, tab: .settings).background(Win95.face),
                                       size: CGSize(width: 778, height: 520), name: "brand-settings-fee-locked")
        #expect(settings.map(Snapshot.hasContent) == true)
        let box = Snapshot.render(FeePasswordView(model: model, step: .choose).padding(10).background(Win95.desktop),
                                  size: CGSize(width: 460, height: 260), name: "fee-password")
        #expect(box.map(Snapshot.hasContent) == true)
    }
}
