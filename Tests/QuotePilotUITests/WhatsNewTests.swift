import Foundation
import Testing
@testable import QuotePilotUI

/// The box at the first launch after an update: what changed, topped up with earlier changes when
/// the release was a small one.
@MainActor
@Suite struct WhatsNewTests {
    typealias Release = WhatsNew.Release

    @Test func aBigReleaseSaysOnlyWhatsNew() {
        let releases = [Release("1.2.0", "A", "B", "C"), Release("1.1.0", "Old")]
        #expect(WhatsNew.text(since: nil, current: "1.2.0", releases: releases) == "New in 1.2.0:\n• A\n• B\n• C")
    }

    @Test func aSmallReleaseAddsTheNewestEarlierChanges() {
        let releases = [Release("1.2.0", "A"), Release("1.1.0", "B", "C"), Release("1.0.0", "D")]
        #expect(WhatsNew.text(since: nil, current: "1.2.0", releases: releases)
            == "New in 1.2.0:\n• A\n\nIn case you missed it:\n• B\n• C")
    }

    @Test func aReleaseWithNothingNewShowsEarlierChanges() {
        let releases = [Release("1.2.1"), Release("1.2.0", "A", "B"), Release("1.1.0", "C", "D")]
        #expect(WhatsNew.text(since: nil, current: "1.2.1", releases: releases)
            == "In case you missed it:\n• A\n• B\n• C")
    }

    /// Skipped versions count as new; entries for versions after the running one don't count at all.
    @Test func everyReleaseSinceTheLastSeenOneIsNew() {
        let releases = [Release("1.3.0", "Later"), Release("1.2.0", "A"), Release("1.1.0", "B"),
                        Release("1.0.0", "C", "D")]
        #expect(WhatsNew.text(since: "1.0.0", current: "1.2.0", releases: releases)
            == "New since 1.0.0:\n• A\n• B\n\nIn case you missed it:\n• C")
        #expect(WhatsNew.text(since: nil, current: "0.0.0", releases: releases) == nil)
    }

    /// Every release gets an entry, with no lines when it brought nothing worth saying.
    @Test func theNewestEntryIsTheAppsVersion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(WhatsNew.releases.first?.version == AppVersion.version(in: info))
        let versions = WhatsNew.releases.compactMap { VersionNumber($0.version) }
        #expect(versions.count == WhatsNew.releases.count, "every entry is a version")
        #expect(versions == versions.sorted(by: >), "newest first")
    }

    // MARK: At launch

    func model(version: String, seen: String?) throws -> (AppModel, MemoryUpdateSettings) {
        let settings = MemoryUpdateSettings()
        settings.lastSeenVersion = seen
        let model = try UIFixture.model()
        model.updates = UpdateFixture.services(version: version, settings: settings)
        return (model, settings)
    }

    @Test func theFirstLaunchOfANewVersionShowsItOnce() throws {
        let (model, settings) = try model(version: "1.6.1", seen: "1.6.0")
        model.showWhatsNewOnce(justUpdated: false)
        #expect(model.message?.title == "What's New in Quote Pilot 1.6.1")
        #expect(settings.lastSeenVersion == "1.6.1")

        model.message = nil
        model.showWhatsNewOnce(justUpdated: false)
        #expect(model.message == nil, "once")
    }

    @Test func aNewInstallStaysQuiet() throws {
        let (model, settings) = try model(version: "1.6.1", seen: nil)
        model.showWhatsNewOnce(justUpdated: false)
        #expect(model.message == nil)
        #expect(settings.lastSeenVersion == "1.6.1")
    }

    /// Versions before What's New remembered no version: the installer's marker says it was an update.
    @Test func anUpdateFromBeforeWhatsNewShowsIt() throws {
        let (model, _) = try model(version: "1.6.1", seen: nil)
        model.showWhatsNewOnce(justUpdated: true)
        #expect(model.message?.title == "What's New in Quote Pilot 1.6.1")
    }

    @Test func theHelpMenuShowsItAnyTime() throws {
        let (model, _) = try model(version: "1.6.1", seen: "1.6.1")
        model.showWhatsNew()
        #expect(model.message?.text.hasPrefix("New in 1.6.1:") == true)
    }

    @Test func theBoxDraws() throws {
        let (model, _) = try model(version: "1.6.1", seen: "1.6.0")
        model.showWhatsNewOnce(justUpdated: false)
        let box = try #require(model.message)
        let rep = Snapshot.render(MessageBoxView(box: box) { _ in }, size: CGSize(width: 480, height: 320), name: "whats-new")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
