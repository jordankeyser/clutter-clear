import SwiftUI

struct SettingsView: View {
    @StateObject private var ui = SettingsUI()
    @EnvironmentObject var state: AppState

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { state.settings[keyPath: keyPath] },
                set: { var s = state.settings; s[keyPath: keyPath] = $0; state.settings = s })
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: state.settings.hour, minute: state.settings.minute, second: 0, of: Date()) ?? Date() },
            set: {
                var s = state.settings
                s.hour = Calendar.current.component(.hour, from: $0)
                s.minute = Calendar.current.component(.minute, from: $0)
                state.settings = s
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Check every morning", isOn: binding(\.dailyCheckEnabled))
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .disabled(!state.settings.dailyCheckEnabled)
                Toggle("Open at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.launchAtLogin = $0 }))
                Stepper("First check looks back \(state.settings.initialLookbackDays) days",
                        value: binding(\.initialLookbackDays), in: 7...365, step: 7)
            } header: {
                Text("Daily check")
            } footer: {
                Text("When checks are off, nothing is read. Turning them back on immediately catches up on every email since the last check, and emails you've already reviewed are never shown twice. If your Mac is asleep at check time, it runs when the Mac wakes.")
            }

            Section {
                Toggle("Use Claude to classify senders", isOn: binding(\.useClaude))
                Picker("Model", selection: binding(\.claudeModel)) {
                    ForEach(ClaudeModel.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .disabled(!state.settings.useClaude)
                HStack {
                    SecureField(state.claudeKey.isEmpty ? "Anthropic API key (sk-ant-…)" : "Key saved. Paste a new one to replace it.",
                                text: $ui.apiKeyDraft)
                    Button("Save Key") {
                        state.claudeKey = ui.apiKeyDraft
                        ui.apiKeyDraft = ""
                    }
                    .disabled(ui.apiKeyDraft.isEmpty)
                    if !state.claudeKey.isEmpty {
                        Button("Remove", role: .destructive) { state.claudeKey = "" }
                    }
                }
                Link("Get an API key at console.anthropic.com →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
            } header: {
                Text("AI classification (optional)")
            } footer: {
                Text("Only sender names, addresses and subject lines are sent, never email bodies, and only for senders that already look automated. Without a key, the built-in rules are used.")
            }

            Section("Approved senders (\(state.data.approvedSenders.count))") {
                if state.data.approvedSenders.isEmpty {
                    Text("Senders you keep are listed here and never flagged again.").foregroundStyle(.secondary)
                }
                ForEach(state.data.approvedSenders.sorted(), id: \.self) { email in
                    HStack {
                        Text(email)
                        Spacer()
                        Button("Forget") { state.unapprove(email) }
                    }
                }
            }

            Section("Blocked senders (\(state.data.blockedSenders.count))") {
                if state.data.blockedSenders.isEmpty {
                    Text("Spam senders you block are moved to Junk automatically.").foregroundStyle(.secondary)
                }
                ForEach(state.data.blockedSenders.sorted(), id: \.self) { email in
                    HStack {
                        Text(email)
                        Spacer()
                        Button("Unblock") { state.unblock(email) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

final class SettingsUI: ObservableObject {
    @Published var apiKeyDraft = ""
}
