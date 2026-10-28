import Foundation

/// Sends a single plain-text email over implicit TLS (port 465). Used for mailto: unsubscribes.
enum SMTPClient {
    static func send(host: String, port: UInt16, username: String, password: String,
                     from: String, to: String, subject: String, body: String) throws {
        let c = try TLSConnection(host: host, port: port)
        defer { c.close() }

        func expect(_ code: String) throws {
            while true {
                let line = try c.readLine()
                if line.hasPrefix(code + "-") { continue }
                if line.hasPrefix(code + " ") || line == code { return }
                if line.hasPrefix("535") || line.hasPrefix("534") { throw MailError.auth(line) }
                throw MailError.server(line)
            }
        }
        func send(_ s: String, expecting code: String) throws {
            try c.write(s + "\r\n")
            try expect(code)
        }

        try expect("220")
        try send("EHLO inboxcleaner.local", expecting: "250")
        let auth = Data("\u{0}\(username)\u{0}\(password)".utf8).base64EncodedString()
        try send("AUTH PLAIN \(auth)", expecting: "235")
        try send("MAIL FROM:<\(from)>", expecting: "250")
        try send("RCPT TO:<\(to)>", expecting: "250")
        try send("DATA", expecting: "354")

        let dateF = DateFormatter()
        dateF.locale = Locale(identifier: "en_US_POSIX")
        dateF.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let domain = from.split(separator: "@").last.map(String.init) ?? "localhost"
        var lines = [
            "From: <\(from)>",
            "To: <\(to)>",
            "Subject: \(subject)",
            "Date: \(dateF.string(from: Date()))",
            "Message-ID: <\(UUID().uuidString)@\(domain)>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "",
        ]
        // Dot-stuffing per RFC 5321.
        lines += body.components(separatedBy: .newlines).map { $0.hasPrefix(".") ? "." + $0 : $0 }
        try c.write(lines.joined(separator: "\r\n") + "\r\n.\r\n")
        try expect("250")
        try? c.write("QUIT\r\n")
    }
}
