//
//  main.swift
//  iFanControl
//
//  Created by iFanControl on 2026-03-17.
//  Copyright © 2026 iFanControl. All rights reserved.
//

import AppKit
import CoreImage
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
private let defaultManualRPMStep = 500
private let supportEmailAddress = "puremilkchun@foxmail.com"
private let wechatDonatePayload = "wxp://f2f0rVY6iLnpjTqEKL4HKTHRw3Ej81vNbWU9UUXk4msd30ehG7Xh9NwXEyNsZaTn5gZE"
private let alipayDonatePayload = "https://qr.alipay.com/fkx16601ptfadpsxd3mfpf6"
private let appUsesEnglish = Locale.preferredLanguages.first?.lowercased().hasPrefix("en") ?? false
private func appL10n(_ zh: String, _ en: String) -> String {
    appUsesEnglish ? en : zh
}

final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    private let queue = DispatchQueue(label: "com.ifancontrol.diagnostic-log")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let maxLogSizeBytes = 2 * 1024 * 1024
    private let maxMessageLength = 3000

    private let logsDirectoryURL: URL
    private let logFileURL: URL
    private let archivedLogFileURL: URL

    private init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("iFanControl")
        self.logsDirectoryURL = base
        self.logFileURL = base.appendingPathComponent("ifancontrol.log")
        self.archivedLogFileURL = base.appendingPathComponent("ifancontrol.log.1")
        prepareLogDirectory()
    }

    var currentLogPath: String {
        logFileURL.path
    }

    func bootstrapSession() {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        info("Session started version=\(shortVersion) (\(buildVersion)) os=\(osVersion) pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func debug(_ message: String) { write(level: "DEBUG", message: message) }
    func info(_ message: String) { write(level: "INFO", message: message) }
    func warning(_ message: String) { write(level: "WARN", message: message) }
    func error(_ message: String) { write(level: "ERROR", message: message) }

    func openLogDirectoryInFinder() -> Bool {
        prepareLogDirectory()
        NSWorkspace.shared.open(logsDirectoryURL)
        return true
    }

    func composeSupportEmail(archiveURL: URL? = nil) {
        let subject = appL10n("iFanControl 日志反馈", "iFanControl Diagnostic Report")
        let archiveLine = archiveURL.map {
            appL10n("诊断包：\n\($0.path)\n\n请将该 ZIP 文件作为附件发送。",
                    "Diagnostic package:\n\($0.path)\n\nPlease attach this ZIP file.")
        } ?? appL10n("请先在应用菜单中导出诊断包，再将 ZIP 作为附件发送。",
                     "Please export a diagnostic package from the app menu, then attach the ZIP.")

        let body = appL10n(
            """
            你好，我遇到了 iFanControl 使用问题。

            \(archiveLine)

            请在这封邮件中描述：
            1) 机型与 macOS 版本
            2) 触发问题的步骤
            3) 预期结果与实际结果
            """,
            """
            Hi, I encountered an iFanControl issue.

            \(archiveLine)

            Please include:
            1) Mac model and macOS version
            2) Steps to reproduce
            3) Expected vs actual result
            """
        )

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        let mailto = "mailto:\(supportEmailAddress)?subject=\(encodedSubject)&body=\(encodedBody)"
        if let url = URL(string: mailto) {
            NSWorkspace.shared.open(url)
        }
    }

    func createDiagnosticArchive() throws -> URL {
        prepareLogDirectory()

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let packageName = "iFanControl-Diagnostics-\(timestamp)"

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(packageName, isDirectory: true)
        try? FileManager.default.removeItem(at: tempRoot)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        var included: [String] = []

        let logsFolder = tempRoot.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            try FileManager.default.copyItem(at: logFileURL, to: logsFolder.appendingPathComponent("ifancontrol.log"))
            included.append("logs/ifancontrol.log")
        }
        if FileManager.default.fileExists(atPath: archivedLogFileURL.path) {
            try FileManager.default.copyItem(at: archivedLogFileURL, to: logsFolder.appendingPathComponent("ifancontrol.log.1"))
            included.append("logs/ifancontrol.log.1")
        }

        let configSource = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MacFanControl")
            .appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configSource.path) {
            let configFolder = tempRoot.appendingPathComponent("config", isDirectory: true)
            try FileManager.default.createDirectory(at: configFolder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: configSource, to: configFolder.appendingPathComponent("config.json"))
            included.append("config/config.json")
        }

        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let locale = Locale.current.identifier
        let summary = """
        generated_at=\(formatter.string(from: Date()))
        app_version=\(shortVersion) (\(buildVersion))
        os=\(osVersion)
        locale=\(locale)
        support_email=\(supportEmailAddress)
        log_directory=\(logsDirectoryURL.path)
        included_files=\(included.joined(separator: ","))
        """
        try summary.write(to: tempRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        let exportBase = preferredExportDirectory()
        try FileManager.default.createDirectory(at: exportBase, withIntermediateDirectories: true)
        let zipURL = exportBase.appendingPathComponent("\(packageName).zip")
        try? FileManager.default.removeItem(at: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", tempRoot.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: tempRoot)

        if process.terminationStatus != 0 || !FileManager.default.fileExists(atPath: zipURL.path) {
            throw NSError(domain: "AppLog", code: 4001, userInfo: [NSLocalizedDescriptionKey: appL10n("导出诊断包失败。", "Failed to export diagnostic package.")])
        }

        info("diagnostic package exported path=\(zipURL.path)")
        return zipURL
    }

    private func preferredExportDirectory() -> URL {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        if (try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)) != nil {
            return desktop
        }
        return logsDirectoryURL
    }

    private func prepareLogDirectory() {
        try? FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
    }

    private func write(level: String, message: String) {
        queue.async {
            self.prepareLogDirectory()
            self.rotateIfNeeded()

            let timestamp = self.formatter.string(from: Date())
            let sanitized = self.sanitize(message)
            let line = "[\(timestamp)] [\(level)] \(sanitized)\n"
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                    do {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                        try handle.close()
                    } catch {
                        try? handle.close()
                    }
                }
            } else {
                try? data.write(to: self.logFileURL, options: .atomic)
            }
        }
    }

    private func sanitize(_ message: String) -> String {
        let normalized = message.replacingOccurrences(of: "\n", with: "\\n")
        if normalized.count <= maxMessageLength {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: maxMessageLength)
        return "\(normalized[..<index])...(truncated)"
    }

    private func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue >= maxLogSizeBytes else {
            return
        }

        try? FileManager.default.removeItem(at: archivedLogFileURL)
        try? FileManager.default.moveItem(at: logFileURL, to: archivedLogFileURL)
    }
}

@MainActor
final class InstallationCoordinator {
    static let shared = InstallationCoordinator()

    private let kentsmcPath = "/usr/local/bin/kentsmc"
    private let sudoersPath = "/private/etc/sudoers.d/kentsmc"
    private let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("LaunchAgents")
        .appendingPathComponent("com.ifancontrol.app.plist")
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("MacFanControl")
    private let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Logs")
        .appendingPathComponent("iFanControl")

    func launchSelfContainedUninstaller() -> Bool {
        do {
            let scriptURL = try createTemporaryFullUninstallScript()
            return launchInTerminal(url: scriptURL)
        } catch {
            AppLog.shared.error("failed to create temporary uninstaller error=\(error.localizedDescription)")
            return false
        }
    }

    private func launchInTerminal(url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", url.path]

        do {
            try process.run()
            return true
        } catch {
            AppLog.shared.error("failed to open uninstaller script path=\(url.path) error=\(error.localizedDescription)")
            return false
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func createTemporaryFullUninstallScript() throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("iFanControl-Uninstall", isDirectory: true)
        try? fm.removeItem(at: tempDir)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let scriptURL = tempDir.appendingPathComponent("run-uninstall.command")
        let appPath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? ""

        let script = """
        #!/bin/bash
        set -u

        APP_PATH=\(shellQuoted(appPath))
        EXECUTABLE_PATH=\(shellQuoted(executablePath))
        KENTSMC_PATH=\(shellQuoted(kentsmcPath))
        SUDOERS_PATH=\(shellQuoted(sudoersPath))
        CONFIG_PATH=\(shellQuoted(configPath.path))
        LOG_PATH=\(shellQuoted(logPath.path))
        LAUNCH_AGENT=\(shellQuoted(launchAgentPath.path))

        echo "============================================"
        echo "  iFanControl 完整卸载"
        echo "============================================"
        echo ""
        echo "正在等待 iFanControl 退出..."
        for _ in $(seq 1 40); do
          if [ -n "$EXECUTABLE_PATH" ] && pgrep -f "$EXECUTABLE_PATH" >/dev/null 2>&1; then
            sleep 0.5
          else
            break
          fi
        done

        echo ""
        echo "步骤 1/6: 删除 App..."
        rm -rf "$APP_PATH"
        echo "✓ App 已删除"

        echo ""
        echo "步骤 2/6: 删除 kentsmc..."
        if [ -f "$KENTSMC_PATH" ]; then
          sudo rm -f "$KENTSMC_PATH"
          echo "✓ kentsmc 已删除"
        else
          echo "kentsmc 不存在，跳过"
        fi

        echo ""
        echo "步骤 3/6: 删除 sudoers 规则..."
        if [ -f "$SUDOERS_PATH" ]; then
          sudo rm -f "$SUDOERS_PATH"
          echo "✓ sudoers 规则已删除"
        else
          echo "sudoers 规则不存在，跳过"
        fi

        echo ""
        echo "步骤 4/6: 删除配置..."
        rm -rf "$CONFIG_PATH"
        echo "✓ 配置已删除"

        echo ""
        echo "步骤 5/6: 删除日志..."
        rm -rf "$LOG_PATH"
        echo "✓ 日志已删除"

        echo ""
        echo "步骤 6/6: 删除开机自启动项..."
        rm -f "$LAUNCH_AGENT"
        echo "✓ LaunchAgent 已删除"

        echo ""
        echo "============================================"
        echo "  卸载完成"
        echo "============================================"
        echo ""
        read -p "按回车键关闭窗口..."
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}

enum ManualRPMControlMode: String {
    case continuous
    case stepped

    init(storedValue: String?) {
        self = ManualRPMControlMode(rawValue: storedValue ?? "") ?? .continuous
    }
}

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
final class CommandExecutor: @unchecked Sendable {
    static let shared = CommandExecutor()
    private let kentsmcPath = "/usr/local/bin/kentsmc"
    private let commandQueue = DispatchQueue(label: "com.ifancontrol.command-executor")
    private let logger = Logger(subsystem: appSubsystem, category: "CommandExecutor")

    private func compact(_ text: String, limit: Int = 1200) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        let index = cleaned.index(cleaned.startIndex, offsetBy: limit)
        return "\(cleaned[..<index])...(truncated)"
    }
    
    // 执行特权命令
    private func executeCommand(args: [String]) -> (success: Bool, output: String, error: String) {
        let startedAt = Date()
        let commandLabel = "\(kentsmcPath) \(args.joined(separator: " "))"
        logger.info("Executing privileged command: \(commandLabel, privacy: .public)")
        AppLog.shared.debug("run sudo \(commandLabel)")

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
            let success = (task.terminationStatus == 0)
            let elapsed = Date().timeIntervalSince(startedAt)

            AppLog.shared.info("sudo command finished success=\(success) exit=\(task.terminationStatus) duration=\(String(format: "%.3f", elapsed))s args=\(args.joined(separator: " "))")
            if !output.isEmpty {
                AppLog.shared.debug("sudo stdout: \(compact(output))")
            }
            if !error.isEmpty {
                AppLog.shared.warning("sudo stderr: \(compact(error))")
            }

            return (success, output, error)
        } catch {
            AppLog.shared.error("sudo command failed to run args=\(args.joined(separator: " ")) error=\(error.localizedDescription)")
            return (false, "", error.localizedDescription)
        }
    }
    
    // 设置风扇转速
    func setFanRPM(rpm: Int) -> (success: Bool, error: String?) {
        let result = executeCommand(args: ["--fan-rpm", "\(rpm)"])
        if result.success {
            AppLog.shared.info("setFanRPM succeeded rpm=\(rpm)")
        } else {
            AppLog.shared.error("setFanRPM failed rpm=\(rpm) error=\(result.error)")
        }
        return (result.success, result.success ? nil : result.error)
    }

    func setFanRPMAsync(
        rpm: Int,
        completion: @MainActor @escaping (_ success: Bool, _ error: String?) -> Void
    ) {
        commandQueue.async {
            let result = self.setFanRPM(rpm: rpm)
            Task { @MainActor in
                completion(result.success, result.error)
            }
        }
    }
    
    // 设置自动模式
    func setFanAuto() -> (success: Bool, error: String?) {
        let result = executeCommand(args: ["--fan-auto"])
        if result.success {
            AppLog.shared.info("setFanAuto succeeded")
        } else {
            AppLog.shared.error("setFanAuto failed error=\(result.error)")
        }
        return (result.success, result.success ? nil : result.error)
    }
    
    // 解锁风扇
    func unlockFans() -> (success: Bool, error: String?) {
        let result = executeCommand(args: ["--unlock-fans"])
        if result.success {
            AppLog.shared.info("unlockFans succeeded")
        } else {
            AppLog.shared.error("unlockFans failed error=\(result.error)")
        }
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
    private let telemetryRefreshInterval: TimeInterval = 2.0
    private let validTemperatureRange = 0.0...120.0
    
    private(set) var fanCount: Int = 0
    private(set) var fans: [FanInfo] = []
    private(set) var availableTemperatureSensors: [TemperatureSensorDefinition] = []
    private(set) var currentMaxRPM: Int = 4900
    
    private var cachedTemperatures: [String: Double] = [:]
    private var cachedFanRPMs: [Int: Int] = [:]
    private var lastTelemetryRefresh: Date?
    private var lastTelemetryLogTimestamp: Date?
    private var hasProbedHardware = false
    private let logger = Logger(subsystem: appSubsystem, category: "Hardware")
    private let telemetryDetailLogInterval: TimeInterval = 10.0
    
    // 稳定性控制参数
    private var lastSetRPM: Int = 0
    private var lastExecutionTime: Date?
    private let minExecutionInterval: TimeInterval = 2.0
    private var fanCommandInFlight = false
    
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
            let startedAt = Date()
            try task.run()
            task.waitUntilExit()
            let elapsed = Date().timeIntervalSince(startedAt)

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputText = String(data: outputData, encoding: .utf8) ?? ""
            let errorText = String(data: errorData, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                if elapsed > 0.4 {
                    AppLog.shared.debug("slow read command args=\(args.joined(separator: " ")) duration=\(String(format: "%.3f", elapsed))s")
                }
                return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            AppLog.shared.warning("read command failed exit=\(task.terminationStatus) args=\(args.joined(separator: " ")) stderr=\(errorText)")
        } catch {
            print("Error executing kentsmc read command: \(error)")
            AppLog.shared.error("read command execution error args=\(args.joined(separator: " ")) error=\(error.localizedDescription)")
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
        let sensorKeys = availableTemperatureSensors.map(\.key).joined(separator: ",")
        AppLog.shared.info("hardware profile refreshed fans=\(fanCount) maxRPM=\(currentMaxRPM) sensors=\(availableTemperatureSensors.count) keys=[\(sensorKeys)]")

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
        maybeLogTelemetrySnapshot()
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

    func readPrimaryFanRPM(refresh: Bool = true) -> Int? {
        if refresh {
            refreshTelemetry()
        }
        return cachedFanRPMs.values.max()
    }
    
    func setFanRPM(rpm: Int) {
        if fanCommandInFlight {
            AppLog.shared.debug("setFanRPM skipped reason=in_flight requested=\(rpm)")
            return
        }

        let boundedTarget = max(0, min(currentMaxRPM, rpm))

        // 检查时间间隔
        if let lastTime = lastExecutionTime,
           Date().timeIntervalSince(lastTime) < minExecutionInterval {
            AppLog.shared.debug("setFanRPM skipped reason=rate_limited requested=\(rpm) bounded=\(boundedTarget)")
            return
        }
        
        // 动态滞后控制
        let minChange = getMinRPMChange(currentRPM: lastSetRPM)
        let absChange = abs(boundedTarget - lastSetRPM)
        guard absChange >= minChange else {
            AppLog.shared.debug("setFanRPM skipped reason=below_threshold requested=\(rpm) bounded=\(boundedTarget) last=\(lastSetRPM) minChange=\(minChange)")
            return
        }
        
        // 平滑滤波
        let smoothingFactor: Double = 0.3
        let smoothedRPM = Int(Double(lastSetRPM) * (1.0 - smoothingFactor) + Double(boundedTarget) * smoothingFactor)
        fanCommandInFlight = true
        AppLog.shared.info("setFanRPM dispatch requested=\(rpm) bounded=\(boundedTarget) smoothed=\(smoothedRPM) last=\(lastSetRPM)")

        CommandExecutor.shared.setFanRPMAsync(rpm: smoothedRPM) { [weak self] success, error in
            guard let self else { return }
            self.fanCommandInFlight = false

            if success {
                self.lastSetRPM = smoothedRPM
                self.lastExecutionTime = Date()
                AppLog.shared.info("setFanRPM applied smoothed=\(smoothedRPM)")
            } else {
                print("Error setting fan RPM: \(error ?? "Unknown error")")
                AppLog.shared.error("setFanRPM apply failed smoothed=\(smoothedRPM) error=\(error ?? "unknown")")
            }
        }
    }
    
    func unlockFans() {
        guard fanCount > 0 else {
            AppLog.shared.warning("unlockFans skipped because fanCount=0")
            return
        }
        let result = CommandExecutor.shared.unlockFans()
        if !result.success {
            print("Error unlocking fans: \(result.error ?? "Unknown error")")
            AppLog.shared.error("unlockFans failed fanCount=\(fanCount) error=\(result.error ?? "unknown")")
        } else {
            AppLog.shared.info("unlockFans finished fanCount=\(fanCount)")
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
                AppLog.shared.error("temperature read failed repeatedly count=\(temperatureReadFailureCount)")
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
            AppLog.shared.warning("critical temperature reached temp=\(String(format: "%.2f", temperature)) floor=\(safetyFloorRPM) clamped=\(clampedRPM)")
            temperatureReadFailureCount = 0
            return max(clampedRPM, safetyFloorRPM)
        }

        return clampedRPM
    }

    private func maybeLogTelemetrySnapshot() {
        let now = Date()
        if let last = lastTelemetryLogTimestamp,
           now.timeIntervalSince(last) < telemetryDetailLogInterval {
            return
        }
        lastTelemetryLogTimestamp = now

        let topTemperatures = cachedTemperatures
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\($0.key)=\(String(format: "%.1f", $0.value))" }
            .joined(separator: ", ")
        let fanRpmText = cachedFanRPMs
            .sorted { $0.key < $1.key }
            .map { "F\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        AppLog.shared.debug("telemetry snapshot fans=[\(fanRpmText)] topTemps=[\(topTemperatures)]")
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
            manualRPMControlMode: ManualRPMControlMode.continuous.rawValue,
            manualRPMStep: defaultManualRPMStep,
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
        if config.manualRPMControlMode == nil {
            config.manualRPMControlMode = ManualRPMControlMode.continuous.rawValue
        }
        config.manualRPMStep = max(config.manualRPMStep ?? defaultManualRPMStep, 1)
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? appL10n("未知版本", "Unknown")
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
                            title: appL10n("已是最新版本", "Up to Date"),
                            message: appL10n(
                                "当前版本：\(currentVersionDisplay)\n远端版本：\(manifest.latestVersion) (\(manifest.latestBuild))",
                                "Current: \(currentVersionDisplay)\nLatest: \(manifest.latestVersion) (\(manifest.latestBuild))"
                            )
                        )
                    }
                    return
                }

                self.logger.info("Update available. currentBuild=\(self.currentBuild, privacy: .public) remoteBuild=\(manifest.latestBuild, privacy: .public)")
                presentUpdatePrompt(manifest: manifest)
            } catch {
                self.logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                if triggeredByUser {
                    showUpdateFailureAlert(title: appL10n("检查更新失败", "Update Check Failed"), message: error.localizedDescription, releaseURL: releasesHomeURL)
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
        let notes = manifest.notes?.isEmpty == false ? manifest.notes! : appL10n("包含稳定性与功能改进。", "Includes stability and feature improvements.")
        let alert = NSAlert()
        alert.messageText = appL10n("发现新版本 \(manifest.latestVersion)", "New Version Available \(manifest.latestVersion)")
        alert.informativeText = appL10n(
            "当前版本：\(currentVersionDisplay)\n远端版本：\(manifest.latestVersion) (\(manifest.latestBuild))\n\n\(notes)",
            "Current: \(currentVersionDisplay)\nLatest: \(manifest.latestVersion) (\(manifest.latestBuild))\n\n\(notes)"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: appL10n("立即更新", "Update Now"))
        alert.addButton(withTitle: appL10n("稍后", "Later"))

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
                    throw NSError(domain: "UpdateService", code: 1001, userInfo: [NSLocalizedDescriptionKey: appL10n("安装包大小校验失败。", "Package size verification failed.")])
                }

                if let expectedSHA = manifest.assets?.sha256?.lowercased(), !expectedSHA.isEmpty {
                    let actualSHA = sha256Hex(data)
                    if expectedSHA != actualSHA {
                        throw NSError(domain: "UpdateService", code: 1002, userInfo: [NSLocalizedDescriptionKey: appL10n("安装包哈希校验失败。", "Package checksum verification failed.")])
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
                    throw NSError(domain: "UpdateService", code: 1003, userInfo: [NSLocalizedDescriptionKey: appL10n("未找到 install.sh。", "install.sh not found.")])
                }

                try runInstallScriptInTerminal(scriptURL: installScript)
                logger.info("Update installer launched successfully for version \(manifest.latestVersion, privacy: .public)")
                showInfoAlert(title: appL10n("下载完成", "Download Complete"), message: appL10n("安装脚本已在终端打开，请按提示完成升级。", "Installer has opened in Terminal. Follow the prompts to finish update."))
            } catch {
                logger.error("Update download/install failed: \(error.localizedDescription, privacy: .public)")
                showUpdateFailureAlert(
                    title: appL10n("更新失败", "Update Failed"),
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
            throw NSError(domain: "UpdateService", code: 1004, userInfo: [NSLocalizedDescriptionKey: appL10n("解压安装包失败。", "Failed to unzip update package.")])
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
                userInfo: [NSLocalizedDescriptionKey: appL10n("无法启动安装终端。请手动打开 \(launcherURL.lastPathComponent) 完成升级。", "Failed to launch installer terminal. Please open \(launcherURL.lastPathComponent) manually.")]
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
        alert.addButton(withTitle: appL10n("好的", "OK"))
        alert.runModal()
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: appL10n("关闭", "Close"))
        alert.runModal()
    }

    private func showUpdateFailureAlert(title: String, message: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = appL10n(
            "\(message)\n\n如需手动更新，可前往 GitHub Releases 下载最新版本。",
            "\(message)\n\nYou can download the latest version from GitHub Releases for manual update."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: appL10n("前往 GitHub", "Open GitHub"))
        alert.addButton(withTitle: appL10n("关闭", "Close"))

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
    private var currentTemperatureSensorName: String = appL10n("自动选择（最热）", "Auto (Hottest)")
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
                return automatic ? appL10n("自动 / \(base)", "Auto / \(base)") : appL10n("手动 / \(base)", "Manual / \(base)")
            }
        }
        return automatic ? appL10n("自动 / \(reading.sensor.key)", "Auto / \(reading.sensor.key)") : appL10n("手动 / \(reading.sensor.key)", "Manual / \(reading.sensor.key)")
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleCurveSaved), name: NSNotification.Name("FanCurveDidSave"), object: nil)
        
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
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
        let readings = FanManager.shared.availableTemperatureReadings()

        let selectedReading: TemperatureReading?
        if config.temperatureSourceMode == "manual",
           let selectedKey = config.selectedTemperatureSensorKey {
            selectedReading = readings.first(where: { $0.sensor.key == selectedKey })
        } else {
            selectedReading = readings.max(by: { $0.value < $1.value })
        }

        if let reading = selectedReading {
            currentTemperature = reading.value
            currentTemperatureSensorName = selectionSummary(for: reading, in: readings, automatic: config.temperatureSourceMode != "manual")
        }

        if let rpm = FanManager.shared.readPrimaryFanRPM(refresh: false) {
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
                appL10n("风扇 \(FanManager.shared.fanCount) | 上限 \(FanManager.shared.currentMaxRPM)", "Fans \(FanManager.shared.fanCount) | Max \(FanManager.shared.currentMaxRPM)") :
                appL10n("无可控风扇", "No controllable fan"),
            action: nil,
            keyEquivalent: ""
        )
        hardwareItem.isEnabled = false
        menu.addItem(hardwareItem)

        let currentSensorItem = NSMenuItem(title: appL10n("温度源 \(currentTemperatureSensorName)", "Temperature Source \(currentTemperatureSensorName)"), action: nil, keyEquivalent: "")
        currentSensorItem.isEnabled = false
        menu.addItem(currentSensorItem)
        menu.addItem(NSMenuItem.separator())

        let temperatureSourceItem = NSMenuItem(title: appL10n("选择温度源", "Select Temperature Source"), action: nil, keyEquivalent: "")
        let temperatureSourceMenu = NSMenu()

        let hottestItem = NSMenuItem(title: appL10n("自动选择（最热）", "Auto (Hottest)"), action: #selector(selectAutomaticTemperatureSource), keyEquivalent: "")
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
            let emptyItem = NSMenuItem(title: appL10n("暂未探测到温度传感器", "No temperature sensor detected"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            temperatureSourceMenu.addItem(emptyItem)
        }

        menu.setSubmenu(temperatureSourceMenu, for: temperatureSourceItem)
        menu.addItem(temperatureSourceItem)
        
        let curveItem = NSMenuItem(title: appL10n("编辑曲线...", "Edit Curve..."), action: #selector(showFanCurveEditor), keyEquivalent: "c")
        curveItem.target = self
        menu.addItem(curveItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let modeItem = NSMenuItem(title: isAutoMode ? appL10n("手动模式", "Manual Mode") : appL10n("自动模式", "Auto Mode"), action: #selector(toggleMode), keyEquivalent: "m")
        modeItem.target = self
        menu.addItem(modeItem)
        
        if !isAutoMode {
            let speedItem = NSMenuItem(title: appL10n("设置转速...", "Set Speed..."), action: #selector(showSpeedSetting), keyEquivalent: "")
            speedItem.target = self
            menu.addItem(speedItem)
        }
        
        let autoStartItem = NSMenuItem(title: appL10n("开机自启动", "Launch at Login"), action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = autoStartEnabled ? .on : .off
        menu.addItem(autoStartItem)

        let safetyFloorItem = NSMenuItem(title: appL10n("安全兜底转速...", "Safety Floor RPM..."), action: #selector(showSafetyFloorSetting), keyEquivalent: "")
        safetyFloorItem.target = self
        menu.addItem(safetyFloorItem)

        let aboutItem = NSMenuItem(title: appL10n("关于/帮助...", "About / Help..."), action: #selector(showHelp), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: appL10n("重新启动", "Restart"), action: #selector(restartApp), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)
        
        let quitItem = NSMenuItem(title: appL10n("退出", "Quit"), action: #selector(quitApp), keyEquivalent: "q")
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
        let controlMode = ManualRPMControlMode(storedValue: config.manualRPMControlMode)
        let stepRPM = max(config.manualRPMStep ?? defaultManualRPMStep, 1)
        speedSettingWindowController = SpeedSettingWindowController(
            initialRPM: currentRPM,
            maxRPM: FanManager.shared.currentMaxRPM,
            controlMode: controlMode,
            stepRPM: stepRPM
        )
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
            alert.messageText = appL10n("未检测到可控风扇", "No Controllable Fan Detected")
            alert.informativeText = appL10n("这台设备可能是无风扇机型，或当前硬件暂不支持手动风扇控制。应用会继续运行，但不会尝试强制控制风扇。", "This device may be fanless, or manual fan control is not supported on current hardware. The app will keep running but won't force fan control.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: appL10n("知道了", "OK"))
            logger.warning("No controllable fans detected on startup")
            alert.runModal()
            return
        }

        let readings = FanManager.shared.availableTemperatureReadings()
        if readings.count > 1 && !defaults.bool(forKey: temperatureSourceHintKey) {
            defaults.set(true, forKey: temperatureSourceHintKey)
            let alert = NSAlert()
            alert.messageText = appL10n("温度源已自动选择", "Temperature Source Set to Auto")
            alert.informativeText = appL10n("默认会使用当前最热的温度传感器来驱动风扇曲线。这里显示的是这台机器真实可读到的温度传感器，不一定与 CPU/GPU 核心数量一一对应。", "By default, the hottest available sensor is used to drive the fan curve. Sensor count may not match CPU/GPU core count.")
            alert.alertStyle = .informational
            alert.addButton(withTitle: appL10n("知道了", "OK"))
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
            alert.messageText = appL10n("无法重新启动", "Unable to Restart")
            alert.informativeText = appL10n("请手动重新打开 iFanControl。\n\n\(error.localizedDescription)", "Please reopen iFanControl manually.\n\n\(error.localizedDescription)")
            alert.alertStyle = .warning
            alert.addButton(withTitle: appL10n("关闭", "Close"))
            alert.runModal()
        }
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func openLogFolder() {
        let opened = AppLog.shared.openLogDirectoryInFinder()
        if opened {
            logger.info("Opened diagnostic log folder")
            AppLog.shared.info("user opened diagnostic log folder")
        }
    }

    @objc func exportDiagnosticArchive() {
        do {
            let archiveURL = try AppLog.shared.createDiagnosticArchive()
            NSWorkspace.shared.activateFileViewerSelecting([archiveURL])

            let alert = NSAlert()
            alert.messageText = appL10n("诊断包已导出", "Diagnostic Package Exported")
            alert.informativeText = appL10n(
                "导出位置：\n\(archiveURL.path)\n\n建议下一步将该 ZIP 作为附件发送给支持邮箱。",
                "Exported to:\n\(archiveURL.path)\n\nAttach this ZIP when contacting support."
            )
            alert.alertStyle = .informational
            alert.addButton(withTitle: appL10n("写邮件", "Compose Email"))
            alert.addButton(withTitle: appL10n("完成", "Done"))
            if alert.runModal() == .alertFirstButtonReturn {
                AppLog.shared.composeSupportEmail(archiveURL: archiveURL)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = appL10n("导出诊断包失败", "Diagnostic Export Failed")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: appL10n("关闭", "Close"))
            alert.runModal()
            AppLog.shared.error("diagnostic export failed error=\(error.localizedDescription)")
        }
    }

    @objc func contactSupport() {
        AppLog.shared.info("user requested support email composition")
        AppLog.shared.composeSupportEmail()
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
    static weak var shared: AppDelegate?
    private var lastControlLoopLogTime: Date?
    private let controlLoopLogInterval: TimeInterval = 10.0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        AppLog.shared.bootstrapSession()
        AppLog.shared.info("application did finish launching")

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
        AppLog.shared.info("application will terminate")
        _ = CommandExecutor.shared.setFanAuto()
    }

    func beginUninstallFlow() {
        let alert = NSAlert()
        alert.messageText = appL10n("确认完整卸载", "Confirm Full Uninstall")
        alert.informativeText = appL10n(
            "这会删除 iFanControl.app、本地控制组件、sudoers 规则、配置、日志和开机自启动项。卸载脚本会在终端里继续执行，应用会随后退出。",
            "This will remove iFanControl.app, local control components, sudoers rule, config, logs, and launch-at-login item. The uninstall script will continue in Terminal and the app will then quit."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: appL10n("开始卸载", "Start Uninstall"))
        alert.addButton(withTitle: appL10n("取消", "Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let launched = InstallationCoordinator.shared.launchSelfContainedUninstaller()
        if launched {
            AppLog.shared.info("self-contained full uninstall launched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        } else {
            let errorAlert = NSAlert()
            errorAlert.messageText = appL10n("无法打开卸载脚本", "Unable to Open Uninstaller")
            errorAlert.informativeText = appL10n(
                "无法创建或启动应用内卸载脚本。请稍后重试，或使用安装包中的卸载脚本。",
                "Unable to create or launch the internal uninstall script. Please try again later, or use the uninstall script from the installer package."
            )
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: appL10n("关闭", "Close"))
            errorAlert.runModal()
        }
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
                    self.logControlLoopSummaryIfNeeded(mode: "auto", reading: reading, targetRPM: targetRPM)
                } else {
                    FanManager.shared.setFanRPM(rpm: config.manualRPM)
                    self.logControlLoopSummaryIfNeeded(mode: "manual", reading: reading, targetRPM: config.manualRPM)
                }
            }
        }
    }

    private func logControlLoopSummaryIfNeeded(mode: String, reading: TemperatureReading, targetRPM: Int) {
        let now = Date()
        if let last = lastControlLoopLogTime,
           now.timeIntervalSince(last) < controlLoopLogInterval {
            return
        }
        lastControlLoopLogTime = now
        AppLog.shared.debug("control loop mode=\(mode) sensor=\(reading.sensor.key) temp=\(String(format: "%.2f", reading.value)) targetRPM=\(targetRPM)")
    }
}

// 转速设置窗口控制器
@MainActor
class SpeedSettingWindowController: NSWindowController {
    private var currentRPM: Int = 0
    private let maxRPM: Int
    private var controlMode: ManualRPMControlMode
    private let stepRPM: Int
    private var rpmSlider: NSSlider?
    private var rpmLabel: NSTextField?
    private var controlModeSegmentedControl: NSSegmentedControl?
    private var stepHintLabel: NSTextField?
    private var applyStatusLabel: NSTextField?
    private var applyStatusResetWorkItem: DispatchWorkItem?

    init(initialRPM: Int, maxRPM: Int, controlMode: ManualRPMControlMode, stepRPM: Int) {
        self.maxRPM = maxRPM
        self.controlMode = controlMode
        self.stepRPM = max(stepRPM, 1)
        self.currentRPM = initialRPM

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = appL10n("设置风扇转速", "Set Fan Speed")
        window.center()
        
        super.init(window: window)

        applyWindowMaterialStyle(window)
        setupUI()
        updateSliderDisplay()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        let titleLabel = NSTextField(labelWithString: appL10n("手动模式目标转速:", "Manual Mode Target RPM:"))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let modeLabel = NSTextField(labelWithString: appL10n("调节方式", "Adjustment Mode"))
        modeLabel.textColor = .secondaryLabelColor
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(modeLabel)

        let controlModeSegmentedControl = NSSegmentedControl(labels: [appL10n("连续", "Continuous"), appL10n("档位", "Stepped")], trackingMode: .selectOne, target: self, action: #selector(controlModeChanged))
        controlModeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controlModeSegmentedControl)
        
        let rpmSlider = NSSlider()
        rpmSlider.minValue = 0
        rpmSlider.maxValue = Double(maxRPM)
        rpmSlider.target = self
        rpmSlider.action = #selector(sliderChanged)
        rpmSlider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rpmSlider)
        
        let rpmLabel = NSTextField(labelWithString: "\(currentRPM) RPM")
        rpmLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rpmLabel)

        let stepHintLabel = NSTextField(labelWithString: "")
        stepHintLabel.textColor = .secondaryLabelColor
        stepHintLabel.alignment = .center
        stepHintLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stepHintLabel)

        let applyStatusLabel = NSTextField(labelWithString: appL10n("✓ 已应用", "✓ Applied"))
        applyStatusLabel.textColor = .systemGreen
        applyStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        applyStatusLabel.alignment = .center
        applyStatusLabel.alphaValue = 0
        applyStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(applyStatusLabel)
        
        let applyButton = NSButton(title: appL10n("应用", "Apply"), target: self, action: #selector(applySpeed))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(applyButton)
        
        let cancelButton = NSButton(title: appL10n("取消", "Cancel"), target: self, action: #selector(cancel))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            modeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            modeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            controlModeSegmentedControl.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            controlModeSegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            rpmSlider.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 14),
            rpmSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rpmSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            rpmLabel.topAnchor.constraint(equalTo: rpmSlider.bottomAnchor, constant: 10),
            rpmLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            stepHintLabel.topAnchor.constraint(equalTo: rpmLabel.bottomAnchor, constant: 6),
            stepHintLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            applyStatusLabel.topAnchor.constraint(equalTo: stepHintLabel.bottomAnchor, constant: 6),
            applyStatusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            applyButton.topAnchor.constraint(equalTo: applyStatusLabel.bottomAnchor, constant: 12),
            applyButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -50),
            
            cancelButton.topAnchor.constraint(equalTo: applyStatusLabel.bottomAnchor, constant: 12),
            cancelButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 50)
        ])

        self.rpmSlider = rpmSlider
        self.rpmLabel = rpmLabel
        self.controlModeSegmentedControl = controlModeSegmentedControl
        self.stepHintLabel = stepHintLabel
        self.applyStatusLabel = applyStatusLabel
    }

    private func boundedRPM(_ rpm: Int) -> Int {
        min(max(rpm, 0), maxRPM)
    }

    private func snappedRPM(for rpm: Int) -> Int {
        let bounded = boundedRPM(rpm)
        guard stepRPM > 1 else { return bounded }

        let lower = Int(floor(Double(bounded) / Double(stepRPM))) * stepRPM
        let upper = Int(ceil(Double(bounded) / Double(stepRPM))) * stepRPM
        let candidates = Array(Set([
            boundedRPM(lower),
            boundedRPM(upper),
            maxRPM
        ]))

        return candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs - bounded)
            let rhsDistance = abs(rhs - bounded)
            if lhsDistance == rhsDistance {
                return lhs < rhs
            }
            return lhsDistance < rhsDistance
        } ?? bounded
    }

    private func effectiveRPM(for sliderValue: Double) -> Int {
        let rawRPM = boundedRPM(Int(sliderValue.rounded()))
        if controlMode == .stepped {
            return snappedRPM(for: rawRPM)
        }
        return rawRPM
    }

    private func updateModeUI() {
        controlModeSegmentedControl?.selectedSegment = (controlMode == .continuous) ? 0 : 1
        let isStepped = (controlMode == .stepped)
        stepHintLabel?.stringValue = isStepped ? appL10n("步进：\(stepRPM) RPM", "Step: \(stepRPM) RPM") : ""
        stepHintLabel?.isHidden = !isStepped
    }

    private func updateSliderDisplay() {
        let effectiveRPM = (controlMode == .stepped) ? snappedRPM(for: currentRPM) : boundedRPM(currentRPM)
        currentRPM = effectiveRPM
        rpmSlider?.doubleValue = Double(effectiveRPM)
        rpmLabel?.stringValue = "\(effectiveRPM) RPM"
        updateModeUI()
    }

    @objc func sliderChanged() {
        guard let slider = rpmSlider else { return }
        let rpm = effectiveRPM(for: slider.doubleValue)
        currentRPM = rpm
        slider.doubleValue = Double(rpm)
        rpmLabel?.stringValue = "\(rpm) RPM"
    }

    @objc private func controlModeChanged() {
        controlMode = (controlModeSegmentedControl?.selectedSegment == 1) ? .stepped : .continuous
        updateSliderDisplay()
    }

    @objc func applySpeed() {
        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.manualRPM = currentRPM
        newConfig.manualRPMControlMode = controlMode.rawValue
        newConfig.manualRPMStep = stepRPM
        ConfigManager.shared.saveConfig(newConfig)
        
        MenuBarManager.shared.setFanCurve(newConfig.curve)
        showApplyFeedback()
    }
    
    @objc func cancel() {
        window?.close()
    }

    private func showApplyFeedback() {
        applyStatusResetWorkItem?.cancel()
        guard let label = applyStatusLabel else { return }

        label.alphaValue = 1.0

        let workItem = DispatchWorkItem { [weak label] in
            guard let label else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                label.animator().alphaValue = 0
            }
        }
        applyStatusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
}

@MainActor
class SafetyFloorWindowController: NSWindowController {
    private var currentRPM: Int = 0
    private let minRPM = 2000
    private let maxRPM: Int
    private var rpmSlider: NSSlider?
    private var rpmLabel: NSTextField?
    private var applyStatusLabel: NSTextField?
    private var applyStatusResetWorkItem: DispatchWorkItem?

    init(initialRPM: Int, maxRPM: Int) {
        self.currentRPM = initialRPM
        self.maxRPM = max(maxRPM, minRPM)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = appL10n("安全兜底转速", "Safety Floor RPM")
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

        let titleLabel = NSTextField(labelWithString: appL10n("危险温度（95℃）时的最低兜底转速", "Minimum floor RPM at critical temperature (95°C)"))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let hintLabel = NSTextField(labelWithString: appL10n("仅作托底，不会压低用户曲线已经给出的更高转速", "Only a safety floor; never caps higher RPM requested by your curve"))
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

        let applyStatusLabel = NSTextField(labelWithString: appL10n("✓ 已应用", "✓ Applied"))
        applyStatusLabel.textColor = .systemGreen
        applyStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        applyStatusLabel.alignment = .center
        applyStatusLabel.alphaValue = 0
        applyStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(applyStatusLabel)

        let applyButton = NSButton(title: appL10n("应用", "Apply"), target: self, action: #selector(applyValue))
        applyButton.bezelStyle = .rounded
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(applyButton)

        let cancelButton = NSButton(title: appL10n("取消", "Cancel"), target: self, action: #selector(cancel))
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

            applyStatusLabel.topAnchor.constraint(equalTo: rpmLabel.bottomAnchor, constant: 6),
            applyStatusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            applyButton.topAnchor.constraint(equalTo: applyStatusLabel.bottomAnchor, constant: 12),
            applyButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -44),

            cancelButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            cancelButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 44)
        ])

        self.rpmSlider = rpmSlider
        self.rpmLabel = rpmLabel
        self.applyStatusLabel = applyStatusLabel
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
        showApplyFeedback()
    }

    @objc private func cancel() {
        window?.close()
    }

    private func showApplyFeedback() {
        applyStatusResetWorkItem?.cancel()
        guard let label = applyStatusLabel else { return }

        label.alphaValue = 1.0

        let workItem = DispatchWorkItem { [weak label] in
            guard let label else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                label.animator().alphaValue = 0
            }
        }
        applyStatusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
}

@MainActor
class HelpWindowController: NSWindowController {
    private enum Section: Int, CaseIterable {
        case overview
        case diagnostics
        case faq
        case donation

        func title() -> String {
            switch self {
                case .overview: return appL10n("简介", "Overview")
                case .diagnostics: return appL10n("诊断与支持", "Diagnostics & Support")
                case .faq: return appL10n("常见问题", "FAQ")
                case .donation: return appL10n("支持作者", "Support the Author")
            }
        }
    }

    private var versionLabel: NSTextField?
    private var automaticUpdateCheckbox: NSButton?
    private var currentSection: Section = .overview
    private var sidebarButtons: [Section: NSButton] = [:]
    private var appHeaderView: NSView?
    private var headerSeparatorView: NSView?
    private var sectionContainerView: NSView?
    private var sectionTitleLabel: NSTextField?
    private var sectionViews: [Section: NSView] = [:]
    private var donationMethodControl: NSSegmentedControl?
    private var qrImageView: NSImageView?
    private var qrCaptionLabel: NSTextField?
    private let qrContext = CIContext(options: nil)
    private let sidebarWidth: CGFloat = 176
    private let contentWidth: CGFloat = 600

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = appL10n("关于/帮助", "About / Help")
        window.center()

        super.init(window: window)
        applyWindowMaterialStyle(window)
        setupUI()
        select(section: .overview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        return label
    }

    private func makeCardView() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.84).cgColor
        return card
    }

    private func makeBodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSymbolView(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular) -> NSImageView {
        let view = NSImageView()
        if let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: pointSize, weight: weight)) {
            view.image = image
        }
        view.imageScaling = .scaleProportionallyUpOrDown
        view.contentTintColor = .secondaryLabelColor
        return view
    }

    private func makeSectionRoot(horizontalCentered: Bool = false, verticalCentered: Bool = false) -> (NSView, NSStackView) {
        let root = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let horizontalConstraint: NSLayoutConstraint = horizontalCentered
            ? stack.centerXAnchor.constraint(equalTo: root.centerXAnchor)
            : stack.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        let topConstraint: NSLayoutConstraint = verticalCentered
            ? stack.centerYAnchor.constraint(equalTo: root.centerYAnchor)
            : stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 8)

        NSLayoutConstraint.activate([
            topConstraint,
            horizontalConstraint,
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: root.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])
        return (root, stack)
    }

    private func makeSidebarButton(for section: Section) -> NSButton {
        let button = NSButton(title: section.title(), target: self, action: #selector(sidebarButtonClicked(_:)))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.font = .systemFont(ofSize: 15, weight: .semibold)
        button.alignment = .center
        button.contentTintColor = .labelColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 13
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.widthAnchor.constraint(equalToConstant: 132).isActive = true
        button.identifier = NSUserInterfaceItemIdentifier("sidebar-\(section.rawValue)")
        return button
    }

    private func updateSidebarSelection() {
        for (section, button) in sidebarButtons {
            let isSelected = section == currentSection
            button.contentTintColor = isSelected ? .white : .labelColor
            button.layer?.backgroundColor = isSelected
                ? NSColor.systemRed.cgColor
                : NSColor.clear.cgColor
        }
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let sidebarContainer = NSView()
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.widthAnchor.constraint(equalToConstant: sidebarWidth).isActive = true
        splitView.addArrangedSubview(sidebarContainer)

        let sidebarBackground = NSVisualEffectView()
        sidebarBackground.material = .sidebar
        sidebarBackground.blendingMode = .withinWindow
        sidebarBackground.state = .active
        sidebarBackground.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(sidebarBackground)
        NSLayoutConstraint.activate([
            sidebarBackground.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarBackground.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarBackground.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            sidebarBackground.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor)
        ])

        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .centerX
        sidebarStack.spacing = 12
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(sidebarStack)
        NSLayoutConstraint.activate([
            sidebarStack.centerXAnchor.constraint(equalTo: sidebarContainer.centerXAnchor),
            sidebarStack.centerYAnchor.constraint(equalTo: sidebarContainer.centerYAnchor),
            sidebarStack.leadingAnchor.constraint(greaterThanOrEqualTo: sidebarContainer.leadingAnchor, constant: 12),
            sidebarStack.trailingAnchor.constraint(lessThanOrEqualTo: sidebarContainer.trailingAnchor, constant: -12)
        ])

        var buttons: [Section: NSButton] = [:]
        for section in Section.allCases {
            let button = makeSidebarButton(for: section)
            sidebarStack.addArrangedSubview(button)
            buttons[section] = button
        }
        let rightContainer = NSView()
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(rightContainer)

        let rightRoot = NSStackView()
        rightRoot.orientation = .vertical
        rightRoot.spacing = 12
        rightRoot.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(rightRoot)
        NSLayoutConstraint.activate([
            rightRoot.topAnchor.constraint(equalTo: rightContainer.topAnchor, constant: 14),
            rightRoot.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 18),
            rightRoot.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -18),
            rightRoot.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor, constant: -14)
        ])

        let appHeader = NSStackView()
        appHeader.orientation = .horizontal
        appHeader.alignment = .centerY
        appHeader.spacing = 10

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 10
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 44).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        appHeader.addArrangedSubview(iconView)

        let appTitleStack = NSStackView()
        appTitleStack.orientation = .vertical
        appTitleStack.spacing = 2
        let appTitle = NSTextField(labelWithString: "iFanControl")
        appTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        let versionLabel = NSTextField(labelWithString: appL10n("版本 \(UpdateService.shared.currentVersionDisplay)", "Version \(UpdateService.shared.currentVersionDisplay)"))
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.font = .systemFont(ofSize: 12)
        appTitleStack.addArrangedSubview(appTitle)
        appTitleStack.addArrangedSubview(versionLabel)
        appHeader.addArrangedSubview(appTitleStack)
        appHeader.addArrangedSubview(NSView())
        rightRoot.addArrangedSubview(appHeader)

        let separator = NSBox()
        separator.boxType = .separator
        rightRoot.addArrangedSubview(separator)

        let sectionTitleLabel = makeSectionTitle("")
        sectionTitleLabel.alignment = .center
        rightRoot.addArrangedSubview(sectionTitleLabel)

        let sectionScroll = NSScrollView()
        sectionScroll.drawsBackground = false
        sectionScroll.hasVerticalScroller = true
        sectionScroll.autohidesScrollers = true
        sectionScroll.scrollerStyle = .overlay
        sectionScroll.translatesAutoresizingMaskIntoConstraints = false
        rightRoot.addArrangedSubview(sectionScroll)
        sectionScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        let sectionCanvas = NSView()
        sectionCanvas.translatesAutoresizingMaskIntoConstraints = false
        sectionScroll.documentView = sectionCanvas

        let sectionContent = NSView()
        sectionContent.translatesAutoresizingMaskIntoConstraints = false
        sectionCanvas.addSubview(sectionContent)
        NSLayoutConstraint.activate([
            sectionCanvas.leadingAnchor.constraint(equalTo: sectionScroll.contentView.leadingAnchor),
            sectionCanvas.trailingAnchor.constraint(equalTo: sectionScroll.contentView.trailingAnchor),
            sectionCanvas.topAnchor.constraint(equalTo: sectionScroll.contentView.topAnchor),
            sectionCanvas.bottomAnchor.constraint(equalTo: sectionScroll.contentView.bottomAnchor),
            sectionCanvas.widthAnchor.constraint(equalTo: sectionScroll.contentView.widthAnchor),

            sectionContent.topAnchor.constraint(equalTo: sectionCanvas.topAnchor),
            sectionContent.centerXAnchor.constraint(equalTo: sectionCanvas.centerXAnchor),
            sectionContent.widthAnchor.constraint(equalToConstant: contentWidth),
            sectionContent.widthAnchor.constraint(lessThanOrEqualTo: sectionCanvas.widthAnchor),
            sectionContent.bottomAnchor.constraint(equalTo: sectionCanvas.bottomAnchor)
        ])

        self.versionLabel = versionLabel
        self.sidebarButtons = buttons
        self.appHeaderView = appHeader
        self.headerSeparatorView = separator
        self.sectionContainerView = sectionContent
        self.sectionTitleLabel = sectionTitleLabel

        buildSectionViews()
        refreshDonationPreview()
        updateSidebarSelection()
    }

    private func buildSectionViews() {
        guard let container = sectionContainerView else { return }
        sectionViews = [
            .overview: makeOverviewSection(),
            .diagnostics: makeDiagnosticsSection(),
            .faq: makeFAQSection(),
            .donation: makeDonationSection()
        ]

        for view in sectionViews.values {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            view.isHidden = true
        }
    }

    private func makeOverviewSection() -> NSView {
        let (view, stack) = makeSectionRoot(horizontalCentered: true, verticalCentered: true)

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 20
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 108).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 108).isActive = true
        stack.addArrangedSubview(iconView)

        let appName = NSTextField(labelWithString: "iFanControl")
        appName.font = .systemFont(ofSize: 36, weight: .bold)
        appName.alignment = .center
        stack.addArrangedSubview(appName)

        let version = NSTextField(labelWithString: appL10n("版本 \(UpdateService.shared.currentVersionDisplay)", "Version \(UpdateService.shared.currentVersionDisplay)"))
        version.font = .systemFont(ofSize: 18, weight: .medium)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        stack.addArrangedSubview(version)

        let intro = makeBodyLabel(
            appL10n(
                "iFanControl 是一款面向 Apple Silicon 设备的轻量风扇控制工具，支持自动曲线与手动转速。",
                "iFanControl is a lightweight fan control utility for Apple Silicon devices, supporting auto curves and manual RPM."
            )
        )
        intro.font = .systemFont(ofSize: 14)
        intro.alignment = .center
        intro.preferredMaxLayoutWidth = 420
        stack.addArrangedSubview(intro)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        let restartButton = NSButton(title: appL10n("重新启动", "Restart"), target: self, action: #selector(restartApp))
        restartButton.bezelStyle = .rounded
        let updateButton = NSButton(title: appL10n("检查更新", "Check Updates"), target: self, action: #selector(checkUpdates))
        updateButton.bezelStyle = .rounded
        let githubButton = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        buttonRow.addArrangedSubview(restartButton)
        buttonRow.addArrangedSubview(updateButton)
        buttonRow.addArrangedSubview(githubButton)
        stack.addArrangedSubview(buttonRow)

        let autoCheck = NSButton(
            checkboxWithTitle: appL10n("自动检查更新", "Check updates automatically"),
            target: self,
            action: #selector(toggleAutomaticChecks(_:))
        )
        autoCheck.state = UpdateService.shared.automaticChecksEnabled ? .on : .off
        automaticUpdateCheckbox = autoCheck
        stack.addArrangedSubview(autoCheck)
        return view
    }

    private func makeDiagnosticsSection() -> NSView {
        let (view, stack) = makeSectionRoot(horizontalCentered: true, verticalCentered: true)

        let supportCard = makeCardView()
        supportCard.translatesAutoresizingMaskIntoConstraints = false
        supportCard.widthAnchor.constraint(equalToConstant: 410).isActive = true
        supportCard.heightAnchor.constraint(equalToConstant: 410).isActive = true
        stack.addArrangedSubview(supportCard)

        let supportStack = NSStackView()
        supportStack.orientation = .vertical
        supportStack.alignment = .centerX
        supportStack.spacing = 18
        supportStack.translatesAutoresizingMaskIntoConstraints = false
        supportCard.addSubview(supportStack)
        NSLayoutConstraint.activate([
            supportStack.centerXAnchor.constraint(equalTo: supportCard.centerXAnchor),
            supportStack.centerYAnchor.constraint(equalTo: supportCard.centerYAnchor),
            supportStack.leadingAnchor.constraint(greaterThanOrEqualTo: supportCard.leadingAnchor, constant: 28),
            supportStack.trailingAnchor.constraint(lessThanOrEqualTo: supportCard.trailingAnchor, constant: -28),
            supportStack.topAnchor.constraint(greaterThanOrEqualTo: supportCard.topAnchor, constant: 28),
            supportStack.bottomAnchor.constraint(lessThanOrEqualTo: supportCard.bottomAnchor, constant: -28)
        ])

        let supportTitle = NSTextField(labelWithString: appL10n("先导出诊断包，再发邮件给我们。", "Export diagnostics first, then email us."))
        supportTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        supportTitle.alignment = .center
        supportTitle.maximumNumberOfLines = 0
        supportTitle.lineBreakMode = .byWordWrapping
        supportTitle.preferredMaxLayoutWidth = 300
        supportStack.addArrangedSubview(supportTitle)

        let supportHint = makeBodyLabel(
            appL10n(
                "我们会结合日志更快定位问题。若只是小异常，也可以先试试重新启动或检查更新。",
                "Logs help us diagnose issues faster. For smaller problems, you can also try restarting the app or checking for updates first."
            )
        )
        supportHint.font = .systemFont(ofSize: 14)
        supportHint.preferredMaxLayoutWidth = 300
        supportHint.alignment = .center
        supportStack.addArrangedSubview(supportHint)

        let primaryButtons = NSStackView()
        primaryButtons.orientation = .horizontal
        primaryButtons.spacing = 10
        primaryButtons.alignment = .centerY

        let exportButton = NSButton(title: appL10n("导出诊断包", "Export Diagnostics"), target: self, action: #selector(exportDiagnostics))
        exportButton.bezelStyle = .rounded
        let contactButton = NSButton(title: appL10n("联系支持", "Contact Support"), target: self, action: #selector(contactSupport))
        contactButton.bezelStyle = .rounded
        let uninstallButton = NSButton(title: appL10n("完整卸载", "Full Uninstall"), target: self, action: #selector(uninstallControlComponents))
        uninstallButton.bezelStyle = .rounded
        primaryButtons.addArrangedSubview(exportButton)
        primaryButtons.addArrangedSubview(contactButton)
        primaryButtons.addArrangedSubview(uninstallButton)
        supportStack.addArrangedSubview(primaryButtons)

        let helperHint = NSTextField(labelWithString: appL10n("也可以先做这两步快速自检：", "You can also try these quick checks first:"))
        helperHint.font = .systemFont(ofSize: 12, weight: .medium)
        helperHint.textColor = .tertiaryLabelColor
        helperHint.alignment = .center
        supportStack.addArrangedSubview(helperHint)

        let secondaryButtons = NSStackView()
        secondaryButtons.orientation = .horizontal
        secondaryButtons.spacing = 10
        secondaryButtons.alignment = .centerY
        let restartButton = NSButton(title: appL10n("重新启动", "Restart"), target: self, action: #selector(restartApp))
        restartButton.bezelStyle = .rounded
        let updateButton = NSButton(title: appL10n("检查更新", "Check Updates"), target: self, action: #selector(checkUpdates))
        updateButton.bezelStyle = .rounded
        let openLogButton = NSButton(title: appL10n("打开日志目录", "Open Log Folder"), target: self, action: #selector(openLogFolder))
        openLogButton.bezelStyle = .rounded
        secondaryButtons.addArrangedSubview(restartButton)
        secondaryButtons.addArrangedSubview(updateButton)
        secondaryButtons.addArrangedSubview(openLogButton)
        supportStack.addArrangedSubview(secondaryButtons)
        return view
    }

    private func makeFAQSection() -> NSView {
        let (view, stack) = makeSectionRoot(horizontalCentered: true)

        let intro = makeBodyLabel(appL10n("整理了最常遇到的几个问题，方便快速定位设置逻辑。", "A short set of answers for the most common questions."))
        intro.font = .systemFont(ofSize: 14)
        intro.preferredMaxLayoutWidth = contentWidth
        intro.alignment = .center
        stack.addArrangedSubview(intro)

        let faqItems: [(String, String)] = [
            (
                appL10n("温度源是自动选择的吗？", "How is the temperature source selected?"),
                appL10n("默认自动选择最热传感器；也可以在主界面手动固定某个温度源。", "By default the hottest sensor is selected automatically; you can pin a specific source in the main panel.")
            ),
            (
                appL10n("为什么传感器数量和核心数不一致？", "Why does sensor count differ from core count?"),
                appL10n("温度传感器由硬件与系统暴露机制决定，不一定和 CPU/GPU 核心一一对应。", "Sensor count depends on hardware and OS exposure and does not necessarily map 1:1 to CPU/GPU cores.")
            ),
            (
                appL10n("自动模式和手动模式有什么区别？", "Auto mode vs Manual mode?"),
                appL10n("自动模式会按温度曲线调速；手动模式会保持你设置的目标转速。", "Auto mode follows the temperature curve; manual mode keeps your target RPM.")
            ),
            (
                appL10n("遇到兼容问题怎么办？", "What if compatibility issues occur?"),
                appL10n("先到“诊断与支持”导出诊断包，再联系支持并附上 ZIP。", "Export diagnostics from Diagnostics & Support, then contact support with the ZIP attached.")
            )
        ]

        for item in faqItems {
            let card = makeCardView()
            card.translatesAutoresizingMaskIntoConstraints = false
            card.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            stack.addArrangedSubview(card)

            let qaStack = NSStackView()
            qaStack.orientation = .vertical
            qaStack.spacing = 8
            qaStack.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(qaStack)

            let q = NSTextField(labelWithString: item.0)
            q.font = .systemFont(ofSize: 16, weight: .semibold)
            qaStack.addArrangedSubview(q)

            let a = makeBodyLabel(item.1)
            a.font = .systemFont(ofSize: 14)
            a.preferredMaxLayoutWidth = contentWidth - 48
            qaStack.addArrangedSubview(a)

            NSLayoutConstraint.activate([
                qaStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
                qaStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
                qaStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
                qaStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
            ])
        }
        return view
    }

    private func makeDonationSection() -> NSView {
        let (view, stack) = makeSectionRoot(horizontalCentered: true, verticalCentered: true)
        stack.alignment = .centerX

        let coffeeIcon = makeSymbolView("cup.and.saucer.fill", pointSize: 28, weight: .medium)
        coffeeIcon.contentTintColor = NSColor.systemBrown
        coffeeIcon.translatesAutoresizingMaskIntoConstraints = false
        coffeeIcon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        coffeeIcon.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(coffeeIcon)

        let introTitle = NSTextField(labelWithString: appL10n("请作者喝杯咖啡", "Buy the author a coffee"))
        introTitle.font = .systemFont(ofSize: 22, weight: .bold)
        introTitle.alignment = .center
        stack.addArrangedSubview(introTitle)

        let intro = makeBodyLabel(appL10n("喜欢 iFanControl 的话，欢迎续一杯。", "If you enjoy iFanControl, a coffee is always welcome."))
        intro.font = .systemFont(ofSize: 14)
        intro.preferredMaxLayoutWidth = 360
        intro.alignment = .center
        stack.addArrangedSubview(intro)

        let methodControl = NSSegmentedControl(
            labels: [appL10n("微信", "WeChat"), appL10n("支付宝", "Alipay")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(donationMethodChanged)
        )
        methodControl.selectedSegment = 0
        stack.addArrangedSubview(methodControl)

        let qrCard = NSView()
        qrCard.wantsLayer = true
        qrCard.layer?.cornerRadius = 18
        qrCard.layer?.borderWidth = 1
        qrCard.layer?.borderColor = NSColor.separatorColor.cgColor
        qrCard.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        qrCard.translatesAutoresizingMaskIntoConstraints = false
        qrCard.widthAnchor.constraint(equalToConstant: 280).isActive = true
        stack.addArrangedSubview(qrCard)

        let qrStack = NSStackView()
        qrStack.orientation = .vertical
        qrStack.spacing = 8
        qrStack.alignment = .centerX
        qrStack.translatesAutoresizingMaskIntoConstraints = false
        qrCard.addSubview(qrStack)
        NSLayoutConstraint.activate([
            qrStack.topAnchor.constraint(equalTo: qrCard.topAnchor, constant: 12),
            qrStack.leadingAnchor.constraint(equalTo: qrCard.leadingAnchor, constant: 12),
            qrStack.trailingAnchor.constraint(equalTo: qrCard.trailingAnchor, constant: -12),
            qrStack.bottomAnchor.constraint(equalTo: qrCard.bottomAnchor, constant: -12)
        ])

        let caption = NSTextField(labelWithString: "")
        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.textColor = .secondaryLabelColor

        let qrImage = NSImageView()
        qrImage.imageScaling = .scaleProportionallyUpOrDown
        qrImage.wantsLayer = true
        qrImage.layer?.backgroundColor = NSColor.white.cgColor
        qrImage.layer?.cornerRadius = 12
        qrImage.layer?.masksToBounds = true
        qrImage.translatesAutoresizingMaskIntoConstraints = false
        qrImage.widthAnchor.constraint(equalToConstant: 168).isActive = true
        qrImage.heightAnchor.constraint(equalToConstant: 168).isActive = true

        let hint = NSTextField(labelWithString: appL10n("感谢支持，帮助 iFanControl 持续改进。", "Thank you for helping iFanControl keep improving."))
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 13)

        qrStack.addArrangedSubview(caption)
        qrStack.addArrangedSubview(qrImage)
        qrStack.addArrangedSubview(hint)

        self.donationMethodControl = methodControl
        self.qrImageView = qrImage
        self.qrCaptionLabel = caption
        return view
    }

    override func showWindow(_ sender: Any?) {
        window?.title = appL10n("关于/帮助", "About / Help")
        versionLabel?.stringValue = appL10n("版本 \(UpdateService.shared.currentVersionDisplay)", "Version \(UpdateService.shared.currentVersionDisplay)")
        automaticUpdateCheckbox?.state = UpdateService.shared.automaticChecksEnabled ? .on : .off
        refreshDonationPreview()
        super.showWindow(sender)
    }

    private func select(section: Section) {
        currentSection = section
        sectionTitleLabel?.stringValue = section.title()
        let isOverview = section == .overview
        appHeaderView?.isHidden = isOverview
        headerSeparatorView?.isHidden = isOverview
        sectionTitleLabel?.isHidden = isOverview
        for (key, view) in sectionViews {
            view.isHidden = (key != section)
        }
        updateSidebarSelection()
    }

    @objc private func sidebarButtonClicked(_ sender: NSButton) {
        guard let match = sidebarButtons.first(where: { $0.value === sender })?.key else { return }
        select(section: match)
    }

    @objc private func donationMethodChanged() {
        refreshDonationPreview()
    }

    private func refreshDonationPreview() {
        let selected = donationMethodControl?.selectedSegment ?? 0
        let isWechat = selected == 0
        let payload = isWechat ? wechatDonatePayload : alipayDonatePayload
        let caption = isWechat ? appL10n("微信赞赏码", "WeChat Donation QR") : appL10n("支付宝收款码", "Alipay Donation QR")
        qrCaptionLabel?.stringValue = caption
        qrImageView?.image = generateQRCodeImage(from: payload, targetSize: 168)
    }

    private func generateQRCodeImage(from string: String, targetSize: CGFloat) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let extent = outputImage.extent.integral
        guard extent.width > 0 else { return nil }
        let scale = max(1, floor(targetSize / extent.width))
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = qrContext.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
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

    @objc private func openLogFolder() {
        _ = AppLog.shared.openLogDirectoryInFinder()
    }

    @objc private func contactSupport() {
        AppLog.shared.composeSupportEmail()
    }

    @objc private func exportDiagnostics() {
        MenuBarManager.shared.exportDiagnosticArchive()
    }

    @objc private func uninstallControlComponents() {
        AppDelegate.shared?.beginUninstallFlow()
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
