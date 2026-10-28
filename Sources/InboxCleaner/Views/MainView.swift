import SwiftUI

struct MainView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var tabs: TabSelection

    var body: some View {
        TabView(selection: $tabs.selected) {
            ReviewView()
                .tabItem { Label("Review", systemImage: "tray.full") }
                .tag(MainTab.review)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "clock") }
                .tag(MainTab.activity)
            AccountsView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(MainTab.accounts)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .padding(.top, 8)
        .frame(minWidth: 820, minHeight: 520)
    }
}

extension Category {
    var color: Color {
        switch self {
        case .promotional: return .blue
        case .repetitive: return .purple
        case .suspicious: return .red
        }
    }
    var icon: String {
        switch self {
        case .promotional: return "megaphone"
        case .repetitive: return "repeat"
        case .suspicious: return "exclamationmark.shield"
        }
    }
}

struct CategoryPill: View {
    let category: Category
    var body: some View {
        Label(category.label, systemImage: category.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(category.color.opacity(0.15), in: Capsule())
            .foregroundStyle(category.color)
    }
}
