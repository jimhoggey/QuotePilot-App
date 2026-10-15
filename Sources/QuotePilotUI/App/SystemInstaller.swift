import Foundation

/// A downloaded, unpacked and checked new app, waiting to be swapped in.
struct StagedUpdate {
    /// The temporary folder everything was unpacked into.
    var workFolder: URL
    /// "Quote Pilot.app" inside it.
    var app: URL
}

/// The two halves of an install. The app model drives them; tests replace them with a fake.
protocol UpdateInstalling {
    /// Downloads the release, unzips it and checks that it is the Quote Pilot it should be. Nothing
    /// outside the temporary folder is touched.
    func stage(_ release: ReleaseInfo, runningVersion: String, log: UpdateLog) async throws -> StagedUpdate

    /// Writes the helper script and starts it, detached, so that it outlives Quote Pilot. The caller
    /// quits right after.
    func handOver(_ staged: StagedUpdate, replacing appPath: String, from oldVersion: String,
                  to newVersion: String, log: UpdateLog) throws
}

enum UpdateFiles {
    /// Starts `script` in the background with /bin/sh, detached from Quote Pilot (`nohup`, output
    /// discarded, and not waited for), so quitting Quote Pilot doesn't stop it.
    static func startDetached(_ script: URL) throws {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", #"/usr/bin/nohup /bin/sh "$1" >/dev/null 2>&1 &"#, "sh", script.path]
        shell.standardInput = FileHandle.nullDevice
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        try shell.run()
    }

    /// Runs a tool to the end and returns its exit status.
    static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// The real installer: URLSession for the download, `ditto` for the unzip (the same tool that made
/// the zip, which keeps the app's symlinks and permissions), and the helper script for the swap.
struct SystemInstaller: UpdateInstalling {
    typealias Download = (_ url: URL, _ version: String, _ destination: URL) async throws -> Void

    /// Saves `url` to `destination`. Tests pass one that copies a local file instead.
    var download: Download = SystemInstaller.downloadFile
    /// Where the temporary folder goes.
    var temporaryFolder = FileManager.default.temporaryDirectory
    var homeFolder = FileManager.default.homeDirectoryForCurrentUser

    static let downloadFile: Download = { url, version, destination in
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("QuotePilot/\(version)", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        do {
            let (temporary, response) = try await URLSession(configuration: .ephemeral).download(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                throw UpdateError.downloadFailed("GitHub answered with an error (\(status)).")
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
    }

    func stage(_ release: ReleaseInfo, runningVersion: String, log: UpdateLog) async throws -> StagedUpdate {
        let files = FileManager.default
        let work = temporaryFolder.appendingPathComponent("QuotePilotUpdate-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let zip = work.appendingPathComponent(UpdateSource.assetName)
            try await download(release.downloadURL, runningVersion, zip)
            let size = (try? files.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? 0
            log.append("Downloaded \(UpdateSource.assetName) (\(size) bytes)")

            let unzipped = work.appendingPathComponent("unzipped", isDirectory: true)
            try files.createDirectory(at: unzipped, withIntermediateDirectories: true)
            guard try await UpdateFiles.run("/usr/bin/ditto", ["-x", "-k", zip.path, unzipped.path]) == 0 else {
                throw UpdateError.unzipFailed
            }
            try? files.removeItem(at: zip)

            let app = unzipped.appendingPathComponent(UpdateSource.appName, isDirectory: true)
            try Self.verify(app, expectedVersion: release.version)
            log.append("Unpacked and checked \(UpdateSource.appName) \(release.version)")
            return StagedUpdate(workFolder: work, app: app)
        } catch {
            // Only the temporary folder made above goes; nothing of the user's is touched.
            try? files.removeItem(at: work)
            throw error
        }
    }

    /// Throws unless `app` is a Quote Pilot of the expected version with a program inside it.
    static func verify(_ app: URL, expectedVersion: String) throws {
        let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        if let problem = UpdateVerifier.problem(in: info, expectedVersion: expectedVersion) {
            throw UpdateError.notTheApp(problem)
        }
        let program = (info?["CFBundleExecutable"] as? String) ?? ""
        guard FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/\(program)").path) else {
            throw UpdateError.notTheApp("it has no program")
        }
    }

    func handOver(_ staged: StagedUpdate, replacing appPath: String, from oldVersion: String,
                  to newVersion: String, log: UpdateLog) throws {
        let plan = HelperPlan(processID: ProcessInfo.processInfo.processIdentifier, oldApp: appPath,
                              newApp: staged.app.path, workFolder: staged.workFolder.path,
                              trashFolder: homeFolder.appendingPathComponent(".Trash").path,
                              oldVersion: oldVersion, newVersion: newVersion, logFile: log.url.path)
        let script = staged.workFolder.appendingPathComponent("update.sh")
        do {
            try Data(UpdateHelper.script(plan).utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            try UpdateFiles.startDetached(script)
        } catch {
            try? FileManager.default.removeItem(at: staged.workFolder)
            throw UpdateError.couldNotStartHelper(error.localizedDescription)
        }
        log.append("Started the helper \(script.path) to replace \(appPath) once Quote Pilot has quit")
    }
}
