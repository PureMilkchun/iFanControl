import AppKit

/// A persistent native menu row. Auto observes actual RPM; Manual edits a target.
@MainActor final class MenuSpeedControl: NSView {
    var onModeChanged: ((Bool) -> Void)?
    var onAdjustmentChanged: ((Bool) -> Void)?
    var onTargetCommitted: ((Int) -> Bool)?

    private let modeControl: NSSegmentedControl
    private let adjustmentControl: NSButton
    private let adjustmentLabel = NSTextField(labelWithString: "")
    private let savedIndicator = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private let reading = NSTextField(labelWithString: "")
    private let slider = MenuSpeedSlider()
    private let maximumLabel = NSTextField(labelWithString: "")
    private let message = NSTextField(labelWithString: "")
    private let language: String
    private var isAutomatic = true
    private var maximumRPM = 4900
    private var stepRPM: Int?
    private var draftRPM: Int?
    private var hideSavedIndicator: DispatchWorkItem?

    init(language: String) {
        self.language = language
        modeControl = NSSegmentedControl(labels: language == "en" ? ["Auto", "Manual"] : ["自动", "手动"],
                                         trackingMode: .selectOne, target: nil, action: nil)
        adjustmentControl = NSButton(checkboxWithTitle: language == "en" ? "Use steps" : "按档位调节", target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 142))
        autoresizingMask = [.width]
        identifier = NSUserInterfaceItemIdentifier("menu-speed-control")

        let modeLabel = NSTextField(labelWithString: text("风扇控制", "Fan control"))
        modeLabel.frame = NSRect(x: 20, y: 112, width: 100, height: 18)
        modeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        addSubview(modeLabel)

        modeControl.frame = NSRect(x: 142, y: 110, width: 118, height: 24)
        modeControl.identifier = NSUserInterfaceItemIdentifier("menu-control-mode")
        modeControl.autoresizingMask = [.minXMargin]
        modeControl.controlSize = .small
        modeControl.font = .systemFont(ofSize: 12)
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.setAccessibilityLabel(text("控制模式", "Control mode"))
        addSubview(modeControl)

        caption.frame = NSRect(x: 20, y: 85, width: 90, height: 18)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        addSubview(caption)
        reading.frame = NSRect(x: 116, y: 83, width: 124, height: 22)
        reading.autoresizingMask = [.minXMargin]
        reading.alignment = .right
        reading.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        addSubview(reading)
        savedIndicator.frame = NSRect(x: 248, y: 88, width: 12, height: 12)
        savedIndicator.autoresizingMask = [.minXMargin]
        savedIndicator.identifier = NSUserInterfaceItemIdentifier("menu-target-saved")
        savedIndicator.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: text("目标转速已应用", "Target speed applied"))
        savedIndicator.contentTintColor = .systemGreen
        savedIndicator.isHidden = true
        savedIndicator.toolTip = text("目标转速已保存，实际转速会逐步接近目标。", "Target speed saved. Actual speed will approach the target.")
        addSubview(savedIndicator)

        slider.frame = NSRect(x: 17, y: 57, width: 246, height: 24)
        slider.autoresizingMask = [.width]
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.minValue = 0
        slider.maxValue = 4900
        slider.onTrackingEnded = { [weak self] in self?.finishEditing() }
        addSubview(slider)

        let minimumLabel = NSTextField(labelWithString: "0 RPM")
        minimumLabel.frame = NSRect(x: 20, y: 40, width: 60, height: 15)
        minimumLabel.font = .systemFont(ofSize: 10)
        minimumLabel.textColor = .secondaryLabelColor
        addSubview(minimumLabel)
        maximumLabel.frame = NSRect(x: 180, y: 40, width: 80, height: 15)
        maximumLabel.autoresizingMask = [.minXMargin]
        maximumLabel.alignment = .right
        maximumLabel.font = .systemFont(ofSize: 10)
        maximumLabel.textColor = .secondaryLabelColor
        addSubview(maximumLabel)
        message.frame = NSRect(x: 76, y: 40, width: 128, height: 15)
        message.autoresizingMask = [.width]
        message.alignment = .center
        message.font = .systemFont(ofSize: 10)
        message.textColor = .secondaryLabelColor
        addSubview(message)

        adjustmentLabel.frame = NSRect(x: 168, y: 10, width: 92, height: 18)
        adjustmentLabel.autoresizingMask = [.minXMargin]
        adjustmentLabel.alignment = .right
        adjustmentLabel.font = .systemFont(ofSize: 10)
        adjustmentLabel.textColor = .secondaryLabelColor
        addSubview(adjustmentLabel)
        adjustmentControl.frame = NSRect(x: 20, y: 8, width: 148, height: 22)
        adjustmentControl.identifier = NSUserInterfaceItemIdentifier("menu-speed-adjustment")
        adjustmentControl.autoresizingMask = [.width]
        adjustmentControl.controlSize = .small
        adjustmentControl.font = .systemFont(ofSize: 11)
        adjustmentControl.target = self
        adjustmentControl.action = #selector(adjustmentChanged)
        adjustmentControl.setAccessibilityHelp(text("关闭时连续调节，开启时按档位调节。", "Off adjusts continuously; on adjusts in steps."))
        addSubview(adjustmentControl)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func text(_ zh: String, _ en: String) -> String { language == "en" ? en : zh }

    func update(automatic: Bool, actualRPM: Int?, manualRPM: Int, maximumRPM: Int, steppedBy: Int?, hasFan: Bool) {
        if automatic != isAutomatic || steppedBy != stepRPM {
            draftRPM = nil
            clearSavedIndicator()
        }
        isAutomatic = automatic
        self.maximumRPM = max(maximumRPM, 0)
        stepRPM = steppedBy
        modeControl.selectedSegment = automatic ? 0 : 1
        modeControl.isEnabled = hasFan
        adjustmentControl.state = steppedBy == nil ? .off : .on
        adjustmentControl.isEnabled = !automatic && hasFan && self.maximumRPM > 0
        adjustmentLabel.stringValue = steppedBy.map { text("\($0) RPM / 档", "\($0) RPM / step") } ?? text("连续调节", "Continuous")
        maximumLabel.stringValue = "\(self.maximumRPM) RPM"
        slider.maxValue = Double(max(self.maximumRPM, 1))
        slider.isEnabled = !automatic && hasFan && self.maximumRPM > 0
        caption.stringValue = automatic ? text("当前转速", "Actual speed") : text("目标转速", "Target speed")
        slider.setAccessibilityLabel(caption.stringValue + " RPM")

        let rpm: Int?
        if automatic {
            rpm = actualRPM.map { max(0, min(self.maximumRPM, $0)) }
            message.stringValue = actualRPM == nil ? text("暂不可用", "Unavailable") : ""
        } else {
            rpm = draftRPM ?? max(0, min(self.maximumRPM, manualRPM))
            message.stringValue = draftRPM == nil ? "" : text("松手应用", "Release to apply")
        }
        reading.stringValue = rpm.map { "\($0) RPM" } ?? "— RPM"
        // A missing reading is not zero RPM. Keep the last thumb position and
        // explicitly hide its meaning behind the unavailable label instead.
        if let rpm, !slider.isTrackingMouse || automatic { slider.doubleValue = Double(rpm) }
        slider.toolTip = automatic
            ? text("自动模式下跟随实际转速，无法拖动。", "Follows actual speed in Auto; dragging is disabled.")
            : text("拖动预览目标转速，松手后应用。", "Drag to preview the target; release to apply.")
        setAccessibilityLabel(text("风扇控制", "Fan control"))
    }

    func showSaveFailure() {
        clearSavedIndicator()
        message.stringValue = text("未保存，请重试", "Not saved; retry")
        message.textColor = .systemRed
    }

    @objc private func modeChanged() {
        guard modeControl.isEnabled else { return }
        draftRPM = nil
        clearSavedIndicator()
        message.textColor = .secondaryLabelColor
        onModeChanged?(modeControl.selectedSegment == 0)
    }

    @objc private func adjustmentChanged() {
        guard adjustmentControl.isEnabled else { return }
        draftRPM = nil
        clearSavedIndicator()
        onAdjustmentChanged?(adjustmentControl.state == .on)
    }

    @objc private func sliderChanged() {
        guard !isAutomatic, slider.isEnabled else { return }
        clearSavedIndicator()
        let rpm = Self.targetRPM(slider.doubleValue, maximum: maximumRPM, step: stepRPM)
        draftRPM = rpm
        reading.stringValue = "\(rpm) RPM"
        if stepRPM != nil { slider.doubleValue = Double(rpm) }
        message.stringValue = text("松手应用", "Release to apply")
        message.textColor = .secondaryLabelColor
        if !slider.isTrackingMouse { finishEditing() } // Keyboard and accessibility actions.
    }

    private func finishEditing() {
        guard !isAutomatic, slider.isEnabled, let rpm = draftRPM else { return }
        draftRPM = nil
        slider.doubleValue = Double(rpm)
        message.stringValue = ""
        let saved = onTargetCommitted?(rpm) ?? false
        guard !isAutomatic else { return }
        if saved { showSavedConfirmation() }
        else { showSaveFailure() }
    }

    private func showSavedConfirmation() {
        clearSavedIndicator()
        savedIndicator.isHidden = false
        let hide = DispatchWorkItem { [weak self] in self?.savedIndicator.isHidden = true }
        hideSavedIndicator = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: hide)
    }

    private func clearSavedIndicator() {
        hideSavedIndicator?.cancel()
        hideSavedIndicator = nil
        savedIndicator.isHidden = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clearSavedIndicator(); draftRPM = nil }
    }

    /// Matches the existing manual window's continuous/stepped policy.
    static func targetRPM(_ rawValue: Double, maximum: Int, step: Int?) -> Int {
        let maximum = max(maximum, 0)
        guard rawValue.isFinite else { return 0 }
        let bounded = Int(min(Double(maximum), max(0, rawValue.rounded())))
        guard let step, step > 1 else { return bounded }
        let lower = Int(floor(Double(bounded) / Double(step))) * step
        let upper = min(Double(maximum), ceil(Double(bounded) / Double(step)) * Double(step))
        let candidates = [max(0, min(maximum, lower)), Int(upper), maximum]
        return candidates.min {
            let lhs = abs($0 - bounded), rhs = abs($1 - bounded)
            return lhs == rhs ? $0 < $1 : lhs < rhs
        } ?? bounded
    }
}

@MainActor private final class MenuSpeedSlider: NSSlider {
    var onTrackingEnded: (() -> Void)?
    private(set) var isTrackingMouse = false

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isTrackingMouse = true
        super.mouseDown(with: event)
        isTrackingMouse = false
        onTrackingEnded?()
    }
}
