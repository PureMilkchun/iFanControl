//
//  main.swift
//  MacFanControl
//
//  Created by MacFanControl on 2026-03-17.
//  Copyright © 2026 MacFanControl. All rights reserved.
//

import AppKit
import CryptoKit
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
    private let safetyRPM = 3500
    
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
        let clampedRPM = max(0, min(maxRPM, rpm))

        // 危险温度保护只做托底，不压低用户曲线已经给出的更高转速。
        if temperature >= criticalTemp {
            print("WARNING: Critical temperature (\(temperature)°C)")
            temperatureReadFailureCount = 0
            return max(clampedRPM, safetyRPM)
        }

        return clampedRPM
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

// 自动更新服务
@MainActor
class UpdateService {
    static let shared = UpdateService()

    private let manifestURL = URL(string: "https://ifan-59w.pages.dev/update-manifest.json")!
    private let fallbackZipURL = URL(string: "https://ifan-59w.pages.dev/iFanControl-macOS.zip")!
    private let releasesHomeURL = URL(string: "https://github.com/PureMilkchun/iFanControl/releases")!
    private let lastCheckKey = "ifancontrol.update.last_check"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var isChecking = false

    private var currentShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知版本"
    }

    private var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    var currentVersionDisplay: String {
        "\(currentShortVersion) (\(currentBuild))"
    }

    private struct UpdateManifest: Decodable {
        let latestVersion: String
        let latestBuild: Int
        let publishedAt: String?
        let notes: String?
        let mandatory: Bool?
        let assets: Assets?

        enum CodingKeys: String, CodingKey {
            case latestVersion = "latest_version"
            case latestBuild = "latest_build"
            case publishedAt = "published_at"
            case notes
            case mandatory
            case assets
        }
    }

    private struct Assets: Decodable {
        let zipURL: String?
        let sha256: String?
        let size: Int?

        enum CodingKeys: String, CodingKey {
            case zipURL = "macos_arm64_zip_url"
            case sha256
            case size
        }
    }

    func checkForUpdates(triggeredByUser: Bool) {
        if isChecking { return }
        if !triggeredByUser && !shouldRunScheduledCheck() { return }

        isChecking = true

        Task {
            defer { isChecking = false }

            do {
                let (data, _) = try await URLSession.shared.data(from: manifestURL)
                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
                recordLastCheckNow()

                if manifest.latestBuild <= currentBuild {
                    if triggeredByUser {
                        showInfoAlert(
                            title: "已是最新版本",
                            message: "当前版本：\(currentVersionDisplay)\n远端版本：\(manifest.latestVersion) (\(manifest.latestBuild))"
                        )
                    }
                    return
                }

                presentUpdatePrompt(manifest: manifest)
            } catch {
                if triggeredByUser {
                    showUpdateFailureAlert(title: "检查更新失败", message: error.localizedDescription, releaseURL: releasesHomeURL)
                } else {
                    print("Update check failed: \(error)")
                }
            }
        }
    }

    private func shouldRunScheduledCheck() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= checkInterval
    }

    private func recordLastCheckNow() {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
    }

    private func presentUpdatePrompt(manifest: UpdateManifest) {
        let notes = manifest.notes?.isEmpty == false ? manifest.notes! : "包含稳定性与功能改进。"
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(manifest.latestVersion)"
        alert.informativeText = "当前版本：\(currentVersionDisplay)\n远端版本：\(manifest.latestVersion) (\(manifest.latestBuild))\n\n\(notes)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            startDownloadAndInstall(manifest: manifest)
        }
    }

    private func startDownloadAndInstall(manifest: UpdateManifest) {
        Task {
            do {
                let zipURL = URL(string: manifest.assets?.zipURL ?? "") ?? fallbackZipURL
                let (data, _) = try await URLSession.shared.data(from: zipURL)

                if let expectedSize = manifest.assets?.size, data.count != expectedSize {
                    throw NSError(domain: "UpdateService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "安装包大小校验失败。"])
                }

                if let expectedSHA = manifest.assets?.sha256?.lowercased(), !expectedSHA.isEmpty {
                    let actualSHA = sha256Hex(data)
                    if expectedSHA != actualSHA {
                        throw NSError(domain: "UpdateService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "安装包哈希校验失败。"])
                    }
                }

                let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("iFanControlUpdate", isDirectory: true)
                try? FileManager.default.removeItem(at: stagingDir)
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

                let zipPath = stagingDir.appendingPathComponent("iFanControl-macOS.zip")
                try data.write(to: zipPath, options: .atomic)

                let extractDir = stagingDir.appendingPathComponent("extracted", isDirectory: true)
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
                try unzip(zipPath: zipPath, to: extractDir)

                guard let installScript = findInstallScript(in: extractDir) else {
                    throw NSError(domain: "UpdateService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "未找到 install.sh。"])
                }

                try runInstallScriptInTerminal(scriptURL: installScript)
                showInfoAlert(title: "下载完成", message: "安装脚本已在终端打开，请按提示完成升级。")
            } catch {
                showUpdateFailureAlert(
                    title: "更新失败",
                    message: error.localizedDescription,
                    releaseURL: githubReleaseURL(for: manifest.latestVersion)
                )
            }
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func unzip(zipPath: URL, to outputDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipPath.path, "-d", outputDir.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "UpdateService", code: 1004, userInfo: [NSLocalizedDescriptionKey: "解压安装包失败。"])
        }
    }

    private func findInstallScript(in root: URL) -> URL? {
        let fm = FileManager.default
        let commandURL = root.appendingPathComponent("Install.command")
        if fm.fileExists(atPath: commandURL.path) {
            return commandURL
        }
        if fm.fileExists(atPath: root.appendingPathComponent("install.sh").path) {
            return root.appendingPathComponent("install.sh")
        }
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let file as URL in e {
                if file.lastPathComponent == "Install.command" {
                    return file
                }
                if file.lastPathComponent == "install.sh" {
                    return file
                }
            }
        }
        return nil
    }

    private func runInstallScriptInTerminal(scriptURL: URL) throws {
        let launcherURL = try prepareInstallLauncher(for: scriptURL)

        if NSWorkspace.shared.open(launcherURL) {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", launcherURL.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "UpdateService",
                code: 1005,
                userInfo: [NSLocalizedDescriptionKey: "无法启动安装终端。请手动打开 \(launcherURL.lastPathComponent) 完成升级。"]
            )
        }
    }

    private func prepareInstallLauncher(for scriptURL: URL) throws -> URL {
        let fm = FileManager.default
        if scriptURL.lastPathComponent == "Install.command" {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            return scriptURL
        }

        let launcherURL = scriptURL.deletingLastPathComponent().appendingPathComponent("Install.command")
        let escapedDir = shellQuoted(scriptURL.deletingLastPathComponent().path)
        let escapedScript = shellQuoted(scriptURL.path)
        let launcher = """
        #!/bin/bash
        cd \(escapedDir)
        chmod +x \(escapedScript)
        exec \(escapedScript)
        """
        try launcher.write(to: launcherURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
        return launcherURL
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func githubReleaseURL(for version: String?) -> URL {
        guard let version, !version.isEmpty else {
            return releasesHomeURL
        }
        return URL(string: "https://github.com/PureMilkchun/iFanControl/releases/tag/v\(version)") ?? releasesHomeURL
    }

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关闭")
        alert.runModal()
    }

    private func showUpdateFailureAlert(title: String, message: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(message)\n\n如需手动更新，可前往 GitHub Releases 下载最新版本。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "前往 GitHub")
        alert.addButton(withTitle: "关闭")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
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

        let versionItem = NSMenuItem(title: "当前版本 \(UpdateService.shared.currentVersionDisplay)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())
        
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

        let updateItem = NSMenuItem(title: "检查更新...", action: #selector(checkForUpdates), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)

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
        
        // 实际启用/禁用开机自启动
        if autoStartEnabled {
            enableAutoStart()
        } else {
            disableAutoStart()
        }
        
        updateMenu()
    }
    
    // 启用开机自启动（创建 LaunchAgent）
    private func enableAutoStart() {
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.ifancontrol.app</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Applications/iFanControl.app/Contents/MacOS/iFanControl</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
        
        let plistPath = launchAgentsDir.appendingPathComponent("com.ifancontrol.app.plist")
        
        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        
        // 写入 plist 文件
        do {
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
            print("LaunchAgent plist created at: \(plistPath.path)")
        } catch {
            print("Failed to create LaunchAgent plist: \(error)")
        }
    }
    
    // 禁用开机自启动（删除 LaunchAgent）
    private func disableAutoStart() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
        
        let plistPath = launchAgentsDir.appendingPathComponent("com.ifancontrol.app.plist")
        
        // 删除 plist 文件
        try? FileManager.default.removeItem(at: plistPath)
        print("LaunchAgent plist removed")
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

    @objc func checkForUpdates() {
        UpdateService.shared.checkForUpdates(triggeredByUser: true)
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
        NSApp.setActivationPolicy(.accessory)

        let config = ConfigManager.shared.loadConfig()
        MenuBarManager.shared.setFanCurve(config.curve)
        MenuBarManager.shared.setIsAutoMode(config.mode == "auto")
        MenuBarManager.shared.setAutoStartEnabled(config.autoStart)
        
        MenuBarManager.shared.setupMenuBar()
        
        // 解锁风扇
        FanManager.shared.unlockFans()
        
        // 启动控制循环
        startAutoControlLoop()

        // 启动后延迟进行后台更新检查
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            UpdateService.shared.checkForUpdates(triggeredByUser: false)
        }
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
