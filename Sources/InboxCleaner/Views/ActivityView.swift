import AppKit
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let entries = Array(state.data.log.reversed())
        let manual = entries.filter { $0.manualURL != nil && !$0.manualDone }
        VStack(spacing: 0) {
            HStack {
                Text("Activity").font(.title2.weight(.semibold))
                Spacer()
                Button("Clear") { state.clearLog() }.disabled(entries.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if entries.isEmpty {
                Text("Nothing yet. Decisions you make in Review show up here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !manual.isEmpty {
                        Section("Needs you to finish (\(manual.count))") {
                            ForEach(manual) { LogRow(entry: $0) }
                        }
                    }
                    Section("History") {
                        ForEach(entries) { LogRow(entry: $0) }
                    }
                }
            }
        }
    }
}

struct LogRow: View {
    @EnvironmentObject var state: AppState
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(entry.success ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.sender.isEmpty ? entry.accountEmail : entry.sender).font(.body.weight(.medium))
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.text).foregroundStyle(.secondary).textSelection(.enabled)
                if let raw = entry.manualURL, let url = URL(string: raw), !entry.manualDone {
                    HStack {
                        Button("Open Unsubscribe Page") { NSWorkspace.shared.open(url) }
                        Button("Mark Done") { state.markManualDone(entry) }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
