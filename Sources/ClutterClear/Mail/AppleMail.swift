import Foundation

/// Reaches accounts through Apple Mail via AppleScript, for inboxes we can't sign in to directly
/// (for example AT&T addresses without a secure mail key). Blocking; call from a background task.
enum AppleMail {
    struct MailAppAccount: Identifiable, Hashable {
        var name: String
        var email: String
        var enabled: Bool
        var id: String { name }
    }

    private static let unitSep = "\u{1F}"
    private static let recordSep = "\u{1E}"

    // MARK: Running scripts

    /// Runs an AppleScript with arguments passed separately (never spliced into the script text).
    private static func run(_ script: String, _ args: [String], timeout: TimeInterval = 600) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-"] + args
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        try p.run()
        input.fileHandleForWriting.write(Data((sharedHandlers + script).utf8))
        try? input.fileHandleForWriting.close()

        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()

        let errText = String(decoding: err, as: UTF8.self)
        guard p.terminationStatus == 0 else {
            if errText.contains("-1743") || errText.contains("Not authorized") {
                throw MailError.auth("Clutter Clear isn't allowed to control Mail. Turn it on in System Settings → Privacy & Security → Automation → Clutter Clear → Mail.")
            }
            if p.terminationReason == .uncaughtSignal { throw MailError.timeout }
            throw MailError.server("Apple Mail: \(errText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        var text = String(decoding: out, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    /// Helpers shared by every script: find an account's inbox and junk folders.
    private static let sharedHandlers = """
    on inboxOf(acct)
        tell application "Mail"
            try
                return mailbox "INBOX" of acct
            end try
            repeat with b in (every mailbox of acct)
                if name of b is "Inbox" then return b
            end repeat
        end tell
        error "Couldn't find the inbox for this account."
    end inboxOf

    on junkOf(acct)
        tell application "Mail"
            repeat with b in (every mailbox of acct)
                if {"Junk", "Bulk Mail", "Bulk", "Spam", "Junk E-mail", "Junk Email"} contains (name of b) then return b
            end repeat
        end tell
        return missing value
    end junkOf

    on textOf(v)
        if v is missing value then return ""
        return v as text
    end textOf


    """

    // MARK: Accounts

    static func listAccounts() throws -> [MailAppAccount] {
        let script = """
        on run argv
            set US to ASCII character 31
            set RS to ASCII character 30
            set out to {}
            tell application "Mail"
                repeat with a in accounts
                    set addrs to email addresses of a
                    set e to ""
                    if (count of addrs) > 0 then set e to item 1 of addrs
                    set end of out to (name of a) & US & e & US & ((enabled of a) as text)
                end repeat
            end tell
            set AppleScript's text item delimiters to RS
            return out as text
        end run
        """
        return try run(script, []).components(separatedBy: recordSep).compactMap { rec in
            let f = rec.components(separatedBy: unitSep)
            guard f.count >= 3, !f[0].isEmpty else { return nil }
            return MailAppAccount(name: f[0], email: f[1].lowercased(), enabled: f[2] == "true")
        }
    }

    static func testAccess(_ account: MailAccount) throws {
        guard let name = account.appleMailName else { throw MailError.server("Missing Apple Mail account name.") }
        guard try listAccounts().contains(where: { $0.name == name }) else {
            throw MailError.server("Apple Mail has no account named \(name).")
        }
    }

    // MARK: Reading

    static func scan(_ account: MailAccount, since: Date, blocked: Set<String>) throws -> (messages: [ScannedMessage], junked: [String: Int]) {
        guard let name = account.appleMailName else { return ([], [:]) }
        let script = """
        on run argv
            set acctName to item 1 of argv
            set secondsBack to (item 2 of argv) as integer
            set US to ASCII character 31
            set RS to ASCII character 30
            set nowDate to current date
            set cutoff to nowDate - secondsBack
            set out to {}
            tell application "Mail"
                set mb to my inboxOf(account acctName)
                set msgs to (messages of mb whose date received is not less than cutoff)
                repeat with m in msgs
                    try
                        set age to (nowDate - (date received of m)) as text
                        set end of out to ((id of m) as text) & US & my textOf(message id of m) & US & age & US & my textOf(sender of m) & US & my textOf(subject of m) & US & my textOf(all headers of m)
                    end try
                end repeat
            end tell
            set AppleScript's text item delimiters to RS
            return out as text
        end run
        """
        let secondsBack = max(86400, Int(Date().timeIntervalSince(since)))
        let raw = try run(script, [name, String(secondsBack)])
        let now = Date()

        var messages: [ScannedMessage] = []
        var blockedIDs: [UInt32] = []
        var junked: [String: Int] = [:]
        for rec in raw.components(separatedBy: recordSep) where !rec.isEmpty {
            let f = rec.components(separatedBy: unitSep)
            guard f.count >= 6, let id = UInt32(f[0]) else { continue }
            let from = MailParser.parseAddress(MailParser.decodeEncodedWords(f[3]))
            if blocked.contains(from.email) {
                blockedIDs.append(id)
                junked[from.email, default: 0] += 1
                continue
            }
            var messageID = f[1]
            if !messageID.isEmpty && !messageID.hasPrefix("<") { messageID = "<\(messageID)>" }
            messages.append(ScannedMessage(
                uid: id, uidValidity: 0, messageID: messageID,
                subject: f[4].isEmpty ? "(no subject)" : f[4],
                date: now.addingTimeInterval(-(Double(f[2]) ?? 0)),
                fromName: from.name, fromEmail: from.email,
                headers: MailParser.parseHeaders(Data(f[5].utf8))))
        }
        if !blockedIDs.isEmpty {
            _ = try move(ids: blockedIDs, account: account, to: .junk)
        }
        return (messages, junked)
    }

    static func source(of ref: MessageRef, account: MailAccount) throws -> Data? {
        guard let name = account.appleMailName else { return nil }
        let script = """
        on run argv
            tell application "Mail"
                set mb to my inboxOf(account (item 1 of argv))
                return source of (first message of mb whose id is ((item 2 of argv) as integer))
            end tell
        end run
        """
        return Data(try run(script, [name, String(ref.uid)]).utf8)
    }

    // MARK: Moving

    /// Moves inbox messages (by Apple Mail id) to Trash or Junk.
    static func move(ids: [UInt32], account: MailAccount, to dest: Destination) throws -> Int {
        guard let name = account.appleMailName, !ids.isEmpty else { return 0 }
        let script = """
        on run argv
            set acctName to item 1 of argv
            set dest to item 2 of argv
            set idList to items 3 thru -1 of argv
            set n to 0
            tell application "Mail"
                set acct to account acctName
                set mb to my inboxOf(acct)
                set junkBox to missing value
                if dest is "junk" then set junkBox to my junkOf(acct)
                repeat with i in idList
                    try
                        set m to first message of mb whose id is (i as integer)
                        if dest is "junk" then
                            set junk mail status of m to true
                            if junkBox is not missing value then move m to junkBox
                        else
                            delete m
                        end if
                        set n to n + 1
                    end try
                end repeat
            end tell
            return n as text
        end run
        """
        return Int(try run(script, [name, dest == .junk ? "junk" : "trash"] + ids.map(String.init))) ?? 0
    }

    /// Moves every message from `sender` in every folder of the account (archive included) to Trash or Junk.
    static func moveAll(from sender: String, account: MailAccount, to dest: Destination) throws -> Int {
        guard let name = account.appleMailName else { return 0 }
        let script = """
        on run argv
            set acctName to item 1 of argv
            set dest to item 2 of argv
            set addr to item 3 of argv
            set skipNames to {"Trash", "Deleted Messages", "Deleted Items", "Deleted", "Junk", "Bulk Mail", "Bulk", "Spam", "Junk E-mail", "Junk Email", "Sent", "Sent Messages", "Sent Items", "Sent Mail", "Drafts", "Draft"}
            set n to 0
            tell application "Mail"
                set acct to account acctName
                set junkBox to missing value
                if dest is "junk" then set junkBox to my junkOf(acct)
                repeat with b in (every mailbox of acct)
                    if skipNames does not contain (name of b) then
                        set found to (messages of b whose sender contains addr)
                        repeat with m in found
                            try
                                if (extract address from (sender of m)) is addr then
                                    if dest is "junk" then
                                        set junk mail status of m to true
                                        if junkBox is not missing value then move m to junkBox
                                    else
                                        delete m
                                    end if
                                    set n to n + 1
                                end if
                            end try
                        end repeat
                    end if
                end repeat
            end tell
            return n as text
        end run
        """
        return Int(try run(script, [name, dest == .junk ? "junk" : "trash", sender])) ?? 0
    }

    // MARK: Sending

    static func send(from account: MailAccount, to: String, subject: String, body: String) throws {
        let script = """
        on run argv
            tell application "Mail"
                set msg to make new outgoing message with properties {subject:(item 3 of argv), content:(item 4 of argv), sender:(item 1 of argv), visible:false}
                tell msg to make new to recipient at end of to recipients with properties {address:(item 2 of argv)}
                send msg
            end tell
            return "sent"
        end run
        """
        _ = try run(script, [account.email, to, subject, body])
    }
}
