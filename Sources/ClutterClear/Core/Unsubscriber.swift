import AppKit
import Foundation
import WebKit

enum UnsubscribeOutcome {
    case done(String)
    case manual(String, URL?)
    case failed(String)
}

/// Tries each unsubscribe method in order of reliability:
/// one-click POST, then mailto, then the web page, then links inside the email body.
@MainActor
enum Unsubscriber {
    static func run(_ c: Candidate, account: MailAccount, password: String) async -> UnsubscribeOutcome {
        let webURLs = c.unsubscribeWeb.compactMap(URL.init(string:)).filter { $0.scheme == "https" || $0.scheme == "http" }

        if c.oneClick, let url = webURLs.first(where: { $0.scheme == "https" }) {
            if await oneClick(url) { return .done("Unsubscribed with one-click unsubscribe.") }
        }

        for raw in c.unsubscribeMailto {
            guard let parts = parseMailto(raw) else { continue }
            do {
                try await Task.detached {
                    if account.kind == .appleMail {
                        try AppleMail.send(from: account, to: parts.to, subject: parts.subject, body: parts.body)
                        return
                    }
                    try SMTPClient.send(host: account.smtpHost, port: UInt16(account.smtpPort),
                                        username: account.email, password: password,
                                        from: account.email, to: parts.to,
                                        subject: parts.subject, body: parts.body)
                }.value
                return .done("Sent an unsubscribe email to \(parts.to).")
            } catch {
                // Fall through to the web methods.
            }
        }

        for url in webURLs {
            if await WebUnsubscriber.run(url) { return .done("Unsubscribed on their web page.") }
        }

        // No usable header: look for an unsubscribe link inside the newest email.
        var bodyLinks: [URL] = []
        if let ref = c.flagged.max(by: { $0.date < $1.date }) {
            let raw = try? await Task.detached { try MailService.fetchMessage(ref, account: account, password: password) }.value
            if let raw: Data = raw ?? nil {
                bodyLinks = MailParser.unsubscribeLinks(in: raw).compactMap(URL.init(string:))
            }
        }
        for url in bodyLinks.prefix(2) {
            if await WebUnsubscriber.run(url) { return .done("Unsubscribed using the link in the email.") }
        }

        if let url = webURLs.first ?? bodyLinks.first {
            return .manual("Couldn't confirm the unsubscribe automatically. Open the page to finish.", url)
        }
        return .failed("No unsubscribe link found. Consider moving this sender to Junk instead.")
    }

    private static func oneClick(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("List-Unsubscribe=One-Click".utf8)
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode else { return false }
        return (200..<300).contains(code)
    }

    nonisolated static func parseMailto(_ raw: String) -> (to: String, subject: String, body: String)? {
        guard let comps = URLComponents(string: raw), comps.scheme?.lowercased() == "mailto", !comps.path.isEmpty else { return nil }
        let q = comps.queryItems ?? []
        let subject = q.first { $0.name.lowercased() == "subject" }?.value ?? "unsubscribe"
        let body = q.first { $0.name.lowercased() == "body" }?.value ?? "Please unsubscribe me from this list."
        return (comps.path, subject, body)
    }
}

/// Loads an unsubscribe page in a hidden, cookie-free web view and clicks the confirm button.
@MainActor
final class WebUnsubscriber: NSObject {
    private var webView: WKWebView?
    private var window: NSWindow?

    static func run(_ url: URL, timeout: TimeInterval = 25) async -> Bool {
        let w = WebUnsubscriber()
        defer { w.teardown() }
        return await w.go(url, timeout: timeout)
    }

    private func go(_ url: URL, timeout: TimeInterval) async -> Bool {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: config)
        let win = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1100, height: 900),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = wv
        webView = wv
        window = win
        wv.load(URLRequest(url: url))

        let deadline = Date().addingTimeInterval(timeout)
        var clicks = 0
        try? await Task.sleep(for: .seconds(2.5))
        while Date() < deadline {
            let result = ((try? await wv.evaluateJavaScript(Self.script)) as? String) ?? "none"
            if result == "done" { return true }
            if result.hasPrefix("clicked") {
                clicks += 1
                if clicks > 3 { break }
                try? await Task.sleep(for: .seconds(3))
            } else {
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        return false
    }

    private func teardown() {
        webView?.stopLoading()
        window?.contentView = nil
        window?.close()
        webView = nil
        window = nil
    }

    /// Returns "done" when the page confirms the unsubscribe, "clicked:<label>" after pressing a button, else "none".
    private static let script = #"""
    (function(){
      function label(e){ return ((e.innerText || e.value || e.getAttribute('aria-label') || '') + '').trim(); }
      function visible(e){ var r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; }
      var els = Array.prototype.slice.call(document.querySelectorAll('button, input[type=submit], input[type=button], a, [role=button]'));
      var actionRe = /^\s*(yes,?\s*)?(unsubscribe|confirm|opt[\s-]?out|remove me|submit|save|update)/i;
      var cands = els.filter(function(e){ var l = label(e); return l.length > 0 && l.length < 60 && actionRe.test(l) && !e.dataset.icClicked && visible(e); });
      function score(e){ var l = label(e).toLowerCase(); return (/unsubscribe/.test(l)?4:0) + (/confirm|opt/.test(l)?2:0) + (e.tagName !== 'A'?1:0); }

      var text = (document.body ? document.body.innerText : '').toLowerCase();
      var okRes = [/you('ve| have) been (successfully )?(unsubscribed|removed|opted out)/, /(successfully|now) unsubscribed/,
                   /unsubscribe(d)? (was )?success/, /you will no longer (receive|get)/, /(has|have) been (unsubscribed|removed)/,
                   /you('re| are) (now )?unsubscribed/, /no longer subscribed/, /(opt-out|unsubscribe) request (has been )?(received|processed|confirmed)/,
                   /email (address )?(has been )?removed/];
      var stillHasButton = cands.some(function(e){ return /unsubscribe|confirm|opt/i.test(label(e)); });
      for (var i = 0; i < okRes.length; i++) { if (okRes[i].test(text) && !stillHasButton) return 'done'; }

      var opts = Array.prototype.slice.call(document.querySelectorAll('input[type=radio], input[type=checkbox]'));
      opts.forEach(function(r){
        var l = ((r.labels && r.labels[0]) ? r.labels[0].innerText : (r.parentElement ? r.parentElement.innerText : '')).toLowerCase();
        if (/unsubscribe (me )?from all|all (emails|communications|marketing|mailings)|opt out of all/.test(l) && !r.checked) r.click();
      });

      cands.sort(function(a, b){ return score(b) - score(a); });
      if (cands.length) { var c = cands[0]; c.dataset.icClicked = '1'; c.click(); return 'clicked:' + label(c); }
      return 'none';
    })();
    """#
}
