import CoreGraphics
import QuartzCore

@MainActor private func menuCheck(_ condition: @autoclosure () -> Bool, _ message: String = "Menu interaction assertion", line: Int = #line) {
    guard condition() else {
        // A failed drag assertion must never leave the system mouse held down.
        if let point = CGEvent(source: nil)?.location {
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        print("FAIL line \(line): \(message)")
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        exit(1)
    }
}

@MainActor extension FanManager {
    fileprivate func setMenuTestProfile() {
        fanCount = 1
        fans = [FanInfo(index: 0, actualKey: "F0Ac", minRPM: 0, maxRPM: 4900)]
        currentMaxRPM = 4900
        availableTemperatureSensors = [TemperatureSensorDefinition(key: "Tp01", name: "CPU Performance 1")]
        cachedTemperatures = ["Tp01": 65]
    }
}

extension BackgroundHardwareReader {
    fileprivate func setMenuTestRPM(_ rpm: Int, age: TimeInterval = 0) {
        lock.withLock {
            _temperatures = ["Tp01": 65]
            _fanRPMs = [0: rpm]
            _lastSuccessfulTemperatureRefresh = Date()
            _lastSuccessfulFanRPMRefresh = Date(timeIntervalSinceNow: -age)
        }
    }
}

@MainActor extension MenuBarManager {
    fileprivate func prepareMenuTest() -> (NSMenu, MenuSpeedControl) {
        setIsAutoMode(true)
        createStatusItem()
        return (menu!, menuSpeedControl!)
    }
}

@MainActor final class MenuSpeedTest: NSObject, NSMenuDelegate {
    let menu: NSMenu
    let control: MenuSpeedControl
    let slider: NSSlider
    let modes: NSSegmentedControl
    let adjustment: NSButton
    let savedIndicator: NSView
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["IFAN_MENU_TEST_OUTPUT"]!)
    let prefix = currentLanguage + "-" + ProcessInfo.processInfo.environment["IFAN_MENU_TEST_THEME"]!
    var phase = 0
    var initialWindow = 0
    var closed = false
    var results: [String: Any] = [:]
    var advancing = false
    var nextAdvanceAt: TimeInterval = 0
    var mainQueueTicks = 0
    var firstTarget = 2400
    var savedAt: TimeInterval = 0
    let originalPointer = CGEvent(source: nil)!.location

    override init() {
        FanManager.shared.setMenuTestProfile()
        BackgroundHardwareReader.shared.setMenuTestRPM(1600)
        ConfigManager.shared.saveConfig(Config(version: "1.0", curve: defaultFanCurve(maxRPM: 4900), mode: "auto", autoStart: false, maxRPM: 4900, manualRPM: 2400))
        ControlStatusStore.save(mode: "normal", detail: "Auto / CPU")
        let (menu, control) = MenuBarManager.shared.prepareMenuTest()
        self.menu = menu
        self.control = control
        slider = control.subviews.compactMap { $0 as? NSSlider }.first!
        modes = control.subviews.first { $0.identifier?.rawValue == "menu-control-mode" } as! NSSegmentedControl
        adjustment = control.subviews.first { $0.identifier?.rawValue == "menu-speed-adjustment" } as! NSButton
        savedIndicator = control.subviews.first { $0.identifier?.rawValue == "menu-target-saved" }!
        super.init()
        menu.delegate = self
        menu.appearance = NSAppearance(named: prefix.hasSuffix("dark") ? .darkAqua : .aqua)
    }

    func menuDidClose(_ menu: NSMenu) { closed = true }

    func post(_ type: NSEvent.EventType, view: NSView, fraction: CGFloat) {
        let window = view.window!
        let point = view.convert(NSPoint(x: view.bounds.width * fraction, y: view.bounds.midY), to: nil)
        let screenPoint = window.convertPoint(toScreen: point)
        let location = CGPoint(x: screenPoint.x, y: NSScreen.screens.first!.frame.maxY - screenPoint.y)
        let mouseType: CGEventType = type == .leftMouseDown ? .leftMouseDown : type == .leftMouseUp ? .leftMouseUp : .leftMouseDragged
        // Use actual posted mouse state: local NSEvents alone don't hold the
        // system mouse button, causing NSSlider tracking to end immediately.
        menuCheck(CGPreflightPostEventAccess(), "Mouse-event permission unavailable")
        CGEvent(mouseEventSource: nil, mouseType: mouseType, mouseCursorPosition: location, mouseButton: .left)!.post(tap: .cghidEventTap)
    }

    func capture(_ scene: String) {
        let window = control.window!
        window.contentView?.layoutSubtreeIfNeeded()
        window.display()
        CATransaction.flush()
        let frameDeadline = Date(timeIntervalSinceNow: 0.08)
        while Date() < frameDeadline {
            _ = RunLoop.current.run(mode: .eventTracking, before: frameDeadline)
        }
        let feedback = menu.items.compactMap(\.view).first { view in
            view.subviews.contains { $0.identifier?.rawValue == "feedback-invitation-surface" }
        }!
        feedback.layoutSubtreeIfNeeded()
        let surface = feedback.subviews.first { $0.identifier?.rawValue == "feedback-invitation-surface" }!
        let button = feedback.subviews.first { $0.identifier?.rawValue == "feedback-invitation-button" }!
        let left = surface.frame.minX, right = feedback.bounds.width - surface.frame.maxX
        menuCheck(abs(left - right) < 0.5, "Feedback box must be centered")
        menuCheck(surface.frame == button.frame, "Feedback hit area must match the box")
        let layout: [String: CGFloat] = ["window_width": window.frame.width, "control_width": control.frame.width, "visible_width": control.visibleRect.width, "menu_width": menu.size.width, "feedback_left": left, "feedback_right": right]
        results["layout_\(scene)"] = layout
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent("\(prefix)-\(scene).png").path]
        try! process.run()
        process.waitUntilExit()
        menuCheck(process.terminationStatus == 0)
    }

    @objc func advance() {
        guard !advancing, ProcessInfo.processInfo.systemUptime >= nextAdvanceAt else { return }
        advancing = true
        defer {
            // Capturing a window can overrun the repeating timer's interval.
            // Leave time for a posted mouse event to dispatch before asserting
            // its result, even when the next timer callback is already due.
            nextAdvanceAt = ProcessInfo.processInfo.systemUptime + 0.12
            advancing = false
        }
        menuCheck(!closed && control.window != nil, "Menu dismissed during interaction")
        switch phase {
        case 0:
            initialWindow = control.window!.windowNumber
            menuCheck(!slider.isEnabled && slider.intValue == 1600)
            menuCheck(!adjustment.isEnabled && savedIndicator.isHidden)
            capture("auto-1600")
            BackgroundHardwareReader.shared.setMenuTestRPM(2800)
            MenuBarManager.shared.updateDynamicMenuItems()
            menuCheck(!slider.isEnabled && slider.intValue == 2800)
            capture("auto-2800")
            post(.leftMouseDown, view: slider, fraction: 0.9)
        case 1:
            post(.leftMouseUp, view: slider, fraction: 0.9)
        case 2:
            menuCheck(slider.intValue == 2800 && ConfigManager.shared.loadConfig().mode == "auto")
            menuCheck(ConfigManager.shared.loadConfig().manualRPM == 2400)
            results["auto_follows_actual_rpm_and_ignores_mouse"] = true
            post(.leftMouseDown, view: modes, fraction: 0.76)
        case 3:
            post(.leftMouseUp, view: modes, fraction: 0.76)
        case 4:
            menuCheck(ConfigManager.shared.loadConfig().mode == "manual")
            menuCheck(slider.isEnabled && slider.intValue == 2400)
            menuCheck(adjustment.isEnabled && adjustment.state == .off)
            menuCheck(control.window?.windowNumber == initialWindow)
            capture("manual")
            post(.leftMouseDown, view: slider, fraction: 0.35)
        case 5:
            menuCheck(ConfigManager.shared.loadConfig().manualRPM == 2400, "Committed before release")
            BackgroundHardwareReader.shared.setMenuTestRPM(3500)
            MenuBarManager.shared.updateDynamicMenuItems()
            post(.leftMouseDragged, view: slider, fraction: 0.71)
        case 6:
            menuCheck(ConfigManager.shared.loadConfig().manualRPM == 2400, "Committed while dragging")
            capture("drag-preview")
            post(.leftMouseUp, view: slider, fraction: 0.71)
        case 7:
            let rpm = ConfigManager.shared.loadConfig().manualRPM
            menuCheck(rpm > 2400 && rpm <= 4900, "Release must save the preview target; saved=\(rpm), slider=\(slider.intValue)")
            menuCheck(slider.intValue == rpm)
            menuCheck(!savedIndicator.isHidden, "Saved target needs a green confirmation")
            firstTarget = rpm
            results["manual_commits_on_release_only"] = true
            results["manual_target_rpm"] = rpm
            capture("manual-applied")
            post(.leftMouseDown, view: adjustment, fraction: 0.3)
        case 8:
            post(.leftMouseUp, view: adjustment, fraction: 0.3)
        case 9:
            let config = ConfigManager.shared.loadConfig()
            menuCheck(config.manualRPMControlMode == "stepped" && config.manualRPMStep == 500)
            menuCheck(adjustment.state == .on && savedIndicator.isHidden)
            capture("stepped")
            post(.leftMouseDown, view: slider, fraction: 0.35)
        case 10:
            menuCheck(ConfigManager.shared.loadConfig().manualRPM == firstTarget)
            post(.leftMouseDragged, view: slider, fraction: 0.71)
        case 11:
            menuCheck(ConfigManager.shared.loadConfig().manualRPM == firstTarget)
            menuCheck(slider.intValue == 3500, "Stepped dragging must snap the thumb as well as the label")
            capture("stepped-preview")
            post(.leftMouseUp, view: slider, fraction: 0.71)
        case 12:
            menuCheck(ConfigManager.shared.loadConfig().manualRPM == 3500)
            menuCheck(!savedIndicator.isHidden)
            MenuBarManager.shared.updateDynamicMenuItems()
            menuCheck(!savedIndicator.isHidden, "Telemetry refresh must not erase the confirmation")
            capture("stepped-confirmed")
            results["stepped_target_rpm"] = 3500
            savedAt = ProcessInfo.processInfo.systemUptime
        case 13:
            if ProcessInfo.processInfo.systemUptime - savedAt < 1.6 { return }
            menuCheck(savedIndicator.isHidden, "Confirmation must disappear after its brief display")
            results["saved_check_visible_then_disappears"] = true
            post(.leftMouseDown, view: adjustment, fraction: 0.3)
        case 14:
            post(.leftMouseUp, view: adjustment, fraction: 0.3)
        case 15:
            menuCheck(ConfigManager.shared.loadConfig().manualRPMControlMode == "continuous")
            let file = MenuTestPaths.configDirectory.appendingPathComponent("config.json")
            try! FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
            post(.leftMouseDown, view: slider, fraction: 0.2)
        case 16:
            post(.leftMouseDragged, view: slider, fraction: 0.55)
        case 17:
            post(.leftMouseUp, view: slider, fraction: 0.55)
        case 18:
            menuCheck(ConfigManager.shared.loadConfig().manualRPM == 3500, "Failed saving must retain the previous target")
            menuCheck(savedIndicator.isHidden, "Failed saving must never show a success check")
            menuCheck(control.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == (currentLanguage == "en" ? "Not saved; retry" : "未保存，请重试") })
            capture("save-failed")
            try! FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: MenuTestPaths.configDirectory.appendingPathComponent("config.json").path)
            results["failed_save_has_error_not_success_check"] = true
            post(.leftMouseDown, view: modes, fraction: 0.24)
        case 19:
            post(.leftMouseUp, view: modes, fraction: 0.24)
        case 20:
            menuCheck(ConfigManager.shared.loadConfig().mode == "auto")
            menuCheck(!slider.isEnabled && slider.intValue == 3500)
            menuCheck(!adjustment.isEnabled && savedIndicator.isHidden)
            menuCheck(control.window?.windowNumber == initialWindow)
            capture("auto-restored")
            BackgroundHardwareReader.shared.setMenuTestRPM(3500, age: 16)
            MenuBarManager.shared.updateDynamicMenuItems()
            menuCheck(control.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "— RPM" })
            menuCheck(!slider.isEnabled)
        case 21:
            capture("unavailable")
            results["stale_rpm_is_unavailable_not_zero"] = true
            results["same_menu_kept_open_across_modes"] = true
            menuCheck(MenuSpeedControl.targetRPM(1250, maximum: 4900, step: 500) == 1000)
            menuCheck(MenuSpeedControl.targetRPM(4880, maximum: 4900, step: 500) == 4900)
            menuCheck(MenuSpeedControl.targetRPM(-200, maximum: 4900, step: nil) == 0)
            menuCheck(MenuSpeedControl.targetRPM(6000, maximum: 4900, step: nil) == 4900)
            menu.cancelTracking()
        default:
            menu.cancelTracking()
        }
        phase += 1
    }

    @objc func run() {
        let poll = DispatchSource.makeTimerSource(queue: .main)
        poll.schedule(deadline: .now() + 0.05, repeating: 0.1)
        poll.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.control.window != nil, !self.closed else { return }
                self.mainQueueTicks += 1
            }
        }
        poll.resume()
        let timer = Timer(timeInterval: 0.22, target: self, selector: #selector(advance), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .eventTracking)
        let screen = NSScreen.main!.visibleFrame
        menu.popUp(positioning: nil, at: NSPoint(x: screen.midX, y: screen.maxY - 60), in: nil)
        timer.invalidate()
        poll.cancel()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        menuCheck(phase >= 22 && closed, "End of tracking: phase=\(phase), closed=\(closed)")
        menuCheck(mainQueueTicks > 0, "Main-queue polling must continue during menu tracking")
        results["main_queue_timer_ticks_while_menu_open"] = mainQueueTicks
        results["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        results["source"] = "Real MenuBarManager and MenuSpeedControl; isolated config and synthetic telemetry; posted mouse clicks/drags on the owned test menu"
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: output.appendingPathComponent("\(prefix)-results.json"))
        print("PASS \(prefix): persistent menu, Auto updates, Continuous/Stepped, release commit, saved check, failed save, centered feedback")
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: originalPointer, mouseButton: .left)?.post(tap: .cghidEventTap)
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let test = MenuSpeedTest()
NSApp.activate(ignoringOtherApps: true)
// AppKit opens status menus from event dispatch, not inside a main-queue block.
// A nested menu inside DispatchQueue.main.async would itself block main-queue
// polling and give a false result for the production presentation path.
test.perform(#selector(MenuSpeedTest.run), with: nil, afterDelay: 0.1)
app.run()
