import Foundation

/// One untagged server response, with any literal ({n}) payloads pulled out.
struct IMAPLine {
    var text: String
    var literals: [Data]
}

struct FetchedHeader {
    var uid: UInt32
    var internalDate: Date?
    var headers: [String: String]
}

struct Mailbox {
    var name: String
    var flags: [String]
}

/// Minimal blocking IMAP4rev1 client: just what Clutter Clear needs.
final class IMAPClient {
    private let conn: TLSConnection
    private var tagCounter = 0
    private(set) var capabilities: Set<String> = []

    static let headerFields = "FROM SUBJECT DATE MESSAGE-ID LIST-UNSUBSCRIBE LIST-UNSUBSCRIBE-POST LIST-ID PRECEDENCE REPLY-TO"

    init(host: String, port: UInt16) throws {
        conn = try TLSConnection(host: host, port: port)
        let greeting = try conn.readLine()
        guard greeting.hasPrefix("* OK") || greeting.hasPrefix("* PREAUTH") else {
            throw MailError.server(greeting)
        }
    }

    deinit { conn.close() }

    // MARK: Plumbing

    private func readResponse() throws -> IMAPLine {
        var line = try conn.readLine()
        var text = line
        var literals: [Data] = []
        while let n = Self.trailingLiteralSize(line) {
            literals.append(try conn.readBytes(n))
            line = try conn.readLine()
            text += line
        }
        return IMAPLine(text: text, literals: literals)
    }

    private static func trailingLiteralSize(_ line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        var digits = line[line.index(after: open)..<line.index(before: line.endIndex)]
        if digits.hasSuffix("+") { digits = digits.dropLast() }
        return Int(digits)
    }

    @discardableResult
    func command(_ cmd: String) throws -> [IMAPLine] {
        tagCounter += 1
        let tag = "A\(tagCounter)"
        try conn.write("\(tag) \(cmd)\r\n")
        var out: [IMAPLine] = []
        while true {
            let resp = try readResponse()
            if resp.text.hasPrefix(tag + " ") {
                let rest = String(resp.text.dropFirst(tag.count + 1))
                if rest.hasPrefix("OK") { return out }
                throw MailError.server(rest)
            }
            out.append(resp)
        }
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func uidSet(_ uids: [UInt32]) -> String {
        uids.map(String.init).joined(separator: ",")
    }

    // MARK: Session

    func login(user: String, password: String) throws {
        do {
            try command("LOGIN \(Self.quote(user)) \(Self.quote(password))")
        } catch MailError.server(let msg) {
            throw MailError.auth(msg)
        }
        let caps = try command("CAPABILITY")
        for line in caps where line.text.hasPrefix("* CAPABILITY") {
            capabilities.formUnion(line.text.dropFirst("* CAPABILITY".count).split(separator: " ").map { $0.uppercased() })
        }
    }

    func logout() {
        _ = try? command("LOGOUT")
    }

    func listMailboxes() throws -> [Mailbox] {
        let lines = try command("LIST \"\" \"*\"")
        var result: [Mailbox] = []
        let re = try! NSRegularExpression(pattern: #"^\* LIST \(([^)]*)\) (NIL|"(?:[^"\\]|\\.)*") (.+)$"#)
        for line in lines {
            let t = line.text
            guard let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let flagsR = Range(m.range(at: 1), in: t),
                  let nameR = Range(m.range(at: 3), in: t) else { continue }
            var name = String(t[nameR])
            if let lit = line.literals.first {
                name = String(decoding: lit, as: UTF8.self)
            } else if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 {
                name = String(name.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            let flags = t[flagsR].split(separator: " ").map { String($0) }
            result.append(Mailbox(name: name, flags: flags))
        }
        return result
    }

    /// Finds the trash or junk folder using RFC 6154 flags, then common names.
    func specialMailbox(flag: String, fallbacks: [String]) throws -> String? {
        let boxes = try listMailboxes()
        if let m = boxes.first(where: { $0.flags.contains { $0.caseInsensitiveCompare(flag) == .orderedSame } }) {
            return m.name
        }
        for name in fallbacks {
            if let m = boxes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return m.name }
        }
        return nil
    }

    /// Selects a mailbox and returns its UIDVALIDITY.
    @discardableResult
    func select(_ mailbox: String) throws -> UInt32 {
        let lines = try command("SELECT \(Self.quote(mailbox))")
        for line in lines {
            if let r = line.text.range(of: "UIDVALIDITY ") {
                let digits = line.text[r.upperBound...].prefix { $0.isNumber }
                return UInt32(digits) ?? 0
            }
        }
        return 0
    }

    // MARK: Search & fetch

    private static let imapDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy"
        return f
    }()

    private static let internalDateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        return f
    }()

    func uidSearch(_ criteria: String) throws -> [UInt32] {
        let lines = try command("UID SEARCH \(criteria)")
        var uids: [UInt32] = []
        for line in lines where line.text.hasPrefix("* SEARCH") {
            uids += line.text.dropFirst("* SEARCH".count).split(separator: " ").compactMap { UInt32($0) }
        }
        return uids
    }

    func searchSince(_ date: Date) throws -> [UInt32] {
        try uidSearch("SINCE \(Self.imapDate.string(from: date))")
    }

    func searchFrom(_ address: String) throws -> [UInt32] {
        try uidSearch("FROM \(Self.quote(address))")
    }

    func searchMessageID(_ id: String) throws -> [UInt32] {
        try uidSearch("HEADER Message-ID \(Self.quote(id))")
    }

    func fetchHeaders(_ uids: [UInt32]) throws -> [FetchedHeader] {
        var out: [FetchedHeader] = []
        let uidRe = try! NSRegularExpression(pattern: #"UID (\d+)"#)
        let dateRe = try! NSRegularExpression(pattern: #"INTERNALDATE "([^"]+)""#)
        for chunk in uids.chunked(150) {
            let lines = try command("UID FETCH \(Self.uidSet(chunk)) (UID INTERNALDATE BODY.PEEK[HEADER.FIELDS (\(Self.headerFields))])")
            for line in lines where line.text.contains(" FETCH ") {
                let t = line.text
                guard let m = uidRe.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                      let r = Range(m.range(at: 1), in: t), let uid = UInt32(t[r]),
                      let raw = line.literals.first else { continue }
                var date: Date?
                if let dm = dateRe.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                   let dr = Range(dm.range(at: 1), in: t) {
                    date = Self.internalDateFormat.date(from: t[dr].trimmingCharacters(in: .whitespaces))
                }
                out.append(FetchedHeader(uid: uid, internalDate: date, headers: MailParser.parseHeaders(raw)))
            }
        }
        return out
    }

    func fetchFullMessage(_ uid: UInt32) throws -> Data? {
        let lines = try command("UID FETCH \(uid) (BODY.PEEK[])")
        return lines.first(where: { $0.text.contains(" FETCH ") && !$0.literals.isEmpty })?.literals.first
    }

    // MARK: Moving

    func move(_ uids: [UInt32], to mailbox: String) throws {
        guard !uids.isEmpty else { return }
        for chunk in uids.chunked(100) {
            let set = Self.uidSet(chunk)
            // Gmail sometimes answers a large move with a temporary "System Error"; wait and retry,
            // then fall back to copy + delete.
            var attempt = 0
            while true {
                do {
                    if capabilities.contains("MOVE") && attempt < 2 {
                        try command("UID MOVE \(set) \(Self.quote(mailbox))")
                    } else {
                        try copyAndDelete(set, to: mailbox)
                    }
                    break
                } catch MailError.server(_) where attempt < 2 {
                    attempt += 1
                    Thread.sleep(forTimeInterval: Double(attempt) * 1.5)
                }
            }
        }
    }

    private func copyAndDelete(_ set: String, to mailbox: String) throws {
        try command("UID COPY \(set) \(Self.quote(mailbox))")
        try command("UID STORE \(set) +FLAGS.SILENT (\\Deleted)")
        if capabilities.contains("UIDPLUS") {
            try command("UID EXPUNGE \(set)")
        } else {
            try command("EXPUNGE")
        }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
