import Foundation
import QuotePilotCore
import Testing
@testable import QuotePilotUI

/// Usage counts: who sends, what one event carries, and the fee events. Nothing reaches the network:
/// every model here records its events instead.
@MainActor
@Suite struct UsageTests {
    final class Recorder {
        var events: [[String: Any]] = []
        var names: [String] { events.compactMap { $0["eventName"] as? String } }
        func props(_ name: String) -> [String: Any]? {
            events.last { $0["eventName"] as? String == name }?["props"] as? [String: Any]
        }
    }

    func recording(_ model: AppModel) -> Recorder {
        let recorder = Recorder()
        model.usage = Usage(isAvailable: true, isDebug: false, settings: nil) { data in
            if let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                recorder.events.append(event)
            }
        }
        return recorder
    }

    @Test func onlyTheInstalledAppSends() {
        let release = Usage.releaseBundleID
        #expect(!Usage.live(environment: [:], bundleID: nil).isAvailable, "swift run and the tests")
        #expect(!Usage.live(environment: [:], bundleID: release + ".walkthrough").isAvailable, "a test copy")
        let installed = Usage.live(environment: [:], bundleID: release)
        #expect(installed.isAvailable && !installed.isDebug)
        #expect(Usage.live(environment: ["QP_LIBRARY_FOLDER": "/tmp/demo"], bundleID: release).isDebug, "a demo library")
        #expect(!Usage.live(environment: ["QP_STATS": "0"], bundleID: release).isAvailable)
        let forced = Usage.live(environment: ["QP_STATS": "1"], bundleID: nil)
        #expect(forced.isAvailable && forced.isDebug)
    }

    @Test func anEventIsItsNameAndTheAppNothingTyped() throws {
        let model = try UIFixture.sampleModel()
        let recorder = recording(model)
        model.newQuote()
        let event = try #require(recorder.events.last)
        #expect(event["eventName"] as? String == "quote_created")
        #expect((event["props"] as? [String: Any])?.isEmpty == true)
        let system = try #require(event["systemProps"] as? [String: Any])
        #expect(system["osName"] as? String == "macOS")
        #expect(system["isDebug"] as? Bool == false)
        #expect(system["sdkVersion"] as? String == "quotepilot-swift@1")
        #expect((event["sessionId"] as? String)?.isEmpty == false)
        #expect((system["locale"] as? String).map { $0.count <= 10 } == true)
    }

    /// Aptabase refuses a locale over 10 characters, so every event from a Mac set to US English in
    /// Australia ("en_US@rg=auzzzz") was refused.
    @Test func theLocaleIsLanguageAndRegionOnly() {
        #expect(Usage.localeTag(Locale(identifier: "en_US@rg=auzzzz")) == "en-AU")
        #expect(Usage.localeTag(Locale(identifier: "en_AU")) == "en-AU")
        #expect(Usage.localeTag(Locale(identifier: "zh-Hant_TW")) == "zh-TW")
        #expect(Usage.localeTag(Locale(identifier: "de")) == "de")
    }

    @Test func aPaymentSaysHowItWasPaidNotHowMuch() throws {
        let model = try UIFixture.sampleModel()
        let recorder = recording(model)
        let entry = try #require(model.library.invoices.lazy.compactMap { model.newPaymentEntry(for: $0.id) }.first)
        #expect(model.recordPayment(entry))
        #expect(recorder.names == ["payment_recorded"])
        #expect(recorder.props("payment_recorded")?.keys.sorted() == ["method"])
        #expect(recorder.props("payment_recorded")?["method"] as? String == "bankTransfer")
    }

    @Test func untickedSendsNothingWithTheFeeOff() throws {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.appFee.calculates = false
        model.updateBrand(brand)
        let recorder = recording(model)
        model.usage.isOn = false
        #expect(!model.usageIsRequired)
        model.newQuote()
        model.newClient()
        #expect(recorder.events.isEmpty)
    }

    /// While the fee is on, the counts are how it gets invoiced: unticking the box changes nothing.
    @Test func theFeeKeepsTheCountsGoing() throws {
        let model = try FeeBarTests().lockedModel()
        let recorder = recording(model)
        model.usage.isOn = false
        #expect(model.usageIsRequired)
        model.track(.appStarted, model.feeSettingProps)
        model.markFeePaid()
        #expect(recorder.names == ["fee_due", "fee_locked", "app_started", "fee_paid"])
    }

    /// September's $22.50 is overdue on 15 Oct: the first event says it's due and locked, once each,
    /// and I've paid sends the month, the rate and the fee.
    @Test func theFeeEventsCarryTheMonthRateAndFee() throws {
        let model = try FeeBarTests().lockedModel()
        var brand = model.library.brand
        brand.appFee.name = " Sam "
        brand.appFee.email = "sam@example.com"
        model.updateBrand(brand)
        let recorder = recording(model)
        model.track(.appStarted, model.feeSettingProps)
        model.markFeePaid()
        model.newQuote()
        #expect(recorder.names == ["fee_due", "fee_locked", "app_started", "fee_paid", "quote_created"])
        let paid = try #require(recorder.props("fee_paid"))
        #expect(paid["month"] as? String == "2026-09")
        #expect(paid["fee_percent"] as? Double == 3)
        #expect(paid["fee"] as? Double == 22.5)
        #expect(recorder.props("fee_due")?["fee"] as? Double == 22.5)
        #expect(recorder.props("app_started")?["fee_on"] as? Bool == true)
        // Who to invoice it to, on every fee event and no other.
        for name in ["fee_due", "fee_locked", "fee_paid"] {
            #expect(recorder.props(name)?["name"] as? String == "Sam", "\(name)")
            #expect(recorder.props(name)?["email"] as? String == "sam@example.com", "\(name)")
        }
        #expect(recorder.props("app_started")?["email"] == nil)
    }

    /// Libraries from before the fee's contact have none.
    @Test func anOlderFeeHasNoContact() throws {
        let fee = try JSONDecoder().decode(AppFee.self, from: Data(#"{"calculates":true,"percent":3}"#.utf8))
        #expect(fee.name.isEmpty && fee.email.isEmpty)
    }

    @Test func changingTheFeeSaysSo() throws {
        let model = try UIFixture.sampleModel()
        let recorder = recording(model)
        var brand = model.library.brand
        brand.businessName = "Sample Renamed"
        model.updateBrand(brand)
        #expect(recorder.events.isEmpty, "other Brand changes send nothing")
        brand.appFee.percent = 2
        model.updateBrand(brand)
        #expect(recorder.props("fee_setting_changed")?["fee_percent"] as? Double == 2)
    }

    @Test func aSessionLastsUntilAnHourIdle() throws {
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        var sessions: [String] = []
        let usage = Usage(isAvailable: true, isDebug: false, settings: nil) { data in
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            sessions.append(event?["sessionId"] as? String ?? "")
        }
        usage.now = { time }
        usage.track(.quoteCreated)
        time += 50 * 60
        usage.track(.quoteCreated)
        time += 61 * 60
        usage.track(.quoteCreated)
        #expect(sessions[0] == sessions[1])
        #expect(sessions[1] != sessions[2])
        #expect(sessions[0].hasPrefix("1800000000"))
    }
}
