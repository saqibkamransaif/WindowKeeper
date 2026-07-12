import AppKit
import WindowKeeperCore

/// Orchestrates everything: watches app launches, applies rules, and saves
/// user-arranged frames for "remember" apps.
final class WindowManager {
    let store: LayoutStore
    private(set) var config: Config
    private(set) var rememberedFrames: [String: [WindowFrame]]
    private(set) var presets: [LayoutPreset]

    private var observers: [pid_t: AXObserver] = [:]
    /// Bundle IDs whose move/resize events we caused ourselves; maps to the
    /// time until which events are ignored.
    private var suppressedUntil: [String: Date] = [:]
    private var saveDebounce: [String: DispatchWorkItem] = [:]

    init(store: LayoutStore) {
        self.store = store
        self.config = store.loadConfig()
        self.rememberedFrames = store.loadFrames()
        self.presets = store.loadPresets()
    }

    // MARK: - Lifecycle

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appDidLaunch(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidTerminate(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for app in NSWorkspace.shared.runningApplications where managedRule(for: app) != nil {
            attach(to: app, applyPlacement: false)
        }
        Log.shared.info("WindowManager started — \(config.rules.count) rule(s), \(presets.count) preset(s)")
    }

    @objc private func appDidLaunch(_ note: Notification) {
        guard config.enabled,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              managedRule(for: app) != nil else { return }
        Log.shared.info("Launch detected: \(app.bundleIdentifier ?? "?")")
        attach(to: app, applyPlacement: true)
    }

    @objc private func appDidTerminate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if let observer = observers.removeValue(forKey: app.processIdentifier) {
            AccessibilityService.removeObserver(observer)
        }
    }

    private func managedRule(for app: NSRunningApplication) -> AppRule? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        return config.rule(for: bundleID)
    }

    // MARK: - Attach & observe

    private func attach(to app: NSRunningApplication, applyPlacement apply: Bool) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else {
            if apply { applyRule(to: app, attempt: 0) }
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // C callback: no captures allowed, so the pid is read back from the
        // element and the manager comes through refcon.
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            var eventPid: pid_t = 0
            guard AXUIElementGetPid(element, &eventPid) == .success else { return }
            let manager = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handleAXEvent(notification as String, pid: eventPid)
        }
        if let observer = AccessibilityService.makeObserver(pid: pid, callback: callback,
                                                            refcon: refcon) {
            observers[pid] = observer
        }
        if apply { applyRule(to: app, attempt: 0) }
    }

    private func handleAXEvent(_ notification: String, pid: pid_t) {
        guard config.enabled,
              let app = NSRunningApplication(processIdentifier: pid),
              let rule = managedRule(for: app) else { return }
        switch notification {
        case kAXWindowCreatedNotification:
            // New window: place it after a beat so the app finishes setup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.applyRule(to: app, attempt: 0)
            }
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard case .remember = rule.mode else { return }
            if let until = suppressedUntil[rule.bundleID], until > Date() { return }
            scheduleFrameCapture(for: app, rule: rule)
        default:
            break
        }
    }

    // MARK: - Placement

    /// Apply a rule to an app's windows, retrying while the app is still
    /// creating them (up to ~5 s).
    func applyRule(to app: NSRunningApplication, attempt: Int) {
        guard let rule = managedRule(for: app) else { return }
        let windows = AccessibilityService.windows(pid: app.processIdentifier)
        if windows.isEmpty {
            guard attempt < 16 else {
                Log.shared.info("No windows appeared for \(rule.bundleID); giving up")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.applyRule(to: app, attempt: attempt + 1)
            }
            return
        }
        let targets = LayoutEngine.targetFrames(
            rule: rule,
            windowCount: windows.count,
            remembered: rememberedFrames[rule.bundleID],
            zoneResolver: { [weak self] id in self?.resolveZone(id: id) }
        )
        suppress(bundleID: rule.bundleID)
        var applied = 0
        for (window, target) in zip(windows, targets) {
            guard let target else { continue }
            if let current = AccessibilityService.frame(of: window),
               LayoutEngine.framesMatch(current, target) { continue }
            if AccessibilityService.setFrame(target, on: window) { applied += 1 }
        }
        if applied > 0 {
            Log.shared.info("Placed \(applied) window(s) of \(rule.bundleID)")
        }
    }

    func resolveZone(id: String) -> WindowFrame? {
        guard let zone = config.zone(id: id) else { return nil }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let screen = screens[min(zone.displayIndex, screens.count - 1)]
        let primaryHeight = screens[0].frame.height
        return LayoutEngine.resolve(zone: zone,
                                    visibleFrame: screen.visibleFrame,
                                    primaryHeight: primaryHeight)
    }

    /// Ignore our own move/resize events for a moment so applying frames
    /// doesn't immediately re-save them.
    private func suppress(bundleID: String, seconds: TimeInterval = 1.5) {
        suppressedUntil[bundleID] = Date().addingTimeInterval(seconds)
    }

    // MARK: - Frame capture (remember mode)

    private func scheduleFrameCapture(for app: NSRunningApplication, rule: AppRule) {
        saveDebounce[rule.bundleID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.captureFrames(of: app, bundleID: rule.bundleID)
        }
        saveDebounce[rule.bundleID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func captureFrames(of app: NSRunningApplication, bundleID: String) {
        let frames = AccessibilityService.windows(pid: app.processIdentifier)
            .compactMap { AccessibilityService.frame(of: $0) }
        guard !frames.isEmpty else { return }
        rememberedFrames[bundleID] = frames
        try? store.save(frames: rememberedFrames)
        Log.shared.info("Remembered \(frames.count) frame(s) for \(bundleID)")
    }

    // MARK: - Commands (menu actions)

    func setEnabled(_ enabled: Bool) {
        config.enabled = enabled
        try? store.save(config: config)
        Log.shared.info(enabled ? "Enabled" : "Disabled")
    }

    func setManaged(_ managed: Bool, app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        if managed {
            let rule = AppRule(bundleID: bundleID,
                               displayName: app.localizedName ?? bundleID)
            config.upsert(rule: rule)
            attach(to: app, applyPlacement: false)
            captureFrames(of: app, bundleID: bundleID)
        } else {
            config.removeRule(bundleID: bundleID)
            if let observer = observers.removeValue(forKey: app.processIdentifier) {
                AccessibilityService.removeObserver(observer)
            }
        }
        try? store.save(config: config)
        Log.shared.info("\(bundleID) managed=\(managed)")
    }

    func setMode(_ mode: PlacementMode, bundleID: String) {
        guard var rule = config.rule(for: bundleID) else { return }
        rule.mode = mode
        config.upsert(rule: rule)
        try? store.save(config: config)
        if let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID }) {
            applyRule(to: app, attempt: 0)
        }
    }

    /// Snapshot current frames of every managed running app into memory + disk.
    @discardableResult
    func captureAllFrames() -> [String: [WindowFrame]] {
        var snapshot: [String: [WindowFrame]] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let rule = managedRule(for: app) else { continue }
            let frames = AccessibilityService.windows(pid: app.processIdentifier)
                .compactMap { AccessibilityService.frame(of: $0) }
            guard !frames.isEmpty else { continue }
            snapshot[rule.bundleID] = frames
        }
        for (bundleID, frames) in snapshot {
            rememberedFrames[bundleID] = frames
        }
        try? store.save(frames: rememberedFrames)
        Log.shared.info("Captured layout of \(snapshot.count) app(s)")
        return snapshot
    }

    // MARK: - Presets

    func savePreset(named name: String) {
        let preset = LayoutPreset(name: name, frames: captureAllFrames())
        presets.append(preset)
        try? store.save(presets: presets)
        Log.shared.info("Preset saved: \(name)")
    }

    func updatePreset(id: String) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].frames = captureAllFrames()
        try? store.save(presets: presets)
        Log.shared.info("Preset updated: \(presets[i].name)")
    }

    func deletePreset(id: String) {
        presets.removeAll { $0.id == id }
        try? store.save(presets: presets)
    }

    func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        // Preset frames become the remembered frames so future launches follow it.
        for (bundleID, frames) in preset.frames {
            rememberedFrames[bundleID] = frames
        }
        try? store.save(frames: rememberedFrames)
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  preset.frames[bundleID] != nil,
                  managedRule(for: app) != nil else { continue }
            applyRule(to: app, attempt: 0)
        }
        Log.shared.info("Preset applied: \(preset.name)")
    }
}
