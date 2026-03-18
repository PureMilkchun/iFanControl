//
//  main.swift
//  MacFanControl
//
//  Created by MacFanControl on 2026-03-17.
//  Copyright © 2026 MacFanControl. All rights reserved.
//

import AppKit
import Foundation
import FanCurveEditor

// 使用 FanCurveEditor 中的类型
typealias FanPoint = FanCurveEditor.FanPoint
typealias Config = FanCurveEditor.Config

// MARK: - CommandExecutor (使用 sudo 执行特权命令)
@MainActor
class CommandExecutor {
    static let shared = CommandExecutor()
    private let kentsmcPath = "/usr/local/bin/kentsmc"
    
    // 执行特权命令
    private func executeCommand(args: [String]) -> (success: Bool, output: String, error: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = [kentsmcPath] + args
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            return (task.terminationStatus == 0, output, error)
        } catch {
            return (false, "", error.localizedDescription)
        }
    }
    
    // 设置风扇转速
    func setFanRPM(rpm: Int) -> (success: Bool, error: String?) {
        let result = executeCommand(args: ["--fan-rpm", "\(rpm)"])
        return (result.success, result.success ? nil : result.error)
    }
    
    // 设置自动模式
    func setFanAuto() -> (success: Bool, error: String?) {
        let result = executeCommand(args: ["--fan-auto"])
        return (result.success, result.success ? nil : result.error)
    }
    
    // 解锁风扇
    func unlockFans() -> (success: Bool, error: String?) {
        let result = executeCommand(args: ["--unlock-fans"])
        return (result.success, result.success ? nil : result.error)
    }
}

// 风扇管理器
@MainActor
class FanManager {
    static let shared = FanManager()
    private let kentsmcPath = "/usr/local/bin/kentsmc"
    private let temperatureKey = "Tp0e" // M4 CPU Performance core 8
    private let maxRPM = 4900
    
    // 稳定性控制参数
    private var lastSetRPM: Int = 0
    private var lastExecutionTime: Date?
    private let minExecutionInterval: TimeInterval = 2.0
    
    // 温度历史记录
    private var temperatureHistory: [Double] = []
    private let maxHistoryCount: Int = 3
    
    // 动态滞后控制
    private func getMinRPMChange(currentRPM: Int) -> Int {
        if currentRPM < 1000 {
            return 50
        } else if currentRPM < 2000 {
            return 75
        } else {
            return 150
        }
    }
    
    private let criticalTemp: Double = 95.0
    
    // 读取温度（不需要特权）
    func readTemperature() -> Double? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: kentsmcPath)
        task.arguments = ["-r", temperatureKey]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                // 解析 "Tp0e = f32(65.61473)" 格式
                if let range = output.range(of: "\\d+\\.\\d+", options: .regularExpression),
                   let temp = Double(output[range]) {
                    return temp
                }
            }
        } catch {
            print("Error reading temperature: \(error)")
        }
        return nil
    }
    
    // 读取风扇转速（不需要特权）
    func readFanRPM() -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: kentsmcPath)
        task.arguments = ["-r", "F0Ac"]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                // 解析 "F0Ac = f32(2000.0)" 格式
                if let range = output.range(of: "\\d+\\.\\d+", options: .regularExpression),
                   let rpmValue = Double(output[range]) {
                    return Int(rpmValue)
                }
            }
        } catch {
            print("Error reading fan RPM: \(error)")
        }
        return nil
    }
    
    func setFanRPM(rpm: Int) {
        // 检查时间间隔
        if let lastTime = lastExecutionTime,
           Date().timeIntervalSince(lastTime) < minExecutionInterval {
            return
        }
        
        // 动态滞后控制
        let minChange = getMinRPMChange(currentRPM: lastSetRPM)
        let absChange = abs(rpm - lastSetRPM)
        guard absChange >= minChange else {
            return
        }
        
        // 平滑滤波
        let smoothingFactor: Double = 0.3
        let smoothedRPM = Int(Double(lastSetRPM) * (1.0 - smoothingFactor) + Double(rpm) * smoothingFactor)
        
        let result = CommandExecutor.shared.setFanRPM(rpm: smoothedRPM)
        
        if result.success {
            lastSetRPM = smoothedRPM
            lastExecutionTime = Date()
        } else {
            print("Error setting fan RPM: \(result.error ?? "Unknown error")")
        }
    }
    
    func unlockFans() {
        let result = CommandExecutor.shared.unlockFans()
        if !result.success {
            print("Error unlocking fans: \(result.error ?? "Unknown error")")
        }
    }
    
    // 温度读取失败计数器
    private var temperatureReadFailureCount: Int = 0
    private let maxTemperatureFailures: Int = 5
    
    func calculateFanRPM(temperature: Double, curve: [FanPoint]) -> Int {
        guard !curve.isEmpty else { return 0 }
        
        // 危险温度保护
        if temperature >= 95.0 {
            print("WARNING: Critical temperature (\(temperature)°C)")
            temperatureReadFailureCount = 0
            return Int(4900 * 0.95)
        }
        
        // 温度读取失败处理
        if temperature.isNaN || temperature < 0 {
            temperatureReadFailureCount += 1
            
            if temperatureReadFailureCount >= maxTemperatureFailures {
                print("CRITICAL: Too many temperature read failures")
                return -1
            }
            
            return lastSetRPM
        }
        
        temperatureReadFailureCount = 0
        
        // 记录温度历史
        temperatureHistory.append(temperature)
        if temperatureHistory.count > maxHistoryCount {
            temperatureHistory.removeFirst()
        }
        
        // 找到温度所在的区间
        var lowerPoint = curve[0]
        var upperPoint = curve.last!
        
        for i in 0..<curve.count - 1 {
            if temperature >= curve[i].temperature && temperature <= curve[i + 1].temperature {
                lowerPoint = curve[i]
                upperPoint = curve[i + 1]
                break
            }
        }
        
        // 温度超出曲线范围
        if temperature < lowerPoint.temperature {
            return lowerPoint.rpm
        }
        if temperature > upperPoint.temperature {
            return upperPoint.rpm
        }
        
        // 线性插值
        if upperPoint.temperature == lowerPoint.temperature {
            return lowerPoint.rpm
        }
        
        let ratio = (temperature - lowerPoint.temperature) / (upperPoint.temperature - lowerPoint.temperature)
        let rpm = Int(Double(lowerPoint.rpm) + ratio * Double(upperPoint.rpm - lowerPoint.rpm))
        
        return max(0, min(maxRPM, rpm))
    }
}

// 配置管理器
@MainActor
class ConfigManager {
    static let shared = ConfigManager()
    private let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MacFanControl")
    private let configFile: URL
    
    init() {
        configFile = configDir.appendingPathComponent("config.json")
        createConfigDir()
    }
    
    private func createConfigDir() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    func loadConfig() -> Config {
        if let data = try? Data(contentsOf: configFile),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        
        if let bundleConfigURL = Bundle.main.url(forResource: "config", withExtension: "json"),
           let data = try? Data(contentsOf: bundleConfigURL),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        
        return Config(
            version: "1.0",
            curve: [
                FanPoint(temperature: 20, rpm: 0),
                FanPoint(temperature: 47.3547794117647, rpm: 650),
                FanPoint(temperature: 68.21691176470588, rpm: 1642),
                FanPoint(temperature: 86.18520220588235, rpm: 2997),
                FanPoint(temperature: 100, rpm: 4900)
            ],
            mode: "auto",
            autoStart: true,
            maxRPM: 4900,
            manualRPM: 2168
        )
    }
    
    func saveConfig(_ config: Config) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFile)
        } catch {
            print("Error saving config: \(error)")
        }
    }
}

// 菜单栏管理
@MainActor
class MenuBarManager {
    static let shared = MenuBarManager()
    private var statusItem: NSStatusItem?
    private var currentTemperature: Double = 0
    private var currentFanRPM: Int = 0
    private var fanCurve: [FanPoint] = []
    private var isAutoMode: Bool = true
    private var autoStartEnabled: Bool = true
    
    private var speedSettingWindowController: SpeedSettingWindowController?
    private var fanCurveWindowController: FanCurveWindowController?
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleCurveSaved), name: NSNotification.Name("FanCurveDidSave"), object: nil)
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateMenu()
            }
        }
    }
    
    @objc private func handleCurveSaved(_ notification: Notification) {
        if let curve = notification.userInfo?["curve"] as? [FanPoint] {
            fanCurve = curve
        }
    }
    
    func updateMenu() {
        guard let statusItem = statusItem else { return }
        
        if let temp = FanManager.shared.readTemperature() {
            currentTemperature = temp
        }
        
        if let rpm = FanManager.shared.readFanRPM() {
            currentFanRPM = rpm
        }
        
        let temperatureText = String(format: "%.0f℃", currentTemperature)
        let fanText = "\(currentFanRPM) RPM"
        let modeText = isAutoMode ? "[Auto]" : "[Manual]"
        
        var statusIcon = ""
        if currentTemperature >= 90.0 {
            statusIcon = " 🔥"
        } else if currentTemperature >= 85.0 {
            statusIcon = " ⚠️"
        }
        
        statusItem.button?.title = "\(temperatureText) | \(fanText) \(modeText)\(statusIcon)"
        
        let menu = NSMenu()
        
        let curveItem = NSMenuItem(title: "风扇曲线编辑器...", action: #selector(showFanCurveEditor), keyEquivalent: "c")
        curveItem.target = self
        menu.addItem(curveItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let modeItem = NSMenuItem(title: isAutoMode ? "手动模式" : "自动模式", action: #selector(toggleMode), keyEquivalent: "m")
        modeItem.target = self
        menu.addItem(modeItem)
        
        if !isAutoMode {
            let speedItem = NSMenuItem(title: "设置转速...", action: #selector(showSpeedSetting), keyEquivalent: "")
            speedItem.target = self
            menu.addItem(speedItem)
        }
        
        let autoStartItem = NSMenuItem(title: "开机自启动", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = autoStartEnabled ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func showFanCurveEditor() {
        fanCurveWindowController = FanCurveWindowController(fanCurve: fanCurve)
        fanCurveWindowController?.showWindow(nil)
    }
    
    @objc func toggleMode() {
        isAutoMode = !isAutoMode
        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.mode = isAutoMode ? "auto" : "manual"
        ConfigManager.shared.saveConfig(newConfig)
        updateMenu()
    }
    
    @objc func toggleAutoStart() {
        autoStartEnabled = !autoStartEnabled
        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.autoStart = autoStartEnabled
        ConfigManager.shared.saveConfig(newConfig)
        updateMenu()
    }
    
    @objc func showSpeedSetting() {
        let config = ConfigManager.shared.loadConfig()
        let currentRPM = config.manualRPM
        speedSettingWindowController = SpeedSettingWindowController(initialRPM: currentRPM)
        speedSettingWindowController?.showWindow(nil)
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    func setFanCurve(_ curve: [FanPoint]) {
        fanCurve = curve
    }
    
    func setIsAutoMode(_ auto: Bool) {
        isAutoMode = auto
    }
    
    func setAutoStartEnabled(_ enabled: Bool) {
        autoStartEnabled = enabled
    }
}

// 应用委托
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = ConfigManager.shared.loadConfig()
        MenuBarManager.shared.setFanCurve(config.curve)
        MenuBarManager.shared.setIsAutoMode(config.mode == "auto")
        MenuBarManager.shared.setAutoStartEnabled(config.autoStart)
        
        MenuBarManager.shared.setupMenuBar()
        
        // 解锁风扇
        FanManager.shared.unlockFans()
        
        // 启动控制循环
        startAutoControlLoop()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        _ = CommandExecutor.shared.setFanAuto()
    }
    
    func startAutoControlLoop() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                let config = ConfigManager.shared.loadConfig()
                let curve = config.curve
                let isAutoMode = config.mode == "auto"
                
                if let temp = FanManager.shared.readTemperature() {
                    if isAutoMode {
                        let targetRPM = FanManager.shared.calculateFanRPM(temperature: temp, curve: curve)
                        
                        if targetRPM == -1 {
                            _ = CommandExecutor.shared.setFanAuto()
                        } else {
                            FanManager.shared.setFanRPM(rpm: targetRPM)
                        }
                    } else {
                        FanManager.shared.setFanRPM(rpm: config.manualRPM)
                    }
                }
            }
        }
    }
}

// 转速设置窗口控制器
@MainActor
class SpeedSettingWindowController: NSWindowController {
    private var currentRPM: Int = 0
    
    init(initialRPM: Int) {
        self.currentRPM = initialRPM
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "设置风扇转速"
        window.center()
        
        super.init(window: window)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        let titleLabel = NSTextField(labelWithString: "手动模式目标转速:")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        let rpmSlider = NSSlider()
        rpmSlider.minValue = 0
        rpmSlider.maxValue = 4900
        rpmSlider.doubleValue = Double(currentRPM)
        rpmSlider.target = self
        rpmSlider.action = #selector(sliderChanged)
        rpmSlider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rpmSlider)
        
        let rpmLabel = NSTextField(labelWithString: "\(currentRPM) RPM")
        rpmLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rpmLabel)
        
        let applyButton = NSButton(title: "应用", target: self, action: #selector(applySpeed))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(applyButton)
        
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            rpmSlider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            rpmSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rpmSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            rpmLabel.topAnchor.constraint(equalTo: rpmSlider.bottomAnchor, constant: 10),
            rpmLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            applyButton.topAnchor.constraint(equalTo: rpmLabel.bottomAnchor, constant: 20),
            applyButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -50),
            
            cancelButton.topAnchor.constraint(equalTo: rpmLabel.bottomAnchor, constant: 20),
            cancelButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 50)
        ])
        
        self.rpmSlider = rpmSlider
        self.rpmLabel = rpmLabel
    }
    
    private var rpmSlider: NSSlider?
    private var rpmLabel: NSTextField?
    
    @objc func sliderChanged() {
        guard let slider = rpmSlider, let label = rpmLabel else { return }
        let rpm = Int(slider.doubleValue)
        label.stringValue = "\(rpm) RPM"
    }
    
    @objc func applySpeed() {
        guard let slider = rpmSlider else { return }
        let rpm = Int(slider.doubleValue)
        
        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.manualRPM = rpm
        ConfigManager.shared.saveConfig(newConfig)
        
        MenuBarManager.shared.setFanCurve(newConfig.curve)
        
        let alert = NSAlert()
        alert.messageText = "设置成功"
        alert.informativeText = "目标转速已设置为 \(rpm) RPM"
        alert.addButton(withTitle: "确定")
        alert.runModal()
        
        window?.close()
    }
    
    @objc func cancel() {
        window?.close()
    }
}

// 主函数
@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
