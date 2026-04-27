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

/// 官方默认曲线（预设 A）
public func defaultFanCurve(maxRPM: Int) -> [FanPoint] {
    return [
        FanPoint(temperature: 20, rpm: 0),
        FanPoint(temperature: 40.3, rpm: 262),
        FanPoint(temperature: 63.3, rpm: 895),
        FanPoint(temperature: 85, rpm: 2222),
        FanPoint(temperature: 100, rpm: 3854)
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
public class FanCurvePresetWindowController: NSWindowController {
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
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 530),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fanCurveL10n("风扇曲线编辑器 v33", "Fan Curve Editor v33")
        window.center()

        super.init(window: window)

        setupUI()

        // 窗口关闭时自动保存
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 1. 曲线视图
        fanCurveView.fanCurve = currentFanCurve
        fanCurveView.maxRPM = maxRPM
        fanCurveView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fanCurveView)

        // 2. 底部：预设按钮 + 分隔符 + 操作按钮（一行）
        // 左侧：预设按钮
        let presetStack = NSStackView()
        presetStack.spacing = 6
        for i in 0..<3 {
            let btn = NSButton(title: presetNames[i], target: self, action: #selector(presetButtonClicked(_:)))
            btn.bezelStyle = .recessed
            btn.setButtonType(.pushOnPushOff)
            btn.tag = i
            btn.state = (i == activePresetIndex) ? .on : .off
            // 双击重命名
            let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(presetDoubleClicked(_:)))
            doubleClick.numberOfClicksRequired = 2
            btn.addGestureRecognizer(doubleClick)
            presetStack.addArrangedSubview(btn)
        }

        // 分隔符
        let separator = NSTextField(labelWithString: "│")
        separator.textColor = .separatorColor
        separator.font = NSFont.systemFont(ofSize: 16)

        // 右侧：操作按钮
        let resetButton = NSButton(title: fanCurveL10n("重置", "Reset"), target: self, action: #selector(resetCurve))
        let closeButton = NSButton(title: fanCurveL10n("关闭", "Close"), target: self, action: #selector(closeWindow))

        let actionStack = NSStackView(views: [resetButton, closeButton])
        actionStack.spacing = 12

        // 整行
        let bottomStack = NSStackView(views: [presetStack, separator, actionStack])
        bottomStack.spacing = 12
        bottomStack.alignment = .centerY
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomStack)

        // 提示标签
        let hintLabel = NSTextField(labelWithString: fanCurveL10n("双击预设名称可重命名 · 关闭窗口自动保存", "Double-click preset name to rename · Saved on close"))
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            fanCurveView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            fanCurveView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            fanCurveView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            fanCurveView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -16),

            bottomStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -4),

            hintLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
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
        guard let btn = sender.view as? NSButton else { return }
        let index = btn.tag
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
                btn.title = newName
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
        // 立即应用新曲线
        NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSwitch"), object: nil, userInfo: ["curve": currentFanCurve])
    }

    @objc private func resetCurve() {
        let defaultCurve = defaultFanCurve(maxRPM: maxRPM)
        presets[activePresetIndex] = defaultCurve
        currentFanCurve = defaultCurve
        fanCurveView.fanCurve = defaultCurve
        // 立即应用
        NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSwitch"), object: nil, userInfo: ["curve": defaultCurve])
    }

    @objc private func closeWindow() {
        window?.close()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // 关闭时自动保存当前编辑状态
        currentFanCurve = fanCurveView.fanCurve
        presets[activePresetIndex] = currentFanCurve
        handleSave(curve: currentFanCurve, names: presetNames, presets: presets, activeIndex: activePresetIndex)
    }

    private func handleSave(curve: [FanPoint], names: [String], presets: [[FanPoint]], activeIndex: Int) {
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
            try data.write(to: configFile)

            NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSave"), object: nil, userInfo: [
                "curve": curve,
                "curvePresetNames": names,
                "curvePresets": presets,
                "activeCurvePreset": activeIndex
            ])
        } catch {
            NSLog("iFanControl: Failed to save fan curve: \(error.localizedDescription)")
        }
    }
}
