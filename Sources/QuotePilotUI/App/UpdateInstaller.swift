import Foundation

// Installing an update. A running app can't replace itself, so Quote Pilot downloads and unpacks the
// new one, checks it, writes a small /bin/sh helper, starts it detached and quits. The helper waits
// for Quote Pilot to be gone, moves the old app to the Trash, puts the new one in its place and opens
// it. Whatever goes wrong, it opens an app: the old one, put back from the Trash, if need be.
//
// This file keeps the rules and the script text pure (so the tests can read and run them) and the
// downloading and unzipping in `SystemInstaller`.

enum UpdateRules {
    static let moveToApplications = "Move Quote Pilot into your Applications folder first, then try again."
    static let notAnApp = "Quote Pilot can only update itself when it is running as an app."

    /// Why this copy of Quote Pilot can't replace itself, or nil when it can. A copy macOS runs from a
    /// random read-only "App Translocation" folder (a freshly downloaded app that was never moved), or
    /// from a folder the user can't write to, would be swapped for a copy nobody opens.
    static func installProblem(bundlePath: String, folderIsWritable: (String) -> Bool) -> String? {
        if bundlePath.contains("/AppTranslocation/") { return moveToApplications }
        guard bundlePath.hasSuffix(".app") else { return notAnApp }
        let folder = (bundlePath as NSString).deletingLastPathComponent
        return folderIsWritable(folder) ? nil : moveToApplications
    }
}

/// Checks the downloaded app before anything is touched.
enum UpdateVerifier {
    /// Why this Info.plist isn't the Quote Pilot version `expectedVersion`, or nil when it is.
    static func problem(in info: [String: Any]?, expectedVersion: String) -> String? {
        guard let info else { return "it has no Info.plist" }
        guard info["CFBundleIdentifier"] as? String == UpdateSource.bundleID else {
            return "it is a different app"
        }
        let found = info["CFBundleShortVersionString"] as? String ?? ""
        guard let foundVersion = VersionNumber(found), let expected = VersionNumber(expectedVersion),
              foundVersion == expected
        else { return "it is version \(found.isEmpty ? "unknown" : found), not \(expectedVersion)" }
        guard let program = info["CFBundleExecutable"] as? String, !program.isEmpty, !program.contains("/") else {
            return "it has no program"
        }
        return nil
    }
}

/// What the next launch makes of an update that was started on the last one.
enum UpdateOutcome: Equatable {
    case updated(String)
    case didNotFinish

    /// `expected` is the version the install was meant to leave running (nil when none was started).
    /// A newer version than expected also counts as updated: the update did happen.
    static func afterLaunch(running: String, expected: String?) -> UpdateOutcome? {
        guard let expected, let wanted = VersionNumber(expected) else { return nil }
        if let current = VersionNumber(running), current >= wanted { return .updated(current.description) }
        return .didNotFinish
    }
}

/// Everything the helper script needs to know.
struct HelperPlan {
    /// Quote Pilot's own process; the helper waits for it to exit.
    var processID: Int32
    /// The app being replaced, as an absolute path.
    var oldApp: String
    /// The unzipped new app.
    var newApp: String
    /// The temporary folder holding the new app, the script and nothing else.
    var workFolder: String
    /// `~/.Trash`, written out.
    var trashFolder: String
    var oldVersion: String
    var newVersion: String
    var logFile: String
    /// What opens an app. Tests swap it for a script that only writes down what it was asked to open.
    var opener = "/usr/bin/open"
    /// How long to wait for Quote Pilot to quit.
    var waitSeconds = 60
}

enum UpdateHelper {
    /// `text` in single quotes, safe to paste into a shell script.
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A version as it may appear in a file name: letters, digits, dots and dashes.
    static func fileSafe(_ version: String) -> String {
        String(version.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") ? $0 : "_" })
    }

    /// The `/bin/sh` script that swaps the app. It never deletes an app: the old copy goes to the Trash
    /// as "Quote Pilot <old version>.app" (with the time added if that name is taken), and comes back
    /// from there if the new one can't be moved in. Every step goes into the log, and `relaunch` runs
    /// at the end of both the success and the failure path.
    static func script(_ plan: HelperPlan) -> String {
        let old = fileSafe(plan.oldVersion)
        return #"""
        #!/bin/sh
        # Quote Pilot update helper, written by Quote Pilot \#(plan.oldVersion) to move it to \#(plan.newVersion).
        # It waits for Quote Pilot to quit, moves the old app to the Trash (it never deletes anything),
        # puts the new app in its place and opens it. If a step fails it puts the old app back. Either
        # way it opens an app at the end.
        PID=\#(plan.processID)
        OLD=\#(quote(plan.oldApp))
        NEW=\#(quote(plan.newApp))
        WORK=\#(quote(plan.workFolder))
        TRASH=\#(quote(plan.trashFolder))
        LOG=\#(quote(plan.logFile))
        OPEN=\#(quote(plan.opener))
        TRASHED="$TRASH/Quote Pilot \#(old).app"
        dest=""

        say() { printf '%s  [helper] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

        relaunch() {
          target="$OLD"
          [ -d "$target" ] || target="$dest"
          [ -d "$target" ] || target="$NEW"
          say "Opening $target"
          "$OPEN" "$target" >> "$LOG" 2>&1 || say "ERROR could not open $target"
        }

        swap() {
          [ -d "$NEW" ] || { say "ERROR the new app is missing: $NEW"; return 1; }
          dest="$TRASHED"
          [ -e "$dest" ] && dest="$TRASH/Quote Pilot \#(old) $(date '+%H%M%S').app"
          mv "$OLD" "$dest" >> "$LOG" 2>&1 || { say "ERROR could not move the old app to the Trash"; dest=""; return 1; }
          say "Moved the old app to the Trash: $dest"
          if mv "$NEW" "$OLD" >> "$LOG" 2>&1; then
            xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
            say "The new app is in place (quarantine flag cleared)"
            return 0
          fi
          say "ERROR could not move the new app into place; putting the old app back"
          if mv "$dest" "$OLD" >> "$LOG" 2>&1; then
            say "The old app is back"
          else
            say "ERROR could not put the old app back from the Trash: $dest"
          fi
          return 1
        }

        mkdir -p "$(dirname "$LOG")"
        say "Updating Quote Pilot \#(plan.oldVersion) to \#(plan.newVersion); waiting for process $PID to quit"
        tries=0
        while kill -0 "$PID" 2>/dev/null && [ "$tries" -lt \#(plan.waitSeconds * 2) ]; do
          sleep 0.5
          tries=$((tries + 1))
        done

        if kill -0 "$PID" 2>/dev/null; then
          say "ERROR Quote Pilot was still running after \#(plan.waitSeconds) seconds; update abandoned"
          updated=no
        elif swap; then
          updated=yes
        else
          updated=no
        fi

        if [ "$updated" = yes ]; then
          say "Update finished: Quote Pilot \#(plan.newVersion)"
          relaunch
        else
          say "The update did not finish; Quote Pilot \#(plan.oldVersion) stays"
          relaunch
        fi

        # Tidy up: only the empty folders and this script, never an app.
        rmdir "$(dirname "$NEW")" 2>/dev/null
        rm -f "$0"
        rmdir "$WORK" 2>/dev/null
        exit 0
        """#
    }
}
