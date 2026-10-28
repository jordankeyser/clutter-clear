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

    var ref: MessageRef {
        MessageRef(uid: uid, uidValidity: uidValidity, messageID: messageID, subject: subject, date: date)
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

/// Blocking, one-session-per-call mail operations. Always call from a background task.
enum MailService {
    private static func open(_ account: MailAccount, _ password: String) throws -> IMAPClient {
        let client = try IMAPClient(host: account.imapHost, port: UInt16(account.imapPort))
        try client.login(user: account.email, password: password)
        return client
    }

    static func testLogin(_ account: MailAccount, password: String) throws {
        let c = try open(account, password)
        try c.select("INBOX")
        c.logout()
    }

    /// Reads headers for every INBOX email since `since`. Mail from blocked senders is moved to Junk.
    static func scan(_ account: MailAccount, password: String, since: Date,
                     blocked: Set<String>) throws -> (messages: [ScannedMessage], junked: [String: Int]) {
        let c = try open(account, password)
        defer { c.logout() }
        let validity = try c.select("INBOX")
        let uids = try c.searchSince(since)
        let fetched = try c.fetchHeaders(uids)

        var messages: [ScannedMessage] = []
        var blockedUIDs: [UInt32] = []
        var junked: [String: Int] = [:]
        for f in fetched {
            let from = MailParser.parseAddress(f.headers["from"] ?? "")
            if blocked.contains(from.email) {
                blockedUIDs.append(f.uid)
                junked[from.email, default: 0] += 1
                continue
            }
            messages.append(ScannedMessage(
                uid: f.uid,
                uidValidity: validity,
                messageID: f.headers["message-id"] ?? "",
                subject: f.headers["subject"] ?? "(no subject)",
                date: f.internalDate ?? Date(),
                fromName: from.name,
                fromEmail: from.email,
                headers: f.headers))
        }
        if !blockedUIDs.isEmpty, let junk = try c.specialMailbox(flag: Destination.junk.flag, fallbacks: Destination.junk.fallbacks) {
            try c.move(blockedUIDs, to: junk)
        }
        return (messages, junked)
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

    static func move(_ refs: [MessageRef], account: MailAccount, password: String, to dest: Destination) throws -> Int {
        let c = try open(account, password)
        defer { c.logout() }
        let target = try mailbox(dest, client: c)
        let validity = try c.select("INBOX")
        let uids = try resolve(refs, client: c, validity: validity)
        try c.move(uids, to: target)
        return uids.count
    }

    /// Moves every INBOX email whose From address is exactly `sender`.
    static func moveAll(from sender: String, account: MailAccount, password: String, to dest: Destination) throws -> Int {
        let c = try open(account, password)
        defer { c.logout() }
        let target = try mailbox(dest, client: c)
        try c.select("INBOX")
        // IMAP FROM search is a substring match, so confirm the exact address before moving.
        let found = try c.fetchHeaders(try c.searchFrom(sender))
        let exact = found.filter { MailParser.parseAddress($0.headers["from"] ?? "").email == sender }.map(\.uid)
        try c.move(exact, to: target)
        return exact.count
    }

    static func fetchMessage(_ ref: MessageRef, account: MailAccount, password: String) throws -> Data? {
        let c = try open(account, password)
        defer { c.logout() }
        let validity = try c.select("INBOX")
        guard let uid = try resolve([ref], client: c, validity: validity).first else { return nil }
        return try c.fetchFullMessage(uid)
    }
}
