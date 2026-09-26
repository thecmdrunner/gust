import AppKit
import SwiftUI

/// `GUST_SNAPSHOT=/path/prefix Gust` renders the panel in light + dark to PNGs and exits. Used for UI checks.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var debugWindow: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        if ProcessInfo.processInfo.environment["GUST_WINDOW"] != nil, let c = FanController.shared {
            // Hosts the live panel in a normal window, for UI testing when the menu bar item is hidden.
            let w = NSWindow(contentViewController: NSHostingController(rootView: PanelView().environmentObject(c)))
            w.title = "Gust"
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            debugWindow = w
            return
        }
        guard let prefix = ProcessInfo.processInfo.environment["GUST_SNAPSHOT"] else { return }
        let c = FanController()
        if let m = ProcessInfo.processInfo.environment["GUST_MODE"].flatMap(FanMode.init(rawValue:)) { c.mode = m }
        for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = NSHostingView(rootView: PanelView().environmentObject(c).background(Color(nsColor: .windowBackgroundColor)))
            view.appearance = NSAppearance(named: look)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.setFrameSize(view.fittingSize)
            window.setContentSize(view.fittingSize)
            window.backgroundColor = look == .aqua ? .windowBackgroundColor : NSColor(white: 0.16, alpha: 1)
            window.appearance = NSAppearance(named: look)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        }
        exit(0)
    }
}
