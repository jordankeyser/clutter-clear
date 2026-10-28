import AppKit
import SwiftUI

extension AccountKind {
    var icon: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .att: return "globe.americas.fill"
        case .other: return "server.rack"
        case .appleMail: return "envelope.open.fill"
        }
    }
    var color: Color {
        switch self {
        case .gmail: return .red
        case .att: return .blue
        case .other: return .gray
        case .appleMail: return .cyan
        }
    }
    var shortLabel: String {
        switch self {
        case .gmail: return "Gmail"
        case .att: return "AT&T / SBC"
        case .other: return "Other"
        case .appleMail: return "Apple Mail"
        }
    }
}

final class AccountsUI: ObservableObject {
    @Published var kind: AccountKind = .gmail
    @Published var email = ""
    @Published var password = ""
    @Published var imapHost = ""
    @Published var smtpHost = ""
    @Published var testing = false
    @Published var message: (String, Bool)?
    @Published var confirmRemove: MailAccount?
    @Published var mailAccounts: [AppleMail.MailAppAccount] = []
    @Published var loadingMail = false
    @Published var mailError: String?
}

struct AccountsView: View {
    @StateObject private var ui = AccountsUI()
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                if state.data.accounts.isEmpty {
                    Label("No inboxes yet. Add one below.", systemImage: "tray").foregroundStyle(.secondary)
                }
                ForEach(state.data.accounts) { a in
                    HStack(spacing: 12) {
                        SettingIcon(symbol: a.kind.icon, color: a.kind.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.email).font(.body.weight(.medium))
                            Group {
                                if let last = state.data.lastScan[a.id.uuidString] {
                                    Text("\(a.kind.shortLabel) · checked \(last.formatted(.relative(presentation: .named)))")
                                } else {
                                    Text("\(a.kind.shortLabel) · not checked yet")
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { ui.confirmRemove = a }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Connected inboxes")
            }

            Section {
                HStack(spacing: 10) {
                    ForEach(AccountKind.allCases) { kind in
                        providerTile(kind)
                    }
                }
                .padding(.vertical, 4)

                if ui.kind == .appleMail {
                    appleMailPicker
                } else {
                    manualFields
                }
            } header: {
                Text("Add an inbox")
            } footer: {
                help
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .confirmationDialog("Remove \(ui.confirmRemove?.email ?? "")?",
                            isPresented: Binding(get: { ui.confirmRemove != nil }, set: { if !$0 { ui.confirmRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Inbox", role: .destructive) {
                if let a = ui.confirmRemove { state.removeAccount(a) }
                ui.confirmRemove = nil
            }
        } message: {
            Text("Clutter Clear stops checking it. Your email isn't touched.")
        }
    }

    @ViewBuilder private var appleMailPicker: some View {
        if ui.mailAccounts.isEmpty {
            HStack(spacing: 12) {
                Button {
                    Task { await loadMailAccounts() }
                } label: {
                    if ui.loadingMail {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Asking Apple Mail…") }
                    } else {
                        Label("Find My Apple Mail Accounts", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(PillButtonStyle(tint: .cyan))
                .disabled(ui.loadingMail)
                if let err = ui.mailError {
                    Label(err, systemImage: "xmark.octagon.fill").foregroundStyle(Brand.remove)
                }
            }
            .padding(.vertical, 4)
        } else {
            ForEach(ui.mailAccounts) { m in
                let connected = state.data.accounts.contains { $0.email.lowercased() == m.email.lowercased() }
                HStack(spacing: 12) {
                    SenderAvatar(name: m.name, email: m.email, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.name).font(.body.weight(.medium))
                        Text(m.email.isEmpty ? "No address" : m.email).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if connected {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.keep)
                    } else if !m.enabled {
                        Text("Turned off in Mail").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Add") { Task { await addMailAccount(m) } }
                            .buttonStyle(PillButtonStyle(tint: .cyan, prominent: false))
                    }
                }
            }
            if let (text, ok) = ui.message {
                Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(ok ? Brand.keep : Brand.remove)
            }
        }
    }

    @ViewBuilder private var manualFields: some View {
                TextField(text: $ui.email, prompt: Text("you@example.com")) {
                    SettingLabel(title: "Email address", symbol: "at", color: .teal)
                }
                .textContentType(.username)
                SecureField(text: $ui.password, prompt: Text(ui.kind == .att ? "Secure mail key" : "App password")) {
                    SettingLabel(title: ui.kind == .att ? "Secure mail key" : "App password", symbol: "key.fill", color: .yellow)
                }
                if ui.kind == .other {
                    TextField(text: $ui.imapHost, prompt: Text("imap.example.com")) {
                        SettingLabel(title: "IMAP server (993)", symbol: "arrow.down.circle.fill", color: .gray)
                    }
                    TextField(text: $ui.smtpHost, prompt: Text("smtp.example.com")) {
                        SettingLabel(title: "SMTP server (465)", symbol: "arrow.up.circle.fill", color: .gray)
                    }
                }
                HStack(spacing: 12) {
                    Button {
                        Task { await add() }
                    } label: {
                        if ui.testing {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Connecting…") }
                        } else {
                            Label("Connect", systemImage: "link")
                        }
                    }
                    .buttonStyle(PillButtonStyle(tint: Brand.pink))
                    .disabled(ui.testing || ui.email.isEmpty || ui.password.isEmpty)
                    if let (text, ok) = ui.message {
                        Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(ok ? Brand.keep : Brand.remove)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
    }

    private func providerTile(_ kind: AccountKind) -> some View {
        let selected = ui.kind == kind
        return Button {
            withAnimation(.snappy) { ui.kind = kind }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: kind.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(kind.color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(kind.shortLabel).font(.callout.weight(selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? kind.color.opacity(0.1) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? kind.color : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var help: some View {
        switch ui.kind {
        case .gmail:
            VStack(alignment: .leading, spacing: 4) {
                FooterText("Gmail needs an app password, not your normal password. 2-Step Verification must be on.")
                Link("Create a Gmail app password →", destination: URL(string: "https://myaccount.google.com/apppasswords")!)
            }
        case .att:
            VStack(alignment: .leading, spacing: 4) {
                FooterText("AT&T and SBC Global addresses need a secure mail key. Sign in at att.com, open Profile → Sign-in info, then create a secure mail key for this address.")
                Link("Open myAT&T →", destination: URL(string: "https://www.att.com/my/")!)
            }
        case .other:
            FooterText("Use an app-specific password if your provider offers one.")
        case .appleMail:
            FooterText("Uses accounts already set up in Apple Mail, with no password needed here. Handy for AT&T/SBC when you can't get a secure mail key. Mail opens in the background during checks, and macOS asks once for permission to let Clutter Clear control it.")
        }
    }

    private func loadMailAccounts() async {
        ui.loadingMail = true
        ui.mailError = nil
        defer { ui.loadingMail = false }
        do {
            let found = try await Task.detached { try AppleMail.listAccounts() }.value
            withAnimation { ui.mailAccounts = found }
            if found.isEmpty { ui.mailError = "Apple Mail has no accounts set up." }
        } catch {
            ui.mailError = error.localizedDescription
        }
    }

    private func addMailAccount(_ m: AppleMail.MailAppAccount) async {
        var account = MailAccount.preset(.appleMail, email: m.email.isEmpty ? m.name : m.email)
        account.appleMailName = m.name
        do {
            try await state.addAccount(account, password: "")
            withAnimation { ui.message = ("Connected \(m.name)", true) }
        } catch {
            withAnimation { ui.message = (error.localizedDescription, false) }
        }
    }

    private func add() async {
        ui.testing = true
        ui.message = nil
        defer { ui.testing = false }
        var account = MailAccount.preset(ui.kind, email: ui.email.trimmingCharacters(in: .whitespaces).lowercased())
        if ui.kind == .other {
            if !ui.imapHost.isEmpty { account.imapHost = ui.imapHost }
            if !ui.smtpHost.isEmpty { account.smtpHost = ui.smtpHost }
        }
        do {
            try await state.addAccount(account, password: ui.password.replacingOccurrences(of: " ", with: ""))
            withAnimation { ui.message = ("Connected \(account.email)", true) }
            ui.email = ""
            ui.password = ""
        } catch {
            withAnimation { ui.message = (error.localizedDescription, false) }
        }
    }
}
