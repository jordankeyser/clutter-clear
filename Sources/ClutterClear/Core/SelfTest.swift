import Foundation

/// `ClutterClear --selftest` checks the parsing logic without touching any mailbox.
enum SelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "  ok   \(name)" : "  FAIL \(name)")
            if !ok { failures += 1 }
        }

        check("base64 encoded word", MailParser.decodeEncodedWords("=?UTF-8?B?SGVsbG8gV29ybGQ=?=") == "Hello World")
        check("Q encoded word", MailParser.decodeEncodedWords("=?utf-8?Q?50%_off_=E2=80=94_today?=") == "50% off — today")
        check("adjacent encoded words", MailParser.decodeEncodedWords("=?UTF-8?B?SGVs?= =?UTF-8?B?bG8=?=") == "Hello")

        let a = MailParser.parseAddress("\"Old Navy\" <Deals@OldNavy.com>")
        check("address with name", a.name == "Old Navy" && a.email == "deals@oldnavy.com")
        check("bare address", MailParser.parseAddress("x@y.com").email == "x@y.com")

        let lu = MailParser.parseListUnsubscribe("<mailto:unsub@list.com?subject=remove>, <https://list.com/u?id=1>")
        check("list-unsubscribe", lu.web == ["https://list.com/u?id=1"] && lu.mailto == ["mailto:unsub@list.com?subject=remove"])

        let mt = Unsubscriber.parseMailto("mailto:unsub@list.com?subject=remove")
        check("mailto parse", mt?.to == "unsub@list.com" && mt?.subject == "remove")

        let headers = MailParser.parseHeaders(Data("From: A <a@b.com>\r\nSubject: =?UTF-8?Q?Hi?=\r\n there\r\nList-Unsubscribe: <https://x.com/u>\r\n\r\n".utf8))
        check("header unfold+decode", headers["subject"] == "Hi there" && headers["list-unsubscribe"] == "<https://x.com/u>")

        let mime = """
        Content-Type: multipart/alternative; boundary="b1"\r
        \r
        --b1\r
        Content-Type: text/plain\r
        \r
        Sale today!\r
        --b1\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        <p>Sale</p><a href=3D"https://shop.com/unsub?u=3D1&amp;t=3D2">Unsub=\r
        scribe</a> <a href=3D"https://shop.com/">Shop</a>\r
        --b1--\r
        """
        check("body unsubscribe link", MailParser.unsubscribeLinks(in: Data(mime.utf8)) == ["https://shop.com/unsub?u=1&t=2"])

        func msg(_ from: String, _ subject: String, _ headers: [String: String] = [:]) -> ScannedMessage {
            ScannedMessage(uid: 1, uidValidity: 1, messageID: UUID().uuidString, subject: subject, date: Date(),
                           fromName: from, fromEmail: from, headers: headers)
        }
        let promo = SenderGroup(email: "deals@shop.com", name: "Shop", messages: [msg("deals@shop.com", "Sale", ["list-unsubscribe": "<https://a>"])],
                                newMessages: [msg("deals@shop.com", "Sale")])
        check("rule: promotional", RuleClassifier.classify(promo, windowDays: 30)?.category == .promotional)
        let scam = SenderGroup(email: "x@random.biz", name: "X", messages: [msg("x@random.biz", "Congratulations, you've won a gift card")],
                               newMessages: [msg("x@random.biz", "Congratulations, you've won a gift card")])
        check("rule: suspicious", RuleClassifier.classify(scam, windowDays: 30)?.category == .suspicious)
        let friend = SenderGroup(email: "mom@gmail.com", name: "Mom", messages: [msg("mom@gmail.com", "Dinner Sunday?")],
                                 newMessages: [msg("mom@gmail.com", "Dinner Sunday?")])
        check("rule: personal mail is left alone", RuleClassifier.classify(friend, windowDays: 30) == nil)

        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        return failures == 0
    }

    /// `ClutterClear --nettest` connects to the real servers with a fake login to exercise the IMAP plumbing.
    static func network() {
        for host in ["imap.gmail.com", "imap.mail.att.net"] {
            do {
                let c = try IMAPClient(host: host, port: 993)
                let caps = try c.command("CAPABILITY").map(\.text).joined()
                print("  ok   \(host) greeting + CAPABILITY (\(caps.prefix(60))…)")
                do {
                    try c.login(user: "nobody-clutterclear-test@example.com", password: "wrong")
                    print("  FAIL \(host) accepted a fake login?")
                } catch MailError.auth(let msg) {
                    print("  ok   \(host) rejected fake login: \(msg.prefix(70))")
                }
            } catch {
                print("  FAIL \(host): \(error.localizedDescription)")
            }
        }
    }
}
