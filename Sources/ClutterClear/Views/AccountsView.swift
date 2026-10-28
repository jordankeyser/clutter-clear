import AppKit
import SwiftUI

extension AccountKind {
    var icon: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .att: return "globe.americas.fill"
        case .other: return "server.rack"
        }
    }
    var color: Color {
        switch self {
        case .gmail: return .red
        case .att: return .blue
        case .other: return .gray
        }
    }
    var shortLabel: String {
        switch self {
        case .gmail: return "Gmail"
        case .att: return "AT&T / SBC"
        case .other: return "Other"
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
            Text("Its saved password is deleted from this Mac. Your email isn't touched.")
        }
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
