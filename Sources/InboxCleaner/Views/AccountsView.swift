import AppKit
import SwiftUI

struct AccountsView: View {
    @StateObject private var ui = AccountsUI()
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Connected inboxes") {
                if state.data.accounts.isEmpty {
                    Text("No accounts yet.").foregroundStyle(.secondary)
                }
                ForEach(state.data.accounts) { a in
                    HStack {
                        Image(systemName: "envelope")
                        VStack(alignment: .leading) {
                            Text(a.email)
                            Text("\(a.kind.label) · \(a.imapHost)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let last = state.data.lastScan[a.id.uuidString] {
                            Text("Checked \(last.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Remove", role: .destructive) { state.removeAccount(a) }
                    }
                }
            }

            Section("Add an inbox") {
                Picker("Provider", selection: $ui.kind) {
                    ForEach(AccountKind.allCases) { Text($0.label).tag($0) }
                }
                TextField("Email address", text: $ui.email)
                    .textContentType(.username)
                SecureField(ui.kind == .att ? "Secure mail key" : "App password", text: $ui.password)
                if ui.kind == .other {
                    TextField("IMAP server (port 993)", text: $ui.imapHost, prompt: Text("imap.example.com"))
                    TextField("SMTP server (port 465)", text: $ui.smtpHost, prompt: Text("smtp.example.com"))
                }
                help
                HStack {
                    Button(ui.testing ? "Connecting…" : "Connect") { Task { await add() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(ui.testing || ui.email.isEmpty || ui.password.isEmpty)
                    if ui.testing { ProgressView().controlSize(.small) }
                    if let (text, ok) = ui.message {
                        Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(ok ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var help: some View {
        switch ui.kind {
        case .gmail:
            VStack(alignment: .leading, spacing: 4) {
                Text("Gmail needs an app password, not your normal password. 2-Step Verification must be on.")
                Link("Create a Gmail app password →", destination: URL(string: "https://myaccount.google.com/apppasswords")!)
            }
            .font(.callout).foregroundStyle(.secondary)
        case .att:
            VStack(alignment: .leading, spacing: 4) {
                Text("AT&T and SBC Global addresses need a secure mail key. Sign in at att.com, open Profile → Sign-in info, then create a secure mail key for this address.")
                Link("Open myAT&T →", destination: URL(string: "https://www.att.com/my/")!)
            }
            .font(.callout).foregroundStyle(.secondary)
        case .other:
            Text("Use an app-specific password if your provider offers one.").font(.callout).foregroundStyle(.secondary)
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
            ui.message = ("Connected \(account.email)", true)
            ui.email = ""
            ui.password = ""
        } catch {
            ui.message = (error.localizedDescription, false)
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
}
