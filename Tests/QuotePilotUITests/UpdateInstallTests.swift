import Foundation
import Testing
@testable import QuotePilotUI

// Everything here works in temporary folders with made-up apps. Nothing downloads, and nothing
// touches the real Applications folder, the real Trash or the real log.

@Suite struct UpdateRulesTests {
    @Test func aTranslocatedCopyCantReplaceItself() {
        let path = "/private/var/folders/ab/xyz/AppTranslocation/1A2B3C/d/Quote Pilot.app"
        #expect(UpdateRules.installProblem(bundlePath: path, folderIsWritable: { _ in true })
                == "Move Quote Pilot into your Applications folder first, then try again.")
    }

    @Test func aFolderThatCantBeWrittenToIsRefusedAndTheFolderIsTheOneAppsIn() {
        var asked: [String] = []
        let problem = UpdateRules.installProblem(bundlePath: "/Applications/Quote Pilot.app") {
            asked.append($0)
            return false
        }
        #expect(problem == "Move Quote Pilot into your Applications folder first, then try again.")
        #expect(asked == ["/Applications"])
    }

    @Test func anAppInAWritableFolderCanUpdate() {
        #expect(UpdateRules.installProblem(bundlePath: "/Applications/Quote Pilot.app", folderIsWritable: { _ in true }) == nil)
        #expect(UpdateRules.installProblem(bundlePath: "/Users/sample/Applications/Quote Pilot.app", folderIsWritable: { _ in true }) == nil)
    }

    @Test func somethingThatIsntAnAppCantUpdate() {
        #expect(UpdateRules.installProblem(bundlePath: "/Users/sample/code/.build/debug", folderIsWritable: { _ in true })
                == UpdateRules.notAnApp)
    }
}

@Suite struct UpdateVerifierTests {
    func info(id: String = "com.fynnprojects.quotepilot", version: String = "1.1.0",
              program: String? = "Quote Pilot") -> [String: Any] {
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version]
        if let program { info["CFBundleExecutable"] = program }
        return info
    }

    @Test func ourAppAtTheExpectedVersionPasses() {
        #expect(UpdateVerifier.problem(in: info(), expectedVersion: "1.1.0") == nil)
        #expect(UpdateVerifier.problem(in: info(version: "1.1"), expectedVersion: "1.1.0") == nil)
    }

    @Test func anythingElseIsRefused() {
        #expect(UpdateVerifier.problem(in: nil, expectedVersion: "1.1.0") == "it has no Info.plist")
        #expect(UpdateVerifier.problem(in: info(id: "com.example.other"), expectedVersion: "1.1.0") == "it is a different app")
        #expect(UpdateVerifier.problem(in: info(version: "1.0.5"), expectedVersion: "1.1.0") == "it is version 1.0.5, not 1.1.0")
        #expect(UpdateVerifier.problem(in: info(version: "beta"), expectedVersion: "1.1.0") != nil)
        #expect(UpdateVerifier.problem(in: info(program: nil), expectedVersion: "1.1.0") == "it has no program")
        #expect(UpdateVerifier.problem(in: info(program: "../evil"), expectedVersion: "1.1.0") == "it has no program")
    }
}

@Suite struct UpdateOutcomeTests {
    @Test func theExpectedVersionMeansItWorked() {
        #expect(UpdateOutcome.afterLaunch(running: "1.1.0", expected: "1.1.0") == .updated("1.1.0"))
        #expect(UpdateOutcome.afterLaunch(running: "1.1.0", expected: "v1.1") == .updated("1.1.0"))
    }

    @Test func theOldVersionMeansItDidntFinish() {
        #expect(UpdateOutcome.afterLaunch(running: "1.0.0", expected: "1.1.0") == .didNotFinish)
        #expect(UpdateOutcome.afterLaunch(running: "0.0.0", expected: "1.1.0") == .didNotFinish)
    }

    /// Someone who got ahead of the marker (a newer copy dropped in by hand) did get updated.
    @Test func aNewerVersionStillCountsAsUpdated() {
        #expect(UpdateOutcome.afterLaunch(running: "1.2.0", expected: "1.1.0") == .updated("1.2.0"))
    }

    @Test func noMarkerOrAnUnreadableOneSaysNothing() {
        #expect(UpdateOutcome.afterLaunch(running: "1.1.0", expected: nil) == nil)
        #expect(UpdateOutcome.afterLaunch(running: "1.1.0", expected: "") == nil)
        #expect(UpdateOutcome.afterLaunch(running: "1.1.0", expected: "soon") == nil)
    }
}

// MARK: The helper script

@Suite struct UpdateHelperScriptTests {
    func plan(waitSeconds: Int = 60) -> HelperPlan {
        HelperPlan(processID: 4242, oldApp: "/Applications/Quote Pilot.app",
                   newApp: "/var/folders/ab/QuotePilotUpdate-1/unzipped/Quote Pilot.app",
                   workFolder: "/var/folders/ab/QuotePilotUpdate-1", trashFolder: "/Users/sample/.Trash",
                   oldVersion: "1.0.0", newVersion: "1.1.0",
                   logFile: "/Users/sample/Library/Logs/Quote Pilot/update.log", waitSeconds: waitSeconds)
    }

    @Test func theOldAppGoesToTheTrashUnderItsVersion() {
        let script = UpdateHelper.script(plan())
        #expect(script.contains("TRASH='/Users/sample/.Trash'"))
        #expect(script.contains(#"TRASHED="$TRASH/Quote Pilot 1.0.0.app""#))
        #expect(script.contains(#"mv "$OLD" "$dest""#))
        #expect(script.contains("OLD='/Applications/Quote Pilot.app'"))
    }

    /// The user's rule is to move old copies to the Trash, never to delete them.
    @Test func itNeverDeletesAnApp() {
        let script = UpdateHelper.script(plan())
        #expect(!script.contains("rm -rf"))
        #expect(!script.contains("rm -r"))
        for line in script.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("rm ") {
            #expect(line.trimmingCharacters(in: .whitespaces) == #"rm -f "$0""#, "only the script itself is removed")
        }
        // The only other removals are rmdir, which refuses a folder with anything in it.
        for line in script.split(separator: "\n") where line.contains("rmdir") {
            #expect(!line.contains("$OLD"))
        }
    }

    @Test func itWaitsForTheProcessUpToSixtySeconds() {
        let script = UpdateHelper.script(plan())
        #expect(script.contains("PID=4242"))
        #expect(script.contains(#"kill -0 "$PID""#))
        #expect(script.contains(#"[ "$tries" -lt 120 ]"#), "120 polls of half a second")
        #expect(UpdateHelper.script(plan(waitSeconds: 90)).contains(#"[ "$tries" -lt 180 ]"#))
    }

    @Test func itOpensAnAppOnTheSuccessAndTheFailurePath() throws {
        let script = UpdateHelper.script(plan())
        let branches = try #require(script.range(of: #"if [ "$updated" = yes ]; then"#))
        let afterBranches = String(script[branches.upperBound...])
        let elseRange = try #require(afterBranches.range(of: "\nelse\n"))
        let success = afterBranches[..<elseRange.lowerBound]
        let rest = afterBranches[elseRange.upperBound...]
        let failure = rest[..<(try #require(rest.range(of: "\nfi\n"))).lowerBound]
        #expect(success.contains("relaunch"))
        #expect(failure.contains("relaunch"))
        #expect(script.contains(#""$OPEN" "$target""#))
    }

    @Test func itClearsQuarantineAndLogsEveryStep() {
        let script = UpdateHelper.script(plan())
        #expect(script.contains(#"xattr -dr com.apple.quarantine "$OLD""#))
        #expect(script.contains("LOG='/Users/sample/Library/Logs/Quote Pilot/update.log'"))
        for step in ["Moved the old app to the Trash", "The new app is in place", "The old app is back",
                     "Update finished", "The update did not finish", "Opening "] {
            #expect(script.contains(step), "\(step) should be logged")
        }
    }

    @Test func pathsWithQuotesAndSpacesStayInsideTheirQuotes() throws {
        #expect(UpdateHelper.quote("it's here") == #"'it'\''s here'"#)
        var odd = plan()
        odd.oldApp = "/Users/o'brien/Apps and Tools/Quote Pilot.app"
        odd.oldVersion = "1.0.0 beta/2"
        let script = UpdateHelper.script(odd)
        #expect(script.contains(#"OLD='/Users/o'\''brien/Apps and Tools/Quote Pilot.app'"#))
        #expect(script.contains("Quote Pilot 1.0.0_beta_2.app"), "a version can't add a folder to the name")
        // And the shell agrees that it is a script.
        let file = UIFixture.makeFolder()
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: file) }
        let url = file.appendingPathComponent("odd.sh")
        try Data(script.utf8).write(to: url)
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/bin/sh")
        check.arguments = ["-n", url.path]
        try check.run()
        check.waitUntilExit()
        #expect(check.terminationStatus == 0)
    }

    @Test func fileSafeVersionsKeepOnlyPlainCharacters() {
        #expect(UpdateHelper.fileSafe("1.10.0") == "1.10.0")
        #expect(UpdateHelper.fileSafe("1.0 beta/2") == "1.0_beta_2")
        #expect(UpdateHelper.fileSafe("../x") == ".._x")
    }
}

/// The helper script, run for real inside a temporary folder whose name has a space and an apostrophe,
/// with a made-up old and new app, a Trash folder of its own, and an "open" that only writes down what
/// it was asked to open.
@Suite struct UpdateHelperRunTests {
    struct Rig {
        let root: URL
        let apps: URL
        let work: URL
        let unzipped: URL
        let trash: URL
        let log: URL
        let opened: URL
        let opener: URL

        var oldApp: URL { apps.appendingPathComponent("Quote Pilot.app") }
        var newApp: URL { unzipped.appendingPathComponent("Quote Pilot.app") }
        var script: URL { work.appendingPathComponent("update.sh") }
        var files: FileManager { .default }

        init(oldApp: Bool = true, newApp: Bool = true, trash makeTrash: Bool = true) throws {
            root = UIFixture.makeFolder().appendingPathComponent("Fynn's Test Mac", isDirectory: true)
            apps = root.appendingPathComponent("Apps and Tools", isDirectory: true)
            work = root.appendingPathComponent("QuotePilotUpdate-1", isDirectory: true)
            unzipped = work.appendingPathComponent("unzipped", isDirectory: true)
            trash = root.appendingPathComponent(".Trash", isDirectory: true)
            log = root.appendingPathComponent("Logs/Quote Pilot/update.log")
            opened = root.appendingPathComponent("opened.txt")
            opener = root.appendingPathComponent("fake open.sh")
            for folder in [apps, unzipped] + (makeTrash ? [trash] : []) {
                try files.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            if oldApp { try makeApp(self.oldApp, marker: "old") }
            if newApp { try makeApp(self.newApp, marker: "new") }
            try Data("#!/bin/sh\necho \"$1\" >> '\(opened.path.replacingOccurrences(of: "'", with: "'\\''"))'\n".utf8)
                .write(to: opener)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path)
        }

        func makeApp(_ url: URL, marker: String) throws {
            try files.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: url.appendingPathComponent("Contents/marker.txt"))
        }

        func marker(of app: URL) -> String? {
            (try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8))
        }

        func plan(processID: Int32, waitSeconds: Int = 60) -> HelperPlan {
            HelperPlan(processID: processID, oldApp: oldApp.path, newApp: newApp.path, workFolder: work.path,
                       trashFolder: trash.path, oldVersion: "1.0.0", newVersion: "1.1.0", logFile: log.path,
                       opener: opener.path, waitSeconds: waitSeconds)
        }

        /// Writes the script and runs it to the end.
        func run(_ plan: HelperPlan) throws {
            try Data(UpdateHelper.script(plan).utf8).write(to: script)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }

        var logText: String { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }
        var openedPaths: [String] {
            ((try? String(contentsOf: opened, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        var trashed: [String] { ((try? files.contentsOfDirectory(atPath: trash.path)) ?? []).sorted() }

        func cleanUp() {
            _ = try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unzipped.path)
            try? files.removeItem(at: root.deletingLastPathComponent())
        }
    }

    /// The id of a process that has already finished, so `kill -0` finds nothing to wait for.
    static func finishedProcessID() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    @Test func theNewAppReplacesTheOldAndTheOldGoesToTheTrash() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.run(rig.plan(processID: try Self.finishedProcessID()))

        #expect(rig.marker(of: rig.oldApp) == "new", "the new app is where the old one was")
        #expect(rig.trashed == ["Quote Pilot 1.0.0.app"])
        #expect(rig.marker(of: rig.trash.appendingPathComponent("Quote Pilot 1.0.0.app")) == "old", "kept, not deleted")
        #expect(rig.openedPaths == [rig.oldApp.path])
        #expect(rig.logText.contains("Moved the old app to the Trash"))
        #expect(rig.logText.contains("The new app is in place"))
        #expect(rig.logText.contains("Update finished"))
        #expect(!rig.files.fileExists(atPath: rig.script.path), "the script removes itself")
        #expect(!rig.files.fileExists(atPath: rig.work.path), "and the empty temporary folder")
    }

    @Test func ifTheNewAppCantMoveInTheOldOneComesBackAndOpens() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        // A folder that can't be taken from makes the second move fail, after the first has worked.
        try rig.files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: rig.unzipped.path)
        try rig.run(rig.plan(processID: try Self.finishedProcessID()))

        #expect(rig.marker(of: rig.oldApp) == "old", "the old app is back where it was")
        #expect(rig.trashed.isEmpty)
        #expect(rig.openedPaths == [rig.oldApp.path])
        #expect(rig.logText.contains("Moved the old app to the Trash"))
        #expect(rig.logText.contains("putting the old app back"))
        #expect(rig.logText.contains("The old app is back"))
        #expect(rig.logText.contains("The update did not finish"))
    }

    @Test func aMissingNewAppChangesNothingAndOpensTheOldOne() throws {
        let rig = try Rig(newApp: false)
        defer { rig.cleanUp() }
        try rig.run(rig.plan(processID: try Self.finishedProcessID()))

        #expect(rig.marker(of: rig.oldApp) == "old")
        #expect(rig.trashed.isEmpty)
        #expect(rig.openedPaths == [rig.oldApp.path])
        #expect(rig.logText.contains("the new app is missing"))
    }

    @Test func aTrashItCantUseChangesNothingAndOpensTheOldOne() throws {
        let rig = try Rig(trash: false)
        defer { rig.cleanUp() }
        try rig.run(rig.plan(processID: try Self.finishedProcessID()))

        #expect(rig.marker(of: rig.oldApp) == "old")
        #expect(rig.marker(of: rig.newApp) == "new", "the new app is left where it was")
        #expect(rig.openedPaths == [rig.oldApp.path])
        #expect(rig.logText.contains("could not move the old app to the Trash"))
    }

    @Test func aCopyAlreadyInTheTrashIsNeverOverwritten() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let earlier = rig.trash.appendingPathComponent("Quote Pilot 1.0.0.app")
        try rig.makeApp(earlier, marker: "older")
        try rig.run(rig.plan(processID: try Self.finishedProcessID()))

        #expect(rig.marker(of: earlier) == "older")
        #expect(rig.trashed.count == 2)
        let other = try #require(rig.trashed.first { $0 != "Quote Pilot 1.0.0.app" })
        #expect(other.hasPrefix("Quote Pilot 1.0.0 ") && other.hasSuffix(".app"))
        #expect(rig.marker(of: rig.trash.appendingPathComponent(other)) == "old")
        #expect(rig.marker(of: rig.oldApp) == "new")
    }

    @Test func ifQuotePilotNeverQuitsItGivesUpAndOpensTheOldApp() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/bin/sleep")
        busy.arguments = ["30"]
        try busy.run()
        defer { busy.terminate() }

        try rig.run(rig.plan(processID: busy.processIdentifier, waitSeconds: 1))
        #expect(rig.marker(of: rig.oldApp) == "old")
        #expect(rig.trashed.isEmpty)
        #expect(rig.openedPaths == [rig.oldApp.path])
        #expect(rig.logText.contains("still running"))
    }

    @Test func theHelperStartsDetachedFromAShell() async throws {
        let folder = UIFixture.makeFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("ran.txt")
        let script = folder.appendingPathComponent("hello.sh")
        try Data("#!/bin/sh\necho started > '\(marker.path)'\n".utf8).write(to: script)
        try UpdateFiles.startDetached(script)
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }
}

// MARK: Download, unzip, check

@Suite struct SystemInstallerTests {
    struct Rig {
        let root = UIFixture.makeFolder()
        var temporary: URL { root.appendingPathComponent("tmp", isDirectory: true) }
        var zip: URL { root.appendingPathComponent("QuotePilot-mac.zip") }

        init() throws {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        }

        /// A made-up "Quote Pilot.app", zipped the way `scripts/release.sh` zips the real one.
        func makeZip(id: String = "com.fynnprojects.quotepilot", version: String = "1.1.0") async throws {
            let source = root.appendingPathComponent("source", isDirectory: true)
            let app = source.appendingPathComponent("Quote Pilot.app", isDirectory: true)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"),
                                                    withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version,
                                       "CFBundleExecutable": "Quote Pilot"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            let program = app.appendingPathComponent("Contents/MacOS/Quote Pilot")
            try Data("#!/bin/sh\n".utf8).write(to: program)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
            let status = try await UpdateFiles.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
            #expect(status == 0)
        }

        func installer(downloading: @escaping SystemInstaller.Download) -> SystemInstaller {
            SystemInstaller(download: downloading, temporaryFolder: temporary)
        }

        /// A "download" that copies the zip made above.
        var copyingTheZip: SystemInstaller.Download {
            { [zip] _, _, destination in try FileManager.default.copyItem(at: zip, to: destination) }
        }

        var leftovers: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: temporary.path)) ?? []) }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    func log(_ rig: Rig) -> UpdateLog { UpdateLog(url: rig.root.appendingPathComponent("update.log")) }

    @Test func aGoodZipIsUnpackedAndChecked() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try await rig.makeZip()
        let staged = try await rig.installer(downloading: rig.copyingTheZip)
            .stage(UpdateFixture.release("1.1.0"), runningVersion: "1.0.0", log: log(rig))
        #expect(staged.app.lastPathComponent == "Quote Pilot.app")
        #expect(staged.app.path.hasPrefix(rig.temporary.path))
        #expect(FileManager.default.isExecutableFile(atPath: staged.app.appendingPathComponent("Contents/MacOS/Quote Pilot").path))
        #expect(!FileManager.default.fileExists(atPath: staged.workFolder.appendingPathComponent("QuotePilot-mac.zip").path),
                "the zip is deleted once it is unpacked")
        #expect((try? String(contentsOf: rig.root.appendingPathComponent("update.log"), encoding: .utf8))?.contains("Downloaded") == true)
    }

    @Test func theDownloadAsksForTheReleaseFileAndNamesTheRunningVersion() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try await rig.makeZip()
        actor Asked {
            var url: URL?
            var version: String?
            func set(_ url: URL, _ version: String) { self.url = url; self.version = version }
        }
        let asked = Asked()
        let zip = rig.zip
        _ = try await rig.installer(downloading: { url, version, destination in
            await asked.set(url, version)
            try FileManager.default.copyItem(at: zip, to: destination)
        }).stage(UpdateFixture.release("1.1.0"), runningVersion: "1.0.0", log: log(rig))
        #expect(await asked.url == UpdateFixture.release("1.1.0").downloadURL)
        #expect(await asked.version == "1.0.0")
    }

    @Test func anotherAppOrVersionIsRefusedAndNothingIsLeftBehind() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try await rig.makeZip(id: "com.example.other")
        await #expect(throws: UpdateError.self) {
            _ = try await rig.installer(downloading: rig.copyingTheZip)
                .stage(UpdateFixture.release("1.1.0"), runningVersion: "1.0.0", log: log(rig))
        }
        #expect(rig.leftovers.isEmpty)

        try? FileManager.default.removeItem(at: rig.zip)
        try? FileManager.default.removeItem(at: rig.root.appendingPathComponent("source"))
        try await rig.makeZip(version: "1.0.5")
        do {
            _ = try await rig.installer(downloading: rig.copyingTheZip)
                .stage(UpdateFixture.release("1.1.0"), runningVersion: "1.0.0", log: log(rig))
            Issue.record("A zip with the wrong version should be refused")
        } catch let error as UpdateError {
            #expect(error.localizedDescription.contains("it is version 1.0.5, not 1.1.0"))
        }
        #expect(rig.leftovers.isEmpty)
    }

    @Test func aFileThatIsntAZipAndAFailedDownloadAreRefusedToo() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        await #expect(throws: UpdateError.self) {
            _ = try await rig.installer(downloading: { _, _, destination in
                try Data("not a zip".utf8).write(to: destination)
            }).stage(UpdateFixture.release("1.1.0"), runningVersion: "1.0.0", log: log(rig))
        }
        #expect(rig.leftovers.isEmpty)

        await #expect(throws: UpdateError.self) {
            _ = try await rig.installer(downloading: { _, _, _ in throw UpdateError.downloadFailed("offline") })
                .stage(UpdateFixture.release("1.1.0"), runningVersion: "1.0.0", log: log(rig))
        }
        #expect(rig.leftovers.isEmpty)
    }
}

// MARK: The model

@MainActor
@Suite struct UpdateInstallModelTests {
    final class Events {
        var list: [String] = []
    }

    struct Setup {
        var model: AppModel
        var installer: FakeInstaller
        var settings: MemoryUpdateSettings
        var events: Events
    }

    /// A model that has found 1.1.0 (when `available`), sitting in /Applications.
    func setup(bundlePath: String = "/Applications/Quote Pilot.app", writable: Bool = true,
               available: Bool = true) throws -> Setup {
        let installer = FakeInstaller()
        let settings = MemoryUpdateSettings()
        let events = Events()
        let model = try UIFixture.model()
        model.updates = UpdateFixture.services(
            bundlePath: bundlePath, settings: settings, installer: installer, folderIsWritable: { _ in writable },
            quit: { events.list.append("quit, expecting \(settings.updateExpectedVersion ?? "nothing")") })
        installer.onHandOver = { events.list.append("handed over, expecting \(settings.updateExpectedVersion ?? "nothing")") }
        if available { model.availableUpdate = UpdateFixture.release("1.1.0") }
        return Setup(model: model, installer: installer, settings: settings, events: events)
    }

    func waitFor(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: Asking

    @Test func installUpdateAsksOnceWithUpdateAsTheDefault() throws {
        let s = try setup()
        s.model.installUpdate()
        let box = try #require(s.model.message)
        #expect(box.title == "Install Update")
        #expect(box.text == "Update to Quote Pilot 1.1.0? Quote Pilot will close and reopen. Your quotes, invoices and settings are kept.")
        #expect(box.choices.map(\.title) == ["Update", "Not Now"])
        #expect(box.choices.first(where: \.isDefault)?.title == "Update")
        #expect(box.choices.first(where: \.isCancel)?.title == "Not Now")
        #expect(s.installer.staged.isEmpty, "nothing happens before the click")
    }

    @Test func notNowDoesNothing() throws {
        let s = try setup()
        s.model.installUpdate()
        s.model.respond(try #require(s.model.message?.choices.last))
        #expect(s.installer.staged.isEmpty)
        #expect(s.events.list.isEmpty)
        #expect(s.settings.updateExpectedVersion == nil)
        #expect(s.model.message == nil)
        #expect(s.model.canInstallUpdate, "still on, for later")
    }

    @Test func aCopyThatCantReplaceItselfIsToldSoInsteadOfBeingAsked() throws {
        let translocated = try setup(bundlePath: "/private/var/folders/ab/AppTranslocation/1A2B/d/Quote Pilot.app")
        translocated.model.installUpdate()
        #expect(translocated.model.message?.text == "Move Quote Pilot into your Applications folder first, then try again.")
        #expect(translocated.model.message?.choices.count == 1)

        let readOnly = try setup(writable: false)
        readOnly.model.installUpdate()
        #expect(readOnly.model.message?.text == "Move Quote Pilot into your Applications folder first, then try again.")
        #expect(readOnly.installer.staged.isEmpty)
    }

    @Test func withNothingToInstallItJustBeeps() throws {
        let s = try setup(available: false)
        var beeps = 0
        s.model.beep = { beeps += 1 }
        s.model.installUpdate()
        #expect(beeps == 1)
        #expect(s.model.message == nil)
    }

    // MARK: Installing

    @Test func updateDownloadsHandsOverRemembersTheVersionAndThenQuits() async throws {
        let s = try setup()
        s.model.installUpdate()
        s.model.respond(try #require(s.model.message?.choices.first))
        try await waitFor { s.events.list.count >= 2 }

        #expect(s.installer.staged == [UpdateFixture.release("1.1.0")])
        #expect(s.installer.handOvers == [.init(appPath: "/Applications/Quote Pilot.app", from: "1.0.0", to: "1.1.0")])
        // The helper is started before the marker is written, and the quit comes last.
        #expect(s.events.list == ["handed over, expecting nothing", "quit, expecting 1.1.0"])
        #expect(s.settings.updateExpectedVersion == "1.1.0")
        #expect(s.model.message == nil)
        let log = try String(contentsOf: s.model.updates.log.url, encoding: .utf8)
        #expect(log.contains("Installing Quote Pilot 1.1.0"))
    }

    @Test func aFailedDownloadShowsOneBoxAndChangesNothing() async throws {
        let s = try setup()
        s.installer.stageResult = .failure(UpdateError.downloadFailed("The Internet connection appears to be offline."))
        await s.model.install(UpdateFixture.release("1.1.0"))

        let box = try #require(s.model.message)
        #expect(box.title == "Couldn't Update")
        #expect(box.text == "The update couldn't be downloaded. The Internet connection appears to be offline.")
        #expect(s.installer.handOvers.isEmpty)
        #expect(s.settings.updateExpectedVersion == nil)
        #expect(s.events.list.isEmpty, "no quit")
        #expect(s.model.canInstallUpdate && s.model.canCheckForUpdates, "it can be tried again")
    }

    @Test func aHelperThatWontStartShowsOneBoxAndLeavesNoMarker() async throws {
        let s = try setup()
        s.installer.handOverError = UpdateError.couldNotStartHelper("Permission denied.")
        await s.model.install(UpdateFixture.release("1.1.0"))

        #expect(s.model.message?.title == "Couldn't Update")
        #expect(s.settings.updateExpectedVersion == nil)
        #expect(s.events.list == ["handed over, expecting nothing"], "tried, but did not quit")
    }

    @Test func aSecondInstallWhileOneRunsIsIgnored() async throws {
        let s = try setup()
        s.model.isInstallingUpdate = true
        await s.model.install(UpdateFixture.release("1.1.0"))
        #expect(s.installer.staged.isEmpty)
    }

    // MARK: The next launch

    @Test func afterAnUpdateTheNextLaunchSaysSoOnce() throws {
        let s = try setup(available: false)
        s.model.updates.version = "1.1.0"
        s.settings.updateExpectedVersion = "1.1.0"
        s.model.finishPendingUpdate()

        #expect(s.model.statusNote?.text == "Updated to 1.1.0")
        #expect(s.model.library.activity.first?.message == "Updated Quote Pilot to 1.1.0")
        #expect(s.settings.updateExpectedVersion == nil, "the marker is cleared")
        #expect(s.model.message == nil)

        let entries = s.model.library.activity.count
        s.model.finishPendingUpdate()
        #expect(s.model.library.activity.count == entries, "said once")
    }

    @Test func ifTheOldVersionCameBackTheNextLaunchPointsToTheLog() throws {
        let s = try setup(available: false)
        s.settings.updateExpectedVersion = "1.1.0"
        s.model.finishPendingUpdate()

        #expect(s.model.statusNote?.text == "The update didn't finish. Details are in ~/Library/Logs/Quote Pilot/update.log")
        #expect(s.model.library.activity.first?.message.contains("didn't finish") == true)
        #expect(s.settings.updateExpectedVersion == nil, "the marker is cleared either way")
        let log = try String(contentsOf: s.model.updates.log.url, encoding: .utf8)
        #expect(log.contains("did not finish"))

        let entries = s.model.library.activity.count
        s.model.finishPendingUpdate()
        #expect(s.model.library.activity.count == entries)
    }

    @Test func withoutAMarkerTheNextLaunchSaysNothing() throws {
        let s = try setup(available: false)
        s.model.finishPendingUpdate()
        #expect(s.model.statusNote == nil)
        #expect(s.model.library.activity.isEmpty)
    }

    @Test func startReportsTheLastUpdateBeforeCheckingForANewOne() async throws {
        let s = try setup(available: false)
        s.model.updates.version = "1.1.0"
        s.settings.updateExpectedVersion = "1.1.0"
        s.settings.lastUpdateCheck = s.model.now()
        await s.model.start()
        #expect(s.model.statusNote?.text == "Updated to 1.1.0")
    }

    // MARK: The Help menu

    @Test func theHelpMenuItemsFollowWhatTheAppCanDo() async throws {
        // Nothing found yet: Check on, Install off.
        let none = try setup(available: false)
        #expect(none.model.canCheckForUpdates)
        #expect(!none.model.canInstallUpdate)

        // A newer version found: both on.
        let found = try setup()
        #expect(found.model.canCheckForUpdates)
        #expect(found.model.canInstallUpdate)

        // While a check waits for GitHub: Check off.
        found.model.isCheckingForUpdates = true
        #expect(!found.model.canCheckForUpdates)
        #expect(found.model.canInstallUpdate)
        found.model.isCheckingForUpdates = false

        // While installing: both off.
        found.model.isInstallingUpdate = true
        #expect(!found.model.canCheckForUpdates)
        #expect(!found.model.canInstallUpdate)
        found.model.isInstallingUpdate = false

        // A check that says this is the newest version turns Install off again.
        found.model.updates = UpdateFixture.services(
            script: FetchScript(json: UpdateFixture.releaseJSON(tag: "v1.0.0")), installer: found.installer)
        await found.model.checkForUpdates(manual: false)
        #expect(!found.model.canInstallUpdate)
        #expect(found.model.canCheckForUpdates)
    }
}
