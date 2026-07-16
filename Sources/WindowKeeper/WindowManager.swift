import AppKit
import WindowKeeperCore

/// Orchestrates captures and restores. Deliberately passive: windows are
/// touched ONLY on an explicit user action (save/update/apply a preset,
/// capture, or changing an app's placement mode). The single exception is
/// finishing an explicit restore — apps the preset just launched get their
/// windows placed once they appear.
final class WindowManager {
    static let commandNotification = "com.saqibkamran.windowkeeper.command"

    let store: LayoutStore
    private(set) var config: Config
    private(set) var rememberedFrames: [String: [SavedFrame]]
    private(set) var presets: [LayoutPreset]

    /// Apps launched by an in-flight preset apply, still waiting for their
    /// first window. Entries expire so a later manual launch of the same app
    /// never triggers placement on its own.
    private var pendingPlacements: [String: Date] = [:]
    private static let pendingPlacementWindow: TimeInterval = 60

    /// State of the reconciliation loop that finishes an explicit preset
    /// apply. Launch notifications are a fast path only — this loop is the
    /// guarantee that every saved frame ends up with a window on it, even
    /// when a notification never arrives, an app is slow to create windows,
    /// or the display arrangement is still settling right after boot.
    private struct ActiveRestore {
        let presetID: String
        let deadline: Date
        /// Apps verified fully in place. Once done, an app is never touched
        /// again during this restore (so the user can drag windows without
        /// fighting the loop) — unless the display arrangement changes.
        var doneApps: Set<String> = []
        /// Window count seen for each app on the previous pass. New windows
        /// are only requested when the count is stable across two passes, so
        /// an app still restoring its own windows isn't handed duplicates.
        var lastWindowCounts: [String: Int] = [:]
        /// New-window requests issued per app, capped at the saved count.
        var newWindowRequests: [String: Int] = [:]
        /// Apps whose menus offer no "New Window" item — logged once.
        var newWindowUnsupported: Set<String> = []
        /// Placements macOS overrode (e.g. Terminal snapping heights to text
        /// rows). A window sitting on the adjusted frame counts as in place —
        /// re-fighting the WindowServer every pass would never converge.
        var acceptedAdjustments: [String: [(target: WindowFrame, final: WindowFrame)]] = [:]
        /// Apps re-launched by the loop after the initial launch went nowhere.
        var relaunched: Set<String> = []
    }
    private var activeRestore: ActiveRestore?
    private static let restoreDeadline: TimeInterval = 120
    private static let reconcileInterval: TimeInterval = 3

    init(store: LayoutStore) {
        self.store = store
        self.config = store.loadConfig()
        self.rememberedFrames = store.loadFrames()
        self.presets = store.loadPresets()
    }

    // MARK: - Lifecycle

    func start() {
        // Only two triggers exist: explicit commands, and launch events used
        // solely to finish an explicit preset apply (see pendingPlacements).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCommand(_:)),
            name: Notification.Name(Self.commandNotification), object: nil)
        // Only acted on while a restore is reconciling: displays waking up
        // after boot shift every resolved target, so verified apps must be
        // re-verified against the new geometry.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Log.shared.info("WindowManager started — \(config.rules.count) rule(s), "
            + "\(presets.count) preset(s), passive mode")
    }

    /// An app we launched as part of a preset apply is up — place its windows.
    /// Launches the user performs themselves are ignored.
    @objc private func appDidLaunch(_ note: Notification) {
        guard config.enabled,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              let requested = pendingPlacements.removeValue(forKey: bundleID),
              Date().timeIntervalSince(requested) < Self.pendingPlacementWindow
        else { return }
        Log.shared.info("Preset-launched app is up: \(bundleID)")
        applyRule(to: app, attempt: 0)
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

    // MARK: - Placement

    /// Apply a rule to an app's windows, retrying while the app is still
    /// creating them (up to ~15 s — preset-launched apps can be slow to show
    /// their first window).
    func applyRule(to app: NSRunningApplication, attempt: Int) {
        guard let rule = managedRule(for: app) else { return }
        let windows = AccessibilityService.windows(pid: app.processIdentifier)
        if windows.isEmpty {
            guard attempt < 50 else {
                Log.shared.info("No windows appeared for \(rule.bundleID); giving up")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.applyRule(to: app, attempt: attempt + 1)
            }
            return
        }
        let targets: [WindowFrame?]
        switch rule.mode {
        case .remember:
            targets = assignedTargets(for: windows,
                                      savedFrames: rememberedFrames[rule.bundleID] ?? [],
                                      displays: DisplayInfo.current())
        case .zone(let id):
            targets = Array(repeating: resolveZone(id: id), count: windows.count)
        }
        place(windows: windows, targets: targets, bundleID: rule.bundleID)
    }

    /// Snapshot an app's windows as SavedFrames, including titles so restores
    /// can tell look-alike windows (browser profiles) apart.
    private func savedFrames(of pid: pid_t, displays: [DisplayInfo]) -> [SavedFrame] {
        AccessibilityService.windows(pid: pid).compactMap { window in
            guard let frame = AccessibilityService.frame(of: window) else { return nil }
            return LayoutEngine.makeSaved(from: frame, displays: displays,
                                          title: AccessibilityService.title(of: window))
        }
    }

    /// Saved frames resolved against the current displays, titles kept for
    /// identity matching.
    private func resolvedSaved(_ savedFrames: [SavedFrame], displays: [DisplayInfo])
        -> [(frame: WindowFrame, title: String?)] {
        savedFrames.compactMap { saved in
            guard let frame = LayoutEngine.resolve(saved: saved, displays: displays)
            else { return nil }
            return (frame, saved.title)
        }
    }

    /// Resolve saved frames against the current displays and match them to
    /// live windows by identity (title key) and proximity.
    private func assignedTargets(for windows: [AXUIElement],
                                 savedFrames: [SavedFrame],
                                 displays: [DisplayInfo]) -> [WindowFrame?] {
        let resolved = resolvedSaved(savedFrames, displays: displays)
        return LayoutEngine.assignTargets(
            current: windows.map { AccessibilityService.frame(of: $0) },
            saved: resolved.map(\.frame),
            currentTitles: windows.map { AccessibilityService.title(of: $0) },
            savedTitles: resolved.map(\.title))
    }

    /// Set frames on windows with verification and honest logging. Returns
    /// the placements macOS overrode so callers (the reconciliation loop) can
    /// accept them instead of re-fighting the WindowServer forever.
    @discardableResult
    private func place(windows: [AXUIElement], targets: [WindowFrame?],
                       bundleID: String) -> [(target: WindowFrame, final: WindowFrame)] {
        var placed = 0, adjusted = 0, failed = 0, skipped = 0
        var adjustments: [(target: WindowFrame, final: WindowFrame)] = []
        for (window, target) in zip(windows, targets) {
            guard let target else { skipped += 1; continue }
            if let current = AccessibilityService.frame(of: window),
               LayoutEngine.framesMatch(current, target) { skipped += 1; continue }
            switch AccessibilityService.setFrame(target, on: window) {
            case .placed: placed += 1
            case .adjusted(let final):
                adjusted += 1
                adjustments.append((target, final))
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
        return adjustments
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

    // MARK: - Frame capture

    private func captureFrames(of app: NSRunningApplication, bundleID: String) {
        let displays = DisplayInfo.current()
        let frames = savedFrames(of: app.processIdentifier, displays: displays)
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
            captureFrames(of: app, bundleID: bundleID)
        } else {
            config.removeRule(bundleID: bundleID)
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

    /// Snapshot current frames of EVERY regular app with open windows (on any
    /// display) into memory + disk — not just managed apps. Apps captured this
    /// way are auto-added to the managed list (Remember mode) so WindowKeeper
    /// keeps watching them. Returns the snapshot so callers can report what
    /// was captured.
    @discardableResult
    func captureAllFrames() -> [String: [SavedFrame]] {
        let displays = DisplayInfo.current()
        var snapshot: [String: [SavedFrame]] = [:]
        var autoManaged: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { continue }
            let frames = savedFrames(of: app.processIdentifier, displays: displays)
            guard !frames.isEmpty else { continue }
            snapshot[bundleID] = frames
            if !config.rules.contains(where: { $0.bundleID == bundleID }) {
                config.upsert(rule: AppRule(bundleID: bundleID,
                                            displayName: app.localizedName ?? bundleID))
                autoManaged.append(bundleID)
            }
        }
        if !autoManaged.isEmpty {
            try? store.save(config: config)
            Log.shared.info("Auto-managed \(autoManaged.count) app(s): "
                + autoManaged.sorted().joined(separator: ", "))
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

    /// The preset behind the one-click magic button: the explicitly chosen
    /// one, else the most recently saved.
    var magicPreset: LayoutPreset? {
        if let id = config.magicPresetID,
           let preset = presets.first(where: { $0.id == id }) { return preset }
        return presets.last
    }

    func setMagicPreset(id: String) {
        config.magicPresetID = id
        try? store.save(config: config)
        Log.shared.info("Magic button now applies preset id \(id)")
    }

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

    /// Re-snapshot a preset. Apps whose windows the capture can't see right
    /// now (another Space, minimized, hidden) but that are still running keep
    /// their existing entry — otherwise updating a preset while one window
    /// sits on a different Space silently drops that app, and a later apply
    /// "ignores" it.
    @discardableResult
    func updatePreset(id: String) -> [String] {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return [] }
        let captured = captureAllFrames()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let result = LayoutEngine.mergePresetFrames(existing: presets[i].frames,
                                                    captured: captured,
                                                    running: running)
        presets[i].frames = result.frames
        try? store.save(presets: presets)
        var message = "Preset updated: \(presets[i].name) (\(result.frames.count) app(s))"
        if !result.kept.isEmpty {
            message += "; kept \(result.kept.count) app(s) with no visible windows: "
                + result.kept.joined(separator: ", ")
        }
        Log.shared.info(message)
        return displayNames(for: Array(result.frames.keys))
    }

    func deletePreset(id: String) {
        presets.removeAll { $0.id == id }
        try? store.save(presets: presets)
    }

    /// Apply a preset: place windows of running apps immediately, and LAUNCH
    /// apps in the preset that aren't running — their windows are placed once
    /// they appear (appDidLaunch → applyRule, gated by pendingPlacements) from
    /// the remembered frames written below. Deliberately bypasses zone rules:
    /// an explicit "Apply" wins over standing placement modes. Running apps
    /// NOT in the preset are left untouched.
    func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        for (bundleID, frames) in preset.frames {
            rememberedFrames[bundleID] = frames
        }
        try? store.save(frames: rememberedFrames)
        ensureRules(for: Array(preset.frames.keys))

        let displays = DisplayInfo.current()
        var appliedApps = 0
        var toLaunch: [String] = []
        var toReopen: [NSRunningApplication] = []
        for (bundleID, savedFrames) in preset.frames {
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == bundleID }
            guard let app = running.first else {
                toLaunch.append(bundleID)
                continue
            }
            let windows = AccessibilityService.windows(pid: app.processIdentifier)
            guard !windows.isEmpty else {
                // Running but windowless (window on another Space just closed,
                // or app parked in the background): re-open and poll until a
                // window shows up — no launch notification will fire for it.
                toLaunch.append(bundleID)
                toReopen.append(app)
                continue
            }
            let targets = assignedTargets(for: windows, savedFrames: savedFrames,
                                          displays: displays)
            guard targets.contains(where: { $0 != nil }) else { continue }
            place(windows: windows, targets: targets, bundleID: bundleID)
            appliedApps += 1
        }

        var launched: [String] = []
        var missing: [String] = []
        for bundleID in toLaunch {
            if launchApp(bundleID: bundleID) {
                launched.append(bundleID)
                pendingPlacements[bundleID] = Date()
            } else {
                missing.append(bundleID)
            }
        }
        for app in toReopen {
            applyRule(to: app, attempt: 0)
        }

        var summary = "Preset applied: \(preset.name) — \(appliedApps) app(s) placed"
        if !launched.isEmpty {
            summary += "; launching: \(launched.joined(separator: ", "))"
        }
        if !missing.isEmpty {
            summary += "; not installed: \(missing.joined(separator: ", "))"
        }
        Log.shared.info(summary)

        // The apply above is a fast first pass; reconciliation owns the
        // guarantee that every saved window ends up open and in place.
        activeRestore = ActiveRestore(
            presetID: id, deadline: Date().addingTimeInterval(Self.restoreDeadline))
        scheduleReconcile(after: Self.reconcileInterval)
    }

    // MARK: - Restore reconciliation

    @objc private func screensChanged() {
        guard activeRestore != nil else { return }
        Log.shared.info("Display arrangement changed mid-restore — re-verifying all apps")
        activeRestore?.doneApps.removeAll()
    }

    private func scheduleReconcile(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reconcile()
        }
    }

    /// One reconciliation pass: verify every app in the restoring preset and
    /// nudge whatever is short — relaunch missing apps, ask for missing
    /// windows, re-place drifted ones. Ends when a pass finds everything in
    /// place, or at the deadline with an honest report of what's still short.
    private func reconcile() {
        guard let restore = activeRestore,
              let preset = presets.first(where: { $0.id == restore.presetID })
        else { return }
        let displays = DisplayInfo.current()
        var shortfalls: [String] = []

        for (bundleID, savedFrames) in preset.frames
        where !restore.doneApps.contains(bundleID) {
            let status = reconcileApp(bundleID: bundleID, savedFrames: savedFrames,
                                      displays: displays)
            if status.satisfied {
                activeRestore?.doneApps.insert(bundleID)
            } else {
                shortfalls.append("\(bundleID) (\(status.detail))")
            }
        }

        if shortfalls.isEmpty {
            Log.shared.info("Restore reconciled: \(preset.name) — every saved "
                + "window is open and in place")
            activeRestore = nil
        } else if Date() > restore.deadline {
            Log.shared.error("Restore deadline reached for \(preset.name); still short: "
                + shortfalls.joined(separator: ", "))
            activeRestore = nil
        } else {
            scheduleReconcile(after: Self.reconcileInterval)
        }
    }

    /// Reconcile a single app against its saved frames. Returns whether it is
    /// fully satisfied and, if not, a human-readable reason for the log.
    private func reconcileApp(bundleID: String, savedFrames: [SavedFrame],
                              displays: [DisplayInfo])
        -> (satisfied: Bool, detail: String) {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID }) else {
            // Initial launch went nowhere (or the app quit) — try once more.
            if activeRestore?.relaunched.contains(bundleID) == false,
               launchApp(bundleID: bundleID) {
                activeRestore?.relaunched.insert(bundleID)
                Log.shared.info("Restore: relaunching \(bundleID)")
            }
            return (false, "not running")
        }

        let windows = AccessibilityService.windows(pid: app.processIdentifier)
        let currentFrames = windows.map { AccessibilityService.frame(of: $0) }
        let resolved = resolvedSaved(savedFrames, displays: displays)
        let progress = LayoutEngine.restoreProgress(
            current: currentFrames,
            saved: resolved.map(\.frame),
            currentTitles: windows.map { AccessibilityService.title(of: $0) },
            savedTitles: resolved.map(\.title))

        // A window macOS already forced off its exact target (row-snapped
        // Terminal heights and the like) counts as in place; re-placing it
        // every pass would never converge.
        let accepted = activeRestore?.acceptedAdjustments[bundleID] ?? []
        let outOfPlace = progress.outOfPlace.filter { move in
            guard let frame = currentFrames[move.windowIndex] else { return true }
            return !accepted.contains {
                LayoutEngine.framesMatch($0.target, move.target)
                    && LayoutEngine.framesMatch($0.final, frame)
            }
        }
        if progress.missingWindows == 0 && outOfPlace.isEmpty { return (true, "") }

        if !outOfPlace.isEmpty {
            var targets = [WindowFrame?](repeating: nil, count: windows.count)
            for move in outOfPlace { targets[move.windowIndex] = move.target }
            let adjustments = place(windows: windows, targets: targets, bundleID: bundleID)
            activeRestore?.acceptedAdjustments[bundleID, default: []]
                .append(contentsOf: adjustments)
        }
        if progress.missingWindows > 0 {
            requestMissingWindows(count: progress.missingWindows, cap: savedFrames.count,
                                  bundleID: bundleID, app: app,
                                  currentWindowCount: windows.count)
        }
        activeRestore?.lastWindowCounts[bundleID] = windows.count
        var detail: [String] = []
        if progress.missingWindows > 0 { detail.append("\(progress.missingWindows) window(s) missing") }
        if !outOfPlace.isEmpty { detail.append("\(outOfPlace.count) out of place") }
        return (false, detail.joined(separator: ", "))
    }

    /// Ask an app for one more window, carefully: only when its window count
    /// has been stable across two passes (an app mid-launch restoring its own
    /// windows must not be handed duplicates), one request per pass, total
    /// requests capped at the saved count.
    private func requestMissingWindows(count: Int, cap: Int, bundleID: String,
                                       app: NSRunningApplication,
                                       currentWindowCount: Int) {
        guard let restore = activeRestore,
              !restore.newWindowUnsupported.contains(bundleID),
              restore.lastWindowCounts[bundleID] == currentWindowCount,
              restore.newWindowRequests[bundleID, default: 0] < cap
        else { return }
        if AccessibilityService.openNewWindow(pid: app.processIdentifier) {
            activeRestore?.newWindowRequests[bundleID, default: 0] += 1
            Log.shared.info("Restore: asked \(bundleID) for a new window "
                + "(\(count) still missing)")
        } else {
            activeRestore?.newWindowUnsupported.insert(bundleID)
            Log.shared.error("Restore: \(bundleID) offers no New Window menu item; "
                + "cannot recreate its missing window(s)")
        }
    }

    /// Make sure every bundle ID has a managed rule so the launch pipeline
    /// places its windows (presets may predate auto-managing, or rules may
    /// have been removed since the preset was saved).
    private func ensureRules(for bundleIDs: [String]) {
        var added = false
        for bundleID in bundleIDs
        where !config.rules.contains(where: { $0.bundleID == bundleID }) {
            let app = NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == bundleID }
            let name = app?.localizedName
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
                    .deletingPathExtension().lastPathComponent
                ?? bundleID
            config.upsert(rule: AppRule(bundleID: bundleID, displayName: name))
            added = true
        }
        if added { try? store.save(config: config) }
    }

    /// Launch (or re-open, if running without windows) an app by bundle ID.
    /// Returns false when the app can't be found on disk. Placement happens
    /// asynchronously once the app's windows appear.
    private func launchApp(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID) else {
            Log.shared.error("Cannot launch \(bundleID): app not installed")
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Log.shared.error("Launch failed for \(bundleID): \(error.localizedDescription)")
            }
        }
        return true
    }

    private func displayNames(for bundleIDs: [String]) -> [String] {
        bundleIDs.sorted().map { id in
            config.rules.first { $0.bundleID == id }?.displayName ?? id
        }
    }
}
