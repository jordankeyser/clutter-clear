import SwiftUI

@MainActor
final class DeepCleanUI: ObservableObject {
    @Published var days = 365
    @Published var accountIDs: Set<UUID>
    @Published var includeArchive = true
    init(accounts: [MailAccount]) { accountIDs = Set(accounts.map(\.id)) }
}

/// Options for a one-time sweep of older mail.
struct DeepCleanSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = DeepCleanUI(accounts: AppState.shared.data.accounts)

    private let ranges: [(String, Int)] = [("6 months", 182), ("1 year", 365), ("2 years", 730), ("Everything", 36500)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep Clean").font(.title2.weight(.bold))
                    Text("Find clutter in older mail, one time").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How far back").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Picker("How far back", selection: $ui.days) {
                    ForEach(ranges, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Inboxes").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(state.data.accounts) { a in
                    Toggle(isOn: Binding(
                        get: { ui.accountIDs.contains(a.id) },
                        set: { on in if on { ui.accountIDs.insert(a.id) } else { ui.accountIDs.remove(a.id) } })) {
                        HStack(spacing: 8) {
                            SettingIcon(symbol: a.kind.icon, color: a.kind.color)
                            Text(a.email)
                            if a.kind == .appleMail {
                                Text("via Apple Mail · slower").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Toggle(isOn: $ui.includeArchive) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include archived mail")
                    Text("Also look in All Mail and other folders, not just the inbox.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                bullet("eye", "Reads only sender, subject, date and unsubscribe info. Never email bodies.")
                bullet("hand.raised", "Deletes and unsubscribes nothing. Senders are added to Review for you to decide.")
                bullet("checkmark.seal", "Skips senders you've kept or blocked. Personal mail is never flagged.")
                if state.settings.useClaude && !state.claudeKey.isEmpty {
                    bullet("sparkles", "Claude double-checks the results. A year of mail costs about $0.50–$1 on Opus, or a few cents on Haiku.")
                }
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(PillButtonStyle(tint: .secondary, prominent: false))
                Button {
                    let options = AppState.DeepCleanOptions(days: ui.days, accountIDs: ui.accountIDs, includeArchive: ui.includeArchive)
                    dismiss()
                    Task { await state.deepClean(options) }
                } label: {
                    Label("Start Deep Clean", systemImage: "wand.and.sparkles")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PillButtonStyle(tint: Brand.accent))
                .disabled(ui.accountIDs.isEmpty || state.isScanning)
            }
        }
        .padding(26)
        .frame(width: 520)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Brand.accent).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
