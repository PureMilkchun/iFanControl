//
//  main.swift
//  iFanControl
//
//  Created by iFanControl on 2026-03-17.
//  Copyright © 2026 iFanControl. All rights reserved.
//

import AppKit
import CryptoKit
import Foundation
import FanCurveEditor
import OSLog

// 使用 FanCurveEditor 中的类型
typealias FanPoint = FanCurveEditor.FanPoint
typealias Config = FanCurveEditor.Config

struct TemperatureReading {
    let sensor: TemperatureSensorDefinition
    let value: Double
}

struct FanInfo {
    let index: Int
    let actualKey: String
    let minRPM: Int?
    let maxRPM: Int?
}

private let appSubsystem = Bundle.main.bundleIdentifier ?? "com.ifancontrol.app"

@MainActor
private func presentWindowFront(_ window: NSWindow?) {
    guard let window else { return }
    NSApp.activate(ignoringOtherApps: true)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}

@MainActor
private func applyWindowMaterialStyle(_ window: NSWindow?) {
    guard let window, let contentView = window.contentView else { return }

    window.titlebarAppearsTransparent = false
    window.isMovableByWindowBackground = false
    window.backgroundColor = .windowBackgroundColor

    for subview in contentView.subviews where subview.identifier?.rawValue == "ifancontrol.material" {
        subview.removeFromSuperview()
    }
}

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
    let defaultSafetyRPM = 3500
    private let fallbackMaxRPM = 4900
    private let telemetryRefreshInterval: TimeInterval = 1.0
    private let validTemperatureRange = 0.0...120.0
    
    private(set) var fanCount: Int = 0
    private(set) var fans: [FanInfo] = []
    private(set) var availableTemperatureSensors: [TemperatureSensorDefinition] = []
    private(set) var currentMaxRPM: Int = 4900
    
    private var cachedTemperatures: [String: Double] = [:]
    private var cachedFanRPMs: [Int: Int] = [:]
    private var lastTelemetryRefresh: Date?
    private var hasProbedHardware = false
    private let logger = Logger(subsystem: appSubsystem, category: "Hardware")
    
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
    
    private func executeReadCommand(args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: kentsmcPath)
        task.arguments = args
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Error executing kentsmc read command: \(error)")
        }
        return nil
    }
    
    private func readNumericValue(forKey key: String) -> Double? {
        guard let output = executeReadCommand(args: ["-r", key]) else {
            return nil
        }

        if let range = output.range(of: "\\((-?\\d+(?:\\.\\d+)?)\\)", options: .regularExpression) {
            let wrapped = output[range]
            let numeric = wrapped.dropFirst().dropLast()
            return Double(numeric)
        }
        return nil
    }

    private func readTemperatureValue(forKey key: String) -> Double? {
        guard let value = readNumericValue(forKey: key), validTemperatureRange.contains(value) else {
            return nil
        }
        return value
    }

    private func readIntValue(forKey key: String) -> Int? {
        guard let value = readNumericValue(forKey: key) else {
            return nil
        }
        return Int(value.rounded())
    }

    private func buildFanList(fanCount: Int) -> [FanInfo] {
        guard fanCount > 0 else { return [] }
        return (0..<fanCount).compactMap { index in
            let actualKey = "F\(index)Ac"
            guard readNumericValue(forKey: actualKey) != nil else {
                return nil
            }
            return FanInfo(
                index: index,
                actualKey: actualKey,
                minRPM: readIntValue(forKey: "F\(index)Mn"),
                maxRPM: readIntValue(forKey: "F\(index)Mx")
            )
        }
    }

    private func determineGlobalMaxRPM(from fans: [FanInfo]) -> Int {
        let candidateMaxima = fans.compactMap { info -> Int? in
            guard let maxRPM = info.maxRPM, maxRPM > 0 else {
                return nil
            }
            return maxRPM
        }

        guard !candidateMaxima.isEmpty else {
            return fallbackMaxRPM
        }
        return candidateMaxima.min() ?? fallbackMaxRPM
    }

    func probeHardwareIfNeeded() {
        guard !hasProbedHardware else { return }
        refreshHardwareProfile()
    }

    func refreshHardwareProfile() {
        hasProbedHardware = true
        fanCount = readIntValue(forKey: "FNum") ?? 0
        fans = buildFanList(fanCount: fanCount)

        if fans.isEmpty, let rpm = readIntValue(forKey: "F0Ac"), rpm >= 0 {
            fans = [
                FanInfo(
                    index: 0,
                    actualKey: "F0Ac",
                    minRPM: readIntValue(forKey: "F0Mn"),
                    maxRPM: readIntValue(forKey: "F0Mx")
                )
            ]
            fanCount = 1
        }

        currentMaxRPM = determineGlobalMaxRPM(from: fans)

        var discoveredSensors: [TemperatureSensorDefinition] = []
        for sensor in SensorCatalog.appleSiliconTemperatureSensors {
            if readTemperatureValue(forKey: sensor.key) != nil {
                discoveredSensors.append(sensor)
            }
        }

        availableTemperatureSensors = Array(Set(discoveredSensors)).sorted {
            if $0.name == $1.name {
                return $0.key < $1.key
            }
            return $0.name < $1.name
        }

        logger.info("Hardware profile refreshed: fans=\(self.fanCount, privacy: .public) sensors=\(self.availableTemperatureSensors.count, privacy: .public) maxRPM=\(self.currentMaxRPM, privacy: .public)")

        refreshTelemetry(force: true)
    }

    func refreshTelemetry(force: Bool = false) {
        probeHardwareIfNeeded()

        if !force,
           let lastTelemetryRefresh,
           Date().timeIntervalSince(lastTelemetryRefresh) < telemetryRefreshInterval {
            return
        }

        var nextTemperatures: [String: Double] = [:]
        for sensor in availableTemperatureSensors {
            if let value = readTemperatureValue(forKey: sensor.key) {
                nextTemperatures[sensor.key] = value
            }
        }
        if !nextTemperatures.isEmpty {
            cachedTemperatures = nextTemperatures
        }

        var nextFanRPMs: [Int: Int] = [:]
        for fan in fans {
            if let rpm = readIntValue(forKey: fan.actualKey), rpm >= 0 {
                nextFanRPMs[fan.index] = rpm
            }
        }
        if !nextFanRPMs.isEmpty {
            cachedFanRPMs = nextFanRPMs
        }

        lastTelemetryRefresh = Date()
    }

    func availableTemperatureReadings() -> [TemperatureReading] {
        refreshTelemetry()
        return availableTemperatureSensors.compactMap { sensor in
            guard let value = cachedTemperatures[sensor.key] else {
                return nil
            }
            return TemperatureReading(sensor: sensor, value: value)
        }.sorted { lhs, rhs in
            if lhs.sensor.sortKey != rhs.sensor.sortKey {
                return lhs.sensor.sortKey < rhs.sensor.sortKey
            }
            return lhs.value > rhs.value
        }
    }

    func currentTemperatureReading(using config: Config) -> TemperatureReading? {
        let readings = availableTemperatureReadings()
        guard !readings.isEmpty else {
            return nil
        }

        if config.temperatureSourceMode == "manual",
           let selectedKey = config.selectedTemperatureSensorKey,
           let selected = readings.first(where: { $0.sensor.key == selectedKey }) {
            return selected
        }

        return readings.max(by: { $0.value < $1.value })
    }

    func readPrimaryFanRPM() -> Int? {
        refreshTelemetry()
        return cachedFanRPMs.values.max()
    }
    
    func setFanRPM(rpm: Int) {
        let boundedTarget = max(0, min(currentMaxRPM, rpm))

        // 检查时间间隔
        if let lastTime = lastExecutionTime,
           Date().timeIntervalSince(lastTime) < minExecutionInterval {
            return
        }
        
        // 动态滞后控制
        let minChange = getMinRPMChange(currentRPM: lastSetRPM)
        let absChange = abs(boundedTarget - lastSetRPM)
        guard absChange >= minChange else {
            return
        }
        
        // 平滑滤波
        let smoothingFactor: Double = 0.3
        let smoothedRPM = Int(Double(lastSetRPM) * (1.0 - smoothingFactor) + Double(boundedTarget) * smoothingFactor)
        
        let result = CommandExecutor.shared.setFanRPM(rpm: smoothedRPM)
        
        if result.success {
            lastSetRPM = smoothedRPM
            lastExecutionTime = Date()
        } else {
            print("Error setting fan RPM: \(result.error ?? "Unknown error")")
        }
    }
    
    func unlockFans() {
        guard fanCount > 0 else {
            return
        }
        let result = CommandExecutor.shared.unlockFans()
        if !result.success {
            print("Error unlocking fans: \(result.error ?? "Unknown error")")
        }
    }
    
    // 温度读取失败计数器
    private var temperatureReadFailureCount: Int = 0
    private let maxTemperatureFailures: Int = 5
    
    func calculateFanRPM(temperature: Double, curve: [FanPoint], safetyFloorRPM: Int) -> Int {
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
        let clampedRPM = max(0, min(currentMaxRPM, rpm))

        // 危险温度保护只做托底，不压低用户曲线已经给出的更高转速。
        if temperature >= criticalTemp {
            print("WARNING: Critical temperature (\(temperature)°C)")
            temperatureReadFailureCount = 0
            return max(clampedRPM, safetyFloorRPM)
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
                FanPoint(temperature: 100, rpm: FanManager.shared.currentMaxRPM)
            ],
            mode: "auto",
            autoStart: true,
            maxRPM: FanManager.shared.currentMaxRPM,
            manualRPM: min(2168, FanManager.shared.currentMaxRPM),
            safetyFloorRPM: min(FanManager.shared.defaultSafetyRPM, FanManager.shared.currentMaxRPM),
            temperatureSourceMode: "hottest",
            selectedTemperatureSensorKey: nil
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

    func syncHardwareProfile(maxRPM: Int) -> Config {
        var config = loadConfig()
        config.maxRPM = maxRPM
        config.manualRPM = min(config.manualRPM, maxRPM)
        let boundedDefaultSafety = min(FanManager.shared.defaultSafetyRPM, maxRPM)
        config.safetyFloorRPM = min(max(config.safetyFloorRPM ?? boundedDefaultSafety, 2000), maxRPM)

        if config.temperatureSourceMode == nil {
            config.temperatureSourceMode = "hottest"
        }

        saveConfig(config)
        return config
    }
}

// 自动更新服务
@MainActor
class UpdateService {
    static let shared = UpdateService()
    private let logger = Logger(subsystem: appSubsystem, category: "Updater")

    private let manifestURL = URL(string: "https://ifan-59w.pages.dev/update-manifest.json")!
    private let fallbackZipURL = URL(string: "https://ifan-59w.pages.dev/iFanControl-macOS.zip")!
    private let releasesHomeURL = URL(string: "https://github.com/PureMilkchun/iFanControl/releases")!
    private let lastCheckKey = "ifancontrol.update.last_check"
    private let automaticCheckEnabledKey = "ifancontrol.update.automatic_check_enabled"
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

    var releasesURL: URL {
        releasesHomeURL
    }

    var automaticChecksEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: automaticCheckEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: automaticCheckEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: automaticCheckEnabledKey)
            logger.info("Automatic update checks toggled. enabled=\(newValue, privacy: .public)")
        }
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
        logger.info("Starting update check. triggeredByUser=\(triggeredByUser, privacy: .public)")

        Task {
            defer { isChecking = false }

            do {
                let (data, _) = try await URLSession.shared.data(from: manifestURL)
                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
                recordLastCheckNow()

                if manifest.latestBuild <= currentBuild {
                    self.logger.info("No update available. currentBuild=\(self.currentBuild, privacy: .public) remoteBuild=\(manifest.latestBuild, privacy: .public)")
                    if triggeredByUser {
                        showInfoAlert(
                            title: "已是最新版本",
                            message: "当前版本：\(currentVersionDisplay)\n远端版本：\(manifest.latestVersion) (\(manifest.latestBuild))"
                        )
                    }
                    return
                }

                self.logger.info("Update available. currentBuild=\(self.currentBuild, privacy: .public) remoteBuild=\(manifest.latestBuild, privacy: .public)")
                presentUpdatePrompt(manifest: manifest)
            } catch {
                self.logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                if triggeredByUser {
                    showUpdateFailureAlert(title: "检查更新失败", message: error.localizedDescription, releaseURL: releasesHomeURL)
                } else {
                    print("Update check failed: \(error)")
                }
            }
        }
    }

    private func shouldRunScheduledCheck() -> Bool {
        guard automaticChecksEnabled else {
            return false
        }
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
                logger.info("Downloading update archive from \(zipURL.absoluteString, privacy: .public)")
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
                logger.info("Update installer launched successfully for version \(manifest.latestVersion, privacy: .public)")
                showInfoAlert(title: "下载完成", message: "安装脚本已在终端打开，请按提示完成升级。")
            } catch {
                logger.error("Update download/install failed: \(error.localizedDescription, privacy: .public)")
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
    private let logger = Logger(subsystem: appSubsystem, category: "MenuBar")
    private let unsupportedHardwareHintKey = "ifancontrol.ui.unsupported_hardware_hint_shown"
    private let temperatureSourceHintKey = "ifancontrol.ui.temperature_source_hint_shown"
    private var statusItem: NSStatusItem?
    private var currentTemperature: Double = 0
    private var currentFanRPM: Int = 0
    private var currentTemperatureSensorName: String = "自动选择（最热）"
    private var fanCurve: [FanPoint] = []
    private var isAutoMode: Bool = true
    private var autoStartEnabled: Bool = true
    
    private var speedSettingWindowController: SpeedSettingWindowController?
    private var safetyFloorWindowController: SafetyFloorWindowController?
    private var fanCurveWindowController: FanCurveWindowController?
    private var helpWindowController: HelpWindowController?

    private func groupedTemperatureReadings(_ readings: [TemperatureReading]) -> [(category: TemperatureSensorCategory, readings: [TemperatureReading])] {
        TemperatureSensorCategory.allCases.compactMap { category in
            let grouped = readings.filter { $0.sensor.category == category }
            guard !grouped.isEmpty else { return nil }
            return (category, grouped)
        }
    }

    private func shortTitle(for reading: TemperatureReading, index: Int) -> String {
        String(format: "%@ %02d  %.0f℃", reading.sensor.compactName, index + 1, reading.value)
    }

    private func selectionSummary(for reading: TemperatureReading, in readings: [TemperatureReading], automatic: Bool) -> String {
        let grouped = groupedTemperatureReadings(readings)
        for (_, sectionReadings) in grouped {
            if let index = sectionReadings.firstIndex(where: { $0.sensor.key == reading.sensor.key }) {
                let base = "\(reading.sensor.compactName) \(String(format: "%02d", index + 1))"
                return automatic ? "自动 / \(base)" : "手动 / \(base)"
            }
        }
        return automatic ? "自动 / \(reading.sensor.key)" : "手动 / \(reading.sensor.key)"
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleCurveSaved), name: NSNotification.Name("FanCurveDidSave"), object: nil)
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateMenu()
            }
        }

        maybeShowStartupGuidance()
    }
    
    @objc private func handleCurveSaved(_ notification: Notification) {
        if let curve = notification.userInfo?["curve"] as? [FanPoint] {
            fanCurve = curve
        }
    }
    
    func updateMenu() {
        guard let statusItem = statusItem else { return }

        let config = ConfigManager.shared.loadConfig()
        FanManager.shared.refreshTelemetry()
        let readings = FanManager.shared.availableTemperatureReadings()

        if let reading = FanManager.shared.currentTemperatureReading(using: config) {
            currentTemperature = reading.value
            currentTemperatureSensorName = selectionSummary(for: reading, in: readings, automatic: config.temperatureSourceMode != "manual")
        }

        if let rpm = FanManager.shared.readPrimaryFanRPM() {
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

        let hardwareItem = NSMenuItem(
            title: FanManager.shared.fanCount > 0 ?
                "风扇 \(FanManager.shared.fanCount) | 上限 \(FanManager.shared.currentMaxRPM)" :
                "无可控风扇",
            action: nil,
            keyEquivalent: ""
        )
        hardwareItem.isEnabled = false
        menu.addItem(hardwareItem)

        let currentSensorItem = NSMenuItem(title: "温度源 \(currentTemperatureSensorName)", action: nil, keyEquivalent: "")
        currentSensorItem.isEnabled = false
        menu.addItem(currentSensorItem)
        menu.addItem(NSMenuItem.separator())

        let temperatureSourceItem = NSMenuItem(title: "选择温度源", action: nil, keyEquivalent: "")
        let temperatureSourceMenu = NSMenu()

        let hottestItem = NSMenuItem(title: "自动选择（最热）", action: #selector(selectAutomaticTemperatureSource), keyEquivalent: "")
        hottestItem.target = self
        hottestItem.state = config.temperatureSourceMode == "manual" ? .off : .on
        temperatureSourceMenu.addItem(hottestItem)

        if !readings.isEmpty {
            temperatureSourceMenu.addItem(NSMenuItem.separator())
            for section in groupedTemperatureReadings(readings) {
                let header = NSMenuItem(title: section.category.title, action: nil, keyEquivalent: "")
                header.isEnabled = false
                temperatureSourceMenu.addItem(header)

                for (index, reading) in section.readings.enumerated() {
                    let item = NSMenuItem(
                        title: shortTitle(for: reading, index: index),
                        action: #selector(selectTemperatureSource(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.toolTip = "\(reading.sensor.name) (\(reading.sensor.key))  \(String(format: "%.1f℃", reading.value))"
                    item.representedObject = reading.sensor.key
                    item.state = (config.temperatureSourceMode == "manual" && config.selectedTemperatureSensorKey == reading.sensor.key) ? .on : .off
                    temperatureSourceMenu.addItem(item)
                }

                temperatureSourceMenu.addItem(NSMenuItem.separator())
            }

            if temperatureSourceMenu.items.last?.isSeparatorItem == true {
                temperatureSourceMenu.removeItem(at: temperatureSourceMenu.items.count - 1)
            }
        }

        if readings.isEmpty {
            let emptyItem = NSMenuItem(title: "暂未探测到温度传感器", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            temperatureSourceMenu.addItem(emptyItem)
        }

        menu.setSubmenu(temperatureSourceMenu, for: temperatureSourceItem)
        menu.addItem(temperatureSourceItem)
        
        let curveItem = NSMenuItem(title: "编辑曲线...", action: #selector(showFanCurveEditor), keyEquivalent: "c")
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

        let safetyFloorItem = NSMenuItem(title: "安全兜底转速...", action: #selector(showSafetyFloorSetting), keyEquivalent: "")
        safetyFloorItem.target = self
        menu.addItem(safetyFloorItem)

        let aboutItem = NSMenuItem(title: "关于 iFanControl...", action: #selector(showHelp), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "重新启动", action: #selector(restartApp), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func showFanCurveEditor() {
        fanCurveWindowController = FanCurveWindowController(fanCurve: fanCurve, maxRPM: FanManager.shared.currentMaxRPM)
        fanCurveWindowController?.showWindow(nil)
        presentWindowFront(fanCurveWindowController?.window)
    }
    
    @objc func toggleMode() {
        isAutoMode = !isAutoMode
        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.mode = isAutoMode ? "auto" : "manual"
        ConfigManager.shared.saveConfig(newConfig)
        logger.info("Control mode switched to \(newConfig.mode, privacy: .public)")
        updateMenu()
    }
    
    @objc func toggleAutoStart() {
        autoStartEnabled = !autoStartEnabled
        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.autoStart = autoStartEnabled
        ConfigManager.shared.saveConfig(newConfig)
        logger.info("Auto start toggled. enabled=\(self.autoStartEnabled, privacy: .public)")
        
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
        let currentRPM = min(config.manualRPM, FanManager.shared.currentMaxRPM)
        speedSettingWindowController = SpeedSettingWindowController(initialRPM: currentRPM, maxRPM: FanManager.shared.currentMaxRPM)
        speedSettingWindowController?.showWindow(nil)
        presentWindowFront(speedSettingWindowController?.window)
    }

    @objc func showSafetyFloorSetting() {
        let config = ConfigManager.shared.loadConfig()
        let currentRPM = min(max(config.safetyFloorRPM ?? FanManager.shared.defaultSafetyRPM, 2000), FanManager.shared.currentMaxRPM)
        safetyFloorWindowController = SafetyFloorWindowController(initialRPM: currentRPM, maxRPM: FanManager.shared.currentMaxRPM)
        safetyFloorWindowController?.showWindow(nil)
        presentWindowFront(safetyFloorWindowController?.window)
    }

    @objc func selectAutomaticTemperatureSource() {
        var config = ConfigManager.shared.loadConfig()
        config.temperatureSourceMode = "hottest"
        config.selectedTemperatureSensorKey = nil
        ConfigManager.shared.saveConfig(config)
        logger.info("Temperature source switched to automatic hottest sensor")
        updateMenu()
    }

    @objc func selectTemperatureSource(_ sender: NSMenuItem) {
        guard let selectedKey = sender.representedObject as? String else {
            return
        }

        var config = ConfigManager.shared.loadConfig()
        config.temperatureSourceMode = "manual"
        config.selectedTemperatureSensorKey = selectedKey
        ConfigManager.shared.saveConfig(config)
        logger.info("Temperature source switched to sensor key \(selectedKey, privacy: .public)")
        updateMenu()
    }

    private func maybeShowStartupGuidance() {
        let defaults = UserDefaults.standard

        if FanManager.shared.fanCount == 0 && !defaults.bool(forKey: unsupportedHardwareHintKey) {
            defaults.set(true, forKey: unsupportedHardwareHintKey)
            let alert = NSAlert()
            alert.messageText = "未检测到可控风扇"
            alert.informativeText = "这台设备可能是无风扇机型，或当前硬件暂不支持手动风扇控制。应用会继续运行，但不会尝试强制控制风扇。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "知道了")
            logger.warning("No controllable fans detected on startup")
            alert.runModal()
            return
        }

        let readings = FanManager.shared.availableTemperatureReadings()
        if readings.count > 1 && !defaults.bool(forKey: temperatureSourceHintKey) {
            defaults.set(true, forKey: temperatureSourceHintKey)
            let alert = NSAlert()
            alert.messageText = "温度源已自动选择"
            alert.informativeText = "默认会使用当前最热的温度传感器来驱动风扇曲线。这里显示的是这台机器真实可读到的温度传感器，不一定与 CPU/GPU 核心数量一一对应。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "知道了")
            logger.info("Displayed first-run temperature source guidance")
            alert.runModal()
        }
    }

    @objc func showHelp() {
        if helpWindowController == nil {
            helpWindowController = HelpWindowController()
        }
        helpWindowController?.showWindow(nil)
        presentWindowFront(helpWindowController?.window)
    }

    @objc func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path]

        do {
            try process.run()
            logger.info("Application restart requested")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        } catch {
            logger.error("Failed to restart app: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "无法重新启动"
            alert.informativeText = "请手动重新打开 iFanControl。\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "关闭")
            alert.runModal()
        }
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

        FanManager.shared.refreshHardwareProfile()
        let config = ConfigManager.shared.syncHardwareProfile(maxRPM: FanManager.shared.currentMaxRPM)
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

                guard let reading = FanManager.shared.currentTemperatureReading(using: config) else {
                    return
                }

                if isAutoMode {
                    let safetyFloorRPM = min(max(config.safetyFloorRPM ?? FanManager.shared.defaultSafetyRPM, 2000), FanManager.shared.currentMaxRPM)
                    let targetRPM = FanManager.shared.calculateFanRPM(
                        temperature: reading.value,
                        curve: curve,
                        safetyFloorRPM: safetyFloorRPM
                    )

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

// 转速设置窗口控制器
@MainActor
class SpeedSettingWindowController: NSWindowController {
    private var currentRPM: Int = 0
    private let maxRPM: Int
    
    init(initialRPM: Int, maxRPM: Int) {
        self.currentRPM = initialRPM
        self.maxRPM = maxRPM
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "设置风扇转速"
        window.center()
        
        super.init(window: window)

        applyWindowMaterialStyle(window)
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
        rpmSlider.maxValue = Double(maxRPM)
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
        let rpm = min(Int(slider.doubleValue), maxRPM)
        
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

@MainActor
class SafetyFloorWindowController: NSWindowController {
    private var currentRPM: Int = 0
    private let minRPM = 2000
    private let maxRPM: Int
    private var rpmSlider: NSSlider?
    private var rpmLabel: NSTextField?

    init(initialRPM: Int, maxRPM: Int) {
        self.currentRPM = initialRPM
        self.maxRPM = max(maxRPM, minRPM)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "安全兜底转速"
        window.center()

        super.init(window: window)

        applyWindowMaterialStyle(window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "危险温度（95℃）时的最低兜底转速")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let hintLabel = NSTextField(labelWithString: "仅作托底，不会压低用户曲线已经给出的更高转速")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hintLabel)

        let rpmSlider = NSSlider()
        rpmSlider.minValue = Double(minRPM)
        rpmSlider.maxValue = Double(maxRPM)
        rpmSlider.doubleValue = Double(currentRPM)
        rpmSlider.target = self
        rpmSlider.action = #selector(sliderChanged)
        rpmSlider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rpmSlider)

        let rpmLabel = NSTextField(labelWithString: "\(currentRPM) RPM")
        rpmLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        rpmLabel.alignment = .center
        rpmLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rpmLabel)

        let applyButton = NSButton(title: "应用", target: self, action: #selector(applyValue))
        applyButton.bezelStyle = .rounded
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(applyButton)

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            rpmSlider.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 14),
            rpmSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rpmSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            rpmLabel.topAnchor.constraint(equalTo: rpmSlider.bottomAnchor, constant: 10),
            rpmLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            applyButton.topAnchor.constraint(equalTo: rpmLabel.bottomAnchor, constant: 18),
            applyButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -44),

            cancelButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            cancelButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 44)
        ])

        self.rpmSlider = rpmSlider
        self.rpmLabel = rpmLabel
    }

    @objc private func sliderChanged() {
        guard let slider = rpmSlider else { return }
        let rpm = Int(slider.doubleValue.rounded())
        rpmLabel?.stringValue = "\(rpm) RPM"
    }

    @objc private func applyValue() {
        guard let slider = rpmSlider else { return }
        let rpm = min(max(Int(slider.doubleValue.rounded()), minRPM), maxRPM)

        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.safetyFloorRPM = rpm
        ConfigManager.shared.saveConfig(newConfig)

        let alert = NSAlert()
        alert.messageText = "设置成功"
        alert.informativeText = "安全兜底转速已设置为 \(rpm) RPM"
        alert.addButton(withTitle: "确定")
        alert.runModal()

        window?.close()
    }

    @objc private func cancel() {
        window?.close()
    }
}

@MainActor
class HelpWindowController: NSWindowController {
    private var versionLabel: NSTextField?
    private var automaticUpdateCheckbox: NSButton?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 iFanControl"
        window.center()

        super.init(window: window)
        applyWindowMaterialStyle(window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = NSApp.applicationIconImage
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 18
        iconView.layer?.masksToBounds = true
        contentView.addSubview(iconView)

        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "iFanControl")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)

        let versionLabel = NSTextField(labelWithString: "版本 \(UpdateService.shared.currentVersionDisplay)")
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.font = .systemFont(ofSize: 13)

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(versionLabel)
        contentView.addSubview(headerStack)

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let restartButton = NSButton(title: "重新启动", target: self, action: #selector(restartApp))
        restartButton.bezelStyle = .rounded

        let updateButton = NSButton(title: "检查更新", target: self, action: #selector(checkUpdates))
        updateButton.bezelStyle = .rounded

        let githubButton = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded

        buttonStack.addArrangedSubview(restartButton)
        buttonStack.addArrangedSubview(updateButton)
        buttonStack.addArrangedSubview(githubButton)
        contentView.addSubview(buttonStack)

        let automaticUpdateCheckbox = NSButton(checkboxWithTitle: "自动检查更新", target: self, action: #selector(toggleAutomaticChecks(_:)))
        automaticUpdateCheckbox.state = UpdateService.shared.automaticChecksEnabled ? .on : .off
        automaticUpdateCheckbox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(automaticUpdateCheckbox)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 560))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .systemFont(ofSize: 13)
        textView.string = """
        常见问题

        1. 温度源默认怎么选？
        默认使用当前最热的温度传感器。你也可以在菜单栏的“选择温度源”里手动指定。

        2. 为什么温度源数量和 CPU / GPU 核心数对不上？
        这里显示的是 Apple Silicon 实际暴露出来的温度传感器，不一定与 CPU 或 GPU 核心数量一一对应。

        3. 如果没有检测到风扇怎么办？
        这通常意味着设备是无风扇机型，或者当前硬件暂不支持手动风扇控制。

        4. 自动更新失败怎么办？
        可以在“检查更新”失败后打开 GitHub Releases，手动下载并覆盖安装。

        5. 手动模式和自动模式有什么区别？
        自动模式会根据风扇曲线调速；手动模式会固定使用你设置的目标转速。

        6. 安全兜底转速是什么？
        当温度达到 95℃ 时，系统会保证风扇至少达到你设置的兜底转速，但不会压低用户曲线已经给出的更高转速。
        """
        textView.textContainer?.containerSize = NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 520)
        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),

            headerStack.topAnchor.constraint(equalTo: iconView.topAnchor, constant: 4),
            headerStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -18),

            buttonStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            buttonStack.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor),

            automaticUpdateCheckbox.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 12),
            automaticUpdateCheckbox.leadingAnchor.constraint(equalTo: headerStack.leadingAnchor),

            separator.topAnchor.constraint(equalTo: automaticUpdateCheckbox.bottomAnchor, constant: 16),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        self.versionLabel = versionLabel
        self.automaticUpdateCheckbox = automaticUpdateCheckbox
    }

    override func showWindow(_ sender: Any?) {
        versionLabel?.stringValue = "版本 \(UpdateService.shared.currentVersionDisplay)"
        automaticUpdateCheckbox?.state = UpdateService.shared.automaticChecksEnabled ? .on : .off
        super.showWindow(sender)
    }

    @objc private func checkUpdates() {
        UpdateService.shared.checkForUpdates(triggeredByUser: true)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(UpdateService.shared.releasesURL)
    }

    @objc private func restartApp() {
        MenuBarManager.shared.restartApp()
    }

    @objc private func toggleAutomaticChecks(_ sender: NSButton) {
        UpdateService.shared.automaticChecksEnabled = (sender.state == .on)
    }
}

// 主函数
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
