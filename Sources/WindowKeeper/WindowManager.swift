import AppKit
import WindowKeeperCore

/// Orchestrates everything: watches app launches, applies rules, and saves
/// user-arranged frames for "remember" apps.
final class WindowManager {
    static let commandNotification = "com.saqibkamran.windowkeeper.command"

    let store: LayoutStore
    private(set) var config: Config
    private(set) var rememberedFrames: [String: [SavedFrame]]
    private(set) var presets: [LayoutPreset]

    private var observers: [pid_t: AXObserver] = [:]
    /// Bundle IDs whose move/resize events we caused ourselves; maps to the
    /// time until which events are ignored.
    private var suppressedUntil: [String: Date] = [:]
    private var saveDebounce: [String: DispatchWorkItem] = [:]
    private var screenChangeDebounce: DispatchWorkItem?

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCommand(_:)),
            name: Notification.Name(Self.commandNotification), object: nil)
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

    /// Display arrangement changed (monitor plugged/unplugged, resolution
    /// switch). macOS scrambles windows in this moment; once things settle,
    /// put every managed app back where it belongs on the new arrangement.
    @objc private func screenParametersChanged() {
        guard config.enabled else { return }
        screenChangeDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Log.shared.info("Display arrangement changed — re-applying layouts")
            for app in NSWorkspace.shared.runningApplications
            where self.managedRule(for: app) != nil {
                self.applyRule(to: app, attempt: 0)
            }
        }
        screenChangeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    /// Scriptable command channel (also used by `WindowKeeper --do "…"`).
    /// Commands: capture | apply-preset:<name> | save-preset:<name>
    @objc private func handleCommand(_ note: Notification) {
        guard let command = note.object as? String else { return }
        Log.shared.info("Command received: \(command)")
        if command == "capture" {
            captureAllFrames()
        } else if command.hasPrefix("apply-preset:") {
            let name = String(command.dropFirst("apply-preset:".count))
            if let preset = presets.first(where: { $0.name == name }) {
                applyPreset(id: preset.id)
            } else {
                Log.shared.error("No preset named '\(name)'")
            }
        } else if command.hasPrefix("save-preset:") {
            let name = String(command.dropFirst("save-preset:".count))
            savePreset(named: name)
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
        let displays = DisplayInfo.current()
        let remembered = rememberedFrames[rule.bundleID]?
            .compactMap { LayoutEngine.resolve(saved: $0, displays: displays) }
        let targets = LayoutEngine.targetFrames(
            rule: rule,
            windowCount: windows.count,
            remembered: remembered,
            zoneResolver: { [weak self] id in self?.resolveZone(id: id) }
        )
        place(windows: windows, targets: targets, bundleID: rule.bundleID)
    }

    /// Set frames on windows with verification, suppression, and honest logging.
    private func place(windows: [AXUIElement], targets: [WindowFrame?], bundleID: String) {
        suppress(bundleID: bundleID)
        var placed = 0, adjusted = 0, failed = 0, skipped = 0
        for (window, target) in zip(windows, targets) {
            guard let target else { skipped += 1; continue }
            if let current = AccessibilityService.frame(of: window),
               LayoutEngine.framesMatch(current, target) { skipped += 1; continue }
            switch AccessibilityService.setFrame(target, on: window) {
            case .placed: placed += 1
            case .adjusted(let final):
                adjusted += 1
                Log.shared.error("macOS adjusted a \(bundleID) window: wanted "
                    + "(\(target.x),\(target.y) \(target.width)x\(target.height)) got "
                    + "(\(final.x),\(final.y) \(final.width)x\(final.height))")
            case .failed: failed += 1
            }
        }
        if placed + adjusted + failed > 0 {
            Log.shared.info("\(bundleID): placed \(placed), adjusted \(adjusted), "
                + "failed \(failed), already-in-place/skipped \(skipped)")
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
        let displays = DisplayInfo.current()
        let frames = AccessibilityService.windows(pid: app.processIdentifier)
            .compactMap { AccessibilityService.frame(of: $0) }
            .map { LayoutEngine.makeSaved(from: $0, displays: displays) }
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
    /// Returns the snapshot so callers can report what was captured.
    @discardableResult
    func captureAllFrames() -> [String: [SavedFrame]] {
        let displays = DisplayInfo.current()
        var snapshot: [String: [SavedFrame]] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let rule = managedRule(for: app) else { continue }
            let frames = AccessibilityService.windows(pid: app.processIdentifier)
                .compactMap { AccessibilityService.frame(of: $0) }
                .map { LayoutEngine.makeSaved(from: $0, displays: displays) }
            guard !frames.isEmpty else { continue }
            snapshot[rule.bundleID] = frames
        }
        for (bundleID, frames) in snapshot {
            rememberedFrames[bundleID] = frames
        }
        try? store.save(frames: rememberedFrames)
        Log.shared.info("Captured layout of \(snapshot.count) app(s): "
            + snapshot.keys.sorted().joined(separator: ", "))
        return snapshot
    }

    /// Managed apps that are NOT running right now (so capture can't see them).
    func managedAppsNotRunning() -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return config.rules.filter { $0.enabled && !running.contains($0.bundleID) }
            .map(\.displayName)
    }

    // MARK: - Presets

    /// Save the current layout as a preset. Returns the captured app names so
    /// the UI can tell the user exactly what's inside the preset.
    @discardableResult
    func savePreset(named name: String) -> [String] {
        let frames = captureAllFrames()
        let preset = LayoutPreset(name: name, frames: frames)
        presets.append(preset)
        try? store.save(presets: presets)
        Log.shared.info("Preset saved: \(name) (\(frames.count) app(s))")
        return displayNames(for: Array(frames.keys))
    }

    @discardableResult
    func updatePreset(id: String) -> [String] {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return [] }
        let frames = captureAllFrames()
        presets[i].frames = frames
        try? store.save(presets: presets)
        Log.shared.info("Preset updated: \(presets[i].name) (\(frames.count) app(s))")
        return displayNames(for: Array(frames.keys))
    }

    func deletePreset(id: String) {
        presets.removeAll { $0.id == id }
        try? store.save(presets: presets)
    }

    /// Apply a preset's frames directly to every running app captured in it —
    /// deliberately bypassing zone rules: an explicit "Apply" wins over
    /// standing placement modes. Frames also become the remembered frames so
    /// apps launched later follow the preset too.
    func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        for (bundleID, frames) in preset.frames {
            rememberedFrames[bundleID] = frames
        }
        try? store.save(frames: rememberedFrames)

        let displays = DisplayInfo.current()
        var appliedApps = 0
        var notRunning: [String] = []
        for (bundleID, savedFrames) in preset.frames {
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == bundleID }
            guard let app = running.first else {
                notRunning.append(bundleID)
                continue
            }
            let windows = AccessibilityService.windows(pid: app.processIdentifier)
            guard !windows.isEmpty else { notRunning.append(bundleID); continue }
            let resolved = savedFrames.compactMap {
                LayoutEngine.resolve(saved: $0, displays: displays)
            }
            guard !resolved.isEmpty else { continue }
            let targets: [WindowFrame?] = (0..<windows.count).map { i in
                i < resolved.count ? resolved[i] : resolved.last
            }
            place(windows: windows, targets: targets, bundleID: bundleID)
            appliedApps += 1
        }
        var summary = "Preset applied: \(preset.name) — \(appliedApps) app(s)"
        if !notRunning.isEmpty {
            summary += "; not running: \(notRunning.joined(separator: ", "))"
        }
        Log.shared.info(summary)
    }

    private func displayNames(for bundleIDs: [String]) -> [String] {
        bundleIDs.sorted().map { id in
            config.rules.first { $0.bundleID == id }?.displayName ?? id
        }
    }
}
