import SwiftUI

/// Rounded colored icon square, like the ones in System Settings.
struct SettingIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct SettingLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            SettingIcon(symbol: symbol, color: color)
            Text(title)
        }
    }
}

struct FooterText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

final class SettingsUI: ObservableObject {
    @Published var apiKeyDraft = ""
}

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
                VStack(alignment: .leading, spacing: 12) {
                    SettingLabel(title: "Review style", symbol: "rectangle.stack.fill", color: Brand.accent)
                    HStack(spacing: 12) {
                        ForEach(ReviewStyle.allCases) { style in
                            StyleTile(style: style, selected: state.settings.reviewStyle == style) {
                                withAnimation(.snappy) { binding(\.reviewStyle).wrappedValue = style }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                HStack {
                    SettingLabel(title: "Deep clean older mail", symbol: "wand.and.sparkles", color: Brand.indigo)
                    Spacer()
                    Button("Deep Clean…") { state.showDeepClean = true }
                        .disabled(state.isScanning || state.data.accounts.isEmpty)
                }
                Picker(selection: binding(\.defaultCleanup)) {
                    ForEach(DeleteScope.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                } label: {
                    SettingLabel(title: "After unsubscribing", symbol: "trash.fill", color: .orange)
                }
            } header: {
                Text("Reviewing")
            } footer: {
                FooterText("Cards show one sender at a time; swipe right to keep, left to unsubscribe. Whatever cleanup choice you pick while reviewing becomes the new default here.")
            }

            Section {
                Toggle(isOn: binding(\.dailyCheckEnabled)) {
                    SettingLabel(title: "Check every morning", symbol: "alarm.fill", color: .blue)
                }
                DatePicker(selection: time, displayedComponents: .hourAndMinute) {
                    SettingLabel(title: "Time", symbol: "clock.fill", color: .indigo)
                }
                .disabled(!state.settings.dailyCheckEnabled)
                Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.launchAtLogin = $0 })) {
                    SettingLabel(title: "Open at login", symbol: "power", color: .gray)
                }
                Stepper(value: binding(\.initialLookbackDays), in: 7...365, step: 7) {
                    SettingLabel(title: "First check looks back \(state.settings.initialLookbackDays) days", symbol: "calendar", color: .red)
                }
            } header: {
                Text("Daily check")
            } footer: {
                FooterText("When checks are off, nothing is read. Turning them back on immediately catches up on every email since the last check, and emails you've already reviewed are never shown twice. If your Mac is asleep at check time, the check runs when it wakes.")
            }

            Section {
                Toggle(isOn: binding(\.useClaude)) {
                    SettingLabel(title: "Use Claude to sort senders", symbol: "sparkles", color: Brand.violet)
                }
                Picker(selection: binding(\.claudeModel)) {
                    ForEach(ClaudeModel.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    SettingLabel(title: "Model", symbol: "cpu", color: .purple)
                }
                .disabled(!state.settings.useClaude)
                HStack {
                    SettingIcon(symbol: "key.fill", color: .yellow)
                    SecureField("", text: $ui.apiKeyDraft,
                                prompt: Text(state.claudeKey.isEmpty ? "Anthropic API key (sk-ant-…)" : "Key saved. Paste a new one to replace it."))
                        .labelsHidden()
                    Button("Save") {
                        state.claudeKey = ui.apiKeyDraft
                        ui.apiKeyDraft = ""
                    }
                    .disabled(ui.apiKeyDraft.isEmpty)
                    if !state.claudeKey.isEmpty {
                        Button("Remove", role: .destructive) { state.claudeKey = "" }
                    }
                }
                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    Label("Get an API key", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("AI sorting (optional)")
            } footer: {
                FooterText("Only sender names, addresses and subject lines are sent, never email bodies, and only for senders that already look automated. Without a key, the built-in rules are used.")
            }

            Section {
                if state.data.unsubscribedSenders.isEmpty {
                    Text("Senders you unsubscribe from show up here.").foregroundStyle(.secondary)
                }
                ForEach(state.data.unsubscribedSenders.sorted { $0.value > $1.value }, id: \.key) { email, date in
                    HStack(spacing: 10) {
                        SenderAvatar(name: email, email: email, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(email)
                            Text("Unsubscribed \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.busy.contains(email) {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Delete All Their Emails") { Task { await state.deleteEverything(from: email) } }
                        }
                    }
                }
            } header: {
                Text("Unsubscribed senders (\(state.data.unsubscribedSenders.count))")
            } footer: {
                FooterText("Moves every email from that sender to Trash in all your inboxes, including archived mail.")
            }

            Section {
                if state.data.approvedSenders.isEmpty {
                    Text("Senders you keep show up here and are never flagged again.").foregroundStyle(.secondary)
                }
                ForEach(state.data.approvedSenders.sorted(), id: \.self) { email in
                    senderRow(email, button: "Forget") { state.unapprove(email) }
                }
            } header: {
                Text("Kept senders (\(state.data.approvedSenders.count))")
            }

            Section {
                if state.data.blockedSenders.isEmpty {
                    Text("Spam senders you block go straight to Junk on every check.").foregroundStyle(.secondary)
                }
                ForEach(state.data.blockedSenders.sorted(), id: \.self) { email in
                    senderRow(email, button: "Unblock") { state.unblock(email) }
                }
            } header: {
                Text("Blocked senders (\(state.data.blockedSenders.count))")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func senderRow(_ email: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            SenderAvatar(name: email, email: email, size: 24)
            Text(email)
            Spacer()
            Button(button, action: action)
        }
    }
}

/// Visual picker tile for the review style setting.
struct StyleTile: View {
    let style: ReviewStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                preview
                    .frame(height: 70)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Label(style.label, systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Brand.accent : .secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.separator), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var preview: some View {
        if style == .cards {
            ZStack {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.background)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
                        .frame(width: 70 - CGFloat(i) * 8, height: 44)
                        .offset(y: CGFloat(i) * -5)
                        .zIndex(Double(-i))
                }
                Circle().fill(Brand.gradient).frame(width: 14, height: 14).offset(x: -20, y: -4)
            }
            .offset(y: 4)
        } else {
            VStack(spacing: 5) {
                ForEach(0..<4) { i in
                    HStack(spacing: 5) {
                        Circle().fill(i == 0 ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.tertiary)).frame(width: 8, height: 8)
                        Capsule().fill(.tertiary).frame(height: 5)
                    }
                    .frame(width: 80)
                }
            }
        }
    }
}
