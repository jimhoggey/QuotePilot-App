import Foundation

extension AppModel {
    // MARK: What the Help menu can run

    /// The running app's version, as the Help menu shows it.
    public var currentVersion: String { updates.version }

    /// Whether Check for Updates… can run: not while a check is waiting for GitHub or an install is
    /// under way.
    public var canCheckForUpdates: Bool { !isCheckingForUpdates && !isInstallingUpdate }

    /// Whether Install Update… can run: a check has found a newer version, and it isn't being
    /// installed already.
    public var canInstallUpdate: Bool { availableUpdate != nil && !isInstallingUpdate }

    // MARK: Launch

    /// Runs when the window first appears: says how the last update went, if one was started, then
    /// does the automatic check for updates.
    public func start() async {
        finishPendingUpdate()
        await checkForUpdatesAtLaunch()
    }

    /// The check at launch. It asks GitHub at most once every 24 hours, only in a real app, and says
    /// nothing unless there is a newer version (and then only in the status bar).
    func checkForUpdatesAtLaunch() async {
        guard updates.isBundledApp,
              UpdateThrottle.isDue(lastCheck: updates.settings.lastUpdateCheck, now: now())
        else { return }
        await checkForUpdates(manual: false)
    }

    /// The first launch after an install. The install left a marker with the version it should have
    /// left running; here that is compared with the version that is, and the marker is cleared either
    /// way, so the status bar and Activity say so once. A failed update leaves the old app running,
    /// which is why the helper's log is named.
    func finishPendingUpdate() {
        let expected = updates.settings.updateExpectedVersion
        updates.settings.updateExpectedVersion = nil
        guard let expected,
              let outcome = UpdateOutcome.afterLaunch(running: updates.version, expected: expected)
        else { return }
        switch outcome {
        case .updated(let version):
            updates.log.append("Next launch: Quote Pilot \(version) is running, as expected. The update worked")
            _ = tryChange { $0.log("Updated Quote Pilot to \(version)") }
            note("Updated to \(version)")
        case .didNotFinish:
            updates.log.append("Next launch: Quote Pilot \(updates.version) is running, but \(expected) was expected. The update did not finish")
            _ = tryChange { $0.log("The update to Quote Pilot \(expected) didn't finish. Quote Pilot \(self.updates.version) is still installed") }
            note("The update didn't finish. Details are in \(UpdateLog.displayPath)")
        }
    }

    // MARK: Checking

    /// Help → Check for Updates…
    public func checkForUpdatesNow() {
        Task { await checkForUpdates(manual: true) }
    }

    /// Asks GitHub for the newest release. A newer one goes in the status bar and turns on Install
    /// Update…. A check the user asked for also answers in a box: it offers the update, says this is
    /// the newest version, or says the check failed. The automatic one never does, and a failure only
    /// reaches the log.
    func checkForUpdates(manual: Bool) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        let version = updates.version
        do {
            let release = try await UpdateChecker(currentVersion: version, fetch: updates.fetch).check()
            // Only a check that got an answer starts the 24 hours: one that failed tries again at the
            // next launch.
            updates.settings.lastUpdateCheck = now()
            availableUpdate = release
            if let release {
                updates.log.append("Checked for updates: Quote Pilot \(release.version) is available (this is \(version))")
                note("Quote Pilot \(release.version) is available. Help → Install Update…")
                if manual, message == nil { installUpdate() }
            } else {
                updates.log.append("Checked for updates: \(version) is the newest version")
                if manual {
                    show(title: "Check for Updates", text: "You have the newest version (\(version)).")
                }
            }
        } catch {
            updates.log.append("Checking for updates failed: \(error.localizedDescription)")
            if manual {
                show(title: "Couldn't Check for Updates",
                     text: "Quote Pilot couldn't check for updates. \(error.localizedDescription)", kind: .warning)
            }
        }
    }

    // MARK: Installing

    /// Help → Install Update…: asks once, then downloads, swaps and reopens. It never installs on its
    /// own. A copy that can't replace itself is told so first, before it is asked anything.
    public func installUpdate() {
        guard canInstallUpdate, let release = availableUpdate else { return beep() }
        if let problem = UpdateRules.installProblem(bundlePath: updates.bundlePath,
                                                    folderIsWritable: updates.folderIsWritable) {
            updates.log.append("Won't install \(release.version) from \(updates.bundlePath): \(problem)")
            show(title: "Can't Update", text: problem, kind: .warning)
            return
        }
        message = MessageBox(
            kind: .question, title: "Install Update",
            text: "Update to Quote Pilot \(release.version)? Quote Pilot will close and reopen. Your quotes, invoices and settings are kept.",
            choices: [
                MessageBox.Choice("Update", isDefault: true) { [weak self] in
                    guard let self else { return }
                    Task { await self.install(release) }
                },
                MessageBox.Choice("Not Now", isCancel: true),
            ])
    }

    /// Download, unpack and check the new app, start the helper, remember which version to expect and
    /// quit. A failure at any step shows one box and leaves the app exactly as it was.
    func install(_ release: ReleaseInfo) async {
        guard !isInstallingUpdate else { return }
        isInstallingUpdate = true
        defer { isInstallingUpdate = false }
        let log = updates.log
        log.append("Installing Quote Pilot \(release.version) over \(updates.version) at \(updates.bundlePath)")
        note("Downloading update…")
        do {
            let staged = try await updates.installer.stage(release, runningVersion: updates.version, log: log)
            try updates.installer.handOver(staged, replacing: updates.bundlePath, from: updates.version,
                                           to: release.version, log: log)
            // The helper is running and waiting for us. The next launch looks for this version.
            updates.settings.updateExpectedVersion = release.version
            log.append("Quitting so the helper can swap in Quote Pilot \(release.version)")
            updates.quit()
        } catch {
            log.append("The update to \(release.version) failed: \(error.localizedDescription)")
            note("The update didn't install")
            show(error, title: "Couldn't Update")
        }
    }
}
