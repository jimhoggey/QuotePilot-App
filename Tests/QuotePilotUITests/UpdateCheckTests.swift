import AppKit
import Foundation
import SwiftUI
import Testing
@testable import QuotePilotUI

@Suite struct VersionNumberTests {
    @Test func readsDottedNumbersWithAnOptionalV() throws {
        #expect(VersionNumber("1.2.3")?.parts == [1, 2, 3])
        #expect(VersionNumber("v1.2.0")?.parts == [1, 2, 0])
        #expect(VersionNumber("V2")?.parts == [2])
        #expect(VersionNumber(" 1.0 \n")?.parts == [1, 0])
        #expect(VersionNumber("v1.2.0")?.description == "1.2.0")
    }

    @Test func anythingElseIsNotAVersion() {
        for text in ["", "v", "latest", "1..2", "1.", ".1", "1.2.x", "1.2.3-beta", "+1.2", "1,2", "v v1", "1 2",
                     "\u{0663}.1", "1.2.3.4.5.6.7", "99999999999999999999.1"] {
            #expect(VersionNumber(text) == nil, "\"\(text)\" should not parse")
        }
    }

    @Test func partsAreComparedAsNumbers() throws {
        let v = { (text: String) in try #require(VersionNumber(text)) }
        #expect(try v("1.10.0") > v("1.9.0"))
        #expect(try v("1.9.0") < v("1.10.0"))
        #expect(try v("2.0.0") > v("1.99.99"))
        #expect(try v("1.0.1") > v("1.0.0"))
        #expect(try v("v1.1.0") > v("1.0.0"))
        #expect(try v("1.0.0.1") > v("1.0.0"))
    }

    @Test func missingPartsCountAsZero() throws {
        let v = { (text: String) in try #require(VersionNumber(text)) }
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try v("1") == v("v1.0.0"))
        #expect(try v("1.0") < v("1.0.1"))
        #expect(try !(v("1.0.0") < v("1.0")))
        #expect(try v("1.2") > v("1.1.9"))
    }
}

@Suite struct ReleaseParsingTests {
    @Test func theZipIsPickedFromTheAssets() throws {
        let release = try #require(ReleaseInfo.parse(Data(UpdateFixture.releaseJSON().utf8)))
        #expect(release.version == "1.1.0")
        #expect(release.tag == "v1.1.0")
        #expect(release.pageURL.absoluteString == "https://github.com/jimhoggey/QuotePilot-App/releases/tag/v1.1.0")
        #expect(release.downloadURL.absoluteString
                == "https://github.com/jimhoggey/QuotePilot-App/releases/download/v1.1.0/QuotePilot-mac.zip")
    }

    @Test func aReleaseWithoutTheZipIsNoUpdate() {
        #expect(ReleaseInfo.parse(Data(UpdateFixture.releaseJSON(assets: []).utf8)) == nil)
        #expect(ReleaseInfo.parse(Data(UpdateFixture.releaseJSON(assets: ["QuotePilot-mac.zip.sha256", "notes.txt"]).utf8)) == nil)
        // The name must match exactly.
        #expect(ReleaseInfo.parse(Data(UpdateFixture.releaseJSON(assets: ["quotepilot-mac.zip"]).utf8)) == nil)
        let noAssetsKey = #"{ "tag_name": "v1.1.0", "html_url": "https://github.com/jimhoggey/QuotePilot-App/releases/tag/v1.1.0" }"#
        #expect(ReleaseInfo.parse(Data(noAssetsKey.utf8)) == nil)
    }

    @Test func aReplyThatIsntUsableIsNoUpdate() {
        #expect(ReleaseInfo.parse(Data()) == nil)
        #expect(ReleaseInfo.parse(Data("<html>Not Found</html>".utf8)) == nil)
        #expect(ReleaseInfo.parse(Data(#"{ "message": "Not Found" }"#.utf8)) == nil)
        #expect(ReleaseInfo.parse(Data(UpdateFixture.releaseJSON(tag: "nightly").utf8)) == nil)
        #expect(ReleaseInfo.parse(Data(UpdateFixture.releaseJSON(tag: "v1.2.0-beta").utf8)) == nil)
    }

    /// The address comes out of GitHub's reply; only this project's own release downloads are followed.
    @Test func aDownloadFromAnywhereElseIsNoUpdate() {
        for base in ["https://example.com/jimhoggey/QuotePilot-App/releases/download",
                     "https://github.com/someone-else/QuotePilot-App/releases/download",
                     "http://github.com/jimhoggey/QuotePilot-App/releases/download",
                     "https://github.com.example.com/jimhoggey/QuotePilot-App/releases/download"] {
            #expect(ReleaseInfo.parse(Data(UpdateFixture.releaseJSON(downloadBase: base).utf8)) == nil, "\(base)")
        }
    }

    @Test func onlyANewerReleaseCounts() throws {
        func newer(_ tag: String, than version: String) -> ReleaseInfo? {
            UpdateChecker.newerRelease(in: Data(UpdateFixture.releaseJSON(tag: tag).utf8), than: version)
        }
        #expect(newer("v1.1.0", than: "1.0.0")?.version == "1.1.0")
        #expect(newer("v1.10.0", than: "1.9.0")?.version == "1.10.0")
        #expect(newer("v1.0.0", than: "1.0.0") == nil)
        #expect(newer("v1.0.0", than: "1.1.0") == nil)
        #expect(newer("v1.0", than: "1.0.0") == nil)
        // A running version that isn't a number can't be compared, so there is nothing to offer.
        #expect(newer("v1.1.0", than: "dev") == nil)
    }
}

@Suite struct UpdateRequestTests {
    @Test func theRequestAsksForTheLatestReleaseAndSendsNothingElse() throws {
        let request = UpdateChecker.request(version: "1.0.0")
        #expect(request.url?.absoluteString == "https://api.github.com/repos/jimhoggey/QuotePilot-App/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 10)
        #expect(request.httpBody == nil)
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.allHTTPHeaderFields == [
            "Accept": "application/vnd.github+json",
            "User-Agent": "QuotePilot/1.0.0",
        ])
    }

    @Test func aNewerReleaseIsReturnedAndTheRequestIsTheOneAbove() async throws {
        let script = FetchScript(json: UpdateFixture.releaseJSON())
        let checker = UpdateChecker(currentVersion: "1.0.0", fetch: script.fetch)
        #expect(try await checker.check()?.version == "1.1.0")
        #expect(script.requests.count == 1)
        #expect(script.requests.first?.value(forHTTPHeaderField: "User-Agent") == "QuotePilot/1.0.0")
    }

    @Test func theNewestVersionAndNoReleasesYetAreNotErrors() async throws {
        let same = UpdateChecker(currentVersion: "1.1.0", fetch: FetchScript(json: UpdateFixture.releaseJSON()).fetch)
        #expect(try await same.check() == nil)
        let none = UpdateChecker(currentVersion: "1.0.0",
                                fetch: FetchScript(.success((Data(#"{"message":"Not Found"}"#.utf8), 404))).fetch)
        #expect(try await none.check() == nil)
    }

    @Test func aRefusalOrNoConnectionThrows() async {
        let refused = UpdateChecker(currentVersion: "1.0.0", fetch: FetchScript(.success((Data(), 403))).fetch)
        await #expect(throws: UpdateError.self) { _ = try await refused.check() }
        let offline = UpdateChecker(currentVersion: "1.0.0",
                                    fetch: FetchScript(.failure(FetchScript.Failure.offline)).fetch)
        await #expect(throws: FetchScript.Failure.self) { _ = try await offline.check() }
    }
}

@MainActor
@Suite struct UpdateCheckModelTests {
    func makeModel(_ script: FetchScript, version: String = "1.0.0", bundlePath: String = "/Applications/Quote Pilot.app",
                   settings: MemoryUpdateSettings = MemoryUpdateSettings()) throws -> (AppModel, MemoryUpdateSettings) {
        let model = try UIFixture.model()
        model.updates = UpdateFixture.services(version: version, bundlePath: bundlePath, script: script, settings: settings)
        return (model, settings)
    }

    func logText(_ model: AppModel) -> String {
        (try? String(contentsOf: model.updates.log.url, encoding: .utf8)) ?? ""
    }

    @Test func launchChecksAndNotesANewerVersion() async throws {
        let script = FetchScript(json: UpdateFixture.releaseJSON())
        let (model, settings) = try makeModel(script)
        await model.start()
        #expect(script.requests.count == 1)
        #expect(model.availableUpdate?.version == "1.1.0")
        #expect(model.statusNote?.text == "Quote Pilot 1.1.0 is available. Help → Install Update…")
        #expect(model.message == nil, "the automatic check never shows a box")
        #expect(settings.lastUpdateCheck == model.now())
        #expect(logText(model).contains("1.1.0 is available"))
    }

    /// No 24-hour wait: every launch asks, however recently the last one did.
    @Test func everyLaunchChecksEvenRightAfterTheLastCheck() async throws {
        let script = FetchScript(json: UpdateFixture.releaseJSON())
        let settings = MemoryUpdateSettings()
        settings.lastUpdateCheck = UIFixture.today.date()
        let (first, _) = try makeModel(script, settings: settings)
        await first.start()
        #expect(script.requests.count == 1)

        // The next launch, a minute later: a new model on the same settings.
        let (second, _) = try makeModel(script, settings: settings)
        await second.start()
        #expect(script.requests.count == 2)
    }

    @Test func nothingChecksOutsideARealApp() async throws {
        let script = FetchScript(json: UpdateFixture.releaseJSON())
        let (model, settings) = try makeModel(script, bundlePath: "/tmp/.build/debug")
        await model.start()
        #expect(script.requests.isEmpty)
        #expect(settings.lastUpdateCheck == nil)
    }

    @Test func aFailedAutomaticCheckIsSilentButLogged() async throws {
        let script = FetchScript(.failure(FetchScript.Failure.offline))
        let (model, settings) = try makeModel(script)
        await model.start()
        #expect(model.message == nil)
        #expect(model.statusNote == nil)
        #expect(model.availableUpdate == nil)
        #expect(settings.lastUpdateCheck == nil, "a failed check tries again at the next launch")
        #expect(logText(model).contains("Checking for updates failed"))
    }

    @Test func theNewestVersionIsAQuietResultAtLaunchAndAnAnswerWhenAsked() async throws {
        let script = FetchScript(json: UpdateFixture.releaseJSON(tag: "v1.0.0"))
        let (model, _) = try makeModel(script)
        await model.start()
        #expect(model.message == nil)
        #expect(model.statusNote == nil)

        await model.checkForUpdates(manual: true)
        #expect(model.message?.text == "You have the newest version (1.0.0).")
        #expect(model.message?.choices.count == 1)
        #expect(script.requests.count == 2, "asking again always asks GitHub")
    }

    @Test func aFailedManualCheckShowsOneBox() async throws {
        let (model, _) = try makeModel(FetchScript(.success((Data(), 500))))
        await model.checkForUpdates(manual: true)
        let box = try #require(model.message)
        #expect(box.title == "Couldn't Check for Updates")
        #expect(box.text.hasPrefix("Quote Pilot couldn't check for updates."))
        #expect(box.text.contains("500"))
        #expect(model.availableUpdate == nil)
    }

    /// Someone who chose Check for Updates… and has an update is asked about it straight away; the
    /// status bar and the Help menu say so as well.
    @Test func aManualCheckThatFindsANewerVersionOffersItToo() async throws {
        let (model, _) = try makeModel(FetchScript(json: UpdateFixture.releaseJSON()))
        await model.checkForUpdates(manual: true)
        #expect(model.availableUpdate?.version == "1.1.0")
        #expect(model.statusNote?.text == "Quote Pilot 1.1.0 is available. Help → Install Update…")
        #expect(model.message?.title == "Install Update")
        #expect(model.canInstallUpdate)
    }

    @Test func checkForUpdatesIsOffWhileACheckIsRunning() async throws {
        let (model, _) = try makeModel(FetchScript(json: UpdateFixture.releaseJSON()))
        #expect(model.canCheckForUpdates)
        model.isCheckingForUpdates = true
        #expect(!model.canCheckForUpdates)
        model.isCheckingForUpdates = false
        #expect(model.canCheckForUpdates)
    }

    @Test func theLogLinesAreStampedAndAppended() throws {
        let folder = UIFixture.makeFolder()
        let url = folder.appendingPathComponent("Logs/Quote Pilot/update.log")
        let log = UpdateLog(url: url, now: { Date(timeIntervalSince1970: 0) })
        log.append("first")
        log.append("second\nline")
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("  first"))
        #expect(lines[1].hasSuffix("  second line"))
        #expect(lines[0].range(of: #"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  "#, options: .regularExpression) != nil)
        try? FileManager.default.removeItem(at: folder)
    }
}

/// The strip under the toolbar that offers a newer version. GitHub is a script and the installer a
/// fake, so nothing here reaches the network or the disk outside a temporary folder.
@MainActor
@Suite struct UpdateBannerTests {
    /// A model that has just launched and asked a scripted GitHub.
    func launched(_ json: String = UpdateFixture.releaseJSON(), installer: FakeInstaller = FakeInstaller(),
                  quit: @escaping () -> Void = {}) async throws -> AppModel {
        let model = try UIFixture.model()
        model.updates = UpdateFixture.services(script: FetchScript(json: json), installer: installer, quit: quit)
        await model.start()
        return model
    }

    @Test func aNewerVersionShowsTheBannerAndKeepsTheStatusNote() async throws {
        let model = try await launched()
        #expect(model.showsUpdateBanner)
        let banner = UpdateBanner(model: model)
        #expect(banner.text == "Quote Pilot 1.1.0 is ready.")
        #expect(banner.canInstall)
        #expect(model.statusNote?.text == "Quote Pilot 1.1.0 is available. Help → Install Update…")
        #expect(model.message == nil, "the banner never blocks the window")
    }

    @Test func theNewestVersionOrAFailedCheckShowsNoBanner() async throws {
        #expect(try await !launched(UpdateFixture.releaseJSON(tag: "v1.0.0")).showsUpdateBanner)
        let offline = try UIFixture.model()
        await offline.start()
        #expect(!offline.showsUpdateBanner)
        #expect(offline.message == nil)
    }

    @Test func laterHidesTheBannerUntilTheNextLaunch() async throws {
        let model = try await launched()
        UpdateBanner(model: model).later()
        #expect(!model.showsUpdateBanner)
        #expect(model.message == nil)
        #expect(model.canInstallUpdate, "Help → Install Update… stays on")
        #expect(model.statusNote?.text == "Quote Pilot 1.1.0 is available. Help → Install Update…")

        // Another check in the same launch finds it again, and the banner stays hidden.
        await model.checkForUpdates(manual: false)
        #expect(model.availableUpdate?.version == "1.1.0")
        #expect(!model.showsUpdateBanner)

        // The next launch is a new model: the banner is back.
        #expect(try await launched().showsUpdateBanner)
    }

    @Test func installUpdateAsksOnceAndThenInstalls() async throws {
        let installer = FakeInstaller()
        var quits = 0
        let model = try await launched(installer: installer, quit: { quits += 1 })
        UpdateBanner(model: model).install()

        let box = try #require(model.message)
        #expect(box.title == "Install Update")
        #expect(box.choices.map(\.title) == ["Update", "Not Now"])
        #expect(installer.staged.isEmpty, "nothing happens before the click")

        model.respond(try #require(box.choices.first))
        for _ in 0..<200 where quits == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(installer.staged == [UpdateFixture.release("1.1.0")])
        #expect(installer.handOvers.count == 1)
        #expect(quits == 1)
    }

    @Test func notNowKeepsTheBanner() async throws {
        let model = try await launched()
        UpdateBanner(model: model).install()
        model.respond(try #require(model.message?.choices.last))
        #expect(model.message == nil)
        #expect(model.showsUpdateBanner)
    }

    @Test func whileInstallingTheBannersInstallIsOff() async throws {
        let model = try await launched()
        model.isInstallingUpdate = true
        #expect(!UpdateBanner(model: model).canInstall)
    }

    /// The banner moves the section down by its height and the gap under it, less the 4 the section
    /// had above it. In the smallest window (980 x 620) the new library's Dashboard, Getting started
    /// box and all, must still fit what is left of its 492 (see the Getting started fit test).
    @Test func theSmallestWindowStillFitsTheDashboardUnderTheBanner() async throws {
        let model = try await launched()
        _ = NSApplication.shared
        let taken = UpdateBanner.height + UpdateBanner.gapBelow - 4
        let area = CGSize(width: 778, height: 620 - 28 - 66 - 26 - 8 - taken)
        let needed = NSHostingView(rootView: DashboardView(model: model).frame(width: area.width)).fittingSize
        #expect(needed.height <= area.height, "the Dashboard needs \(needed.height) of \(area.height)")

        let bannerSize = NSHostingView(rootView: UpdateBanner(model: model)).fittingSize
        #expect(bannerSize.height == UpdateBanner.height)
        #expect(bannerSize.width <= 980 - 8, "one line across the window")

        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "update-banner-small")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
