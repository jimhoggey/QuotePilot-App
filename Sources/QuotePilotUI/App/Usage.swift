import Foundation
import Observation

/// Everything Quote Pilot can tell its developer about how it's used, through Aptabase
/// (aptabase.com). This list is the whole of it: an event's name, plus a few short words or numbers.
/// The fee events also carry the Quote Pilot fee's month, rate and amount, so the developer can check
/// them against what was transferred (the user, 24 Oct 2026). Never client names, document numbers,
/// amounts received, file names or anything typed.
public enum UsageEvent: String, CaseIterable, Sendable {
    /// fee_on, fee_percent.
    case appStarted = "app_started"
    case updated
    case quoteCreated = "quote_created"
    case invoiceCreated = "invoice_created"
    case clientCreated = "client_created"
    case expenseCreated = "expense_created"
    /// kind: quote, invoice or receipt. Sent once the user says Yes, Sent.
    case sent
    case replyRead = "reply_read"
    case jobCompleted = "job_completed"
    /// method: how it was paid.
    case paymentRecorded = "payment_recorded"
    /// kind: PDF, CSV or backup.
    case fileSaved = "file_saved"
    /// kind: quote, invoice, client or expense.
    case deleted
    case imported
    case recordsOpened = "records_opened"
    case backupRestored = "backup_restored"
    case startedFresh = "started_fresh"
    case numbersReset = "numbers_reset"
    /// fee_on, fee_percent: the fee's tick box or rate changed.
    case feeSettingChanged = "fee_setting_changed"
    /// month, fee_percent, fee: once for each month whose fee falls due.
    case feeDue = "fee_due"
    /// month, fee_percent, fee: once if that fee locks Quote Pilot.
    case feeLocked = "fee_locked"
    /// month, fee_percent, fee: I've paid.
    case feePaid = "fee_paid"
    /// tool: which of Claude's tools ran (`AppModel+Claude`).
    case claudeTool = "claude_tool"
}

/// Sends `UsageEvent`s to Aptabase, one small HTTPS post each, without waiting and without a word
/// when one fails. No identifier: a session is a random number kept in memory and renewed after an
/// hour idle, as Aptabase's own SDKs do. Only the installed app sends (or a run with `QP_STATS=1`);
/// the tests, `swift run` and test copies with their own bundle id send nothing, and `QP_STATS=0`
/// turns it off. Brand → Settings has a tick box for it.
@MainActor @Observable
public final class Usage {
    /// Quote Pilot's Aptabase key. It can only add events, so it's fine in a public repo.
    static let appKey = "A-US-1806196913"
    static let endpoint = URL(string: "https://us.aptabase.com/api/v0/event")!
    static let releaseBundleID = "com.fynnprojects.quotepilot"
    static let onKey = "SendUsage"
    static let sentMonthsKey = "UsageFeeMonthsSent"

    /// Whether this copy can send at all.
    @ObservationIgnored let isAvailable: Bool
    /// Marks events from a demo library or a forced run, which Aptabase keeps apart as Debug.
    @ObservationIgnored let isDebug: Bool
    /// Brand → Settings' tick box: on unless the user unticks it. Kept in the app's preferences.
    public var isOn: Bool {
        didSet { settings?.set(isOn, forKey: Self.onKey) }
    }
    @ObservationIgnored private let settings: UserDefaults?
    @ObservationIgnored private let post: (Data) -> Void
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var version: String = AppVersion.current
    @ObservationIgnored private var session: (id: String, last: Date)?
    /// The fee events already sent, "fee_due 2026-10", so each goes once a month; kept in the
    /// preferences, or here when there are none (tests).
    @ObservationIgnored private var sentMonths: Set<String>

    init(isAvailable: Bool, isDebug: Bool, settings: UserDefaults?, post: @escaping (Data) -> Void) {
        self.isAvailable = isAvailable
        self.isDebug = isDebug
        self.settings = settings
        self.post = post
        isOn = settings?.object(forKey: Self.onKey) as? Bool ?? true
        sentMonths = Set(settings?.stringArray(forKey: Self.sentMonthsKey) ?? [])
    }

    /// The running app's: sends from the installed Quote Pilot only, unless `QP_STATS` says otherwise.
    static func live(environment: [String: String] = ProcessInfo.processInfo.environment,
                     bundleID: String? = Bundle.main.bundleIdentifier) -> Usage {
        let forced = environment["QP_STATS"]
        let available = forced == "1" || (forced != "0" && bundleID == releaseBundleID)
        let debug = forced == "1" || environment["QP_LIBRARY_FOLDER"] != nil
        return Usage(isAvailable: available, isDebug: debug, settings: .standard, post: send)
    }

    /// Sends `event` if this copy can and the box is ticked. Props that aren't text, a number or
    /// true/false are left out.
    func track(_ event: UsageEvent, _ props: [String: Any] = [:]) {
        guard isAvailable, isOn, let body = body(event, props) else { return }
        post(body)
    }

    /// `track`, but only once for `event` in `month` ("2026-10"), ever.
    func trackOnce(_ event: UsageEvent, month: String, _ props: [String: Any]) {
        guard isAvailable, isOn else { return }
        let key = "\(event.rawValue) \(month)"
        guard !sentMonths.contains(key) else { return }
        sentMonths.insert(key)
        settings?.set(sentMonths.sorted(), forKey: Self.sentMonthsKey)
        track(event, props)
    }

    /// The JSON Aptabase takes for one event.
    func body(_ event: UsageEvent, _ props: [String: Any]) -> Data? {
        let time = now()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let object: [String: Any] = [
            "timestamp": Self.timestamp.string(from: time),
            "sessionId": sessionID(at: time),
            "eventName": event.rawValue,
            "systemProps": [
                "isDebug": isDebug,
                "locale": Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
                "osName": "macOS",
                "osVersion": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                "appVersion": version,
                "sdkVersion": "quotepilot-swift@1",
            ] as [String: Any],
            "props": props.filter { $0.value is String || $0.value is Bool || $0.value is Int || $0.value is Double },
        ]
        return try? JSONSerialization.data(withJSONObject: object)
    }

    /// Seconds since 1970 × 10⁸ plus eight random digits, renewed after an hour with no events.
    private func sessionID(at time: Date) -> String {
        if let session, time.timeIntervalSince(session.last) < 3600 {
            self.session = (session.id, time)
            return session.id
        }
        let id = String(Int(time.timeIntervalSince1970) * 100_000_000 + Int.random(in: 0..<100_000_000))
        session = (id, time)
        return id
    }

    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// No cookies, no cache, five seconds at most; a failure is dropped.
    private static let urlSession = URLSession(configuration: .ephemeral)

    private static func send(_ body: Data) {
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue(appKey, forHTTPHeaderField: "App-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        urlSession.dataTask(with: request).resume()
    }
}
