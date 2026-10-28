import AppKit
import SwiftUI
import UserNotifications

@main
struct InboxCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(state)
        } label: {
            Image(systemName: state.data.candidates.isEmpty ? "envelope" : "envelope.badge")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--nettest") {
            SelfTest.network()
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshot.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
            exit(0)
        }
        if CommandLine.arguments.contains("--selftest") {
            let ok = MainActor.assumeIsolated { SelfTest.run() }
            exit(ok ? 0 : 1)
        }
        NSApp.setActivationPolicy(.accessory)
        if AppState.canNotify { UNUserNotificationCenter.current().delegate = self }
        Task { @MainActor in
            let state = AppState.shared
            state.requestNotificationPermission()
            state.start()
            if state.data.accounts.isEmpty { WindowManager.shared.show(tab: .accounts) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in WindowManager.shared.show() }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in WindowManager.shared.show(tab: .review) }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let count = state.data.candidates.count
        Button(count == 0 ? "Open Inbox Cleaner" : "Review \(count) sender\(count == 1 ? "" : "s")…") {
            WindowManager.shared.show(tab: .review)
        }
        .keyboardShortcut("r")
        Button(state.isScanning ? "Checking…" : "Check Now") {
            Task { await state.scan(auto: false) }
        }
        .disabled(state.isScanning || state.data.accounts.isEmpty)
        Divider()
        Toggle("Daily Check", isOn: Binding(
            get: { state.settings.dailyCheckEnabled },
            set: { var s = state.settings; s.dailyCheckEnabled = $0; state.settings = s }))
        Text(state.nextRunDescription)
        Divider()
        Button("Activity…") { WindowManager.shared.show(tab: .activity) }
        Button("Settings…") { WindowManager.shared.show(tab: .settings) }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Inbox Cleaner") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Owns the main window. The app lives in the menu bar and shows a Dock icon only while this window is open.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    private var window: NSWindow?
    let tabs = TabSelection()

    func show(tab: MainTab? = nil) {
        if let tab { tabs.selected = tab }
        if window == nil {
            let host = NSHostingController(rootView: MainView().environmentObject(AppState.shared).environmentObject(tabs))
            let w = NSWindow(contentViewController: host)
            w.title = "Inbox Cleaner"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 1000, height: 680))
            w.minSize = NSSize(width: 820, height: 520)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("InboxCleanerMain")
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

enum MainTab: Hashable { case review, activity, accounts, settings }

final class TabSelection: ObservableObject {
    @Published var selected: MainTab = .review
}
