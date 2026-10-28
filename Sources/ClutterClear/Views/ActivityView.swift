import AppKit
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let entries = Array(state.data.log.reversed())
        let manual = entries.filter { $0.manualURL != nil && !$0.manualDone }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Activity").font(.largeTitle.weight(.bold))
                        Text("Everything Clutter Clear has done for you").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear History") { state.clearLog() }
                        .buttonStyle(PillButtonStyle(tint: .secondary, prominent: false))
                        .disabled(entries.isEmpty)
                }

                HStack(spacing: 12) {
                    StatTile(icon: "sparkles", value: state.data.clearedEmails.formatted(), label: "emails cleared", tint: Brand.pink)
                    StatTile(icon: "hand.wave.fill", value: "\(state.data.unsubscribedSenders.count)", label: "unsubscribed", tint: Brand.violet)
                    StatTile(icon: "xmark.shield.fill", value: "\(state.data.blockedSenders.count)", label: "blocked", tint: Brand.remove)
                    StatTile(icon: "heart.fill", value: "\(state.data.approvedSenders.count)", label: "kept", tint: Brand.keep)
                }

                if !manual.isEmpty {
                    section("Needs you to finish", count: manual.count, tint: .orange) {
                        ForEach(manual) { LogRow(entry: $0, showActions: true) }
                    }
                }

                if entries.isEmpty {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "No activity yet",
                                   detail: "Decisions you make in Review show up here.")
                        .frame(height: 300)
                } else {
                    section("History", count: entries.count, tint: .secondary) {
                        ForEach(entries) { LogRow(entry: $0, showActions: false) }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private func section<Content: View>(_ title: String, count: Int, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }
            VStack(spacing: 0) { content() }
                .surface(radius: 16, padding: 6)
        }
    }
}

struct LogRow: View {
    @EnvironmentObject var state: AppState
    let entry: LogEntry
    let showActions: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                SenderAvatar(name: entry.sender.isEmpty ? entry.accountEmail : entry.sender,
                             email: entry.sender.isEmpty ? entry.accountEmail : entry.sender, size: 32)
                Image(systemName: entry.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, entry.success ? Brand.keep : .orange)
                    .background(Circle().fill(.background).padding(-1))
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.sender.isEmpty ? entry.accountEmail : entry.sender).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(entry.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.text).foregroundStyle(.secondary).textSelection(.enabled)
                if showActions, let raw = entry.manualURL, let url = URL(string: raw) {
                    HStack(spacing: 8) {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Open Unsubscribe Page", systemImage: "safari") }
                            .buttonStyle(PillButtonStyle(tint: .orange))
                        Button("Mark Done") { withAnimation { state.markManualDone(entry) } }
                            .buttonStyle(PillButtonStyle(tint: .secondary, prominent: false))
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(12)
    }
}
