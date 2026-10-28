import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var tabs: TabSelection
    @StateObject private var ui = ReviewUI()

    var body: some View {
        let items = state.pending
        VStack(spacing: 0) {
            header(count: items.count)
            if let err = state.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { state.lastError = nil }.buttonStyle(.borderless)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
            }
            Divider()
            if state.data.accounts.isEmpty {
                empty(title: "Add an email account to get started",
                      detail: "Inbox Cleaner needs an app password for each inbox you want cleaned.",
                      action: ("Add Account", { tabs.selected = .accounts }))
            } else if items.isEmpty {
                empty(title: state.isScanning ? "Checking your inboxes…" : "Nothing to review",
                      detail: state.isScanning ? state.scanStatus : "New promotional or spam senders will show up here after each check.",
                      action: nil)
            } else {
                HStack(spacing: 0) {
                    List(items, selection: $ui.selection) { c in
                        CandidateRow(candidate: c, accountEmail: state.account(for: c.accountID)?.email ?? "")
                            .tag(c.id)
                    }
                    .listStyle(.sidebar)
                    .frame(width: 320)
                    Divider()
                    if let c = items.first(where: { $0.id == ui.selection }) {
                        CandidateDetail(candidate: c, onDone: { advance(from: c.id, in: items) })
                            .id(c.id)
                    } else {
                        empty(title: "Select a sender", detail: "", action: nil)
                    }
                }
            }
        }
        .onAppear { if ui.selection == nil { ui.selection = items.first?.id } }
        .onChange(of: items.map(\.id)) { _, ids in
            if ui.selection == nil || !ids.contains(ui.selection!) { ui.selection = ids.first }
        }
    }

    private func advance(from id: String, in items: [Candidate]) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let rest = items.enumerated().filter { $0.offset != i }.map(\.element)
        ui.selection = rest.isEmpty ? nil : rest[min(i, rest.count - 1)].id
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "All clear" : "\(count) sender\(count == 1 ? "" : "s") to review")
                    .font(.title2.weight(.semibold))
                Text(state.isScanning ? state.scanStatus : state.nextRunDescription)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if state.isScanning { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button {
                Task { await state.scan(auto: false) }
            } label: {
                Label("Check Now", systemImage: "arrow.clockwise")
            }
            .disabled(state.isScanning || state.data.accounts.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func empty(title: String, detail: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.medium))
            if !detail.isEmpty { Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let action { Button(action.0, action: action.1).buttonStyle(.borderedProminent) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CandidateRow: View {
    let candidate: Candidate
    let accountEmail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: candidate.category.icon)
                .foregroundStyle(candidate.category.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.senderName).font(.body.weight(.medium)).lineLimit(1)
                Text(candidate.flagged.max(by: { $0.date < $1.date })?.subject ?? candidate.senderEmail)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(accountEmail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text("\(candidate.flagged.count)")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 3)
    }
}

struct CandidateDetail: View {
    @EnvironmentObject var state: AppState
    let candidate: Candidate
    let onDone: () -> Void
    @StateObject private var ui = DetailUI()

    private var c: Candidate { candidate }
    private var isBusy: Bool { state.busy.contains(c.id) }
    private var thisOrThese: String { c.flagged.count == 1 ? "this email" : "these \(c.flagged.count) emails" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    CategoryPill(category: c.category)
                    Text(c.senderName).font(.title.weight(.semibold)).textSelection(.enabled)
                    Text(c.senderEmail).foregroundStyle(.secondary).textSelection(.enabled)
                    if let account = state.account(for: c.accountID) {
                        Label(account.email, systemImage: "tray").font(.caption).foregroundStyle(.secondary)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(c.reason)
                        Text("\(c.recentCount) email\(c.recentCount == 1 ? "" : "s") from this sender in the last \(c.windowDays) days.")
                            .foregroundStyle(.secondary)
                        if let when = c.previouslyUnsubscribed {
                            Label("You unsubscribed on \(when.formatted(date: .abbreviated, time: .omitted)) and they're still sending.",
                                  systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                        if c.category == .suspicious {
                            Label("Don't unsubscribe from spam. Clicking its links tells the sender your address is real. Move it to Junk instead.",
                                  systemImage: "hand.raised.fill")
                                .foregroundStyle(.red)
                        } else {
                            Label(c.unsubscribeSummary, systemImage: "link").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                actions

                VStack(alignment: .leading, spacing: 6) {
                    Text("Flagged emails").font(.headline)
                    ForEach(c.flagged.sorted { $0.date > $1.date }, id: \.self) { m in
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.subject).lineLimit(1)
                            Spacer()
                            Text(m.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Unsubscribe from \(c.senderName)?", isPresented: $ui.askUnsubscribe, titleVisibility: .visible) {
            Button("Unsubscribe and delete \(thisOrThese)") { run { await state.unsubscribe(c, delete: .flagged) } }
            Button("Unsubscribe and delete all emails from this sender") { run { await state.unsubscribe(c, delete: .allFromSender) } }
            Button("Unsubscribe only") { run { await state.unsubscribe(c, delete: .none) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleted emails go to Trash, so you can still recover them.")
        }
        .confirmationDialog("Move \(c.senderName) to Junk?", isPresented: $ui.askJunk, titleVisibility: .visible) {
            Button("Junk \(thisOrThese) and block sender") { run { await state.junk(c, scope: .flagged) } }
            Button("Junk all emails from this sender and block") { run { await state.junk(c, scope: .allFromSender) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Future emails from this address will be moved to Junk automatically during each check.")
        }
    }

    @ViewBuilder private var actions: some View {
        if isBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(c.category == .suspicious ? "Moving to Junk…" : "Unsubscribing…").foregroundStyle(.secondary)
            }
            .frame(height: 32)
        } else {
            HStack(spacing: 10) {
                Button {
                    state.keep(c)
                    onDone()
                } label: {
                    Label("Keep", systemImage: "checkmark").frame(minWidth: 90)
                }
                .controlSize(.large)
                .keyboardShortcut("k", modifiers: [])

                if c.category == .suspicious {
                    Button {
                        ui.askJunk = true
                    } label: {
                        Label("Move to Junk…", systemImage: "xmark.bin").frame(minWidth: 130)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut("j", modifiers: [])

                    Button("It's a real newsletter: unsubscribe instead…") { ui.askUnsubscribe = true }
                        .buttonStyle(.link)
                } else {
                    Button {
                        ui.askUnsubscribe = true
                    } label: {
                        Label("Unsubscribe…", systemImage: "xmark.circle").frame(minWidth: 130)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut("u", modifiers: [])
                }
            }
            Text(c.category == .suspicious ? "Shortcuts: K keep · J junk" : "Shortcuts: K keep · U unsubscribe")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        let done = onDone
        Task {
            await work()
            done()
        }
    }
}

final class ReviewUI: ObservableObject {
    @Published var selection: String?
}

final class DetailUI: ObservableObject {
    @Published var askUnsubscribe = false
    @Published var askJunk = false
}
