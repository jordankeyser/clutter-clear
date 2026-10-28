import AppKit
import SwiftUI

/// `InboxCleaner --snapshot <dir>` renders each tab with sample data to PNGs, for checking layout.
@MainActor
enum Snapshot {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppState.shared.loadDemo()
        for (tab, name) in [(MainTab.review, "review"), (.activity, "activity"), (.accounts, "accounts"), (.settings, "settings")] {
            let tabs = TabSelection()
            tabs.selected = tab
            let view = MainView().environmentObject(AppState.shared).environmentObject(tabs)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }
    }
}
