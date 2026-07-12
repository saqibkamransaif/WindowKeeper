import AppKit
import WindowKeeperCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: WindowManager!
    private var menuController: StatusMenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = try LayoutStore()
            manager = WindowManager(store: store)
        } catch {
            Log.shared.error("Failed to initialize store: \(error)")
            NSApp.terminate(nil)
            return
        }

        menuController = StatusMenuController(manager: manager)

        if AccessibilityService.isTrusted(prompt: true) {
            Log.shared.info("Accessibility access granted")
        } else {
            Log.shared.info("Waiting for Accessibility access — grant it in "
                + "System Settings → Privacy & Security → Accessibility, then relaunch")
        }

        manager.start()
    }
}
