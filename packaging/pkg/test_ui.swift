// AppKit controller regressions. All state, network and config use a throwaway test bundle.
@MainActor extension DisplaySettingsWindowController {
    static func runUIRegression() {
        UserDefaults.standard.set("mini",forKey:"ifancontrol.ui.display_mode")
        UserDefaults.standard.set("power,rpm,power,invalid",forKey:"ifancontrol.ui.mini_top_source")
        let c=DisplaySettingsWindowController()
        precondition(c.currentMiniTopLine.sources.map(\.rawValue)==["power","rpm"])
        precondition(c.previewField.stringValue.hasPrefix("12.3W｜2400 RPM｜A"))
        c.currentMiniTopLine=([.temperature],.value)
        c.syncMiniLineControls()
        let button=c.topSourceCheckboxes["temperature"]!;button.state = .off;c.topSourceChanged(button)
        precondition(button.state == .on && c.currentMiniTopLine.sources.count==1)
        for key in ["power","rpm"] {let button=c.topSourceCheckboxes[key]!;button.state = .on;c.topSourceChanged(button)}
        precondition(c.currentMiniTopLine.sources.map(\.rawValue)==["temperature","power","rpm"])
        c.currentMiniBottomLine=([.rpm],.unit)
        c.swapLines(c)
        let reopened=DisplaySettingsWindowController()
        precondition(reopened.currentMiniBottomLine.sources.map(\.rawValue)==["temperature","power","rpm"])
        precondition(reopened.previewField.stringValue=="2400 RPM\n65｜12.3｜2400")
        for (style,prefix,accent) in [("value","65｜2400",""),("unit","65℃｜2400 RPM",""),("mode","65｜2400｜","M"),("full","65℃｜2400 RPM｜","M")] {
            let line=MiniDisplayFormatter.line(values:["65","2400"],units:["65℃","2400 RPM"],style:style,mode:"M")
            precondition(line.primary==prefix && line.accent==accent)
        }
        c.modeControl.selectedSegment = 1; c.modeSelectionChanged(c.modeControl)
        precondition(c.currentDisplayMode == "compact" && c.miniOptionsStack.isHidden && c.previewField.stringValue == "65｜2400｜A")
        c.modeControl.selectedSegment = 2; c.modeSelectionChanged(c.modeControl)
        c.topStylePopup.selectItem(at: 0); c.topPopupChanged(c.topStylePopup)
        precondition(c.currentMiniTopLine.style.rawValue == "value" && c.previewField.stringValue.hasPrefix("2400\n"))
        c.window?.close();reopened.window?.close()
        print("PASS: legacy display preferences, ordered deduplication, last-source guard, shared formatting, swap and reopening persistence")
    }
}
@MainActor extension PowerTelemetryReader {
    func testSnapshot(_ supported:Bool, _ updated:Date?) {
        _snapshot=PowerTelemetrySnapshot(cpuWatts:6.4,gpuWatts:2.1,aneWatts:0,ramWatts:1.2,pciWatts:0.3,dcInWatts:18.4,lastUpdatedAt:updated,isSupported:supported)
    }
}
@MainActor extension PowerConsumptionWindowController {
    static func runUIRegression() {
        PowerTelemetryReader.shared.testSnapshot(true,nil)
        let c=PowerConsumptionWindowController();c.refreshSnapshot()
        precondition(c.valueLabels.values.allSatisfy{$0.stringValue=="--"})
        precondition(c.samplingStatus.stringValue.contains("读取") || c.samplingStatus.stringValue.contains("Reading"))
        PowerTelemetryReader.shared.testSnapshot(true,Date());c.refreshSnapshot()
        precondition(c.valueLabels["total"]?.stringValue=="18.40 W")
        PowerTelemetryReader.shared.testSnapshot(false,Date());c.refreshSnapshot()
        precondition(c.valueLabels.values.allSatisfy{$0.stringValue=="--"})
        c.startTimerIfNeeded();precondition(c.updateTimer != nil)
        c.windowWillClose(Notification(name:NSWindow.willCloseNotification,object:c.window))
        precondition(c.updateTimer==nil)
        c.startTimerIfNeeded();precondition(c.updateTimer != nil)
        c.windowWillClose(Notification(name:NSWindow.willCloseNotification,object:c.window))
        print("PASS: power loading/data/unsupported states and close/reopen timer lifecycle")
    }
}
@MainActor extension FeedbackWindowController {
    static func runUIRegression() async throws {
        let c=FeedbackWindowController()
        c.sendFeedback();precondition(c.statusLabel?.stringValue == appL10n("请输入内容","Please enter something"))
        c.contentTextView?.string="draft"
        UserDefaults.standard.set(Array(repeating:Date().timeIntervalSince1970,count:5),forKey:"ifancontrol.feedback.send_timestamps")
        c.sendFeedback();precondition(c.statusLabel?.stringValue.contains("5")==true)
        UserDefaults.standard.removeObject(forKey:"ifancontrol.feedback.send_timestamps")
        c.contentTextView?.string="fail retained draft";c.emailField?.stringValue="qa@example.invalid"
        c.sendFeedback();precondition(c.sendButton?.isEnabled==false && c.statusLabel?.alphaValue==0)
        try await Task.sleep(for:.milliseconds(100))
        precondition(c.sendButton?.isEnabled==true && c.contentTextView?.string=="fail retained draft")
        c.window?.close();c.showWindow(nil)
        precondition(c.contentTextView?.string=="fail retained draft" && c.emailField?.stringValue=="qa@example.invalid")
        c.contentTextView?.string="success";c.emailField?.stringValue=""
        c.sendFeedback();try await Task.sleep(for:.milliseconds(100))
        precondition(c.submittedSuccessfully && !(c.statusLabel?.stringValue.contains("reply") ?? false) && !(c.statusLabel?.stringValue.contains("邮箱") ?? false))
        c.window?.close();c.showWindow(nil)
        precondition(c.sendButton?.isEnabled==true && c.contentTextView?.string=="" && c.closeAfterSuccess==nil)
        c.contentTextView?.string="new draft"
        try await Task.sleep(for:.milliseconds(2150))
        precondition(c.window?.isVisible==true && c.contentTextView?.string=="new draft","Prior success close must not close a reopened editor")
        c.emailField?.stringValue="qa@example.invalid";c.sendFeedback();try await Task.sleep(for:.milliseconds(100))
        precondition(c.statusLabel?.stringValue.contains(appL10n("邮箱","email"))==true)
        c.closeAfterSuccess?.cancel();c.window?.close()
        print("PASS: empty/limited/sending/failure draft persistence, optional-email success wording, resend and prior-close cancellation")
    }
}

@MainActor extension HelpWindowController {
    static func runUIRegression() {
        let c = HelpWindowController()
        for page in [Section.overview, .diagnostics, .faq, .donation] {
            c.select(section: page); c.window?.contentView?.layoutSubtreeIfNeeded()
            let document = c.sectionContainerView as! NSStackView
            precondition(document.arrangedSubviews.count == 1 && document.arrangedSubviews[0] === c.sectionViews[page])
            precondition(c.window!.frame.height <= 550, "Hidden help pages must not enlarge the help window")
        }
        UpdatePreferences.shared.unlockDeveloperMode(); c.addDeveloperSectionIfNeeded(); c.select(section:.developer)
        precondition(c.sidebarButtons[.developer] != nil && c.betaUpdateCheckbox?.state == .off)
        c.exitDeveloperMode()
        precondition(c.currentSection == .overview && c.sidebarButtons[.developer] == nil && !UpdatePreferences.shared.betaEnabled)
        c.window?.close()
        print("PASS: isolated active help-page layout, bounded window, developer availability and exit")
    }
}
