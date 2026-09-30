import AppKit
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayManager()
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory app: no Dock icon, no main menu
        NSApp.setActivationPolicy(.accessory)

        menuBar = MenuBarController()
        menuBar.onVisibilityChange = { [weak self] in self?.overlay.applyVisibility() }
        menuBar.onSettingsChange = { [weak self] in self?.overlay.applySettingsChange() }
        menuBar.onQuit = { NSApp.terminate(nil) }

        // f3 toggles the overlay system-wide
        HotKeyCenter.install { [weak self] in
            SettingsModel.shared.isVisible.toggle()
            self?.overlay.applyVisibility()
        }

        // window was already built in OverlayManager.init; just show it and begin sampling
        overlay.applyVisibility()
        overlay.start()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // desktop windows get re-layered on space switches on some builds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.overlay.reposition()
                self?.overlay.applyVisibility()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.overlay.reposition()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.overlay.rebuildWindow()
            self?.overlay.applyVisibility()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.stop()
    }
}
