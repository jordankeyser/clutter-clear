import Foundation

enum MailParser {
    // MARK: Headers

    /// Parses an RFC 5322 header block into lowercase keys (first occurrence wins), unfolded and decoded.
    static func parseHeaders(_ data: Data) -> [String: String] {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        var result: [String: String] = [:]
        var currentKey: String?
        var currentValue = ""

        func flush() {
            if let k = currentKey, result[k] == nil {
                result[k] = decodeEncodedWords(currentValue.trimmingCharacters(in: .whitespaces))
            }
        }

        for rawLine in text.components(separatedBy: "\r\n").flatMap({ $0.components(separatedBy: "\n") }) {
            if rawLine.isEmpty { break }
            if rawLine.first == " " || rawLine.first == "\t" {
                currentValue += " " + rawLine.trimmingCharacters(in: .whitespaces)
            } else if let colon = rawLine.firstIndex(of: ":") {
                flush()
                currentKey = rawLine[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                currentValue = String(rawLine[rawLine.index(after: colon)...])
            }
        }
        flush()
        return result
    }

    /// Decodes RFC 2047 encoded words like =?UTF-8?B?...?= and =?utf-8?Q?...?=.
    static func decodeEncodedWords(_ s: String) -> String {
        guard s.contains("=?") else { return s }
        // Whitespace between two adjacent encoded words is not significant.
        let joined = s.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
        let re = try! NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#)
        var out = ""
        var last = joined.startIndex
        for m in re.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)) {
            guard let whole = Range(m.range, in: joined),
                  let csR = Range(m.range(at: 1), in: joined),
                  let encR = Range(m.range(at: 2), in: joined),
                  let txtR = Range(m.range(at: 3), in: joined) else { continue }
            out += joined[last..<whole.lowerBound]
            let encoding = stringEncoding(forCharset: String(joined[csR]))
            let payload = String(joined[txtR])
            var bytes: Data?
            if joined[encR].uppercased() == "B" {
                bytes = Data(base64Encoded: padBase64(payload))
            } else {
                bytes = decodeQuotedPrintable(payload.replacingOccurrences(of: "_", with: " "), headerMode: true)
            }
            if let bytes, let decoded = String(data: bytes, encoding: encoding) ?? String(data: bytes, encoding: .isoLatin1) {
                out += decoded
            } else {
                out += joined[whole]
            }
            last = whole.upperBound
        }
        out += joined[last...]
        return out
    }

    static func stringEncoding(forCharset charset: String) -> String.Encoding {
        let cf = CFStringConvertIANACharSetNameToEncoding(charset.lowercased() as CFString)
        if cf == kCFStringEncodingInvalidId { return .utf8 }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    private static func padBase64(_ s: String) -> String {
        let clean = s.filter { !$0.isWhitespace }
        let rem = clean.count % 4
        return rem == 0 ? clean : clean + String(repeating: "=", count: 4 - rem)
    }

    static func decodeQuotedPrintable(_ s: String, headerMode: Bool = false) -> Data {
        var out = Data()
        let bytes = Array(s.utf8)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "=") {
                if i + 2 < bytes.count,
                   let v = UInt8(String(bytes: bytes[(i + 1)...(i + 2)], encoding: .ascii) ?? "", radix: 16) {
                    out.append(v)
                    i += 3
                    continue
                }
                // Soft line break: "=\r\n" or "=\n"
                if !headerMode {
                    if i + 2 < bytes.count, bytes[i + 1] == 13, bytes[i + 2] == 10 { i += 3; continue }
                    if i + 1 < bytes.count, bytes[i + 1] == 10 { i += 2; continue }
                }
            }
            out.append(b)
            i += 1
        }
        return out
    }

    /// Splits `"Name" <addr@x.com>` into its parts. The address is lowercased.
    static func parseAddress(_ raw: String) -> (name: String, email: String) {
        if let lt = raw.lastIndex(of: "<"), let gt = raw.lastIndex(of: ">"), lt < gt {
            let email = raw[raw.index(after: lt)..<gt].trimmingCharacters(in: .whitespaces).lowercased()
            var name = raw[..<lt].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 { name = String(name.dropFirst().dropLast()) }
            return (name.isEmpty ? email : name, email)
        }
        let email = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return (email, email)
    }

    /// Parses List-Unsubscribe into web and mailto targets.
    static func parseListUnsubscribe(_ value: String?) -> (web: [String], mailto: [String]) {
        guard let value else { return ([], []) }
        var web: [String] = []
        var mail: [String] = []
        let re = try! NSRegularExpression(pattern: #"<([^>]+)>"#)
        for m in re.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let r = Range(m.range(at: 1), in: value) else { continue }
            let target = value[r].trimmingCharacters(in: .whitespaces)
            let lower = target.lowercased()
            if lower.hasPrefix("https://") || lower.hasPrefix("http://") { web.append(target) }
            else if lower.hasPrefix("mailto:") { mail.append(target) }
        }
        return (web, mail)
    }

    // MARK: Body links (fallback when there is no List-Unsubscribe header)

    /// Walks the MIME tree and returns decoded text/html and text/plain parts.
    static func textParts(of message: Data) -> [(type: String, text: String)] {
        guard let split = splitHeaderBody(message) else { return [] }
        let headers = parseHeaders(split.header)
        return parts(headers: headers, body: split.body)
    }

    private static func splitHeaderBody(_ data: Data) -> (header: Data, body: Data)? {
        if let r = data.range(of: Data("\r\n\r\n".utf8)) {
            return (data.subdata(in: data.startIndex..<r.lowerBound), data.subdata(in: r.upperBound..<data.endIndex))
        }
        if let r = data.range(of: Data("\n\n".utf8)) {
            return (data.subdata(in: data.startIndex..<r.lowerBound), data.subdata(in: r.upperBound..<data.endIndex))
        }
        return nil
    }

    private static func param(_ name: String, in header: String) -> String? {
        let re = try! NSRegularExpression(pattern: name + #"\s*=\s*(?:"([^"]+)"|([^;\s]+))"#, options: .caseInsensitive)
        guard let m = re.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else { return nil }
        for i in 1...2 { if let r = Range(m.range(at: i), in: header) { return String(header[r]) } }
        return nil
    }

    private static func parts(headers: [String: String], body: Data, depth: Int = 0) -> [(type: String, text: String)] {
        guard depth < 8 else { return [] }
        let ctype = headers["content-type"] ?? "text/plain"
        let mime = ctype.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "text/plain"

        if mime.hasPrefix("multipart/"), let boundary = param("boundary", in: ctype) {
            let bodyText = String(decoding: body, as: UTF8.self)
            var result: [(String, String)] = []
            for chunk in bodyText.components(separatedBy: "--" + boundary).dropFirst() {
                if chunk.hasPrefix("--") { break }
                let data = Data(chunk.trimmingPrefixNewline().utf8)
                guard let split = splitHeaderBody(data) else { continue }
                result += parts(headers: parseHeaders(split.header), body: split.body, depth: depth + 1)
            }
            return result
        }
        guard mime == "text/html" || mime == "text/plain" else { return [] }

        let cte = headers["content-transfer-encoding"]?.lowercased() ?? ""
        var decoded = body
        if cte.contains("base64") {
            decoded = Data(base64Encoded: padBase64(String(decoding: body, as: UTF8.self))) ?? body
        } else if cte.contains("quoted-printable") {
            decoded = decodeQuotedPrintable(String(decoding: body, as: UTF8.self))
        }
        let enc = param("charset", in: ctype).map(stringEncoding(forCharset:)) ?? .utf8
        let text = String(data: decoded, encoding: enc) ?? String(decoding: decoded, as: UTF8.self)
        return [(mime, text)]
    }

    /// Finds likely unsubscribe links in an email body. HTML anchors are preferred.
    static func unsubscribeLinks(in message: Data) -> [String] {
        var links: [String] = []
        let keyword = try! NSRegularExpression(pattern: #"unsubscribe|opt[ -]?out|optout|email preferences|manage (your )?(subscription|preferences)"#, options: .caseInsensitive)
        func matches(_ s: String) -> Bool { keyword.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

        let anchor = try! NSRegularExpression(pattern: #"<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#,
                                              options: [.caseInsensitive, .dotMatchesLineSeparators])
        for part in textParts(of: message) {
            let t = part.text
            if part.type == "text/html" {
                for m in anchor.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                    guard let hr = Range(m.range(at: 1), in: t), let tr = Range(m.range(at: 2), in: t) else { continue }
                    let href = t[hr].replacingOccurrences(of: "&amp;", with: "&")
                    let label = t[tr].replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                    if (matches(label) || matches(href)) && href.lowercased().hasPrefix("http") {
                        links.append(href)
                    }
                }
            } else {
                for line in t.components(separatedBy: .newlines) where matches(line) {
                    if let r = line.range(of: #"https?://[^\s<>"]+"#, options: .regularExpression) {
                        links.append(String(line[r]))
                    }
                }
            }
        }
        var seen = Set<String>()
        return links.filter { seen.insert($0).inserted }
    }
}

private extension String {
    func trimmingPrefixNewline() -> String {
        // "\r\n" is a single Character in Swift, so one dropFirst() removes it.
        if hasPrefix("\r\n") || hasPrefix("\n") { return String(dropFirst()) }
        return self
    }
}
