//
//  FanCurveWindow.swift
//  iFanControl
//
//  Created by iFanControl on 2026-03-17.
//  Copyright © 2026 iFanControl. All rights reserved.
//

import AppKit
import Foundation

private let currentLanguage: String = {
    if let saved = UserDefaults.standard.string(forKey: "ifancontrol.ui.language") {
        return saved
    }
    return Locale.preferredLanguages.first?.lowercased().hasPrefix("en") == true ? "en" : "zh"
}()
private func fanCurveL10n(_ zh: String, _ en: String) -> String {
    currentLanguage == "en" ? en : zh
}

private let fanCurveYAxisReversedKey = "ifancontrol.ui.fan_curve_y_axis_reversed"

/// 官方默认曲线（预设 A）
public func defaultFanCurve(maxRPM: Int) -> [FanPoint] {
    let referenceMaxRPM = 4900.0
    let clampedMaxRPM = max(maxRPM, 0)
    func scaledRPM(_ referenceRPM: Double) -> Int {
        Int((referenceRPM / referenceMaxRPM * Double(clampedMaxRPM)).rounded())
    }

    return [
        FanPoint(temperature: 20, rpm: scaledRPM(602)),
        FanPoint(temperature: 41.09696691176471, rpm: scaledRPM(695)),
        FanPoint(temperature: 62.62178308823529, rpm: scaledRPM(1388)),
        FanPoint(temperature: 84.76838235294117, rpm: scaledRPM(2825)),
        FanPoint(temperature: 100, rpm: scaledRPM(3504))
    ]
}

// 配置结构（与主应用一致）
public struct Config: Codable {
    public var version: String
    public var curve: [FanPoint]
    public var mode: String
    public var autoStart: Bool
    public var maxRPM: Int
    public var manualRPM: Int
    public var manualRPMControlMode: String?
    public var manualRPMStep: Int?
    public var safetyFloorRPM: Int?
    public var temperatureSourceMode: String?
    public var selectedTemperatureSensorKey: String?
    public var curvePresetNames: [String]?
    public var curvePresets: [[FanPoint]]?
    public var activeCurvePreset: Int?

    public init(
        version: String,
        curve: [FanPoint],
        mode: String,
        autoStart: Bool,
        maxRPM: Int,
        manualRPM: Int = 2000,
        manualRPMControlMode: String? = nil,
        manualRPMStep: Int? = nil,
        safetyFloorRPM: Int? = nil,
        temperatureSourceMode: String? = nil,
        selectedTemperatureSensorKey: String? = nil,
        curvePresetNames: [String]? = nil,
        curvePresets: [[FanPoint]]? = nil,
        activeCurvePreset: Int? = nil
    ) {
        self.version = version
        self.curve = curve
        self.mode = mode
        self.autoStart = autoStart
        self.maxRPM = maxRPM
        self.manualRPM = manualRPM
        self.manualRPMControlMode = manualRPMControlMode
        self.manualRPMStep = manualRPMStep
        self.safetyFloorRPM = safetyFloorRPM
        self.temperatureSourceMode = temperatureSourceMode
        self.selectedTemperatureSensorKey = selectedTemperatureSensorKey
        self.curvePresetNames = curvePresetNames
        self.curvePresets = curvePresets
        self.activeCurvePreset = activeCurvePreset
    }
}

// 风扇曲线窗口控制器
@MainActor
public class FanCurveWindowController: NSWindowController {
    private let fanCurveView = FanCurveView()
    private var fanCurve: [FanPoint] = []
    private let maxRPM: Int
    
    public init(fanCurve: [FanPoint], maxRPM: Int) {
        self.fanCurve = fanCurve
        self.maxRPM = maxRPM
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = fanCurveL10n("风扇曲线编辑器", "Fan Curve Editor")
        window.center()
        
        super.init(window: window)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // 设置曲线视图
        fanCurveView.fanCurve = fanCurve
        fanCurveView.maxRPM = maxRPM
        fanCurveView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fanCurveView)
        
        NSLayoutConstraint.activate([
            fanCurveView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            fanCurveView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            fanCurveView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            fanCurveView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -60)
        ])
        
        // 添加按钮
        let resetButton = NSButton(title: fanCurveL10n("重置", "Reset"), target: self, action: #selector(resetCurve))
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(resetButton)
        
        let saveButton = NSButton(title: fanCurveL10n("保存", "Save"), target: self, action: #selector(saveCurve))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(saveButton)
        
        let closeButton = NSButton(title: fanCurveL10n("关闭", "Close"), target: self, action: #selector(closeWindow))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            resetButton.topAnchor.constraint(equalTo: fanCurveView.bottomAnchor, constant: 10),
            resetButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            saveButton.topAnchor.constraint(equalTo: fanCurveView.bottomAnchor, constant: 10),
            saveButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            closeButton.topAnchor.constraint(equalTo: fanCurveView.bottomAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }
    
    @objc private func resetCurve() {
        fanCurve = defaultFanCurve(maxRPM: maxRPM)
        fanCurveView.fanCurve = fanCurve
    }

    @objc private func saveCurve() {
        fanCurve = fanCurveView.fanCurve
        
        let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MacFanControl")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        let configFile = configDir.appendingPathComponent("config.json")
        
        print("DEBUG: Saving curve to \(configFile.path)")
        
        // 读取现有配置以保留 mode、autoStart 和 manualRPM
        var existingMode = "auto"
        var existingAutoStart = true
        var existingManualRPM = 2000
        var existingManualRPMControlMode: String?
        var existingManualRPMStep: Int?
        var existingSafetyFloorRPM: Int?
        var existingTemperatureSourceMode: String?
        var existingSelectedTemperatureSensorKey: String?
        var existingCurvePresetNames: [String]?
        var existingCurvePresets: [[FanPoint]]?
        var existingActiveCurvePreset: Int?

        if let existingData = try? Data(contentsOf: configFile),
           let existingConfig = try? JSONDecoder().decode(Config.self, from: existingData) {
            existingMode = existingConfig.mode
            existingAutoStart = existingConfig.autoStart
            existingManualRPM = existingConfig.manualRPM
            existingManualRPMControlMode = existingConfig.manualRPMControlMode
            existingManualRPMStep = existingConfig.manualRPMStep
            existingSafetyFloorRPM = existingConfig.safetyFloorRPM
            existingTemperatureSourceMode = existingConfig.temperatureSourceMode
            existingSelectedTemperatureSensorKey = existingConfig.selectedTemperatureSensorKey
            existingCurvePresetNames = existingConfig.curvePresetNames
            existingCurvePresets = existingConfig.curvePresets
            existingActiveCurvePreset = existingConfig.activeCurvePreset
        }

        do {
            let config = Config(
                version: "1.0",
                curve: fanCurve,
                mode: existingMode,
                autoStart: existingAutoStart,
                maxRPM: maxRPM,
                manualRPM: existingManualRPM,
                manualRPMControlMode: existingManualRPMControlMode,
                manualRPMStep: existingManualRPMStep,
                safetyFloorRPM: existingSafetyFloorRPM,
                temperatureSourceMode: existingTemperatureSourceMode,
                selectedTemperatureSensorKey: existingSelectedTemperatureSensorKey,
                curvePresetNames: existingCurvePresetNames,
                curvePresets: existingCurvePresets,
                activeCurvePreset: existingActiveCurvePreset
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFile)
            
            print("DEBUG: Save successful")
            
            // 发送通知告知主应用配置已更新
            NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSave"), object: nil, userInfo: ["curve": fanCurve])
            
            let alert = NSAlert()
            alert.messageText = fanCurveL10n("保存成功", "Saved")
            alert.informativeText = fanCurveL10n("风扇曲线已保存", "Fan curve has been saved.")
            alert.addButton(withTitle: fanCurveL10n("确定", "OK"))
            alert.runModal()
        } catch {
            print("DEBUG: Save failed: \(error)")
            let alert = NSAlert()
            alert.messageText = fanCurveL10n("保存失败", "Save Failed")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: fanCurveL10n("确定", "OK"))
            alert.runModal()
        }
    }
    
    @objc private func closeWindow() {
        window?.close()
    }
}

// MARK: - 新窗口控制器（混合架构：AppKit 布局 + AppKit 预设按钮）

@MainActor
public class FanCurvePresetWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let initialFanCurve: [FanPoint]
    private let maxRPM: Int
    private let initialPresetNames: [String]?
    private let initialPresets: [[FanPoint]]?
    private let initialActivePreset: Int?

    // 纯 AppKit 架构：曲线视图 + 预设按钮 + 操作按钮
    private let fanCurveView = FanCurveView()
    private var currentFanCurve: [FanPoint]
    private var presetNames: [String]
    private var presets: [[FanPoint]]
    private var activePresetIndex: Int
    private let editStatus = NSTextField(labelWithString: "")
    private let activeLabel = NSTextField(labelWithString: "")
    private var originalFieldText: [ObjectIdentifier: String] = [:]
    private var hasInvalidPointInput = false
    private var pointFields: [(temperature: NSTextField, rpm: NSTextField)] = []
    private var presetButtons: [NSButton] = []
    private let pointStack = NSStackView()
    private var numericToggle: NSButton?
    private var showNumericEditor = UserDefaults.standard.bool(forKey: "ifancontrol.curve.numeric_editor")
    private var isYAxisReversed = UserDefaults.standard.bool(forKey: fanCurveYAxisReversedKey)

    public init(fanCurve: [FanPoint], maxRPM: Int,
                presetNames: [String]? = nil,
                presets: [[FanPoint]]? = nil,
                activePresetIndex: Int? = nil) {
        self.initialFanCurve = fanCurve
        self.maxRPM = maxRPM
        self.initialPresetNames = presetNames
        self.initialPresets = presets
        self.initialActivePreset = activePresetIndex

        // 初始化预设数据
        if let names = presetNames, let curves = presets, names.count == 3, curves.count == 3 {
            self.presetNames = names
            self.presets = curves
            self.activePresetIndex = min(activePresetIndex ?? 0, 2)
        } else {
            self.presetNames = [
                fanCurveL10n("预设 A", "Preset A"),
                fanCurveL10n("预设 B", "Preset B"),
                fanCurveL10n("预设 C", "Preset C")
            ]
            self.presets = [fanCurve, fanCurve, fanCurve]
            self.activePresetIndex = 0
        }
        self.currentFanCurve = self.presets[self.activePresetIndex]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: showNumericEditor ? 900 : 720, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fanCurveL10n("风扇曲线", "Fan Curve")
        window.center()

        super.init(window: window)

        setupUI()

        window.delegate = self
        window.minSize = NSSize(width: 720, height: 470)

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(root)
        activeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        activeLabel.textColor = .secondaryLabelColor
        activeLabel.lineBreakMode = .byTruncatingTail
        root.addArrangedSubview(activeLabel)
        activeLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let presetRow = NSStackView(); presetRow.spacing = 4
        for i in 0..<3 {
            let button = NSButton(title: presetNames[i], target: self, action: #selector(presetButtonClicked(_:)))
            button.controlSize = .small; button.font = .systemFont(ofSize: 12)
            button.bezelStyle = .recessed; button.setButtonType(.pushOnPushOff); button.tag = i
            button.state = i == activePresetIndex ? .on : .off
            button.widthAnchor.constraint(equalToConstant: 106).isActive = true
            button.cell?.lineBreakMode = .byTruncatingTail
            button.toolTip = presetNames[i]
            let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(presetDoubleClicked(_:)))
            doubleClick.numberOfClicksRequired = 2; button.addGestureRecognizer(doubleClick)
            presetButtons.append(button); presetRow.addArrangedSubview(button)
        }
        let rename = NSButton(title: fanCurveL10n("重命名…", "Rename…"), target: self, action: #selector(renameActivePreset))
        rename.controlSize = .small; rename.font = .systemFont(ofSize: 12)
        presetRow.addArrangedSubview(rename); presetRow.addArrangedSubview(NSView())
        let numeric = NSButton(checkboxWithTitle: fanCurveL10n("数值编辑", "Edit values"), target: self, action: #selector(toggleNumericEditor))
        numeric.state = showNumericEditor ? .on : .off; numeric.controlSize = .small; numeric.font = .systemFont(ofSize: 12)
        numeric.keyEquivalent = "i"; numeric.keyEquivalentModifierMask = [.command, .option]
        numeric.toolTip = fanCurveL10n("显示精确数值输入 · ⌘⌥I", "Show precise value fields · ⌘⌥I")
        numericToggle = numeric; presetRow.addArrangedSubview(numeric); root.addArrangedSubview(presetRow)
        presetRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        fanCurveView.fanCurve = currentFanCurve; fanCurveView.maxRPM = maxRPM; fanCurveView.isYAxisReversed = isYAxisReversed
        fanCurveView.setAccessibilityElement(true); fanCurveView.setAccessibilityRole(.image)
        fanCurveView.setAccessibilityLabel(fanCurveL10n("温度与目标转速曲线，可在控制点输入框编辑数值", "Temperature and target RPM curve. Edit values in the control point fields."))
        fanCurveView.onCurveChanged = { [weak self] curve in
            guard let self else { return }
            self.currentFanCurve = curve; self.syncPointFields(); self.markEdited()
        }
        pointStack.orientation = .vertical; pointStack.alignment = .leading; pointStack.spacing = 6
        pointStack.widthAnchor.constraint(equalToConstant: 162).isActive = true
        let graphRow = NSStackView(views: [fanCurveView, pointStack]); graphRow.spacing = 20; graphRow.alignment = .top
        root.addArrangedSubview(graphRow)
        graphRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        fanCurveView.heightAnchor.constraint(equalToConstant: 280).isActive = true
        graphRow.heightAnchor.constraint(equalToConstant: 280).isActive = true
        rebuildPointFields()
        pointStack.isHidden = !showNumericEditor
        let direction = NSSegmentedControl(labels: [fanCurveL10n("正向", "Normal"), fanCurveL10n("反向", "Reversed")], trackingMode: .selectOne, target: self, action: #selector(yAxisDirectionChanged(_:)))
        direction.controlSize = .small; direction.font = .systemFont(ofSize: 11)
        direction.selectedSegment = isYAxisReversed ? 1 : 0
        let directionLabel = NSTextField(labelWithString: fanCurveL10n("坐标显示", "Axis Direction"))
        let reset = NSButton(title: fanCurveL10n("重置", "Reset"), target: self, action: #selector(resetCurve))
        let close = NSButton(title: fanCurveL10n("保存并关闭", "Save and Close"), target: self, action: #selector(closeWindow))
        reset.toolTip = fanCurveL10n("重置当前预设", "Reset current preset")
        reset.bezelStyle = .rounded; reset.controlSize = .small
        directionLabel.font = .systemFont(ofSize: 11); directionLabel.textColor = .secondaryLabelColor
        close.bezelStyle = .rounded; close.keyEquivalent = "\r"
        let actions = NSStackView(views: [directionLabel, direction, NSView(), reset, close]); actions.spacing = 10
        root.addArrangedSubview(actions); actions.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        editStatus.font = .systemFont(ofSize: 11); editStatus.textColor = .secondaryLabelColor
        editStatus.stringValue = fanCurveL10n("拖动控制点或输入数值 · 关闭窗口自动保存", "Drag a point or enter values · Saved when you close this window")
        root.addArrangedSubview(editStatus)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20), root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])
        refreshPresetLabels()
    }

    @objc private func toggleNumericEditor(_ sender: NSButton) {
        showNumericEditor = sender.state == .on
        UserDefaults.standard.set(showNumericEditor, forKey: "ifancontrol.curve.numeric_editor")
        pointStack.isHidden = !showNumericEditor
        guard let window else { return }
        var frame = window.frame; frame.size.width = showNumericEditor ? 900 : 720
        window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func rebuildPointFields() {
        for view in pointStack.arrangedSubviews { pointStack.removeArrangedSubview(view); view.removeFromSuperview() }
        pointFields.removeAll(); originalFieldText.removeAll()
        let title = NSTextField(labelWithString: fanCurveL10n("控制点 · ℃ / RPM", "Points · °C / RPM"))
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .secondaryLabelColor; pointStack.addArrangedSubview(title)
        for (index, point) in fanCurveView.fanCurve.enumerated() {
            let temperature = NSTextField(string: String(format: "%.1f", point.temperature))
            let rpm = NSTextField(string: "\(point.rpm)")
            temperature.tag = index; rpm.tag = index
            temperature.isEditable = index > 0 && index < fanCurveView.fanCurve.count - 1
            for field in [temperature, rpm] { field.controlSize = .small; field.target = self; field.action = #selector(pointEdited(_:)); field.delegate = self; field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); field.widthAnchor.constraint(equalToConstant: 62).isActive = true }
            temperature.setAccessibilityLabel(fanCurveL10n("控制点\(index+1)温度，摄氏度", "Point \(index+1) temperature, Celsius"))
            rpm.setAccessibilityLabel(fanCurveL10n("控制点\(index+1)目标转速，RPM", "Point \(index+1) target speed, RPM"))
            pointStack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "\(index+1)"), temperature, rpm]))
            pointFields.append((temperature, rpm))
            originalFieldText[ObjectIdentifier(temperature)] = temperature.stringValue
            originalFieldText[ObjectIdentifier(rpm)] = rpm.stringValue
        }
    }
    private func syncPointFields() {
        if pointFields.count != fanCurveView.fanCurve.count { rebuildPointFields(); return }
        for (index, point) in fanCurveView.fanCurve.enumerated() {
            pointFields[index].temperature.stringValue = String(format: "%.1f", point.temperature)
            pointFields[index].rpm.stringValue = "\(point.rpm)"
            originalFieldText[ObjectIdentifier(pointFields[index].temperature)] = pointFields[index].temperature.stringValue
            originalFieldText[ObjectIdentifier(pointFields[index].rpm)] = pointFields[index].rpm.stringValue
        }
    }
    public func controlTextDidEndEditing(_ notification: Notification) {
        if let field = notification.object as? NSTextField { pointEdited(field) }
    }
    @objc private func pointEdited(_ sender: NSTextField) {
        guard pointFields.indices.contains(sender.tag) else { return }
        let valid = pointFields.allSatisfy { fields in
            guard let temperature = Double(fields.temperature.stringValue), temperature.isFinite, Int(fields.rpm.stringValue) != nil else { return false }
            return true
        }
        guard valid else {
            hasInvalidPointInput = true
            editStatus.stringValue = fanCurveL10n("请输入有效的温度和整数转速，原曲线仍保留。", "Enter a valid temperature and whole-number RPM. Your curve is retained.")
            editStatus.textColor = .systemRed; return
        }
        hasInvalidPointInput = false
        guard originalFieldText[ObjectIdentifier(sender)] != sender.stringValue else { return }
        let point = fanCurveView.fanCurve[sender.tag]
        let temperature = sender === pointFields[sender.tag].temperature ? Double(sender.stringValue)! : point.temperature
        let rpm = sender === pointFields[sender.tag].rpm ? Int(sender.stringValue)! : point.rpm
        fanCurveView.updatePoint(sender.tag, temperature: temperature, rpm: rpm)
    }
    private func markEdited() {
        hasInvalidPointInput = false
        editStatus.stringValue = fanCurveL10n("有修改 · 关闭窗口时保存", "Changes pending · Saved when you close")
        editStatus.textColor = .secondaryLabelColor
    }
    private func refreshPresetLabels() {
        activeLabel.toolTip = presetNames[activePresetIndex]
        activeLabel.stringValue = fanCurveL10n("当前预设：\(presetNames[activePresetIndex])", "Current preset: \(presetNames[activePresetIndex])")
        for (index, button) in presetButtons.enumerated() { button.title = presetNames[index]; button.toolTip = presetNames[index]; button.state = index == activePresetIndex ? .on : .off }
    }
    @objc private func renameActivePreset() { renamePreset(index: activePresetIndex) }

    @objc private func yAxisDirectionChanged(_ sender: NSSegmentedControl) {
        let reversed = sender.selectedSegment == 1
        guard reversed != isYAxisReversed else { return }

        isYAxisReversed = reversed
        UserDefaults.standard.set(reversed, forKey: fanCurveYAxisReversedKey)
        fanCurveView.isYAxisReversed = reversed
    }

    @objc private func presetButtonClicked(_ sender: NSButton) {
        let newIndex = sender.tag
        guard newIndex != activePresetIndex else { return }
        switchPreset(to: newIndex)
        // 更新按钮状态
        guard let stack = sender.superview as? NSStackView else { return }
        for case let btn as NSButton in stack.arrangedSubviews {
            btn.state = (btn.tag == activePresetIndex) ? .on : .off
        }
    }

    @objc private func presetDoubleClicked(_ sender: NSClickGestureRecognizer) {
        guard let button = sender.view as? NSButton else { return }
        renamePreset(index: button.tag)
    }

    private func renamePreset(index: Int) {
        let alert = NSAlert()
        alert.messageText = fanCurveL10n("重命名预设", "Rename Preset")
        alert.informativeText = fanCurveL10n("输入新名称：", "Enter new name:")
        alert.addButton(withTitle: fanCurveL10n("确定", "OK"))
        alert.addButton(withTitle: fanCurveL10n("取消", "Cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = presetNames[index]
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty {
                presetNames[index] = newName
                refreshPresetLabels()
                markEdited()
            }
        }
    }

    private func switchPreset(to newIndex: Int) {
        guard newIndex != activePresetIndex else { return }
        // 先从曲线视图同步当前编辑的曲线
        presets[activePresetIndex] = fanCurveView.fanCurve
        // 切换
        activePresetIndex = newIndex
        currentFanCurve = presets[newIndex]
        fanCurveView.fanCurve = currentFanCurve
        syncPointFields(); refreshPresetLabels(); markEdited()
        // 立即应用新曲线
        NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSwitch"), object: nil, userInfo: ["curve": currentFanCurve])
    }

    @objc private func resetCurve() {
        let defaultCurve = defaultFanCurve(maxRPM: maxRPM)
        presets[activePresetIndex] = defaultCurve
        currentFanCurve = defaultCurve
        fanCurveView.fanCurve = defaultCurve
        syncPointFields(); markEdited()
        // 立即应用
        NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSwitch"), object: nil, userInfo: ["curve": defaultCurve])
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil)
        guard !hasInvalidPointInput else {
            numericToggle?.state = .on
            if let numericToggle { toggleNumericEditor(numericToggle) }
            return false
        }
        currentFanCurve = fanCurveView.fanCurve
        presets[activePresetIndex] = currentFanCurve
        return handleSave(curve: currentFanCurve, names: presetNames, presets: presets, activeIndex: activePresetIndex)
    }

    private func handleSave(curve: [FanPoint], names: [String], presets: [[FanPoint]], activeIndex: Int) -> Bool {
        let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MacFanControl")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let configFile = configDir.appendingPathComponent("config.json")

        // 读取现有配置保留其他字段
        var existingMode = "auto"
        var existingAutoStart = true
        var existingManualRPM = 2000
        var existingManualRPMControlMode: String?
        var existingManualRPMStep: Int?
        var existingSafetyFloorRPM: Int?
        var existingTemperatureSourceMode: String?
        var existingSelectedTemperatureSensorKey: String?

        if let existingData = try? Data(contentsOf: configFile),
           let existingConfig = try? JSONDecoder().decode(Config.self, from: existingData) {
            existingMode = existingConfig.mode
            existingAutoStart = existingConfig.autoStart
            existingManualRPM = existingConfig.manualRPM
            existingManualRPMControlMode = existingConfig.manualRPMControlMode
            existingManualRPMStep = existingConfig.manualRPMStep
            existingSafetyFloorRPM = existingConfig.safetyFloorRPM
            existingTemperatureSourceMode = existingConfig.temperatureSourceMode
            existingSelectedTemperatureSensorKey = existingConfig.selectedTemperatureSensorKey
        }

        do {
            let config = Config(
                version: "1.0",
                curve: curve,
                mode: existingMode,
                autoStart: existingAutoStart,
                maxRPM: maxRPM,
                manualRPM: existingManualRPM,
                manualRPMControlMode: existingManualRPMControlMode,
                manualRPMStep: existingManualRPMStep,
                safetyFloorRPM: existingSafetyFloorRPM,
                temperatureSourceMode: existingTemperatureSourceMode,
                selectedTemperatureSensorKey: existingSelectedTemperatureSensorKey,
                curvePresetNames: names,
                curvePresets: presets,
                activeCurvePreset: activeIndex
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFile, options: .atomic)

            NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSave"), object: nil, userInfo: [
                "curve": curve,
                "curvePresetNames": names,
                "curvePresets": presets,
                "activeCurvePreset": activeIndex
            ])
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = fanCurveL10n("保存未完成", "Save Not Completed")
            alert.informativeText = fanCurveL10n("无法写入配置，编辑内容仍保留在窗口中。\n", "Could not write settings. Your edits are retained in this window.\n") + error.localizedDescription
            alert.addButton(withTitle: fanCurveL10n("返回编辑", "Back to Editing"))
            alert.runModal()
            NSLog("iFanControl: Failed to save fan curve: \(error.localizedDescription)")
            return false
        }
    }
}
