import AppKit
import SwiftUI

/// `ClutterClear --snapshot <dir>` renders each screen with sample data to PNGs, for checking layout.
@MainActor
enum Snapshot {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = AppState.shared
        state.loadDemo()

        let shots: [(String, MainTab, ReviewStyle, NSAppearance.Name)] = [
            ("cards", .review, .cards, .aqua),
            ("cards-dark", .review, .cards, .darkAqua),
            ("list", .review, .list, .aqua),
            ("list-dark", .review, .list, .darkAqua),
            ("activity", .activity, .cards, .aqua),
            ("accounts", .accounts, .cards, .aqua),
            ("settings", .settings, .cards, .aqua),
        ]
        for (name, tab, style, appearance) in shots {
            var s = state.settings
            s.reviewStyle = style
            state.settings = s
            let tabs = TabSelection()
            tabs.selected = tab
            let host = NSHostingView(rootView: MainView().environmentObject(state).environmentObject(tabs))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }

        let sheet = NSHostingView(rootView: DeepCleanSheet().environmentObject(state))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = sheet
        sheet.setFrameSize(sheet.fittingSize)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        if let rep = sheet.bitmapImageRepForCachingDisplay(in: sheet.bounds) {
            sheet.cacheDisplay(in: sheet.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("deep-clean.png"))
            print("wrote deep-clean.png")
        }
    }
}
