import SwiftUI

struct MainView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var tabs: TabSelection

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            Group {
                switch tabs.selected ?? .review {
                case .review: ReviewView()
                case .activity: ActivityView()
                case .accounts: AccountsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(isPresented: $state.showDeepClean) {
            DeepCleanSheet().environmentObject(state)
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var tabs: TabSelection

    var body: some View {
        let manual = state.data.log.filter { $0.manualURL != nil && !$0.manualDone }.count
        List(selection: $tabs.selected) {
            Section {
                Label("Review", systemImage: "tray.full.fill")
                    .badge(state.pending.count)
                    .tag(MainTab.review)
                Label("Activity", systemImage: "clock.arrow.circlepath")
                    .badge(manual)
                    .tag(MainTab.activity)
            }
            Section("Setup") {
                Label("Accounts", systemImage: "person.crop.circle")
                    .tag(MainTab.accounts)
                Label("Settings", systemImage: "gearshape")
                    .tag(MainTab.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { brand }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            if Bundle.main.bundleIdentifier != nil {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.gradient)
                    Image(systemName: "sparkles").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
            }
            Text("Clutter Clear").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.data.clearedEmails > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Brand.gradient)
                    Text("\(state.data.clearedEmails.formatted()) emails cleared")
                        .font(.callout.weight(.medium))
                }
            }
            HStack(spacing: 8) {
                if state.isScanning {
                    ProgressView().controlSize(.small)
                    Text(state.scanStatus.isEmpty ? "Checking…" : state.scanStatus)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Image(systemName: state.settings.dailyCheckEnabled ? "alarm" : "alarm.waves.left.and.right")
                        .foregroundStyle(.secondary)
                    Text(state.nextRunDescription).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button {
                Task { await state.scan(auto: false) }
            } label: {
                Label("Check Now", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(tint: Brand.accent, prominent: false))
            .disabled(state.isScanning || state.data.accounts.isEmpty)
        }
        .padding(14)
    }
}
