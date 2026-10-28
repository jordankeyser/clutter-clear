import Foundation

enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case gmail, att, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .gmail: return "Gmail"
        case .att: return "AT&T / SBC Global"
        case .other: return "Other (IMAP)"
        }
    }
}

struct MailAccount: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: AccountKind
    var email: String
    var imapHost: String
    var imapPort: Int
    var smtpHost: String
    var smtpPort: Int

    var keychainKey: String { "imap:\(id.uuidString)" }

    static func preset(_ kind: AccountKind, email: String) -> MailAccount {
        switch kind {
        case .gmail:
            return MailAccount(kind: kind, email: email, imapHost: "imap.gmail.com", imapPort: 993,
                               smtpHost: "smtp.gmail.com", smtpPort: 465)
        case .att:
            return MailAccount(kind: kind, email: email, imapHost: "imap.mail.att.net", imapPort: 993,
                               smtpHost: "smtp.mail.att.net", smtpPort: 465)
        case .other:
            let domain = email.split(separator: "@").last.map(String.init) ?? ""
            return MailAccount(kind: kind, email: email, imapHost: "imap.\(domain)", imapPort: 993,
                               smtpHost: "smtp.\(domain)", smtpPort: 465)
        }
    }
}

enum Category: String, Codable {
    case promotional
    case repetitive
    case suspicious

    var label: String {
        switch self {
        case .promotional: return "Promotional"
        case .repetitive: return "Repetitive"
        case .suspicious: return "Likely spam"
        }
    }
}

struct MessageRef: Codable, Hashable {
    var uid: UInt32
    var uidValidity: UInt32
    var messageID: String
    var subject: String
    var date: Date
}

struct Candidate: Codable, Identifiable, Hashable {
    var accountID: UUID
    var senderEmail: String
    var senderName: String
    var category: Category
    var reason: String
    /// The new emails that triggered this review.
    var flagged: [MessageRef]
    /// How many emails from this sender arrived in the recent window.
    var recentCount: Int
    var windowDays: Int
    var unsubscribeWeb: [String]
    var unsubscribeMailto: [String]
    var oneClick: Bool
    var foundAt: Date
    var previouslyUnsubscribed: Date?

    var id: String { "\(accountID.uuidString)|\(senderEmail)" }

    var unsubscribeSummary: String {
        if oneClick && !unsubscribeWeb.isEmpty { return "Supports one-click unsubscribe" }
        if !unsubscribeMailto.isEmpty { return "Unsubscribes by sending them an email" }
        if !unsubscribeWeb.isEmpty { return "Unsubscribes through their web page" }
        return "No unsubscribe header. The app will look for a link in the email itself."
    }
}

struct LogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var accountEmail: String
    var sender: String
    var text: String
    var success: Bool
    /// Set when a step needs the person to finish it in a browser.
    var manualURL: String?
    var manualDone = false
}

enum DeleteScope: String, Codable {
    case none, flagged, allFromSender
}

struct AppSettings: Codable, Equatable {
    var dailyCheckEnabled = true
    var hour = 8
    var minute = 0
    var initialLookbackDays = 30
    var useClaude = false
    var claudeModel = ClaudeModel.opus.rawValue
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case haiku = "claude-haiku-5-5"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .opus: return "Claude Opus 5.5 (smartest)"
        case .haiku: return "Claude Haiku 5.5 (cheapest)"
        }
    }
}

struct PersistedState: Codable {
    var accounts: [MailAccount] = []
    var approvedSenders: Set<String> = []
    var blockedSenders: Set<String> = []
    var unsubscribedSenders: [String: Date] = [:]
    /// account|message key -> when first seen. Prevents re-flagging the same email twice.
    var seen: [String: Date] = [:]
    var candidates: [Candidate] = []
    var log: [LogEntry] = []
    /// Account UUID -> start time of the last successful scan.
    var lastScan: [String: Date] = [:]
    var lastAutoRun: Date?
    var settings = AppSettings()
}
