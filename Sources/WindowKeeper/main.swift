import AppKit
import WindowKeeperCore

let version = "1.3.1"
let args = CommandLine.arguments.dropFirst()

if args.contains("--version") {
    print("WindowKeeper \(version)")
    exit(0)
}

if args.contains("--diagnose") {
    print("WindowKeeper \(version) — diagnostics")
    print("Accessibility trusted: \(AccessibilityService.isTrusted())")
    let store = try? LayoutStore()
    if let store {
        let config = store.loadConfig()
        print("Config dir: \(store.directory.path)")
        print("Enabled: \(config.enabled)")
        print("Rules: \(config.rules.count)")
        for rule in config.rules {
            print("  - \(rule.displayName) [\(rule.bundleID)] mode=\(rule.mode)")
        }
        print("Zones: \(config.zones.count)")
        print("Presets: \(store.loadPresets().count)")
        print("Remembered apps: \(store.loadFrames().count)")
    } else {
        print("ERROR: could not open layout store")
    }
    print("Screens:")
    for (i, screen) in NSScreen.screens.enumerated() {
        let f = screen.frame
        let v = screen.visibleFrame
        print("  [\(i)] frame=\(Int(f.width))x\(Int(f.height)) at (\(Int(f.origin.x)),\(Int(f.origin.y)))"
            + " visible=\(Int(v.width))x\(Int(v.height))")
    }
    exit(0)
}

// `--do <command>`: send a command to the running WindowKeeper instance.
// Commands: capture | apply-preset:<name> | save-preset:<name>
if let flagIndex = CommandLine.arguments.firstIndex(of: "--do"),
   CommandLine.arguments.count > flagIndex + 1 {
    let command = CommandLine.arguments[flagIndex + 1]
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(WindowManager.commandNotification),
        object: command, userInfo: nil, deliverImmediately: true)
    print("Sent: \(command)")
    exit(0)
}

// `--frames <bundle-id>`: print live window frames of a running app (AX coords).
if let flagIndex = CommandLine.arguments.firstIndex(of: "--frames"),
   CommandLine.arguments.count > flagIndex + 1 {
    let bundleID = CommandLine.arguments[flagIndex + 1]
    guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        print("Not running: \(bundleID)")
        exit(1)
    }
    let windows = AccessibilityService.windows(pid: target.processIdentifier)
    print("\(bundleID): \(windows.count) window(s)")
    for (i, window) in windows.enumerated() {
        if let frame = AccessibilityService.frame(of: window) {
            print("  [\(i)] x=\(frame.x) y=\(frame.y) w=\(frame.width) h=\(frame.height)")
        }
    }
    exit(0)
}

// GUI launch: menu-bar only (no Dock icon).
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
