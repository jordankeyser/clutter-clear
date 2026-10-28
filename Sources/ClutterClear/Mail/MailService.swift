import Foundation

struct ScannedMessage {
    var uid: UInt32
    var uidValidity: UInt32
    var messageID: String
    var subject: String
    var date: Date
    var fromName: String
    var fromEmail: String
    var headers: [String: String]
    /// Folder the email was found in. Nil means the inbox.
    var mailbox: String? = nil

    var ref: MessageRef {
        MessageRef(uid: uid, uidValidity: uidValidity, messageID: messageID, subject: subject, date: date, mailbox: mailbox)
    }
}

enum Destination {
    case trash, junk

    var flag: String { self == .trash ? "\\Trash" : "\\Junk" }
    var fallbacks: [String] {
        switch self {
        case .trash: return ["[Gmail]/Trash", "Trash", "Deleted Messages", "Deleted Items", "Deleted"]
        case .junk: return ["[Gmail]/Spam", "Bulk Mail", "Spam", "Junk", "Junk Email"]
        }
    }
}

/// Lets a long-running background job be stopped from the UI.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Blocking, one-session-per-call mail operations. Always call from a background task.
enum MailService {
    private static func open(_ account: MailAccount, _ password: String) throws -> IMAPClient {
        let client = try IMAPClient(host: account.imapHost, port: UInt16(account.imapPort))
        try client.login(user: account.email, password: password)
        return client
    }

    static func testLogin(_ account: MailAccount, password: String) throws {
        if account.kind == .appleMail { return try AppleMail.testAccess(account) }
        let c = try open(account, password)
        try c.select("INBOX")
        c.logout()
    }

    private static func scanned(_ f: FetchedHeader, validity: UInt32, mailbox: String?) -> ScannedMessage {
        let from = MailParser.parseAddress(f.headers["from"] ?? "")
        return ScannedMessage(
            uid: f.uid,
            uidValidity: validity,
            messageID: f.headers["message-id"] ?? "",
            subject: f.headers["subject"] ?? "(no subject)",
            date: f.internalDate ?? Date(),
            fromName: from.name,
            fromEmail: from.email,
            headers: f.headers,
            mailbox: mailbox)
    }

    /// Reads headers for every INBOX email since `since`. Mail from blocked senders is moved to Junk.
    static func scan(_ account: MailAccount, password: String, since: Date,
                     blocked: Set<String>) throws -> (messages: [ScannedMessage], junked: [String: Int]) {
        if account.kind == .appleMail { return try AppleMail.scan(account, since: since, blocked: blocked) }
        let c = try open(account, password)
        defer { c.logout() }
        let validity = try c.select("INBOX")
        let fetched = try c.fetchHeaders(try c.searchSince(since))

        var messages: [ScannedMessage] = []
        var blockedUIDs: [UInt32] = []
        var junked: [String: Int] = [:]
        for f in fetched {
            let m = scanned(f, validity: validity, mailbox: nil)
            if blocked.contains(m.fromEmail) {
                blockedUIDs.append(f.uid)
                junked[m.fromEmail, default: 0] += 1
                continue
            }
            messages.append(m)
        }
        if !blockedUIDs.isEmpty, let junk = try c.specialMailbox(flag: Destination.junk.flag, fallbacks: Destination.junk.fallbacks) {
            try c.move(blockedUIDs, to: junk)
        }
        return (messages, junked)
    }

    /// Reads headers for every email since `since`, optionally including archived mail. Moves nothing.
    static func deepScan(_ account: MailAccount, password: String, since: Date, includeArchive: Bool,
                         cancel: CancelFlag, progress: @escaping (String) -> Void) throws -> [ScannedMessage] {
        if account.kind == .appleMail {
            progress("Reading \(account.email) through Apple Mail. This can take a few minutes…")
            return try AppleMail.deepScan(account, since: since, includeArchive: includeArchive, cancel: cancel)
        }
        let c = try open(account, password)
        defer { c.logout() }
        let boxes = includeArchive ? try sourceMailboxes(client: c, excluding: "") : ["INBOX"]
        var messages: [ScannedMessage] = []
        var seenIDs = Set<String>()
        for box in boxes {
            if cancel.isCancelled { break }
            let validity: UInt32
            do { validity = try c.select(box) } catch { continue }
            let uids = try c.searchSince(since)
            var done = 0
            for chunk in uids.chunked(600) {
                if cancel.isCancelled { break }
                progress("Reading \(account.email): \((done + chunk.count).formatted()) of \(uids.count.formatted()) emails…")
                for f in try c.fetchHeaders(chunk) {
                    let m = scanned(f, validity: validity, mailbox: box == "INBOX" ? nil : box)
                    // The same email can sit in more than one folder; count it once.
                    if !m.messageID.isEmpty && !seenIDs.insert(m.messageID).inserted { continue }
                    messages.append(m)
                }
                done += chunk.count
            }
        }
        return messages
    }

    private static func resolve(_ refs: [MessageRef], client c: IMAPClient, validity: UInt32) throws -> [UInt32] {
        var uids: [UInt32] = []
        for ref in refs {
            if ref.uidValidity == validity {
                uids.append(ref.uid)
            } else if !ref.messageID.isEmpty {
                uids += try c.searchMessageID(ref.messageID)
            }
        }
        return uids
    }

    private static func mailbox(_ dest: Destination, client c: IMAPClient) throws -> String {
        guard let name = try c.specialMailbox(flag: dest.flag, fallbacks: dest.fallbacks) else {
            throw MailError.server("Couldn't find the \(dest == .trash ? "Trash" : "Junk") folder.")
        }
        return name
    }

    /// Moves specific emails, each from the folder it was found in.
    static func move(_ refs: [MessageRef], account: MailAccount, password: String, to dest: Destination) throws -> Int {
        if account.kind == .appleMail { return try AppleMail.move(refs, account: account, to: dest) }
        let c = try open(account, password)
        defer { c.logout() }
        let target = try mailbox(dest, client: c)
        var total = 0
        for (box, group) in Dictionary(grouping: refs, by: { $0.mailbox ?? "INBOX" }) {
            let validity: UInt32
            do { validity = try c.select(box) } catch { continue }
            let uids = try resolve(group, client: c, validity: validity)
            try c.move(uids, to: target)
            total += uids.count
        }
        return total
    }

    /// Folders that can hold a sender's past mail, archived mail included.
    /// Gmail keeps every message in All Mail, so that one folder covers the inbox and archive.
    /// Other providers are searched folder by folder, skipping Trash, Junk, Sent and Drafts.
    private static func sourceMailboxes(client c: IMAPClient, excluding target: String) throws -> [String] {
        let boxes = try c.listMailboxes()
        func has(_ box: Mailbox, _ flag: String) -> Bool { box.flags.contains { $0.caseInsensitiveCompare(flag) == .orderedSame } }
        if let all = boxes.first(where: { has($0, "\\All") }) { return [all.name] }
        let skipFlags = ["\\Trash", "\\Junk", "\\Sent", "\\Drafts", "\\Noselect", "\\NonExistent"]
        let skipNames = Set((Destination.trash.fallbacks + Destination.junk.fallbacks + ["Sent", "Sent Messages", "Sent Items", "Drafts", "Draft"]).map { $0.lowercased() })
        return boxes.filter { box in
            box.name != target && !skipFlags.contains { has(box, $0) } && !skipNames.contains(box.name.lowercased())
        }.map(\.name)
    }

    /// Moves every email whose From address is exactly `sender`, from every folder (not just the inbox).
    static func moveAll(from sender: String, account: MailAccount, password: String, to dest: Destination) throws -> Int {
        if account.kind == .appleMail { return try AppleMail.moveAll(from: sender, account: account, to: dest) }
        let c = try open(account, password)
        defer { c.logout() }
        let target = try mailbox(dest, client: c)
        var total = 0
        for box in try sourceMailboxes(client: c, excluding: target) {
            do { try c.select(box) } catch { continue }
            // IMAP FROM search is a substring match, so confirm the exact address before moving.
            let found = try c.fetchHeaders(try c.searchFrom(sender))
            let exact = found.filter { MailParser.parseAddress($0.headers["from"] ?? "").email == sender }.map(\.uid)
            try c.move(exact, to: target)
            total += exact.count
        }
        return total
    }

    static func fetchMessage(_ ref: MessageRef, account: MailAccount, password: String) throws -> Data? {
        if account.kind == .appleMail { return try AppleMail.source(of: ref, account: account) }
        let c = try open(account, password)
        defer { c.logout() }
        let validity = try c.select(ref.mailbox ?? "INBOX")
        guard let uid = try resolve([ref], client: c, validity: validity).first else { return nil }
        return try c.fetchFullMessage(uid)
    }
}
