import Foundation

extension AppModel {
    // MARK: What the Help menu can run

    /// The running app's version, as the Help menu shows it.
    public var currentVersion: String { updates.version }

    /// Whether Check for Updates… can run: not while a check is already waiting for GitHub.
    public var canCheckForUpdates: Bool { !isCheckingForUpdates }

    // MARK: Checking

    /// Runs when the window first appears: the automatic check for updates.
    public func start() async {
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

    /// Help → Check for Updates…
    public func checkForUpdatesNow() {
        Task { await checkForUpdates(manual: true) }
    }

    /// Asks GitHub for the newest release. A newer one goes in the status bar and turns on Install
    /// Update…. A check the user asked for also answers in a box when this is the newest version or
    /// the check failed; the automatic one never does, and a failure only reaches the log.
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
}
