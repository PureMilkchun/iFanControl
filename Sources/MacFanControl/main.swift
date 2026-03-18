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

// MARK: - CommandExecutor (特权命令执行器 - 使用 sudoers 免密)
@MainActor
class CommandExecutor {
    static let shared = CommandExecutor()
    private let kentsmcPath = "/usr/local/bin/kentsmc"
    
    // 执行命令（sudo 已配置免密）
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
        return (result.success, result.success ? nil : result.error.isEmpty ? result.output : result.error)
    }
    
    // 设置自动模式
    func setFanAuto() -> (success: Bool, error: String?) {
        let result = executeCommand(args: ["--fan-auto"])
        return (result.success, result.success ? nil : result.error.isEmpty ? result.output : result.error)
    }
    
    // 解锁风扇
    func unlockFans() -> (success: Bool, error: String?) {
        let result = executeCommand(args: ["--unlock-fans"])
        return (result.success, result.success ? nil : result.error.isEmpty ? result.output : result.error)
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
    private var lastExecutionTime: Date?  // 上次执行时间
    private let minExecutionInterval: TimeInterval = 2.0  // 最小执行间隔（秒）
    
    // 温度历史记录（用于趋势检测）
    private var temperatureHistory: [Double] = []
    private let maxHistoryCount: Int = 3
    
    // 动态滞后控制：根据 RPM 调整阈值
    private func getMinRPMChange(currentRPM: Int) -> Int {
        if currentRPM < 1000 {
            return 50   // 低速时更敏感
        } else if currentRPM < 2000 {
            return 75
        } else {
            return 150  // 高速时放宽阈值
        }
    }
    
    // 温度趋势检测：检测快速升温
    private func isRapidTemperatureRise(currentTemp: Double) -> Bool {
        guard temperatureHistory.count >= 2 else { return false }
        
        let recentTemp = temperatureHistory.suffix(2)
        if recentTemp.count == 2 {
            let change = recentTemp[1] - recentTemp[0]
            return change > 3.0  // 2秒内上升超过3℃
        }
        return false
    }
    
    private let criticalTemp: Double = 95.0  // 危险温度阈值（℃）
    private let criticalRPM: Int = 4900  // 危险温度下的最低转速
    
    func readTemperature() -> Double? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        let command = "\(kentsmcPath) -r \(temperatureKey) 2>/dev/null | grep -oE '[0-9]+\\.[0-9]+' | head -1"
        task.arguments = ["-c", command]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               let temp = Double(output) {
                return temp
            }
        } catch {
            print("Error reading temperature: \(error)")
        }
        return nil
    }
    
    func readFanRPM() -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        let command = "\(kentsmcPath) -r F0Ac 2>/dev/null | grep -oE '[0-9]+\\.[0-9]+' | head -1 | cut -d. -f1"
        task.arguments = ["-c", command]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               let rpm = Int(output) {
                return rpm
            }
        } catch {
            print("Error reading fan RPM: \(error)")
        }
        return nil
    }
    
    func setFanRPM(rpm: Int) {
        // 检查时间间隔：确保 ≥2 秒才执行
        if let lastTime = lastExecutionTime,
           Date().timeIntervalSince(lastTime) < minExecutionInterval {
            return
        }
        
        // 动态滞后控制：根据当前 RPM 调整阈值
        let minChange = getMinRPMChange(currentRPM: lastSetRPM)
        let absChange = abs(rpm - lastSetRPM)
        guard absChange >= minChange else {
            return
        }
        
        // 平滑滤波：避免剧烈变化
        let smoothingFactor: Double = 0.3
        let smoothedRPM = Int(Double(lastSetRPM) * (1.0 - smoothingFactor) + Double(rpm) * smoothingFactor)
        
        // 使用 CommandExecutor 执行特权命令
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
    
    // 温度读取失败计数器（用于安全恢复）
    private var temperatureReadFailureCount: Int = 0
    private let maxTemperatureFailures: Int = 5
    
    func calculateFanRPM(temperature: Double, curve: [FanPoint]) -> Int {
        guard !curve.isEmpty else { return 0 }
        
        // 异常保护 1: 温度过高 - 仅在 95℃ 时强制干预
        if temperature >= 95.0 {
            print("WARNING: Critical temperature (\(temperature)°C), forcing 95% fan speed")
            temperatureReadFailureCount = 0
            return Int(4900 * 0.95)
        }
        
        // 异常保护 2: 温度读取失败（NaN 或负数）
        if temperature.isNaN || temperature < 0 {
            temperatureReadFailureCount += 1
            print("WARNING: Invalid temperature (\(temperature)), failure count: \(temperatureReadFailureCount)")
            
            if temperatureReadFailureCount >= maxTemperatureFailures {
                print("CRITICAL: Too many temperature read failures, switching to safe mode")
                return -1
            }
            
            return lastSetRPM
        }
        
        // 温度读取成功，重置计数器
        temperatureReadFailureCount = 0
        
        // 记录温度历史（用于趋势检测）
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
        
        // 如果温度超出曲线范围
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
        // 优先从用户目录读取配置
        if let data = try? Data(contentsOf: configFile),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        
        // 从 app bundle 的 Resources 目录读取默认配置
        if let bundleConfigURL = Bundle.main.url(forResource: "config", withExtension: "json"),
           let data = try? Data(contentsOf: bundleConfigURL),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        
        // 使用内置默认配置
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
    
    // 强引用持有窗口控制器，防止被释放
    private var speedSettingWindowController: SpeedSettingWindowController?
    private var fanCurveWindowController: FanCurveWindowController?
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        
        // 监听曲线编辑器保存通知
        NotificationCenter.default.addObserver(self, selector: #selector(handleCurveSaved), name: NSNotification.Name("FanCurveDidSave"), object: nil)
        
        // 定时更新
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
        
        // 读取温度和风扇状态
        if let temp = FanManager.shared.readTemperature() {
            currentTemperature = temp
        }
        
        if let rpm = FanManager.shared.readFanRPM() {
            currentFanRPM = rpm
        }
        
        // 更新显示
        let temperatureText = String(format: "%.0f℃", currentTemperature)
        let fanText = "\(currentFanRPM) RPM"
        
        // 添加模式状态
        let modeText = isAutoMode ? "[Auto]" : "[Manual]"
        
        // 添加状态提示（高温警告）
        var statusIcon = ""
        if currentTemperature >= 90.0 {
            statusIcon = " 🔥"
        } else if currentTemperature >= 85.0 {
            statusIcon = " ⚠️"
        }
        
        statusItem.button?.title = "\(temperatureText) | \(fanText) \(modeText)\(statusIcon)"
        
        // 创建菜单
        let menu = NSMenu()
        
        // 风扇曲线编辑器
        let curveItem = NSMenuItem(title: "风扇曲线编辑器...", action: #selector(showFanCurveEditor), keyEquivalent: "c")
        curveItem.target = self
        menu.addItem(curveItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 手动/自动模式
        let modeItem = NSMenuItem(title: isAutoMode ? "手动模式" : "自动模式", action: #selector(toggleMode), keyEquivalent: "m")
        modeItem.target = self
        menu.addItem(modeItem)
        
        // 手动模式下显示转速设置
        if !isAutoMode {
            let speedItem = NSMenuItem(title: "设置转速...", action: #selector(showSpeedSetting), keyEquivalent: "")
            speedItem.target = self
            menu.addItem(speedItem)
        }
        
        // 开机自启动
        let autoStartItem = NSMenuItem(title: "开机自启动", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = autoStartEnabled ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 退出
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
        // 加载配置并更新菜单栏管理器
        let config = ConfigManager.shared.loadConfig()
        MenuBarManager.shared.setFanCurve(config.curve)
        MenuBarManager.shared.setIsAutoMode(config.mode == "auto")
        MenuBarManager.shared.setAutoStartEnabled(config.autoStart)
        
        // 设置菜单栏
        MenuBarManager.shared.setupMenuBar()
        
        // 直接解锁风扇（无需密码，已通过 sudoers 配置免密）
        FanManager.shared.unlockFans()
        
        // 启动自动控制循环
        startAutoControlLoop()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 应用退出时恢复自动风扇模式
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
                            // 安全模式：恢复自动风扇
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
