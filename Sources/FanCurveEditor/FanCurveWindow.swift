//
//  FanCurveWindow.swift
//  MacFanControl
//
//  Created by MacFanControl on 2026-03-17.
//  Copyright © 2026 MacFanControl. All rights reserved.
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
    public var language: String

    enum CodingKeys: String, CodingKey {
        case version
        case curve
        case mode
        case autoStart
        case maxRPM
        case manualRPM
        case language
    }
    
    public init(
        version: String,
        curve: [FanPoint],
        mode: String,
        autoStart: Bool,
        maxRPM: Int,
        manualRPM: Int = 2000,
        language: String = AppLanguage.fallback.rawValue
    ) {
        self.version = version
        self.curve = curve
        self.mode = mode
        self.autoStart = autoStart
        self.maxRPM = maxRPM
        self.manualRPM = manualRPM
        self.language = language
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        curve = try container.decodeIfPresent([FanPoint].self, forKey: .curve) ?? []
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "auto"
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        maxRPM = try container.decodeIfPresent(Int.self, forKey: .maxRPM) ?? 4900
        manualRPM = try container.decodeIfPresent(Int.self, forKey: .manualRPM) ?? 2000
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? AppLanguage.fallback.rawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(curve, forKey: .curve)
        try container.encode(mode, forKey: .mode)
        try container.encode(autoStart, forKey: .autoStart)
        try container.encode(maxRPM, forKey: .maxRPM)
        try container.encode(manualRPM, forKey: .manualRPM)
        try container.encode(language, forKey: .language)
    }
}

// 风扇曲线窗口控制器
@MainActor
public class FanCurveWindowController: NSWindowController {
    private let fanCurveView = FanCurveView()
    private var fanCurve: [FanPoint] = []
    private let resetButton = NSButton()
    private let saveButton = NSButton()
    private let closeButton = NSButton()
    
    public init(fanCurve: [FanPoint]) {
        self.fanCurve = fanCurve
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = LocalizationManager.shared.text(.fanCurveEditor).replacingOccurrences(of: "...", with: "")
        window.center()
        
        super.init(window: window)
        
        setupUI()
        applyLocalizedStrings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChanged),
            name: .appLanguageDidChange,
            object: nil
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // 设置曲线视图
        fanCurveView.fanCurve = fanCurve
        fanCurveView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fanCurveView)
        
        NSLayoutConstraint.activate([
            fanCurveView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            fanCurveView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            fanCurveView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            fanCurveView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -60)
        ])
        
        // 添加按钮
        resetButton.target = self
        resetButton.action = #selector(resetCurve)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(resetButton)
        
        saveButton.target = self
        saveButton.action = #selector(saveCurve)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(saveButton)
        
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
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

    private func applyLocalizedStrings() {
        let localization = LocalizationManager.shared
        window?.title = localization.text(.fanCurveEditor).replacingOccurrences(of: "...", with: "")
        resetButton.title = localization.text(.reset)
        saveButton.title = localization.text(.save)
        closeButton.title = localization.text(.close)
    }

    @objc private func handleLanguageChanged() {
        applyLocalizedStrings()
    }
    
    @objc private func resetCurve() {
        fanCurve = [
            FanPoint(temperature: 20, rpm: 0),
            FanPoint(temperature: 40, rpm: 1225),
            FanPoint(temperature: 60, rpm: 2450),
            FanPoint(temperature: 80, rpm: 3675),
            FanPoint(temperature: 100, rpm: 4900)
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
        var existingLanguage = LocalizationManager.shared.currentLanguage.rawValue
        
        if let existingData = try? Data(contentsOf: configFile),
           let existingConfig = try? JSONDecoder().decode(Config.self, from: existingData) {
            existingMode = existingConfig.mode
            existingAutoStart = existingConfig.autoStart
            existingManualRPM = existingConfig.manualRPM
            existingLanguage = existingConfig.language
        }
        
        do {
            let config = Config(
                version: "1.0",
                curve: fanCurve,
                mode: existingMode,
                autoStart: existingAutoStart,
                maxRPM: 4900,
                manualRPM: existingManualRPM,
                language: existingLanguage
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFile)
            
            print("DEBUG: Save successful")
            
            // 发送通知告知主应用配置已更新
            NotificationCenter.default.post(name: NSNotification.Name("FanCurveDidSave"), object: nil, userInfo: ["curve": fanCurve])
            
            let alert = NSAlert()
            alert.messageText = LocalizationManager.shared.text(.saveSuccessTitle)
            alert.informativeText = LocalizationManager.shared.text(.saveSuccessMessage)
            alert.addButton(withTitle: LocalizationManager.shared.text(.ok))
            alert.runModal()
        } catch {
            print("DEBUG: Save failed: \(error)")
            let alert = NSAlert()
            alert.messageText = LocalizationManager.shared.text(.saveFailureTitle)
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: LocalizationManager.shared.text(.ok))
            alert.runModal()
        }
    }
    
    @objc private func closeWindow() {
        window?.close()
    }
}
