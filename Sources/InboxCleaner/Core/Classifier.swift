import Foundation

/// All recent emails from one sender in one account.
struct SenderGroup {
    var email: String
    var name: String
    var messages: [ScannedMessage]   // everything in the window, newest first
    var newMessages: [ScannedMessage] // not reviewed before

    var latestWithUnsubscribe: ScannedMessage? {
        messages.first { $0.headers["list-unsubscribe"] != nil }
    }
    var isBulk: Bool {
        messages.contains { m in
            m.headers["list-unsubscribe"] != nil || m.headers["list-id"] != nil ||
                ["bulk", "list", "junk"].contains(m.headers["precedence"]?.lowercased() ?? "")
        }
    }
    var looksAutomated: Bool {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        return local.range(of: #"no-?reply|donotreply|do-not-reply|newsletter|news|marketing|promo|deals|offers|info|hello|updates|notifications?|mailer"#,
                           options: .regularExpression) != nil
    }
}

struct Verdict {
    var category: Category
    var reason: String
}

/// Rule-based detection. Works without any API key.
enum RuleClassifier {
    private static let scamPattern = #"(?i)\b(you('ve| have)? won|winner|claim (your|now)|gift ?card|lottery|inheritance|crypto(currency)? (profit|opportunity)|bitcoin|wire transfer|act now|final notice|urgent( action)?|verify your account|account (suspended|locked|on hold)|limited time only|100% free|risk[- ]free|congratulations|you('ve| have) been selected|refund (pending|available)|unclaimed|beneficiary)\b"#

    static func classify(_ g: SenderGroup, windowDays: Int) -> Verdict? {
        let subjects = g.newMessages.map(\.subject)
        let scammy = subjects.contains { $0.range(of: scamPattern, options: .regularExpression) != nil }
        let senderDomain = g.email.split(separator: "@").last.map(String.init) ?? ""
        let nameHasOtherDomain: Bool = {
            guard let r = g.name.range(of: #"[A-Za-z0-9-]+\.(com|net|org|co|io)"#, options: .regularExpression) else { return false }
            return !senderDomain.hasSuffix(g.name[r].lowercased())
        }()

        if !g.isBulk && (scammy || nameHasOtherDomain) {
            return Verdict(category: .suspicious,
                           reason: scammy ? "Subject uses common scam wording and the sender isn't a real mailing list."
                                          : "The display name points to a different website than the sending address.")
        }
        if g.isBulk {
            return Verdict(category: .promotional,
                           reason: "Sent from a mailing list (\(g.messages.count) in the last \(windowDays) days).")
        }
        if g.messages.count >= 4 && g.looksAutomated {
            return Verdict(category: .repetitive,
                           reason: "Automated sender with \(g.messages.count) emails in the last \(windowDays) days.")
        }
        return nil
    }
}
