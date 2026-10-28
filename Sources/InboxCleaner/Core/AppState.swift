import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var data = PersistedState()
    @Published private(set) var isScanning = false
    @Published private(set) var scanStatus = ""
    @Published private(set) var busy: Set<String> = []
    @Published var lastError: String?

    private var timer: Timer?
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InboxCleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    private init() {
        if let raw = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(PersistedState.self, from: raw) { data = decoded }
        }
    }

    /// Fills in sample data for `--snapshot`. Never saved to disk.
    func loadDemo() {
        let acct = MailAccount.preset(.gmail, email: "you@gmail.com")
        let att = MailAccount.preset(.att, email: "you@sbcglobal.net")
        func refs(_ subjects: [String]) -> [MessageRef] {
            subjects.enumerated().map { MessageRef(uid: UInt32($0.offset), uidValidity: 1, messageID: "", subject: $0.element,
                                                   date: Date().addingTimeInterval(-Double($0.offset) * 86400)) }
        }
        data = PersistedState()
        data.accounts = [acct, att]
        data.candidates = [
            Candidate(accountID: acct.id, senderEmail: "deals@oldnavy.com", senderName: "Old Navy", category: .promotional,
                      reason: "Daily sale emails from a clothing store.", flagged: refs(["Extra 50% off ends tonight", "Your weekend deals are here", "New arrivals just dropped"]),
                      recentCount: 14, windowDays: 30, unsubscribeWeb: ["https://x"], unsubscribeMailto: [], oneClick: true, foundAt: Date()),
            Candidate(accountID: att.id, senderEmail: "winner@prize-center.biz", senderName: "Prize Center", category: .suspicious,
                      reason: "Subject uses common scam wording and the sender isn't a real mailing list.", flagged: refs(["Congratulations! You've won a $500 gift card"]),
                      recentCount: 3, windowDays: 30, unsubscribeWeb: [], unsubscribeMailto: [], oneClick: false, foundAt: Date()),
            Candidate(accountID: acct.id, senderEmail: "noreply@linkedin.com", senderName: "LinkedIn", category: .repetitive,
                      reason: "Social notifications you rarely need.", flagged: refs(["You appeared in 9 searches this week", "Jordan, see who viewed your profile"]),
                      recentCount: 22, windowDays: 30, unsubscribeWeb: [], unsubscribeMailto: ["mailto:u@linkedin.com"], oneClick: false, foundAt: Date()),
        ]
        data.log = [
            LogEntry(accountEmail: acct.email, sender: "news@target.com", text: "Unsubscribed with one-click unsubscribe.", success: true),
            LogEntry(accountEmail: acct.email, sender: "news@target.com", text: "Moved all 41 email(s) from this sender to Trash.", success: true),
            LogEntry(accountEmail: att.email, sender: "offers@hotels.com", text: "Couldn't confirm the unsubscribe automatically. Open the page to finish.",
                     success: false, manualURL: "https://example.com/unsub"),
        ]
        data.approvedSenders = ["alerts@chase.com"]
    }

    // MARK: Persistence

    private func save() {
        let cutoff = Date().addingTimeInterval(-200 * 86400)
        data.seen = data.seen.filter { $0.value > cutoff }
        if data.log.count > 500 { data.log = Array(data.log.suffix(500)) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let raw = try? encoder.encode(data) { try? raw.write(to: fileURL, options: .atomic) }
    }

    var settings: AppSettings {
        get { data.settings }
        set {
            let wasEnabled = data.settings.dailyCheckEnabled
            data.settings = newValue
            save()
            // Turning daily checks back on catches up on everything since the last scan.
            if !wasEnabled && newValue.dailyCheckEnabled { Task { await scan(auto: false) } }
        }
    }

    var pending: [Candidate] {
        data.candidates.sorted {
            if $0.category != $1.category { return $0.category == .suspicious }
            return $0.flagged.count > $1.flagged.count
        }
    }

    func account(for id: UUID) -> MailAccount? { data.accounts.first { $0.id == id } }

    // MARK: Accounts

    func addAccount(_ account: MailAccount, password: String) async throws {
        try await Task.detached { try MailService.testLogin(account, password: password) }.value
        Keychain.set(password, for: account.keychainKey)
        data.accounts.removeAll { $0.email.lowercased() == account.email.lowercased() }
        data.accounts.append(account)
        save()
    }

    func removeAccount(_ account: MailAccount) {
        Keychain.delete(account.keychainKey)
        data.accounts.removeAll { $0.id == account.id }
        data.candidates.removeAll { $0.accountID == account.id }
        data.lastScan[account.id.uuidString] = nil
        save()
    }

    var claudeKey: String {
        get { Keychain.get("anthropic") ?? "" }
        set { Keychain.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: "anthropic"); objectWillChange.send() }
    }

    // MARK: Scanning

    private func seenKey(_ account: MailAccount, _ m: ScannedMessage) -> String {
        "\(account.id.uuidString)|" + (m.messageID.isEmpty ? "\(m.uidValidity):\(m.uid)" : m.messageID)
    }

    func scan(auto: Bool) async {
        guard !isScanning, !data.accounts.isEmpty else { return }
        isScanning = true
        lastError = nil
        let before = Set(data.candidates.map(\.id))
        defer {
            isScanning = false
            scanStatus = ""
            save()
        }

        for account in data.accounts {
            guard let password = Keychain.get(account.keychainKey) else {
                record(account, "", "No saved password. Re-add this account.", success: false)
                continue
            }
            scanStatus = "Checking \(account.email)…"
            let started = Date()
            // Look back at least 30 days so "how often do they email" is meaningful,
            // and further when checks were paused for longer.
            let lookbackDays = data.lastScan[account.id.uuidString] == nil ? data.settings.initialLookbackDays : 30
            var since = Date().addingTimeInterval(-Double(max(lookbackDays, 30)) * 86400)
            if let last = data.lastScan[account.id.uuidString], last < since { since = last }
            let windowDays = max(1, Int(Date().timeIntervalSince(since) / 86400))

            do {
                let blocked = data.blockedSenders
                let result = try await Task.detached {
                    try MailService.scan(account, password: password, since: since, blocked: blocked)
                }.value
                for (sender, n) in result.junked {
                    record(account, sender, "Moved \(n) email(s) from a blocked sender to Junk.", success: true)
                }
                await buildCandidates(account: account, messages: result.messages, windowDays: windowDays)
                for m in result.messages { data.seen[seenKey(account, m), default: started] = started }
                data.lastScan[account.id.uuidString] = started
                save()
            } catch {
                lastError = "\(account.email): \(error.localizedDescription)"
                record(account, "", error.localizedDescription, success: false)
            }
        }

        if auto { data.lastAutoRun = Date() }
        let newOnes = Set(data.candidates.map(\.id)).subtracting(before).count
        if auto && newOnes > 0 { notify(count: data.candidates.count) }
    }

    private func buildCandidates(account: MailAccount, messages: [ScannedMessage], windowDays: Int) async {
        let mine = Set(data.accounts.map { $0.email.lowercased() })
        let grouped = Dictionary(grouping: messages.filter { !mine.contains($0.fromEmail) && !$0.fromEmail.isEmpty }, by: \.fromEmail)

        var groups: [String: SenderGroup] = [:]
        for (email, msgs) in grouped {
            guard !data.approvedSenders.contains(email) else { continue }
            let sorted = msgs.sorted { $0.date > $1.date }
            let fresh = sorted.filter { data.seen[seenKey(account, $0)] == nil }
            guard !fresh.isEmpty else { continue }
            groups[email] = SenderGroup(email: email, name: sorted[0].fromName, messages: sorted, newMessages: fresh)
        }

        var verdicts: [String: Verdict] = [:]
        for (email, g) in groups {
            if let v = RuleClassifier.classify(g, windowDays: windowDays) { verdicts[email] = v }
        }

        let key = claudeKey
        if data.settings.useClaude && !key.isEmpty {
            // Ask Claude about anything the rules flagged or that looks automated; personal mail stays local.
            let toAsk = groups.filter { verdicts[$0.key] != nil || $0.value.looksAutomated || $0.value.messages.count >= 3 }
            if !toAsk.isEmpty {
                scanStatus = "Asking Claude about \(toAsk.count) senders…"
                do {
                    let results = try await ClaudeClassifier.classify(toAsk.map { ($0.key, $0.value) }, apiKey: key, model: data.settings.claudeModel)
                    for (email, r) in results {
                        switch r.choice {
                        case .keep: verdicts[email] = nil
                        case .promotional:
                            let cat: Category = (groups[email]?.isBulk ?? true) ? .promotional : .repetitive
                            verdicts[email] = Verdict(category: cat, reason: r.reason)
                        case .spam: verdicts[email] = Verdict(category: .suspicious, reason: r.reason)
                        }
                    }
                } catch {
                    lastError = "\(error.localizedDescription) Rule-based detection was used instead."
                }
            }
        }

        for (email, v) in verdicts {
            guard let g = groups[email] else { continue }
            let unsubSource = g.latestWithUnsubscribe
            let links = MailParser.parseListUnsubscribe(unsubSource?.headers["list-unsubscribe"])
            let oneClick = unsubSource?.headers["list-unsubscribe-post"]?.lowercased().contains("one-click") ?? false
            var c = Candidate(accountID: account.id, senderEmail: email, senderName: g.name, category: v.category,
                              reason: v.reason, flagged: g.newMessages.map(\.ref), recentCount: g.messages.count,
                              windowDays: windowDays, unsubscribeWeb: links.web, unsubscribeMailto: links.mailto,
                              oneClick: oneClick, foundAt: Date(), previouslyUnsubscribed: data.unsubscribedSenders[email])
            if let i = data.candidates.firstIndex(where: { $0.id == c.id }) {
                let existing = data.candidates[i]
                var refs = existing.flagged
                for r in c.flagged where !refs.contains(where: { $0.uid == r.uid && $0.uidValidity == r.uidValidity }) { refs.append(r) }
                c.flagged = refs
                c.foundAt = existing.foundAt
                data.candidates[i] = c
            } else {
                data.candidates.append(c)
            }
        }
    }

    // MARK: Decisions

    func keep(_ c: Candidate) {
        data.approvedSenders.insert(c.senderEmail)
        data.candidates.removeAll { $0.id == c.id }
        if let a = account(for: c.accountID) { record(a, c.senderEmail, "Kept. You won't be asked about this sender again.", success: true) }
        save()
    }

    func unapprove(_ email: String) { data.approvedSenders.remove(email); save() }
    func unblock(_ email: String) { data.blockedSenders.remove(email); save() }

    func unsubscribe(_ c: Candidate, delete scope: DeleteScope) async {
        guard let account = account(for: c.accountID), let password = Keychain.get(account.keychainKey) else { return }
        busy.insert(c.id)
        defer { busy.remove(c.id); save() }

        switch await Unsubscriber.run(c, account: account, password: password) {
        case .done(let msg):
            record(account, c.senderEmail, msg, success: true)
        case .manual(let msg, let url):
            record(account, c.senderEmail, msg, success: false, manualURL: url?.absoluteString)
        case .failed(let msg):
            record(account, c.senderEmail, msg, success: false)
        }
        data.unsubscribedSenders[c.senderEmail] = Date()
        await remove(c, scope: scope, to: .trash, account: account, password: password)
        data.candidates.removeAll { $0.id == c.id }
    }

    /// For spam: never touch its links. Move it to Junk and auto-junk anything else they send.
    func junk(_ c: Candidate, scope: DeleteScope) async {
        guard let account = account(for: c.accountID), let password = Keychain.get(account.keychainKey) else { return }
        busy.insert(c.id)
        defer { busy.remove(c.id); save() }
        data.blockedSenders.insert(c.senderEmail)
        await remove(c, scope: scope == .none ? .flagged : scope, to: .junk, account: account, password: password)
        record(account, c.senderEmail, "Blocked. Future emails from this sender go straight to Junk.", success: true)
        data.candidates.removeAll { $0.id == c.id }
    }

    private func remove(_ c: Candidate, scope: DeleteScope, to dest: Destination, account: MailAccount, password: String) async {
        let place = dest == .trash ? "Trash" : "Junk"
        do {
            switch scope {
            case .none:
                return
            case .flagged:
                let refs = c.flagged
                let n = try await Task.detached { try MailService.move(refs, account: account, password: password, to: dest) }.value
                record(account, c.senderEmail, "Moved \(n) flagged email(s) to \(place).", success: true)
            case .allFromSender:
                let sender = c.senderEmail
                let n = try await Task.detached { try MailService.moveAll(from: sender, account: account, password: password, to: dest) }.value
                record(account, c.senderEmail, "Moved all \(n) email(s) from this sender to \(place).", success: true)
            }
        } catch {
            record(account, c.senderEmail, "Couldn't move emails: \(error.localizedDescription)", success: false)
        }
    }

    func markManualDone(_ entry: LogEntry) {
        if let i = data.log.firstIndex(where: { $0.id == entry.id }) { data.log[i].manualDone = true; save() }
    }

    func clearLog() { data.log.removeAll(); save() }

    private func record(_ account: MailAccount, _ sender: String, _ text: String, success: Bool, manualURL: String? = nil) {
        data.log.append(LogEntry(accountEmail: account.email, sender: sender, text: text, success: success, manualURL: manualURL))
    }

    // MARK: Daily schedule

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in AppState.shared.runIfDue() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppState.shared.runIfDue() }
        }
        runIfDue()
    }

    private func runIfDue() {
        let s = data.settings
        guard s.dailyCheckEnabled, !data.accounts.isEmpty,
              let due = Calendar.current.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: Date()),
              Date() >= due, (data.lastAutoRun ?? .distantPast) < due else { return }
        Task { await scan(auto: true) }
    }

    var nextRunDescription: String {
        let s = data.settings
        guard s.dailyCheckEnabled else { return "Daily checks are off" }
        let f = DateFormatter()
        f.timeStyle = .short
        let t = Calendar.current.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: Date()) ?? Date()
        return "Checks daily at \(f.string(from: t))"
    }

    // MARK: Notifications & login item

    static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func requestNotificationPermission() {
        guard Self.canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notify(count: Int) {
        guard Self.canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = "Inbox Cleaner"
        content.body = count == 1 ? "1 sender to review." : "\(count) senders to review."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "daily", content: content, trigger: nil))
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Couldn't change Open at Login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
