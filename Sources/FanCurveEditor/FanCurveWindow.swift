//
//  FanCurveWindow.swift
//  iFanControl
//
//  Created by iFanControl on 2026-03-17.
//  Copyright © 2026 iFanControl. All rights reserved.
//

import AppKit
import Foundation

// 配置结构（与主应用一致）
public struct Config: Codable {
    public var version: String
    public var curve: [FanPoint]
    public var mode: String
    public var autoStart: Bool
    public var maxRPM: Int
    public var manualRPM: Int
    public var safetyFloorRPM: Int?
    public var temperatureSourceMode: String?
    public var selectedTemperatureSensorKey: String?
    
    public init(
        version: String,
        curve: [FanPoint],
        mode: String,
        autoStart: Bool,
        maxRPM: Int,
        manualRPM: Int = 2000,
        safetyFloorRPM: Int? = nil,
        temperatureSourceMode: String? = nil,
        selectedTemperatureSensorKey: String? = nil
    ) {
        self.version = version
        self.curve = curve
        self.mode = mode
        self.autoStart = autoStart
        self.maxRPM = maxRPM
        self.manualRPM = manualRPM
        self.safetyFloorRPM = safetyFloorRPM
        self.temperatureSourceMode = temperatureSourceMode
        self.selectedTemperatureSensorKey = selectedTemperatureSensorKey
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
        
        window.title = "风扇曲线编辑器"
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
        let resetButton = NSButton(title: "重置", target: self, action: #selector(resetCurve))
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(resetButton)
        
        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveCurve))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(saveButton)
        
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
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
        let quarter = max(1, maxRPM / 4)
        fanCurve = [
            FanPoint(temperature: 20, rpm: 0),
            FanPoint(temperature: 40, rpm: quarter),
            FanPoint(temperature: 60, rpm: quarter * 2),
            FanPoint(temperature: 80, rpm: quarter * 3),
            FanPoint(temperature: 100, rpm: maxRPM)
        ]
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
        var existingSafetyFloorRPM: Int?
        var existingTemperatureSourceMode: String?
        var existingSelectedTemperatureSensorKey: String?
        
        if let existingData = try? Data(contentsOf: configFile),
           let existingConfig = try? JSONDecoder().decode(Config.self, from: existingData) {
            existingMode = existingConfig.mode
            existingAutoStart = existingConfig.autoStart
            existingManualRPM = existingConfig.manualRPM
            existingSafetyFloorRPM = existingConfig.safetyFloorRPM
            existingTemperatureSourceMode = existingConfig.temperatureSourceMode
            existingSelectedTemperatureSensorKey = existingConfig.selectedTemperatureSensorKey
        }
        
        do {
            let config = Config(
                version: "1.0",
                curve: fanCurve,
                mode: existingMode,
                autoStart: existingAutoStart,
                maxRPM: maxRPM,
                manualRPM: existingManualRPM,
                safetyFloorRPM: existingSafetyFloorRPM,
                temperatureSourceMode: existingTemperatureSourceMode,
                selectedTemperatureSensorKey: existingSelectedTemperatureSensorKey
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFile)
            
            print("DEBUG: Save successful")
            
            // 发送通知告知主应用配置已更新
            NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSave"), object: nil, userInfo: ["curve": fanCurve])
            
            let alert = NSAlert()
            alert.messageText = "保存成功"
            alert.informativeText = "风扇曲线已保存"
            alert.addButton(withTitle: "确定")
            alert.runModal()
        } catch {
            print("DEBUG: Save failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    @objc private func closeWindow() {
        window?.close()
    }
}
