import AppKit
import SwiftUI
import WindowKeeperCore

/// Owns the Preferences window: everyday settings that used to hide in
/// submenus or in hand-edited JSON files.
final class PreferencesWindowController {
    private let model: PreferencesModel
    private var window: NSWindow?

    init(manager: WindowManager) {
        model = PreferencesModel(manager: manager)
    }

    func show() {
        model.refresh()
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        model.refresh()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: PreferencesView(model: model)))
        window.title = "WindowKeeper Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// Thin observable wrapper: views read straight from the manager and call
/// `refresh()` after each change so SwiftUI redraws.
final class PreferencesModel: ObservableObject {
    let manager: WindowManager
    @Published private(set) var revision = 0

    init(manager: WindowManager) {
        self.manager = manager
    }

    func refresh() { revision += 1 }

    var defaultID: String? { manager.magicPreset?.id }

    func appNames(in preset: LayoutPreset) -> String {
        preset.frames.keys
            .map { id in manager.config.rules.first { $0.bundleID == id }?.displayName ?? id }
            .map { $0.trimmingCharacters(in: .controlCharacters.union(.init(charactersIn: "\u{200E}"))) }
            .sorted()
            .joined(separator: ", ")
    }

    var unmanagedRunningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                      id != Bundle.main.bundleIdentifier else { return false }
                return !manager.config.rules.contains { $0.bundleID == id }
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func modeTag(_ mode: PlacementMode) -> String {
        if case .zone(let id) = mode { return "zone:\(id)" }
        return "remember"
    }

    static func mode(fromTag tag: String) -> PlacementMode {
        tag.hasPrefix("zone:") ? .zone(String(tag.dropFirst(5))) : .remember
    }
}

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        TabView {
            LayoutsTab(model: model)
                .tabItem { Label("Layouts", systemImage: "rectangle.3.group") }
            AppsTab(model: model)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(16)
        .frame(width: 600, height: 440)
    }
}

// MARK: - Layouts

private struct LayoutsTab: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        let _ = model.revision
        VStack(alignment: .leading, spacing: 12) {
            Text("The default layout is the one the Restore button and ⌥⌘R use.")
                .foregroundStyle(.secondary)
            List(model.manager.presets) { preset in
                PresetRow(model: model, preset: preset)
            }
            HStack {
                Spacer()
                Button("Save Current Layout as New…", action: saveNew)
            }
        }
        .padding(12)
    }

    private func saveNew() {
        guard let raw = Dialogs.askName(title: "Save Current Layout",
                                        message: "Saves where every open window is now, on all displays.",
                                        button: "Save") else { return }
        let name = PresetCatalog.cleanName(raw, fallback: "Untitled Layout")
        let captured = model.manager.savePreset(named: name)
        Dialogs.captureSummary(captured: captured, removed: [], presetName: name)
        model.refresh()
    }
}

private struct PresetRow: View {
    @ObservedObject var model: PreferencesModel
    let preset: LayoutPreset

    private var isDefault: Bool { model.defaultID == preset.id }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(preset.name).font(.headline)
                    if isDefault {
                        Text("Default")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text("\(preset.frames.count) apps: \(model.appNames(in: preset))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Restore") { model.manager.applyPreset(id: preset.id) }
            Button("Remember Current Layout", action: remember)
            Menu {
                Button("Use as Default (Magic Button)") {
                    model.manager.setMagicPreset(id: preset.id)
                    model.refresh()
                }
                .disabled(isDefault)
                Button("Rename…", action: rename)
                Divider()
                Button("Delete…", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private func remember() {
        guard Dialogs.confirm(title: "Remember current layout as “\(preset.name)”?",
                              message: "Every open window's place is saved. Apps with no open "
                                + "windows leave “\(preset.name)”.",
                              button: "Remember") else { return }
        let result = model.manager.updatePreset(id: preset.id)
        Dialogs.captureSummary(captured: result.captured, removed: result.removed,
                               presetName: preset.name)
        model.refresh()
    }

    private func rename() {
        guard let name = Dialogs.askName(title: "Rename “\(preset.name)”", message: "",
                                         button: "Rename", initial: preset.name) else { return }
        model.manager.renamePreset(id: preset.id, to: name)
        model.refresh()
    }

    private func delete() {
        guard Dialogs.confirm(title: "Delete “\(preset.name)”?",
                              message: "This layout is removed. Your windows do not move.",
                              button: "Delete", destructive: true) else { return }
        model.manager.deletePreset(id: preset.id)
        model.refresh()
    }
}

// MARK: - Apps

private struct AppsTab: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        let _ = model.revision
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps WindowKeeper looks after. Remove the ones you no longer use.")
                .foregroundStyle(.secondary)
            List(model.manager.config.rules, id: \.bundleID) { rule in
                AppRuleRow(model: model, rule: rule)
            }
            HStack {
                Spacer()
                Menu("Add Running App") {
                    ForEach(model.unmanagedRunningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            model.manager.setManaged(true, app: app)
                            model.refresh()
                        }
                    }
                }
                .fixedSize()
                .disabled(model.unmanagedRunningApps.isEmpty)
            }
        }
        .padding(12)
    }
}

private struct AppRuleRow: View {
    @ObservedObject var model: PreferencesModel
    let rule: AppRule

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName.trimmingCharacters(in: .init(charactersIn: "\u{200E}")))
                Text(model.isRunning(rule.bundleID) ? "Running" : "Not running")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: modeBinding) {
                Text("Remember last position").tag("remember")
                Divider()
                ForEach(model.manager.config.zones) { zone in
                    Text("Snap to \(zone.name)").tag("zone:\(zone.id)")
                }
            }
            .labelsHidden()
            .frame(width: 210)
            Button(role: .destructive) {
                model.manager.removeRule(bundleID: rule.bundleID)
                model.refresh()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Stop managing \(rule.displayName)")
        }
        .padding(.vertical, 2)
    }

    private var modeBinding: Binding<String> {
        Binding(
            get: { PreferencesModel.modeTag(rule.mode) },
            set: { tag in
                model.manager.setMode(PreferencesModel.mode(fromTag: tag), bundleID: rule.bundleID)
                model.refresh()
            })
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        let _ = model.revision
        Form {
            Section {
                Toggle("WindowKeeper is on", isOn: Binding(
                    get: { model.manager.config.enabled },
                    set: { model.manager.setEnabled($0); model.refresh() }))
                Text("When off, WindowKeeper never moves a window and ⌥⌘R only beeps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                LabeledContent("Restore default layout", value: "⌘R (menu open)")
                LabeledContent("Send focused window back", value: "⌥⌘R (anywhere)")
                LabeledContent("Preferences", value: "⌘, (menu open)")
            }
            Section("Data") {
                LabeledContent("Saved automatically in") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(model.manager.store.directory)
                    }
                }
                Text("You never need to edit these files: every setting is here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
