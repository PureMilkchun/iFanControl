//
//  main.swift
//  MacFanControl
//
//  使用 launchd 守护进程通信，无需 sudo
//

import AppKit
import Foundation
import FanCurveEditor

typealias FanPoint = FanCurveEditor.FanPoint
typealias Config = FanCurveEditor.Config

// MARK: - 守护进程通信
@MainActor
class CommandExecutor {
    static let shared = CommandExecutor()
    private let commandPipe = "/tmp/mfc_command"
    private let resultFile = "/tmp/mfc_result"
    
    // 发送命令到守护进程（internal 供 FanManager 使用）
    func sendCommand(_ command: String) -> String? {
        // 清理旧的结果
        try? FileManager.default.removeItem(atPath: resultFile)
        
        // 发送命令到命名管道
        guard FileManager.default.fileExists(atPath: commandPipe) else {
            print("Error: Daemon not running (pipe not found)")
            return nil
        }
        
        // 写入命令（阻塞直到守护进程读取）
        if let fileHandle = FileHandle(forWritingAtPath: commandPipe) {
            if let data = (command + "\n").data(using: .utf8) {
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        }
        
        // 等待结果（最多 2 秒）
        var attempts = 0
        while !FileManager.default.fileExists(atPath: resultFile) && attempts < 20 {
            Thread.sleep(forTimeInterval: 0.1)
            attempts += 1
        }
        
        // 读取结果
        if let data = try? Data(contentsOf: URL(fileURLWithPath: resultFile)),
           let result = String(data: data, encoding: .utf8) {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    // 检查守护进程是否运行
    func isDaemonRunning() -> Bool {
        let result = sendCommand("ping")
        return result == "pong"
    }
    
    // 设置风扇转速
    func setFanRPM(rpm: Int) -> (success: Bool, error: String?) {
        guard let result = sendCommand("set_rpm_\(rpm)") else {
            return (false, "守护进程未响应")
        }
        return (true, nil)
    }
    
    // 设置自动模式
    func setFanAuto() -> (success: Bool, error: String?) {
        guard let result = sendCommand("set_auto") else {
            return (false, "守护进程未响应")
        }
        return (true, nil)
    }
    
    // 解锁风扇
    func unlockFans() -> (success: Bool, error: String?) {
        guard let result = sendCommand("unlock_fans") else {
            return (false, "守护进程未响应")
        }
        return (true, nil)
    }
}

// MARK: - 风扇管理器
@MainActor
class FanManager {
    static let shared = FanManager()
    
    private var lastSetRPM: Int = 0
    private var lastExecutionTime: Date?
    private let minExecutionInterval: TimeInterval = 2.0
    private var temperatureHistory: [Double] = []
    private let maxHistoryCount: Int = 3
    private let maxRPM = 4900
    
    private func getMinRPMChange(currentRPM: Int) -> Int {
        if currentRPM < 1000 { return 50 }
        else if currentRPM < 2000 { return 75 }
        else { return 150 }
    }
    
    func readTemperature() -> Double? {
        if let result = CommandExecutor.shared.sendCommand("read_temp"),
           let temp = Double(result) {
            return temp
        }
        return nil
    }
    
    func readFanRPM() -> Int? {
        if let result = CommandExecutor.shared.sendCommand("read_rpm"),
           let rpm = Int(result) {
            return rpm
        }
        return nil
    }
    
    func setFanRPM(rpm: Int) {
        if let lastTime = lastExecutionTime,
           Date().timeIntervalSince(lastTime) < minExecutionInterval {
            return
        }
        
        let minChange = getMinRPMChange(currentRPM: lastSetRPM)
        let absChange = abs(rpm - lastSetRPM)
        guard absChange >= minChange else { return }
        
        let smoothingFactor: Double = 0.3
        let smoothedRPM = Int(Double(lastSetRPM) * (1.0 - smoothingFactor) + Double(rpm) * smoothingFactor)
        
        let result = CommandExecutor.shared.setFanRPM(rpm: smoothedRPM)
        
        if result.success {
            lastSetRPM = smoothedRPM
            lastExecutionTime = Date()
        }
    }
    
    func unlockFans() {
        _ = CommandExecutor.shared.unlockFans()
    }
    
    private var temperatureReadFailureCount: Int = 0
    private let maxTemperatureFailures: Int = 5
    
    func calculateFanRPM(temperature: Double, curve: [FanPoint]) -> Int {
        guard !curve.isEmpty else { return 0 }
        
        if temperature >= 95.0 {
            temperatureReadFailureCount = 0
            return Int(4900 * 0.95)
        }
        
        if temperature.isNaN || temperature < 0 {
            temperatureReadFailureCount += 1
            if temperatureReadFailureCount >= maxTemperatureFailures {
                return -1
            }
            return 0
        }
        
        temperatureReadFailureCount = 0
        temperatureHistory.append(temperature)
        if temperatureHistory.count > maxHistoryCount {
            temperatureHistory.removeFirst()
        }
        
        var lowerPoint = curve[0]
        var upperPoint = curve.last!
        
        for i in 0..<curve.count - 1 {
            if temperature >= curve[i].temperature && temperature <= curve[i + 1].temperature {
                lowerPoint = curve[i]
                upperPoint = curve[i + 1]
                break
            }
        }
        
        if temperature < lowerPoint.temperature { return lowerPoint.rpm }
        if temperature > upperPoint.temperature { return upperPoint.rpm }
        
        if upperPoint.temperature == lowerPoint.temperature { return lowerPoint.rpm }
        
        let ratio = (temperature - lowerPoint.temperature) / (upperPoint.temperature - lowerPoint.temperature)
        let rpm = Int(Double(lowerPoint.rpm) + ratio * Double(upperPoint.rpm - lowerPoint.rpm))
        
        return max(0, min(maxRPM, rpm))
    }
}

// MARK: - 配置管理器
@MainActor
class ConfigManager {
    static let shared = ConfigManager()
    private let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MacFanControl")
    private let configFile: URL
    
    init() {
        configFile = configDir.appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    func loadConfig() -> Config {
        if let data = try? Data(contentsOf: configFile),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        
        if let bundleURL = Bundle.main.url(forResource: "config", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
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
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configFile)
        }
    }
}

// MARK: - 菜单栏管理
@MainActor
class MenuBarManager {
    static let shared = MenuBarManager()
    private var statusItem: NSStatusItem?
    private var currentTemperature: Double = 0
    private var currentFanRPM: Int = 0
    private var fanCurve: [FanPoint] = []
    private var isAutoMode: Bool = true
    private var autoStartEnabled: Bool = true
    
    private var fanCurveWindowController: FanCurveWindowController?
    private var speedSettingWindowController: SpeedSettingWindowController?
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleCurveSaved), name: NSNotification.Name("FanCurveDidSave"), object: nil)
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in self.updateMenu() }
        }
    }
    
    @objc private func handleCurveSaved(_ notification: Notification) {
        if let curve = notification.userInfo?["curve"] as? [FanPoint] {
            fanCurve = curve
        }
    }
    
    func updateMenu() {
        guard let statusItem = statusItem else { return }
        
        if let temp = FanManager.shared.readTemperature() { currentTemperature = temp }
        if let rpm = FanManager.shared.readFanRPM() { currentFanRPM = rpm }
        
        let temperatureText = String(format: "%.0f℃", currentTemperature)
        let fanText = "\(currentFanRPM) RPM"
        let modeText = isAutoMode ? "[Auto]" : "[Manual]"
        
        var statusIcon = ""
        if currentTemperature >= 90.0 { statusIcon = " 🔥" }
        else if currentTemperature >= 85.0 { statusIcon = " ⚠️" }
        
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
        speedSettingWindowController = SpeedSettingWindowController(initialRPM: config.manualRPM)
        speedSettingWindowController?.showWindow(nil)
    }
    
    @objc func quitApp() { NSApp.terminate(nil) }
    
    func setFanCurve(_ curve: [FanPoint]) { fanCurve = curve }
    func setIsAutoMode(_ auto: Bool) { isAutoMode = auto }
    func setAutoStartEnabled(_ enabled: Bool) { autoStartEnabled = enabled }
}

// MARK: - 应用委托
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

// MARK: - 转速设置窗口
@MainActor
class SpeedSettingWindowController: NSWindowController {
    private var currentRPM: Int = 0
    private var rpmSlider: NSSlider?
    private var rpmLabel: NSTextField?
    
    init(initialRPM: Int) {
        self.currentRPM = initialRPM
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "设置风扇转速"
        window.center()
        super.init(window: window)
        setupUI()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        let titleLabel = NSTextField(labelWithString: "手动模式目标转速:")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        let slider = NSSlider(value: Double(currentRPM), minValue: 0, maxValue: 4900, target: self, action: #selector(sliderChanged))
        slider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(slider)
        
        let label = NSTextField(labelWithString: "\(currentRPM) RPM")
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        
        let applyButton = NSButton(title: "应用", target: self, action: #selector(applySpeed))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(applyButton)
        
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 10),
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            applyButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
            applyButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -50),
            cancelButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
            cancelButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 50)
        ])
        
        self.rpmSlider = slider
        self.rpmLabel = label
    }
    
    @objc func sliderChanged() {
        guard let slider = rpmSlider, let label = rpmLabel else { return }
        label.stringValue = "\(Int(slider.doubleValue)) RPM"
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
    
    @objc func cancel() { window?.close() }
}

// MARK: - 主函数
@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
