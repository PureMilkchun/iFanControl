// Only appended to the isolated native launch fixture, never shipped.
@MainActor enum LaunchEffects {
    static var events: [String] = []
    static var captures = Set<String>()
    static let preview = CommandLine.arguments.contains("--preview")
    static var loadingVisible: Bool {
        NSApp.windows.contains { $0.isVisible && $0.windowController is StartupProgressWindowController }
    }
    static func record(_ event: String) {
        events.append(event)
        print("LAUNCH: \(event)")
    }
    static func stats() {}
    static func capture(_ window: NSWindow?) {
        guard let window, window.isVisible, let view = window.contentView else { return }
        func fields(_ v: NSView) -> [NSTextField] { [v as? NSTextField].compactMap { $0 } + v.subviews.flatMap { fields($0) } }
        let stage = fields(view).first { $0.identifier?.rawValue == "startup-stage" }!.stringValue
        let name = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark-" : "light-") + stage
        guard captures.insert(name).inserted, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "FIXTURE_OUTPUT/" + name + ".png"))
    }
    static func assertReady() {
        guard !preview else { return }
        let ordered = ["present", "probe", "stage:preferences", "stage:controls", "unlock", "control_loop", "dismiss", "receipt", "guidance"]
        let indices = ordered.map { events.firstIndex(of: $0)! }
        precondition(zip(indices, indices.dropFirst()).allSatisfy { $0 < $1 }, "Launch order changed")
        precondition(!loadingVisible)
        AppDelegate.shared!.assertLaunchTimers()
        MenuBarManager.shared.assertLaunchMenu()
        let remaining = UserDefaults.standard.integer(forKey: "ifancontrol.update.pending_build")
        precondition(remaining == (CommandLine.arguments.contains("--future-receipt") ? 71 : 0))
        let alertExpected = CommandLine.arguments.contains("--fanless") || CommandLine.arguments.contains("--first-launch")
        precondition((LaunchFixtureAlert.count > 0) == alertExpected)
        let suffix = CommandLine.arguments.dropFirst().joined(separator: "_")
        let report: [String: Any] = ["events": events, "loading_hidden_after_real_initialization": true, "native_threaded_indeterminate_indicator": true, "pending_build_remaining": remaining, "startup_alerts_after_loading": LaunchFixtureAlert.count, "real_hardware_or_network_used": false]
        try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "FIXTURE_OUTPUT/launch-" + suffix + ".json"))
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        print("PASS: actual delegate launch / panel visibility / timers and menu / late receipt and guidance / \(suffix)")
        exit(0)
    }
}

@MainActor final class LaunchFixtureAlert: NSAlert {
    static var count = 0
    override func runModal() -> NSApplication.ModalResponse {
        precondition(!LaunchEffects.loadingVisible, "Startup guidance must not overlap launch UI")
        Self.count += 1
        return .alertFirstButtonReturn
    }
}

@MainActor extension AppDelegate {
    func assertLaunchTimers() { precondition(controlLoopTimer != nil && statsHeartbeatTimer != nil) }
}
@MainActor extension MenuBarManager {
    func assertLaunchMenu() {
        precondition(statusItem?.button != nil && menuPollTimer != nil && menu != nil)
        let configured = ConfigManager.shared.loadConfig().curve
        precondition(currentFanCurve.count == configured.count)
        precondition(zip(currentFanCurve, configured).allSatisfy { $0.temperature == $1.temperature && $0.rpm == $1.rpm })
    }
}

@MainActor final class LaunchPreview: NSObject {
    let controller = StartupProgressWindowController()
    @objc func hardware() { controller.present() }
    @objc func preferences() { controller.setStage(.preferences) }
    @objc func controls() { controller.setStage(.controls) }
    @objc func finish() { controller.dismiss(); InteractionNotice.shared.show(appL10n("已更新至 2.9.10 Beta (70)", "Updated to 2.9.10 Beta (70)")) }
}

let application = NSApplication.shared
precondition(Bundle.main.bundleIdentifier!.hasPrefix("com.ifancontrol.startup-test."))
UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
if !CommandLine.arguments.contains("--first-launch") {
    UserDefaults.standard.set(CommandLine.arguments.contains("--en") ? "en" : "zh", forKey: "ifancontrol.ui.language")
}
UserDefaults.standard.set(true, forKey: "ifancontrol.ui.temperature_source_hint_shown")
UserDefaults.standard.set(CommandLine.arguments.contains("--future-receipt") ? 71 : 70, forKey: "ifancontrol.update.pending_build")
application.applicationIconImage = NSImage(contentsOfFile: Bundle.main.resourcePath! + "/icon.png")
application.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
var fixtureConfig = ConfigManager.shared.loadConfig()
fixtureConfig.autoStart = false
ConfigManager.shared.saveConfig(fixtureConfig)
let delegate = AppDelegate()
let preview = LaunchPreview()
if LaunchEffects.preview {
    application.setActivationPolicy(.regular)
    let root = NSMenu(); let item = NSMenuItem(); root.addItem(item); let commands = NSMenu(); item.submenu = commands
    for (i, pair) in [("识别硬件", #selector(LaunchPreview.hardware)), ("恢复设置", #selector(LaunchPreview.preferences)), ("准备控制", #selector(LaunchPreview.controls)), ("完成启动", #selector(LaunchPreview.finish))].enumerated() {
        let command = NSMenuItem(title: pair.0, action: pair.1, keyEquivalent: String(i + 1)); command.keyEquivalentModifierMask = [.command]; command.target = preview; commands.addItem(command)
    }
    application.mainMenu = root
    preview.hardware()
    application.activate(ignoringOtherApps: true)
} else {
    application.delegate = delegate
}
application.run()
