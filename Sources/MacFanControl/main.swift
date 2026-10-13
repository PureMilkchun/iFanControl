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
import Darwin
import Foundation
import FanCurveEditor
import IOReportBridge
import OSLog
import ServiceManagement

// 使用 FanCurveEditor 中的类型
typealias FanPoint = FanCurveEditor.FanPoint
typealias Config = FanCurveEditor.Config

struct TemperatureReading {
    let sensor: TemperatureSensorDefinition
    let value: Double
}

private func averagedTemperatureSourceDefinition(for mode: String?) -> TemperatureSensorDefinition? {
    switch mode {
    case "cpu_average":
        return SensorCatalog.cpuAverageTemperatureSource
    case "gpu_average":
        return SensorCatalog.gpuAverageTemperatureSource
    default:
        return nil
    }
}

private func averageTemperatureReading(
    from readings: [TemperatureReading],
    category: TemperatureSensorCategory,
    source: TemperatureSensorDefinition
) -> TemperatureReading? {
    let componentReadings = readings.filter { $0.sensor.category == category }
    guard !componentReadings.isEmpty else {
        return nil
    }
    let average = componentReadings.map(\.value).reduce(0, +) / Double(componentReadings.count)
    return TemperatureReading(sensor: source, value: average)
}

private func selectedTemperatureReading(from readings: [TemperatureReading], config: Config) -> TemperatureReading? {
    guard !readings.isEmpty else {
        return nil
    }

    switch config.temperatureSourceMode {
    case "cpu_average":
        return averageTemperatureReading(
            from: readings,
            category: .cpu,
            source: SensorCatalog.cpuAverageTemperatureSource
        )
    case "gpu_average":
        return averageTemperatureReading(
            from: readings,
            category: .gpu,
            source: SensorCatalog.gpuAverageTemperatureSource
        )
    case "manual":
        if let selectedKey = config.selectedTemperatureSensorKey,
           let selected = readings.first(where: { $0.sensor.key == selectedKey }) {
            return selected
        }
        fallthrough
    default:
        return readings.max(by: { $0.value < $1.value })
    }
}

struct FanInfo {
    let index: Int
    let actualKey: String
    let minRPM: Int?
    let maxRPM: Int?
}

private let appSubsystem = Bundle.main.bundleIdentifier ?? "com.ifancontrol.app"
private let defaultManualRPMStep = 500
private let backgroundTelemetryStaleThreshold: TimeInterval = 15.0
private let backgroundTelemetryExpiryThreshold: TimeInterval = 45.0
private let supportEmailAddress = "puremilkchun@foxmail.com"
private let wechatDonatePayload = "wxp://f2f0rVY6iLnpjTqEKL4HKTHRw3Ej81vNbWU9UUXk4msd30ehG7Xh9NwXEyNsZaTn5gZE"
private let alipayDonatePayload = "https://qr.alipay.com/fkx16601ptfadpsxd3mfpf6"
private let currentLanguage: String = {
    if let saved = UserDefaults.standard.string(forKey: "ifancontrol.ui.language") {
        return saved
    }
    return Locale.preferredLanguages.first?.lowercased().hasPrefix("en") == true ? "en" : "zh"
}()
private func appL10n(_ zh: String, _ en: String) -> String {
    currentLanguage == "en" ? en : zh
}

private func sysctlString(named name: String) -> String? {
    var size: size_t = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
        return nil
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
        return nil
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

private let systemModelIdentifier: String = {
    sysctlString(named: "hw.model") ?? "unknown"
}()

private let systemArchitecture: String = {
    var uts = utsname()
    uname(&uts)
    return withUnsafePointer(to: &uts.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
            String(cString: $0)
        }
    }
}()

private enum TelemetrySnapshotState: String {
    case fresh
    case cachedStale = "cached_stale"
    case expired
}

private struct ControlStatusSnapshot {
    let mode: String
    let detail: String
    let recordedAt: Date
}

private enum ControlStatusStore {
    private static let modeKey = "ifancontrol.control_status.mode"
    private static let detailKey = "ifancontrol.control_status.detail"
    private static let recordedAtKey = "ifancontrol.control_status.recorded_at"

    static func load() -> ControlStatusSnapshot? {
        let defaults = UserDefaults.standard
        guard let mode = defaults.string(forKey: modeKey),
              let detail = defaults.string(forKey: detailKey),
              let recordedAt = defaults.object(forKey: recordedAtKey) as? Date else {
            return nil
        }
        return ControlStatusSnapshot(mode: mode, detail: detail, recordedAt: recordedAt)
    }

    static func save(mode: String, detail: String, recordedAt: Date = Date()) {
        let defaults = UserDefaults.standard
        defaults.set(mode, forKey: modeKey)
        defaults.set(detail, forKey: detailKey)
        defaults.set(recordedAt, forKey: recordedAtKey)
    }
}

private struct PowerTelemetrySnapshot {
    let cpuWatts: Double
    let gpuWatts: Double
    let aneWatts: Double
    let ramWatts: Double
    let pciWatts: Double
    let dcInWatts: Double?
    let lastUpdatedAt: Date?
    let isSupported: Bool

    var componentTotalWatts: Double {
        cpuWatts + gpuWatts + aneWatts + ramWatts + pciWatts
    }

    var displayTotalWatts: Double {
        if let dcInWatts, dcInWatts > 0 {
            return dcInWatts
        }
        return componentTotalWatts
    }

    var hasAnyReading: Bool {
        lastUpdatedAt != nil
    }
}

private final class PowerTelemetryReader: @unchecked Sendable {
    static let shared = PowerTelemetryReader()

    private let queue = DispatchQueue(label: "com.ifancontrol.power-telemetry", qos: .utility)
    private let kentsmcPath = "/usr/local/bin/kentsmc"
    private let lock = NSLock()
    private var _refreshInFlight = false
    private var _snapshot = PowerTelemetrySnapshot(
        cpuWatts: 0,
        gpuWatts: 0,
        aneWatts: 0,
        ramWatts: 0,
        pciWatts: 0,
        dcInWatts: nil,
        lastUpdatedAt: nil,
        isSupported: false
    )
    private var _loggedFirstSuccess = false

#if arch(arm64)
    private var channels: CFMutableDictionary?
    private var subscription: IOReportSubscriptionRef?
    private var lastReadAt: Date?
    private var previousEnergies: (cpu: Double, gpu: Double, ane: Double, ram: Double, pci: Double)?
#endif

    private init() {
#if arch(arm64)
        self.channels = makeChannels()
        if let channels {
            var dict: Unmanaged<CFMutableDictionary>?
            self.subscription = IOReportCreateSubscription(nil, channels, &dict, 0, nil)
            dict?.release()
        }
#endif
        let supported = {
#if arch(arm64)
            self.subscription != nil
#else
            false
#endif
        }()
        _snapshot = PowerTelemetrySnapshot(
            cpuWatts: 0,
            gpuWatts: 0,
            aneWatts: 0,
            ramWatts: 0,
            pciWatts: 0,
            dcInWatts: nil,
            lastUpdatedAt: nil,
            isSupported: supported
        )
        if !supported {
            AppLog.shared.info("power telemetry unsupported or unavailable")
        }
    }

    var snapshot: PowerTelemetrySnapshot {
        lock.lock(); defer { lock.unlock() }
        return _snapshot
    }

    func refresh() {
        lock.lock()
        if _refreshInFlight {
            lock.unlock()
            return
        }
        _refreshInFlight = true
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self._refreshInFlight = false
                self.lock.unlock()
            }

            guard let updated = self.readSnapshot() else { return }

            self.lock.lock()
            self._snapshot = updated
            let shouldLogSuccess = !self._loggedFirstSuccess && updated.hasAnyReading
            if shouldLogSuccess {
                self._loggedFirstSuccess = true
            }
            self.lock.unlock()

            if shouldLogSuccess {
                AppLog.shared.info(
                    "power telemetry ready cpu=\(String(format: "%.2f", updated.cpuWatts)) " +
                    "gpu=\(String(format: "%.2f", updated.gpuWatts)) " +
                    "ane=\(String(format: "%.2f", updated.aneWatts)) " +
                    "ram=\(String(format: "%.2f", updated.ramWatts)) " +
                    "pci=\(String(format: "%.2f", updated.pciWatts)) " +
                    "dcin=\(String(format: "%.2f", updated.dcInWatts ?? 0))"
                )
            }
        }
    }

    private func readSnapshot() -> PowerTelemetrySnapshot? {
#if arch(arm64)
        guard let subscription, let channels else {
            return PowerTelemetrySnapshot(
                cpuWatts: 0, gpuWatts: 0, aneWatts: 0, ramWatts: 0, pciWatts: 0, dcInWatts: nil,
                lastUpdatedAt: nil, isSupported: false
            )
        }
        guard let reportSample = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue(),
              let dict = reportSample as? [String: Any],
              let rawItems = dict["IOReportChannels"] else {
            return nil
        }
        let items = rawItems as! CFArray

        var current = (cpu: 0.0, gpu: 0.0, ane: 0.0, ram: 0.0, pci: 0.0)
        for index in 0..<CFArrayGetCount(items) {
            let rawValue = CFArrayGetValueAtIndex(items, index)
            let item = unsafeBitCast(rawValue, to: CFDictionary.self)
            guard let group = IOReportChannelGetGroup(item)?.takeUnretainedValue() as? String,
                  group == "Energy Model",
                  let channel = IOReportChannelGetChannelName(item)?.takeUnretainedValue() as? String else {
                continue
            }

            let rawEnergy = Double(IOReportSimpleGetIntegerValue(item, 0))
            let unitLabel = (IOReportChannelGetUnitLabel(item)?.takeUnretainedValue() as? String) ?? ""
            let joules = Self.energyToJoules(rawEnergy, unitLabel: unitLabel)

            if channel.hasSuffix("CPU Energy") {
                current.cpu = joules
            } else if channel.hasSuffix("GPU Energy") {
                current.gpu = joules
            } else if channel.hasPrefix("ANE") {
                current.ane = joules
            } else if channel.hasPrefix("DRAM") {
                current.ram = joules
            } else if channel.hasPrefix("PCI") && channel.hasSuffix("Energy") {
                current.pci = joules
            }
        }

        let now = Date()
        defer {
            previousEnergies = current
            lastReadAt = now
        }

        guard let previous = previousEnergies, let previousReadAt = lastReadAt else {
            return PowerTelemetrySnapshot(
                cpuWatts: 0, gpuWatts: 0, aneWatts: 0, ramWatts: 0, pciWatts: 0, dcInWatts: readSMCPower(key: "PDTR"),
                lastUpdatedAt: nil, isSupported: true
            )
        }

        let elapsed = now.timeIntervalSince(previousReadAt)
        guard elapsed > 0 else { return nil }

        return PowerTelemetrySnapshot(
            cpuWatts: max(0, (current.cpu - previous.cpu) / elapsed),
            gpuWatts: max(0, (current.gpu - previous.gpu) / elapsed),
            aneWatts: max(0, (current.ane - previous.ane) / elapsed),
            ramWatts: max(0, (current.ram - previous.ram) / elapsed),
            pciWatts: max(0, (current.pci - previous.pci) / elapsed),
            dcInWatts: readSMCPower(key: "PDTR"),
            lastUpdatedAt: now,
            isSupported: true
        )
#else
        return PowerTelemetrySnapshot(
            cpuWatts: 0, gpuWatts: 0, aneWatts: 0, ramWatts: 0, pciWatts: 0, dcInWatts: nil,
            lastUpdatedAt: nil, isSupported: false
        )
#endif
    }

#if arch(arm64)
    private func makeChannels() -> CFMutableDictionary? {
        guard let channel = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else {
            return nil
        }
        let size = CFDictionaryGetCount(channel)
        guard let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, size, channel),
              let dict = mutable as? [String: Any],
              dict["IOReportChannels"] != nil else {
            return nil
        }
        return mutable
    }
#endif

    private static func energyToJoules(_ raw: Double, unitLabel: String) -> Double {
        switch unitLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "j":
            return raw
        case "mj":
            return raw / 1_000
        case "uj", "µj":
            return raw / 1_000_000
        case "nj":
            return raw / 1_000_000_000
        case "pj":
            return raw / 1_000_000_000_000
        default:
            // Stats defaults to nJ when the unit label is unusual/blank.
            return raw / 1_000_000_000
        }
    }

    private func readSMCPower(key: String) -> Double? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: kentsmcPath)
        task.arguments = ["-r", key]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8),
                  let range = output.range(of: "\\((-?\\d+(?:\\.\\d+)?)\\)", options: .regularExpression) else {
                return nil
            }
            return Double(output[range].dropFirst().dropLast())
        } catch {
            return nil
        }
    }
}

private final class ThermalAnomalyAlertService: @unchecked Sendable {
    static let shared = ThermalAnomalyAlertService()

    private struct Bucket {
        let bucketStart: TimeInterval
        var firstSampleAt: TimeInterval
        var lastSampleAt: TimeInterval
        var sampleCount: Int
        var accumulatedDuration: TimeInterval
        var autoDuration: TimeInterval
        var hotEnergyJoules: Double
        var normalizedRPMTimeIntegral: Double
        var temperatureTimeIntegral: Double
        var rpmHighDuration: TimeInterval
        var tempHighDuration: TimeInterval
    }

    private let queue = DispatchQueue(label: "com.ifancontrol.thermal-alert", qos: .utility)
    private let enabledKey = "ifancontrol.thermal_alert.enabled"
    private let lastAlertAtKey = "ifancontrol.thermal_alert.last_alert_at"
    private let bucketDuration: TimeInterval = 600
    private let minimumBucketSpan: TimeInterval = 480
    private let minimumBucketSamples = 200
    private let hotPowerThreshold = 10.0
    private let highRPMThreshold = 0.60
    private let highTemperatureThreshold = 100.0
    private let sustainedFractionThreshold = 0.90
    private let cooldownInterval: TimeInterval = 12 * 60 * 60

    private var currentBucket: Bucket?
    private var lastFinalizedBucketStart: TimeInterval?
    private var lastBucketQualified = false
    private var consecutiveQualifiedBuckets = 0
    private var qualifyingBucketStarts: [TimeInterval] = []

    private init() {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: enabledKey)
        }
    }

    func recordSample(
        timestamp: TimeInterval,
        weightedHotTemperatureCelsius: Double?,
        hottestFanRPM: Int?,
        currentMaxRPM: Int,
        hotWatts: Double,
        controlModeAutomatic: Bool
    ) {
        guard UserDefaults.standard.bool(forKey: enabledKey),
              let temperature = weightedHotTemperatureCelsius,
              let hottestFanRPM,
              currentMaxRPM > 0 else {
            return
        }

        let normalizedRPM = min(max(Double(hottestFanRPM) / Double(currentMaxRPM), 0), 1)
        let bucketStart = floor(timestamp / bucketDuration) * bucketDuration

        queue.async { [weak self] in
            guard let self else { return }

            if self.currentBucket == nil {
                self.currentBucket = Bucket(
                    bucketStart: bucketStart,
                    firstSampleAt: timestamp,
                    lastSampleAt: timestamp,
                    sampleCount: 0,
                    accumulatedDuration: 0,
                    autoDuration: 0,
                    hotEnergyJoules: 0,
                    normalizedRPMTimeIntegral: 0,
                    temperatureTimeIntegral: 0,
                    rpmHighDuration: 0,
                    tempHighDuration: 0
                )
            } else if self.currentBucket?.bucketStart != bucketStart {
                if let finished = self.currentBucket {
                    self.finalize(bucket: finished)
                }
                self.currentBucket = Bucket(
                    bucketStart: bucketStart,
                    firstSampleAt: timestamp,
                    lastSampleAt: timestamp,
                    sampleCount: 0,
                    accumulatedDuration: 0,
                    autoDuration: 0,
                    hotEnergyJoules: 0,
                    normalizedRPMTimeIntegral: 0,
                    temperatureTimeIntegral: 0,
                    rpmHighDuration: 0,
                    tempHighDuration: 0
                )
            }

            guard var bucket = self.currentBucket else { return }
            let dt = max(0, timestamp - bucket.lastSampleAt)
            bucket.lastSampleAt = timestamp
            bucket.sampleCount += 1
            bucket.accumulatedDuration += dt
            bucket.hotEnergyJoules += hotWatts * dt
            bucket.normalizedRPMTimeIntegral += normalizedRPM * dt
            bucket.temperatureTimeIntegral += temperature * dt
            if controlModeAutomatic {
                bucket.autoDuration += dt
            }
            if normalizedRPM >= self.highRPMThreshold {
                bucket.rpmHighDuration += dt
            }
            if temperature >= self.highTemperatureThreshold {
                bucket.tempHighDuration += dt
            }
            self.currentBucket = bucket
        }
    }

    private func finalize(bucket: Bucket) {
        let span = bucket.lastSampleAt - bucket.firstSampleAt
        let effectiveDuration = max(bucket.accumulatedDuration, 0)
        guard bucket.sampleCount >= minimumBucketSamples, span >= minimumBucketSpan, effectiveDuration > 0 else {
            consecutiveQualifiedBuckets = 0
            lastBucketQualified = false
            lastFinalizedBucketStart = bucket.bucketStart
            return
        }

        let avgHotWatts = bucket.hotEnergyJoules / effectiveDuration
        let avgNormalizedRPM = bucket.normalizedRPMTimeIntegral / effectiveDuration
        let avgTemperature = bucket.temperatureTimeIntegral / effectiveDuration
        let autoFraction = bucket.autoDuration / effectiveDuration
        let rpmHighFraction = bucket.rpmHighDuration / effectiveDuration
        let tempHighFraction = bucket.tempHighDuration / effectiveDuration

        let qualifies =
            avgHotWatts < hotPowerThreshold &&
            avgNormalizedRPM >= highRPMThreshold &&
            avgTemperature >= highTemperatureThreshold &&
            autoFraction >= sustainedFractionThreshold &&
            rpmHighFraction >= sustainedFractionThreshold &&
            tempHighFraction >= sustainedFractionThreshold

        if qualifies {
            if let lastFinalizedBucketStart,
               lastBucketQualified,
               bucket.bucketStart == lastFinalizedBucketStart + bucketDuration {
                consecutiveQualifiedBuckets += 1
            } else {
                consecutiveQualifiedBuckets = 1
            }
            qualifyingBucketStarts.append(bucket.bucketStart)
            let trailingEdge = bucket.bucketStart - 3600
            qualifyingBucketStarts.removeAll(where: { $0 < trailingEdge })
        } else {
            consecutiveQualifiedBuckets = 0
        }

        let shouldAlert = qualifies &&
            (consecutiveQualifiedBuckets >= 2 || qualifyingBucketStarts.count >= 4) &&
            cooldownElapsed(referenceTimestamp: bucket.lastSampleAt)

        AppLog.shared.info(
            "thermal alert bucket start=\(bucket.bucketStart) hot=\(String(format: "%.2f", avgHotWatts)) " +
            "rpm=\(String(format: "%.3f", avgNormalizedRPM)) temp=\(String(format: "%.2f", avgTemperature)) " +
            "autoFrac=\(String(format: "%.2f", autoFraction)) rpmHighFrac=\(String(format: "%.2f", rpmHighFraction)) " +
            "tempHighFrac=\(String(format: "%.2f", tempHighFraction)) qualifies=\(qualifies) " +
            "consecutive=\(consecutiveQualifiedBuckets) recent=\(qualifyingBucketStarts.count) alert=\(shouldAlert)"
        )

        if shouldAlert {
            UserDefaults.standard.set(bucket.lastSampleAt, forKey: lastAlertAtKey)
            presentAlert()
        }

        lastBucketQualified = qualifies
        lastFinalizedBucketStart = bucket.bucketStart
    }

    private func cooldownElapsed(referenceTimestamp: TimeInterval) -> Bool {
        let defaults = UserDefaults.standard
        guard let lastAlertAt = defaults.object(forKey: lastAlertAtKey) as? TimeInterval else {
            return true
        }
        return referenceTimestamp - lastAlertAt >= cooldownInterval
    }

    private func presentAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = appL10n("散热异常提醒", "Thermal Warning")
            alert.informativeText = appL10n(
                "检测到设备在较低输入功率下，风扇已长时间保持较高转速，但温度仍持续维持在高位。请检查进风口和出风口是否被遮挡；如通风正常，建议联系 Apple 官方售后进一步检查。",
                "The device has stayed at a high temperature for an extended period despite low input power and sustained high fan speed. Please check whether the intake and exhaust are blocked. If airflow is normal, consider contacting Apple Support for further inspection."
            )
            alert.alertStyle = .warning
            alert.addButton(withTitle: appL10n("知道了", "OK"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

// MARK: - Mini status display (custom NSView, direct Core Text rendering)

private final class MiniStatusView: NSView {
    var topPrimaryText: String = ""
    var topAccentText: String = ""
    var topAccentColor: NSColor = .systemGreen
    var bottomPrimaryText: String = ""
    var bottomAccentText: String = ""
    var bottomAccentColor: NSColor = .systemGreen

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        let primaryAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let topAccentAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: topAccentColor]
        let botAccentAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: bottomAccentColor]

        let topPrimaryW = (topPrimaryText as NSString).size(withAttributes: primaryAttrs).width
        let topAccentW = topAccentText.isEmpty ? 0 : (topAccentText as NSString).size(withAttributes: topAccentAttrs).width
        let topTotalW = topPrimaryW + topAccentW

        let botPrimaryW = (bottomPrimaryText as NSString).size(withAttributes: primaryAttrs).width
        let botAccentW = bottomAccentText.isEmpty ? 0 : (bottomAccentText as NSString).size(withAttributes: botAccentAttrs).width
        let botTotalW = botPrimaryW + botAccentW

        let lineHeight: CGFloat = font.ascender - font.descender - 2

        // 上行
        let topX = (bounds.width - topTotalW) / 2
        (topPrimaryText as NSString).draw(at: NSPoint(x: topX, y: 0), withAttributes: primaryAttrs)
        if !topAccentText.isEmpty {
            (topAccentText as NSString).draw(at: NSPoint(x: topX + topPrimaryW, y: 0), withAttributes: topAccentAttrs)
        }

        // 下行
        let botX = (bounds.width - botTotalW) / 2
        (bottomPrimaryText as NSString).draw(at: NSPoint(x: botX, y: lineHeight), withAttributes: primaryAttrs)
        if !bottomAccentText.isEmpty {
            (bottomAccentText as NSString).draw(at: NSPoint(x: botX + botPrimaryW, y: lineHeight), withAttributes: botAccentAttrs)
        }
    }
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
        info("Session started version=\(shortVersion) (\(buildVersion)) os=\(osVersion) model=\(systemModelIdentifier) arch=\(systemArchitecture) pid=\(ProcessInfo.processInfo.processIdentifier)")
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
        model=\(systemModelIdentifier)
        arch=\(systemArchitecture)
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
    private let legacyConfigPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("iFanControl")
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
        LEGACY_CONFIG_PATH=\(shellQuoted(legacyConfigPath.path))
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

        if [ -t 2 ]; then
          PASSWORD_PROMPT=$(printf '\\033[1;35m请输入你的 Mac 登录密码。\\n输入时不会显示字符或星号，输入后按回车即可。\\033[0m\\n密码：')
        else
          PASSWORD_PROMPT=$(printf '请输入你的 Mac 登录密码。\\n输入时不会显示字符或星号，输入后按回车即可。\\n密码：')
        fi

        echo ""
        echo "步骤 1/6: 删除 App..."
        rm -rf "$APP_PATH"
        echo "✓ App 已删除"

        echo ""
        echo "步骤 2/6: 删除 kentsmc..."
        if [ -f "$KENTSMC_PATH" ]; then
          sudo -p "$PASSWORD_PROMPT" rm -f "$KENTSMC_PATH"
          echo "✓ kentsmc 已删除"
        else
          echo "kentsmc 不存在，跳过"
        fi

        echo ""
        echo "步骤 3/6: 删除 sudoers 规则..."
        if [ -f "$SUDOERS_PATH" ]; then
          sudo -p "$PASSWORD_PROMPT" rm -f "$SUDOERS_PATH"
          echo "✓ sudoers 规则已删除"
        else
          echo "sudoers 规则不存在，跳过"
        fi

        echo ""
        echo "步骤 4/6: 删除配置..."
        rm -rf "$CONFIG_PATH"
        rm -rf "$LEGACY_CONFIG_PATH"
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

// 匿名运行反馈：仅发送随机安装 ID、版本号和 build，按固定间隔上报。
final class PrivacyStatsService: @unchecked Sendable {
    static let shared = PrivacyStatsService()

    private let logger = Logger(subsystem: appSubsystem, category: "PrivacyStats")
    private let endpointURL = URL(string: "https://ifan-59w.pages.dev/api/heartbeat")!
    private let enabledKey = "ifancontrol.privacy_stats.enabled"
    private let installIDKey = "ifancontrol.privacy_stats.install_id"
    private let flushDateKey = "ifancontrol.privacy_stats.last_flush_date"
    private let activationAckKey = "ifancontrol.privacy_stats.last_activation_ack_version_build"

    private let recordInterval: TimeInterval = 15 * 60   // 每 15 分钟入队一条
    private let maxQueuedEvents = 2880                     // 30 天（2880 × 15min）
    private let maxUploadEventsPerBatch = 80
    private let targetUploadPayloadBytes = 3800

    private let queueFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MacFanControl")
            .appendingPathComponent("heartbeat_queue.json")
    }()

    private let lock = NSLock()
    private var pendingEvents: [HeartbeatEvent] = []
    private var lastRecordAt: TimeInterval = 0

    struct HeartbeatEvent: Codable {
        let ts: TimeInterval
        let type: String
        let version: String
        let build: String

        init(ts: TimeInterval, type: String, version: String, build: String) {
            self.ts = ts
            self.type = type
            self.version = version
            self.build = build
        }

        private enum CodingKeys: String, CodingKey {
            case ts
            case type
            case version
            case build
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let current = PrivacyStatsService.currentVersionInfo()
            ts = try container.decode(TimeInterval.self, forKey: .ts)
            type = try container.decode(String.self, forKey: .type)
            version = try container.decodeIfPresent(String.self, forKey: .version) ?? current.version
            build = try container.decodeIfPresent(String.self, forKey: .build) ?? current.build
        }
    }

    private init() {
        loadQueue()
    }

    var anonymousStatsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            logger.info("Anonymous user-count stats toggled. enabled=\(newValue, privacy: .public)")
        }
    }

    // MARK: - 日期辅助

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: Date())
    }

    private func localDateString(for ts: TimeInterval) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: Date(timeIntervalSince1970: ts))
    }

    private var lastFlushDate: String? {
        get { UserDefaults.standard.string(forKey: flushDateKey) }
        set { UserDefaults.standard.set(newValue, forKey: flushDateKey) }
    }

    private var lastActivationAckVersionBuild: String? {
        get { UserDefaults.standard.string(forKey: activationAckKey) }
        set { UserDefaults.standard.set(newValue, forKey: activationAckKey) }
    }

    static func currentVersionInfo() -> (version: String, build: String) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return (version, build)
    }

    private func currentVersionInfo() -> (version: String, build: String) {
        Self.currentVersionInfo()
    }

    private func currentVersionBuild() -> String {
        let info = currentVersionInfo()
        return "\(info.version)-\(info.build)"
    }

    private func activationAckedForCurrentBuild() -> Bool {
        lastActivationAckVersionBuild == currentVersionBuild()
    }

    /// 判断事件是否是昨天或更早（本地时间）
    private func isYesterdayOrEarlier(_ event: HeartbeatEvent) -> Bool {
        localDateString(for: event.ts) < todayString()
    }

    // MARK: - 公开接口

    /// 每 15 分钟由 Timer 调用：入队一条事件，到时间则上报昨天的事件
    func tick() {
        guard anonymousStatsEnabled else { return }

        let now = Date().timeIntervalSince1970
        var shouldEnqueue = false
        var shouldFlush = false
        let shouldRetryActivation = !activationAckedForCurrentBuild()

        lock.withLock {
            shouldEnqueue = now - lastRecordAt >= recordInterval
            if shouldEnqueue { lastRecordAt = now }
            // 今天还没 flush 过，且队列中有昨天的事件
            shouldFlush = lastFlushDate != todayString() && pendingEvents.contains { isYesterdayOrEarlier($0) }
        }

        if shouldEnqueue {
            enqueueEvent(ts: now)
        }
        if shouldFlush {
            Task { await flush() }
        }
        if shouldRetryActivation {
            Task { await retryCurrentBuildActivation() }
        }
    }

    /// 启动时调用：入队一条新事件，然后立即上报所有积压事件
    func startup() {
        guard anonymousStatsEnabled else { return }
        let now = Date().timeIntervalSince1970
        enqueueEvent(ts: now)
        lock.withLock { lastRecordAt = now }
        Task { await flushAll() }
    }

    /// 退出时调用：同步发送昨天及更早的事件（阻塞，最长 8 秒）
    func shutdown() {
        guard anonymousStatsEnabled else { return }
        let events = lock.withLock {
            let current = currentVersionBuild()
            return extractEvents { event in
                isYesterdayOrEarlier(event) || "\(event.version)-\(event.build)" == current
            }
        }
        guard !events.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            _ = await sendEventBatch(events, markFlushDateOnSuccess: events.contains(where: isYesterdayOrEarlier))
            semaphore.signal()
        }
        semaphore.wait()
    }

    // MARK: - 内部逻辑

    private func enqueueEvent(ts: TimeInterval) {
        let current = currentVersionInfo()
        lock.withLock {
            // 去重：同一 15 分钟桶内，同一版本不重复入队
            let bucket = floor(ts / 900) * 900
            if let last = pendingEvents.last,
               floor(last.ts / 900) * 900 == bucket,
               last.version == current.version,
               last.build == current.build {
                return
            }
            if pendingEvents.count < maxQueuedEvents {
                pendingEvents.append(HeartbeatEvent(ts: ts, type: "heartbeat", version: current.version, build: current.build))
                saveQueue()
            }
        }
    }

    private func extractEvents(where predicate: (HeartbeatEvent) -> Bool) -> [HeartbeatEvent] {
        let extracted = pendingEvents.filter(predicate)
        pendingEvents.removeAll(where: predicate)
        saveQueue()
        return extracted
    }

    private func flush() async {
        let events = lock.withLock { extractEvents(where: isYesterdayOrEarlier) }
        guard !events.isEmpty else { return }
        _ = await sendEventBatch(events, markFlushDateOnSuccess: true)
    }

    /// 启动时调用：上报所有积压事件（含今天），用于首次安装立即上报
    private func flushAll() async {
        let events = lock.withLock {
            let all = pendingEvents
            pendingEvents.removeAll()
            saveQueue()
            return all
        }
        guard !events.isEmpty else { return }
        let containsYesterday = events.contains(where: isYesterdayOrEarlier)
        _ = await sendEventBatch(events, markFlushDateOnSuccess: containsYesterday)
    }

    private func retryCurrentBuildActivation() async {
        let current = currentVersionBuild()
        let events = lock.withLock {
            extractEvents { "\( $0.version)-\($0.build)" == current }
        }
        guard !events.isEmpty else { return }
        _ = await sendEventBatch(events, markFlushDateOnSuccess: false)
    }

    private func sendEventBatch(_ events: [HeartbeatEvent], markFlushDateOnSuccess: Bool) async -> Bool {
        guard !events.isEmpty else { return true }

        let grouped = Dictionary(grouping: events) { "\($0.version)-\($0.build)" }
        var allSucceeded = true
        for (_, group) in grouped {
            guard let first = group.first else { continue }
            let success = await sendEventsToHeartbeat(group, version: first.version, build: first.build)
            allSucceeded = allSucceeded && success
        }

        if allSucceeded && markFlushDateOnSuccess {
            lock.withLock { lastFlushDate = todayString() }
        }
        return allSucceeded
    }

    private func sendEventsToHeartbeat(_ events: [HeartbeatEvent], version: String, build: String) async -> Bool {
        let installID = currentInstallID()
        let chunks = chunkEventsForUpload(events, installID: installID, version: version, build: build)
        var allSucceeded = true
        for chunk in chunks {
            let success = await sendHeartbeatRequest(chunk, installID: installID, version: version, build: build)
            allSucceeded = allSucceeded && success
        }
        return allSucceeded
    }

    private func sendHeartbeatRequest(_ events: [HeartbeatEvent], installID: String, version: String, build: String) async -> Bool {
        do {
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 8

            let body = try payloadData(for: events, installID: installID, version: version, build: build)
            let (_, response) = try await URLSession.shared.upload(for: request, from: body)
            let payloadBytes = body.count

            guard let http = response as? HTTPURLResponse else {
                logger.warning("Heartbeat batch rejected by server status=non_http events=\(events.count) bytes=\(payloadBytes) version=\(version, privacy: .public)-\(build, privacy: .public), re-queuing.")
                requeueEvents(events)
                return false
            }

            if http.statusCode == 413, events.count > 1 {
                let splitIndex = max(1, events.count / 2)
                let firstHalf = Array(events[..<splitIndex])
                let secondHalf = Array(events[splitIndex...])
                logger.warning("Heartbeat batch too large status=413 events=\(events.count) bytes=\(payloadBytes) split=\(firstHalf.count)+\(secondHalf.count) version=\(version, privacy: .public)-\(build, privacy: .public).")
                let firstSucceeded = await sendEventsToHeartbeat(firstHalf, version: version, build: build)
                let secondSucceeded = await sendEventsToHeartbeat(secondHalf, version: version, build: build)
                return firstSucceeded && secondSucceeded
            }

            guard (200..<300).contains(http.statusCode) else {
                logger.warning("Heartbeat batch rejected by server status=\(http.statusCode) events=\(events.count) bytes=\(payloadBytes) version=\(version, privacy: .public)-\(build, privacy: .public), re-queuing.")
                requeueEvents(events)
                return false
            }

            if "\(version)-\(build)" == currentVersionBuild() {
                lock.withLock { lastActivationAckVersionBuild = currentVersionBuild() }
            }
            logger.info("Heartbeat batch sent status=\(http.statusCode) events=\(events.count) bytes=\(payloadBytes) version=\(version, privacy: .public)-\(build, privacy: .public).")
            return true
        } catch {
            logger.warning("Heartbeat batch failed error=\(error.localizedDescription, privacy: .public) events=\(events.count) version=\(version, privacy: .public)-\(build, privacy: .public), re-queuing.")
            requeueEvents(events)
            return false
        }
    }

    private func payloadData(for events: [HeartbeatEvent], installID: String, version: String, build: String) throws -> Data {
        let eventDicts = events.map { ["ts": $0.ts, "type": $0.type] as [String: Any] }
        let payload: [String: Any] = [
            "install_id": installID,
            "version": version,
            "build": build,
            "events": eventDicts
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func chunkEventsForUpload(_ events: [HeartbeatEvent], installID: String, version: String, build: String) -> [[HeartbeatEvent]] {
        guard !events.isEmpty else { return [] }

        var chunks: [[HeartbeatEvent]] = []
        var currentChunk: [HeartbeatEvent] = []

        for event in events {
            let candidateChunk = currentChunk + [event]
            let isOverEventLimit = candidateChunk.count > maxUploadEventsPerBatch
            let isOverPayloadLimit: Bool
            do {
                let data = try payloadData(for: candidateChunk, installID: installID, version: version, build: build)
                isOverPayloadLimit = data.count > targetUploadPayloadBytes
            } catch {
                isOverPayloadLimit = candidateChunk.count > 1
            }

            if !currentChunk.isEmpty && (isOverEventLimit || isOverPayloadLimit) {
                chunks.append(currentChunk)
                currentChunk = [event]
            } else {
                currentChunk = candidateChunk
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return chunks
    }

    func requeueEvents(_ events: [HeartbeatEvent]) {
        lock.withLock {
            pendingEvents.insert(contentsOf: events, at: 0)
            // 超出上限时丢弃最旧的
            if pendingEvents.count > maxQueuedEvents {
                pendingEvents = Array(pendingEvents.suffix(maxQueuedEvents))
            }
            saveQueue()
        }
    }

    // MARK: - 持久化

    private func loadQueue() {
        do {
            let data = try Data(contentsOf: queueFileURL)
            let events = try JSONDecoder().decode([HeartbeatEvent].self, from: data)
            lock.withLock { pendingEvents = events }
            logger.info("Loaded \(events.count) queued heartbeat events from disk.")
        } catch {
            // 文件不存在或格式错误，正常情况
        }
    }

    private func saveQueue() {
        do {
            let dir = queueFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(pendingEvents)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            logger.warning("Failed to save heartbeat queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - install_id

    func currentInstallID() -> String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey), !existing.isEmpty {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: installIDKey)
        return newID
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

    func setFanAutoAsync(
        completion: (@MainActor (_ success: Bool, _ error: String?) -> Void)? = nil
    ) {
        commandQueue.async {
            let result = self.setFanAuto()
            guard let completion else { return }
            Task { @MainActor in
                completion(result.success, result.error)
            }
        }
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

// 后台硬件读取器（不绑定 MainActor，真正的后台线程执行）
private final class BackgroundHardwareReader: @unchecked Sendable {
    static let shared = BackgroundHardwareReader()
    private let kentsmcPath = "/usr/local/bin/kentsmc"
    private let queue = DispatchQueue(label: "com.ifancontrol.hw-reader", qos: .utility)
    private let lock = NSLock()

    // 读取结果缓存（由后台线程写入，主线程读取）
    private var _temperatures: [String: Double] = [:]
    private var _fanRPMs: [Int: Int] = [:]
    private var _lastSuccessfulTemperatureRefresh: Date?
    private var _lastSuccessfulFanRPMRefresh: Date?
    private var _consecutiveTemperatureFailures: Int = 0
    private var _refreshInFlight = false

    struct Snapshot {
        let temperatures: [String: Double]
        let fanRPMs: [Int: Int]
        let consecutiveTemperatureFailures: Int
        let secondsSinceTemperatureSuccess: TimeInterval?
        let secondsSinceFanRPMSuccess: TimeInterval?
    }

    var temperatures: [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return _temperatures
    }
    var fanRPMs: [Int: Int] {
        lock.lock(); defer { lock.unlock() }
        return _fanRPMs
    }
    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(
            temperatures: _temperatures,
            fanRPMs: _fanRPMs,
            consecutiveTemperatureFailures: _consecutiveTemperatureFailures,
            secondsSinceTemperatureSuccess: _lastSuccessfulTemperatureRefresh.map { Date().timeIntervalSince($0) },
            secondsSinceFanRPMSuccess: _lastSuccessfulFanRPMRefresh.map { Date().timeIntervalSince($0) }
        )
    }

    private func executeRead(args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: kentsmcPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            AppLog.shared.error("kentsmc Process.run failed: \(error.localizedDescription) args=\(args.joined(separator: " "))")
            return nil
        }
    }

    private func readNumeric(forKey key: String) -> Double? {
        guard let output = executeRead(args: ["-r", key]),
              let range = output.range(of: "\\((-?\\d+(?:\\.\\d+)?)\\)", options: .regularExpression) else {
            return nil
        }
        return Double(output[range].dropFirst().dropLast())
    }

    /// 在后台队列执行一次完整的硬件轮询
    func refresh(sensors: [TemperatureSensorDefinition], fans: [FanInfo]) {
        lock.lock()
        if _refreshInFlight {
            lock.unlock()
            return
        }
        _refreshInFlight = true
        lock.unlock()

        queue.async { [self] in
            defer {
                lock.lock()
                _refreshInFlight = false
                lock.unlock()
            }

            var temps: [String: Double] = [:]
            for sensor in sensors {
                if let val = readNumeric(forKey: sensor.key), val >= 0, val <= 120 {
                    temps[sensor.key] = val
                }
            }
            var rpms: [Int: Int] = [:]
            for fan in fans {
                if let val = readNumeric(forKey: fan.actualKey), val >= 0 {
                    rpms[fan.index] = Int(val.rounded())
                }
            }
            let finishedAt = Date()
            lock.lock()
            if !temps.isEmpty {
                _temperatures = temps
                _lastSuccessfulTemperatureRefresh = finishedAt
                _consecutiveTemperatureFailures = 0
            } else if !sensors.isEmpty {
                _consecutiveTemperatureFailures += 1
            }
            if !rpms.isEmpty {
                _fanRPMs = rpms
                _lastSuccessfulFanRPMRefresh = finishedAt
            }
            let gotTemps = !temps.isEmpty
            let consecutiveFailures = _consecutiveTemperatureFailures
            let cachedTempCount = _temperatures.count
            let cachedRPMCount = _fanRPMs.count
            let tempAge = _lastSuccessfulTemperatureRefresh.map { finishedAt.timeIntervalSince($0) } ?? .infinity
            let rpmAge = _lastSuccessfulFanRPMRefresh.map { finishedAt.timeIntervalSince($0) } ?? .infinity
            lock.unlock()

            if !gotTemps && !sensors.isEmpty {
                let tempAgeText = tempAge.isFinite ? String(format: "%.1f", tempAge) : "inf"
                let rpmAgeText = rpmAge.isFinite ? String(format: "%.1f", rpmAge) : "inf"
                AppLog.shared.warning("bg refresh: all \(sensors.count) sensor reads failed consecutive=\(consecutiveFailures) keepingCachedTemps=\(cachedTempCount) keepingCachedRPMs=\(cachedRPMCount) tempAge=\(tempAgeText) rpmAge=\(rpmAgeText)")
            }
        }
    }

    func replaceSnapshotFromMainThread(temperatures: [String: Double], fanRPMs: [Int: Int], reason: String) {
        lock.lock()
        if !temperatures.isEmpty {
            _temperatures = temperatures
            _lastSuccessfulTemperatureRefresh = Date()
            _consecutiveTemperatureFailures = 0
        }
        if !fanRPMs.isEmpty {
            _fanRPMs = fanRPMs
            _lastSuccessfulFanRPMRefresh = Date()
        }
        lock.unlock()
        AppLog.shared.info("bg snapshot replaced reason=\(reason) temps=\(temperatures.count) rpms=\(fanRPMs.count)")
    }
}

// 风扇管理器
@MainActor
class FanManager {
    static let shared = FanManager()
    private let kentsmcPath = "/usr/local/bin/kentsmc"
    let defaultSafetyRPM = 3500
    var criticalTemperatureForDisplay: Double { criticalTemp }
    private let fallbackMaxRPM = 4900
    private let telemetryRefreshInterval: TimeInterval = 2.0
    private let validTemperatureRange = 0.0...120.0
    
    private(set) var fanCount: Int = 0
    private(set) var fans: [FanInfo] = []
    private(set) var availableTemperatureSensors: [TemperatureSensorDefinition] = []
    private(set) var currentMaxRPM: Int = 4900

    private(set) var cachedTemperatures: [String: Double] = [:]
    private var cachedFanRPMs: [Int: Int] = [:]
    private var lastTelemetryRefresh: Date?
    private var lastTelemetryLogTimestamp: Date?
    private var hasProbedHardware = false
    private var lastHardwareReprobeAt: Date?
    private let discoveryQueue = DispatchQueue(label: "com.ifancontrol.dynamic-sensor-discovery", qos: .utility)
    private var cachedDynamicTemperatureCandidateKeys: [String] = []
    private var dynamicSensorDiscoveryInFlight = false
    private var dynamicSensorDiscoveryAttempted = false
    private let logger = Logger(subsystem: appSubsystem, category: "Hardware")
    private let telemetryDetailLogInterval: TimeInterval = 10.0
    
    // 稳定性控制参数
    private var lastSetRPM: Int = 0
    private var lastExecutionTime: Date?
    private let minExecutionInterval: TimeInterval = 2.0
    private var fanCommandInFlight = false
    private let criticalTemp: Double = 110.0
    
    
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
    
    private var lastFailSafeAutoReturnAt: Date?
    private let failSafeAutoReturnInterval: TimeInterval = 15.0
    
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

    private func discoverTemperatureCandidateKeys() -> [String] {
        var orderedKeys: [String] = SensorCatalog.appleSiliconTemperatureSensors.map(\.key)
        var seen = Set(orderedKeys)
        for key in cachedDynamicTemperatureCandidateKeys where !seen.contains(key) {
            seen.insert(key)
            orderedKeys.append(key)
        }

        if cachedDynamicTemperatureCandidateKeys.isEmpty {
            kickOffDynamicSensorDiscoveryIfNeeded()
        }

        AppLog.shared.info("dynamic sensor discovery candidates model=\(systemModelIdentifier) static=\(SensorCatalog.appleSiliconTemperatureSensors.count) cachedDynamic=\(cachedDynamicTemperatureCandidateKeys.count) mergedCandidates=\(orderedKeys.count)")
        return orderedKeys
    }

    private func kickOffDynamicSensorDiscoveryIfNeeded() {
        guard !dynamicSensorDiscoveryInFlight, !dynamicSensorDiscoveryAttempted else { return }
        dynamicSensorDiscoveryInFlight = true
        dynamicSensorDiscoveryAttempted = true
        let kentsmcPath = self.kentsmcPath

        discoveryQueue.async { [weak self] in
            guard let self else { return }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: kentsmcPath)
            task.arguments = ["-l"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            let discoveredKeys: [String]
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0,
                   let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
                   !output.isEmpty,
                   let regex = try? NSRegularExpression(pattern: "\\bT[A-Za-z0-9]{3}\\b") {
                    let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
                    var seen = Set<String>()
                    discoveredKeys = regex.matches(in: output, options: [], range: nsRange).compactMap { match -> String? in
                        guard let range = Range(match.range, in: output) else { return nil }
                        let key = String(output[range])
                        return seen.insert(key).inserted ? key : nil
                    }
                } else {
                    discoveredKeys = []
                }
            } catch {
                Task { @MainActor in
                    AppLog.shared.warning("dynamic sensor discovery failed to launch model=\(systemModelIdentifier) error=\(error.localizedDescription)")
                    self.dynamicSensorDiscoveryInFlight = false
                }
                return
            }

            Task { @MainActor in
                self.dynamicSensorDiscoveryInFlight = false
                guard !discoveredKeys.isEmpty else {
                    AppLog.shared.warning("dynamic sensor discovery unavailable: kentsmc -l returned no usable temperature keys model=\(systemModelIdentifier) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
                    return
                }
                self.cachedDynamicTemperatureCandidateKeys = discoveredKeys
                AppLog.shared.info("dynamic sensor discovery completed model=\(systemModelIdentifier) discovered=\(discoveredKeys.count)")
                self.reprobeHardware(reason: "dynamic_sensor_discovery_ready", minimumInterval: 0)
            }
        }
    }

    private func validateDiscoveredTemperatureKey(_ key: String, isKnown: Bool) -> TemperatureSensorDefinition? {
        var successfulReadings: [Double] = []
        let attempts = isKnown ? 1 : 2
        for _ in 0..<attempts {
            if let value = readTemperatureValue(forKey: key) {
                successfulReadings.append(value)
            }
        }

        guard !successfulReadings.isEmpty else {
            return nil
        }
        if !isKnown && successfulReadings.count < attempts {
            return nil
        }
        if successfulReadings.count >= 2,
           let minValue = successfulReadings.min(),
           let maxValue = successfulReadings.max(),
           maxValue - minValue > 15 {
            AppLog.shared.warning("dynamic sensor candidate rejected key=\(key) reason=unstable delta=\(String(format: "%.2f", maxValue - minValue))")
            return nil
        }

        return SensorCatalog.definition(forTemperatureKey: key)
    }

    func probeHardwareIfNeeded() {
        guard !hasProbedHardware else { return }
        refreshHardwareProfile()
    }

    func refreshHardwareProfile() {
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

        let candidateKeys = discoverTemperatureCandidateKeys()
        let knownKeys = Set(SensorCatalog.appleSiliconTemperatureSensors.map(\.key))
        var discoveredSensors: [TemperatureSensorDefinition] = []
        var dynamicOnlyKeys: [String] = []
        for key in candidateKeys {
            let isKnown = knownKeys.contains(key)
            if let sensor = validateDiscoveredTemperatureKey(key, isKnown: isKnown) {
                discoveredSensors.append(sensor)
                if !isKnown {
                    dynamicOnlyKeys.append(key)
                }
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
        let dynamicKeyText = dynamicOnlyKeys.isEmpty ? "none" : dynamicOnlyKeys.joined(separator: ",")
        AppLog.shared.info("hardware profile refreshed model=\(systemModelIdentifier) os=\(ProcessInfo.processInfo.operatingSystemVersionString) fans=\(fanCount) maxRPM=\(currentMaxRPM) sensors=\(availableTemperatureSensors.count) dynamicOnly=\(dynamicOnlyKeys.count) dynamicKeys=[\(dynamicKeyText)] keys=[\(sensorKeys)]")

        hasProbedHardware = true
        lastHardwareReprobeAt = Date()
        refreshTelemetry(force: true)
        if let initialRPM = cachedFanRPMs.values.max(), initialRPM > 0 {
            lastSetRPM = initialRPM
        }
    }

    func reprobeHardware(reason: String, minimumInterval: TimeInterval = 15.0) {
        if let lastHardwareReprobeAt,
           minimumInterval > 0,
           Date().timeIntervalSince(lastHardwareReprobeAt) < minimumInterval {
            return
        }
        AppLog.shared.info("hardware reprobe requested reason=\(reason)")
        hasProbedHardware = false
        refreshHardwareProfile()
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
        return selectedTemperatureReading(from: readings, config: config)
    }

    func readPrimaryFanRPM(refresh: Bool = true) -> Int? {
        if refresh {
            refreshTelemetry()
        }
        return cachedFanRPMs.values.max()
    }

    func telemetrySnapshot() -> (temperatures: [String: Double], fanRPMs: [Int: Int]) {
        (cachedTemperatures, cachedFanRPMs)
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
                self.returnControlToSystemFailSafe(reason: "fan_command_failed")
            }
        }
    }

    private func returnControlToSystemFailSafe(reason: String) {
        if let lastFailSafeAutoReturnAt,
           Date().timeIntervalSince(lastFailSafeAutoReturnAt) < failSafeAutoReturnInterval {
            return
        }
        lastFailSafeAutoReturnAt = Date()
        AppLog.shared.warning("returning control to system fail-safe reason=\(reason) model=\(systemModelIdentifier) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        Task { @MainActor in
            AppDelegate.shared?.recordSystemAutoFallback(reason: reason)
            AppDelegate.shared?.showSafetyAlert(
                state: "system_auto_fallback_command_failure",
                title: appL10n("风扇控制已交还系统", "Fan Control Returned to System"),
                message: appL10n(
                    "iFanControl 无法继续可靠地下发风扇命令，已自动将风扇控制权交还给系统。请检查日志或联系支持。",
                    "iFanControl could not continue sending reliable fan commands, so control has been returned to the system. Please check the logs or contact support."
                )
            )
        }
        CommandExecutor.shared.setFanAutoAsync()
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
    private var cachedConfig: Config?
    private var cachedConfigMtime: Date?

    init() {
        configFile = configDir.appendingPathComponent("config.json")
        createConfigDir()
    }
    
    private func createConfigDir() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    func loadConfig() -> Config {
        // 检查文件是否被外部修改
        if let mtime = try? configFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           let cached = cachedConfig,
           mtime == cachedConfigMtime {
            return cached
        }

        if let data = try? Data(contentsOf: configFile),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            cachedConfig = config
            cachedConfigMtime = try? configFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return config
        }

        if let bundleConfigURL = Bundle.main.url(forResource: "config", withExtension: "json"),
           let data = try? Data(contentsOf: bundleConfigURL),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            cachedConfig = config
            cachedConfigMtime = nil
            return config
        }

        let maxRPM = FanManager.shared.currentMaxRPM
        return Config(
            version: "1.0",
            curve: defaultFanCurve(maxRPM: maxRPM),
            mode: "auto",
            autoStart: true,
            maxRPM: maxRPM,
            manualRPM: min(2168, maxRPM),
            manualRPMControlMode: ManualRPMControlMode.continuous.rawValue,
            manualRPMStep: defaultManualRPMStep,
            safetyFloorRPM: min(FanManager.shared.defaultSafetyRPM, maxRPM),
            temperatureSourceMode: "hottest",
            selectedTemperatureSensorKey: nil
        )
    }
    
    @discardableResult
    func saveConfig(_ config: Config) -> Bool {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFile)
            cachedConfig = config
            cachedConfigMtime = try? configFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return true
        } catch {
            print("Error saving config: \(error)")
            return false
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
class UpdateService: NSObject {
    static let shared = UpdateService()
    private let logger = Logger(subsystem: appSubsystem, category: "Updater")

    private let updatePreferences = UpdatePreferences.shared
    private let releasesHomeURL = URL(string: "https://github.com/PureMilkchun/iFanControl/releases")!
    private let lastCheckKey = "ifancontrol.update.last_check"
    private let automaticCheckEnabledKey = "ifancontrol.update.automatic_check_enabled"
    private var isChecking = false
    private var isDownloading = false
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var downloader: UpdatePackageDownloader?
    private var activeSelection: UpdateSelection?
    private var isTransferring = false
    private var transferID = UUID()
    private var manualCheckRequested = false
    private let progressWindow = UpdateProgressWindowController()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)),
            name: UpdatePreferences.channelDidChange, object: nil)
    }

    @objc private func routeChanged(_ notification: Notification) {
        if let activeSelection, activeSelection != updatePreferences.selection { cancelCurrentOperation() }
    }

    private func cancelCurrentOperation() {
        checkTask?.cancel(); downloadTask?.cancel(); downloader?.cancel()
        transferID = UUID()
        isTransferring = false
        progressWindow.dismiss()
    }

    func presentInstalledUpdateIfNeeded() {
        let defaults = UserDefaults.standard
        let expected = defaults.integer(forKey: "ifancontrol.update.pending_build")
        guard expected > 0, currentBuild >= expected else { return }
        defaults.removeObject(forKey: "ifancontrol.update.pending_build")
        InteractionNotice.shared.show(appL10n("已更新至 \(currentVersionDisplay)", "Updated to \(currentVersionDisplay)"))
    }

    private var currentShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? appL10n("未知版本", "Unknown")
    }

    private var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    var currentVersionDisplay: String {
        let betaLabel = Bundle.main.object(forInfoDictionaryKey: "IFanControlReleaseChannel") as? String == "beta" ? " Beta" : ""
        return "\(currentShortVersion)\(betaLabel) (\(currentBuild))"
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

    func checkForUpdates(triggeredByUser: Bool) {
        if isChecking || isDownloading {
            if triggeredByUser {
                manualCheckRequested = true
                if isChecking { progressWindow.present(title: appL10n("正在检查更新", "Checking for Updates"), detail: appL10n("请稍候，正在读取可用版本。", "Please wait while we check the available version."), cancel: { [weak self] in self?.cancelCurrentOperation() }) }
                else { progressWindow.bringForward() }
            }
            return
        }
        if !triggeredByUser && !automaticChecksEnabled {
            logger.info("Skipping automatic update check because automatic checks are disabled.")
            return
        }

        isChecking = true
        let selection = updatePreferences.selection
        activeSelection = selection
        manualCheckRequested = triggeredByUser
        if triggeredByUser {
            progressWindow.present(title: appL10n("正在检查更新", "Checking for Updates"), detail: appL10n("当前通道：\(selection.channel == .beta ? "Beta" : "正式版")", "Update channel: \(selection.channel == .beta ? "Beta" : "Stable")"), cancel: { [weak self] in self?.cancelCurrentOperation() })
        }
        logger.info("Starting update check. triggeredByUser=\(triggeredByUser, privacy: .public)")

        checkTask = Task { [self] in
            defer { isChecking = false; checkTask = nil }

            do {
                let (data, _) = try await URLSession.shared.data(from: selection.channel.manifestURL)
                guard !Task.isCancelled, updatePreferences.selection == selection else { return }
                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
                guard manifest.isCompatible(with: selection.channel) else {
                    throw NSError(domain: "UpdateService", code: 1005, userInfo: [NSLocalizedDescriptionKey: appL10n("更新通道信息不匹配，请稍后重试。", "Update channel information does not match. Please try again later.")])
                }
                recordLastCheckNow()

                if manifest.latestBuild <= currentBuild {
                    self.logger.info("No update available. currentBuild=\(self.currentBuild, privacy: .public) remoteBuild=\(manifest.latestBuild, privacy: .public)")
                    if manualCheckRequested {
                        progressWindow.dismiss()
                        showInfoAlert(
                            title: appL10n("已是最新版本", "Up to Date"),
                            message: appL10n(
                                "当前版本：\(currentVersionDisplay)\n可用版本：\(manifest.versionDisplay) (\(manifest.latestBuild))",
                                "Current: \(currentVersionDisplay)\nLatest: \(manifest.versionDisplay) (\(manifest.latestBuild))"
                            )
                        )
                    }
                    return
                }

                self.logger.info("Update available. currentBuild=\(self.currentBuild, privacy: .public) remoteBuild=\(manifest.latestBuild, privacy: .public)")
                progressWindow.dismiss()
                presentUpdatePrompt(manifest: manifest, selection: selection)
            } catch {
                guard !Task.isCancelled, updatePreferences.selection == selection else { return }
                self.logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                if manualCheckRequested {
                    progressWindow.present(title: appL10n("检查更新失败", "Update Check Failed"), detail: error.localizedDescription,
                        retry: { [weak self] in self?.checkForUpdates(triggeredByUser: true) },
                        manual: { [weak self] in guard let self else { return }; NSWorkspace.shared.open(self.releasesHomeURL) })
                } else {
                    print("Update check failed: \(error)")
                }
            }
        }
    }

    private func recordLastCheckNow() {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
    }

    private func presentUpdatePrompt(manifest: UpdateManifest, selection: UpdateSelection) {
        let notes = manifest.notes?.isEmpty == false ? manifest.notes! : appL10n("包含稳定性与功能改进。", "Includes stability and feature improvements.")
        let alert = NSAlert()
        alert.messageText = appL10n("发现新版本 \(manifest.versionDisplay)", "New Version Available \(manifest.versionDisplay)")
        alert.informativeText = appL10n(
            "当前版本：\(currentVersionDisplay)\n可用版本：\(manifest.versionDisplay) (\(manifest.latestBuild))\n\n\(notes)\n\n下载安装包并验证后，应用会退出并打开系统安装器。",
            "Current: \(currentVersionDisplay)\nLatest: \(manifest.versionDisplay) (\(manifest.latestBuild))\n\n\(notes)\n\nAfter download and verification, the app will quit and open the system installer."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: appL10n("立即更新", "Update Now"))
        alert.addButton(withTitle: appL10n("稍后", "Later"))

        if alert.runModal() == .alertFirstButtonReturn {
            startDownloadAndInstall(manifest: manifest, selection: selection)
        }
    }

    private func startDownloadAndInstall(manifest: UpdateManifest, selection: UpdateSelection) {
        guard !isDownloading, updatePreferences.selection == selection else { return }
        isDownloading = true
        let id = UUID()
        transferID = id
        isTransferring = true
        activeSelection = selection
        progressWindow.present(title: appL10n("正在下载安装包", "Downloading Installer"),
            detail: manifest.versionDisplay, cancel: { [weak self] in self?.cancelCurrentOperation() })
        downloadTask = Task { [self] in
            defer { isDownloading = false; isTransferring = false; downloader = nil; downloadTask = nil }
            do {
                let packageURL: URL
                do {
                    packageURL = try manifest.packageDownloadURL()
                } catch {
                    throw NSError(domain: "UpdateService", code: 1001, userInfo: [NSLocalizedDescriptionKey: appL10n("更新信息暂不可用，请稍后重试。", "Update information is unavailable. Please try again later.")])
                }
                logger.info("Downloading update package from \(packageURL.absoluteString, privacy: .public)")
                let transfer = UpdatePackageDownloader()
                downloader = transfer
                let (data, response) = try await transfer.download(packageURL) { [weak self] received, total in
                    Task { @MainActor in
                        guard let self, self.isTransferring, self.transferID == id, self.updatePreferences.selection == selection else { return }
                        self.progressWindow.updateTransfer(received: received, total: total)
                    }
                }
                isTransferring = false
                guard !Task.isCancelled, updatePreferences.selection == selection else { return }
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                    throw NSError(domain: "UpdateService", code: 1002, userInfo: [NSLocalizedDescriptionKey: appL10n("下载安装包失败，请稍后重试。", "Could not download the installer. Please try again later.")])
                }
                progressWindow.present(title: appL10n("正在验证安装包", "Verifying Installer"),
                    detail: appL10n("下载已完成，正在确认文件完整性。", "Download complete. Checking file integrity."), cancel: { [weak self] in self?.cancelCurrentOperation() })
                do {
                    try await Task.detached(priority: .userInitiated) { try manifest.verifyPackage(data) }.value
                } catch {
                    throw NSError(domain: "UpdateService", code: 1003, userInfo: [NSLocalizedDescriptionKey: appL10n("安装包校验失败，请重新下载。", "Installer verification failed. Please download it again.")])
                }

                try Task.checkCancellation()
                // Keep each downloaded installer at its own path while Installer uses it.
                let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("iFanControlUpdate-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                let packagePath = stagingDir.appendingPathComponent("iFanControl-macOS.pkg")
                try data.write(to: packagePath, options: .atomic)

                try Task.checkCancellation()
                progressWindow.present(title: appL10n("即将打开系统安装器", "Opening Installer"),
                    detail: appL10n("iFanControl 将退出。请按系统向导安装，完成后重新打开应用。", "iFanControl will quit. Follow the system installer, then reopen the app."), cancel: { [weak self] in self?.cancelCurrentOperation() })
                guard NSWorkspace.shared.open(packagePath) else {
                    throw NSError(domain: "UpdateService", code: 1004, userInfo: [NSLocalizedDescriptionKey: appL10n("无法打开系统安装器，请从官网下载后打开安装包。", "Could not open Installer. Please download the package from our website and open it.")])
                }
                logger.info("Native PKG installer launched for version \(manifest.latestVersion, privacy: .public)")
                // Normal termination restores automatic fan control before installation.
                UserDefaults.standard.set(manifest.latestBuild, forKey: "ifancontrol.update.pending_build")
                NSApp.terminate(nil)
            } catch {
                guard !Task.isCancelled, updatePreferences.selection == selection else { return }
                logger.error("Update download/install failed: \(error.localizedDescription, privacy: .public)")
                let releaseURL = selection.channel == .beta ? (manifest.betaReleaseURL ?? releasesHomeURL) : githubReleaseURL(for: manifest.latestVersion)
                progressWindow.present(title: appL10n("更新未完成", "Update Not Completed"), detail: error.localizedDescription,
                    retry: { [weak self] in self?.checkForUpdates(triggeredByUser: true) },
                    manual: { NSWorkspace.shared.open(releaseURL) })
            }
        }
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
class MenuBarManager: NSObject {
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
    private let displayModeKey = "ifancontrol.ui.display_mode"
    private var displayMode: String {
        get { UserDefaults.standard.string(forKey: displayModeKey) ?? "full" }
        set { UserDefaults.standard.set(newValue, forKey: displayModeKey) }
    }
    private let miniTopSourceKey = "ifancontrol.ui.mini_top_source"
    private let miniTopStyleKey = "ifancontrol.ui.mini_top_style"
    private let miniBottomSourceKey = "ifancontrol.ui.mini_bottom_source"
    private let miniBottomStyleKey = "ifancontrol.ui.mini_bottom_style"

    private enum MiniLineSource: String {
        case temperature
        case rpm
        case power
    }

    private enum MiniLineStyle: String {
        case value
        case unit
        case mode
        case full
    }

    private func parseMiniLineSources(_ rawValue: String?) -> [MiniLineSource] {
        guard let rawValue, !rawValue.isEmpty else { return [] }
        var seen = Set<String>()
        return rawValue
            .split(separator: ",")
            .compactMap { MiniLineSource(rawValue: String($0)) }
            .filter { seen.insert($0.rawValue).inserted }
    }

    private func serializedMiniLineSources(_ sources: [MiniLineSource]) -> String {
        var seen = Set<String>()
        return sources
            .filter { seen.insert($0.rawValue).inserted }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    private func miniLineConfiguration(sourceKey: String, styleKey: String, legacyKey: String, defaultSources: [MiniLineSource], defaultStyle: MiniLineStyle) -> ([MiniLineSource], MiniLineStyle) {
        let defaults = UserDefaults.standard
        let savedSources = parseMiniLineSources(defaults.string(forKey: sourceKey))
        if !savedSources.isEmpty,
           let style = defaults.string(forKey: styleKey).flatMap(MiniLineStyle.init(rawValue:)) {
            return (savedSources, style)
        }
        if let legacy = defaults.string(forKey: legacyKey) {
            let migrated = Self.mapLegacyMiniContentType(legacy)
            defaults.set(serializedMiniLineSources([migrated.0]), forKey: sourceKey)
            defaults.set(migrated.1.rawValue, forKey: styleKey)
            return ([migrated.0], migrated.1)
        }
        return (defaultSources, defaultStyle)
    }

    private var miniTopLine: (sources: [MiniLineSource], style: MiniLineStyle) {
        get { miniLineConfiguration(sourceKey: miniTopSourceKey, styleKey: miniTopStyleKey, legacyKey: "ifancontrol.ui.mini_top_line", defaultSources: [.temperature], defaultStyle: .full) }
        set {
            UserDefaults.standard.set(serializedMiniLineSources(newValue.sources), forKey: miniTopSourceKey)
            UserDefaults.standard.set(newValue.style.rawValue, forKey: miniTopStyleKey)
        }
    }

    private var miniBottomLine: (sources: [MiniLineSource], style: MiniLineStyle) {
        get { miniLineConfiguration(sourceKey: miniBottomSourceKey, styleKey: miniBottomStyleKey, legacyKey: "ifancontrol.ui.mini_bottom_line", defaultSources: [.rpm], defaultStyle: .unit) }
        set {
            UserDefaults.standard.set(serializedMiniLineSources(newValue.sources), forKey: miniBottomSourceKey)
            UserDefaults.standard.set(newValue.style.rawValue, forKey: miniBottomStyleKey)
        }
    }

    // Mini display mode: custom NSView with direct Core Text rendering
    private var miniStatusView: MiniStatusView?

    private var speedSettingWindowController: SpeedSettingWindowController?
    private var safetyFloorWindowController: SafetyFloorWindowController?
    private var fanCurveWindowController: NSWindowController?
    private var helpWindowController: HelpWindowController?
    private var feedbackWindowController: FeedbackWindowController?
    private var displaySettingsWindowController: DisplaySettingsWindowController?
    private var powerConsumptionWindowController: PowerConsumptionWindowController?

    // GCD 定时器（不依赖 RunLoop，无显示器也能运行）
    private var menuPollTimer: DispatchSourceTimer?

    // 菜单项引用（用于原地更新，避免每 2 秒重建整个菜单）
    private var menu: NSMenu?
    private var hardwareItem: NSMenuItem?
    private var currentSensorItem: NSMenuItem?
    private var controlStatusItem: NSMenuItem?
    private var controlStatusContainerView: NSView?
    private var controlStatusBottomLeftField: NSTextField?
    private var controlModeField: NSTextField?
    private var modeItem: NSMenuItem?
    private var speedItem: NSMenuItem?
    private var autoStartItem: NSMenuItem?
    private var hottestItem: NSMenuItem?
    private var cpuAverageItem: NSMenuItem?
    private var gpuAverageItem: NSMenuItem?
    private var sensorMenuItems: [NSMenuItem] = []
    private var zhItem: NSMenuItem?
    private var enItem: NSMenuItem?

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

    private func sourceSummary(for reading: TemperatureReading, config: Config, in readings: [TemperatureReading]) -> String {
        if let averagedSource = averagedTemperatureSourceDefinition(for: config.temperatureSourceMode) {
            return averagedSource.name
        }
        return selectionSummary(
            for: reading,
            in: readings,
            automatic: config.temperatureSourceMode != "manual"
        )
    }

    private struct StatusBarDisplayData {
        let temperatureNumberText: String
        let temperatureTextWithUnit: String
        let rpmNumberText: String
        let rpmTextWithUnit: String
        let powerNumberText: String
        let powerTextWithUnit: String
        let isTemperatureAvailable: Bool
        let isRPMAvailable: Bool
        let isPowerAvailable: Bool

        private func sourceTexts(for source: MiniLineSource) -> (value: String, unit: String) {
            switch source {
            case .temperature:
                return (temperatureNumberText, temperatureTextWithUnit)
            case .rpm:
                return (rpmNumberText, rpmTextWithUnit)
            case .power:
                return (powerNumberText, powerTextWithUnit)
            }
        }

        func miniContent(sources: [MiniLineSource], style: MiniLineStyle, modeLetter: String) -> (primary: String, accent: String) {
            let effectiveSources = sources.isEmpty ? [.temperature] : sources
            let values = effectiveSources.map { sourceTexts(for: $0).value }
            let units = effectiveSources.map { sourceTexts(for: $0).unit }
            return MiniDisplayFormatter.line(values: values, units: units, style: style.rawValue, mode: modeLetter)
        }
    }

    private func makeStatusBarDisplayData(
        selectedReading: TemperatureReading?,
        latestRPM: Int?,
        bgSnapshot: BackgroundHardwareReader.Snapshot,
        powerSnapshot: PowerTelemetrySnapshot
    ) -> StatusBarDisplayData {
        let temperatureIsStale = (bgSnapshot.secondsSinceTemperatureSuccess ?? .infinity) > backgroundTelemetryStaleThreshold
        let rpmIsStale = (bgSnapshot.secondsSinceFanRPMSuccess ?? .infinity) > backgroundTelemetryStaleThreshold
        let powerIsStale = {
            guard powerSnapshot.isSupported,
                  let updatedAt = powerSnapshot.lastUpdatedAt else { return true }
            return Date().timeIntervalSince(updatedAt) > backgroundTelemetryStaleThreshold
        }()

        let isTemperatureAvailable = selectedReading != nil && !temperatureIsStale
        let isRPMAvailable = latestRPM != nil && !rpmIsStale
        let isPowerAvailable = powerSnapshot.isSupported && !powerIsStale

        let temperatureNumberText = isTemperatureAvailable
            ? String(format: "%.0f", selectedReading!.value)
            : "--"
        let rpmNumberText = isRPMAvailable
            ? "\(latestRPM!)"
            : "--"
        let powerNumberText = isPowerAvailable
            ? String(format: "%.1f", max(powerSnapshot.cpuWatts + powerSnapshot.gpuWatts + powerSnapshot.aneWatts + powerSnapshot.ramWatts, 0))
            : "--"

        return StatusBarDisplayData(
            temperatureNumberText: temperatureNumberText,
            temperatureTextWithUnit: "\(temperatureNumberText)℃",
            rpmNumberText: rpmNumberText,
            rpmTextWithUnit: "\(rpmNumberText) RPM",
            powerNumberText: powerNumberText,
            powerTextWithUnit: "\(powerNumberText)W",
            isTemperatureAvailable: isTemperatureAvailable,
            isRPMAvailable: isRPMAvailable
            ,
            isPowerAvailable: isPowerAvailable
        )
    }

    private static func mapLegacyMiniContentType(_ legacy: String) -> (MiniLineSource, MiniLineStyle) {
        switch legacy {
        case "temp":
            return (.temperature, .value)
        case "temp_unit":
            return (.temperature, .unit)
        case "temp_mode":
            return (.temperature, .mode)
        case "temp_unit_mode":
            return (.temperature, .full)
        case "rpm":
            return (.rpm, .value)
        case "rpm_unit":
            return (.rpm, .unit)
        case "rpm_short":
            return (.rpm, .value)
        default:
            return (.rpm, .unit)
        }
    }
    
    func setupMenuBar() {
        createStatusItem()
        PowerTelemetryReader.shared.refresh()

        NotificationCenter.default.addObserver(self, selector: #selector(handleCurveSaved), name: NSNotification.Name("FanCurveDidSave"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCurveSwitched), name: NSNotification.Name("FanCurveDidSwitch"), object: nil)

        // 监听 SystemUIServer 重启（macOS 菜单栏图标丢失的常见原因）
        // didChangeScreenParametersNotification 在显示器变更和 SystemUIServer 重启时都会触发
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenOrDisplayChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // 后台轮询硬件（GCD 定时器，不依赖 RunLoop，无显示器也能运行）
        let menuTimer = DispatchSource.makeTimerSource(queue: .main)
        menuTimer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        menuTimer.setEventHandler { [weak self] in
            guard let self else { return }
            // 健康检查：如果 statusItem 因 SystemUIServer 重启而丢失，自动恢复
            if self.statusItem?.button?.window == nil {
                self.logger.warning("statusItem lost, recreating")
                self.createStatusItem()
            }
            let fm = FanManager.shared
            fm.probeHardwareIfNeeded()
            // 后台线程读取传感器 + 风扇（真正非阻塞）
            BackgroundHardwareReader.shared.refresh(
                sensors: fm.availableTemperatureSensors,
                fans: fm.fans
            )
            PowerTelemetryReader.shared.refresh()
            // 主线程更新菜单 UI
            self.updateDynamicMenuItems()
        }
        menuTimer.resume()
        self.menuPollTimer = menuTimer

    }

    private func createStatusItem() {
        // 清理旧的 statusItem（如果存在）
        if let old = statusItem {
            NSStatusBar.system.removeStatusItem(old)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "···"
        }
        statusItem?.length = NSStatusItem.variableLength
        buildMenuOnce()
        setupMiniStatusHostingView()
        updateDynamicMenuItems()
    }

    private func setupMiniStatusHostingView() {
        guard let button = statusItem?.button else { return }
        miniStatusView?.removeFromSuperview()

        let view = MiniStatusView()
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            view.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 22),
        ])

        miniStatusView = view
    }

    @objc private func handleScreenOrDisplayChange() {
        // SystemUIServer 重启后，statusItem 会失效，需要重建
        if statusItem?.button?.window == nil {
            logger.warning("screen/display change detected stale statusItem, recreating")
            createStatusItem()
        }
        if FanManager.shared.fanCount == 0 || FanManager.shared.availableTemperatureSensors.isEmpty {
            FanManager.shared.reprobeHardware(reason: "screen_or_display_change_missing_profile", minimumInterval: 0)
        }
        BackgroundHardwareReader.shared.refresh(
            sensors: FanManager.shared.availableTemperatureSensors,
            fans: FanManager.shared.fans
        )
        updateDynamicMenuItems()
    }
    
    @objc private func handleCurveSaved(_ notification: Notification) {
        InteractionNotice.shared.show(appL10n("曲线已保存", "Curve saved"))
        if let curve = notification.userInfo?["curve"] as? [FanPoint] {
            fanCurve = curve
        }
        // 同步预设数据到 config
        if let names = notification.userInfo?["curvePresetNames"] as? [String],
           let presets = notification.userInfo?["curvePresets"] as? [[FanPoint]],
           let active = notification.userInfo?["activeCurvePreset"] as? Int {
            var config = ConfigManager.shared.loadConfig()
            config.curvePresetNames = names
            config.curvePresets = presets
            config.activeCurvePreset = active
            ConfigManager.shared.saveConfig(config)
        }
    }

    @objc private func handleCurveSwitched(_ notification: Notification) {
        if let curve = notification.userInfo?["curve"] as? [FanPoint] {
            fanCurve = curve
        }
    }
    
    /// 构建菜单结构（仅在启动时调用一次）
    private func buildMenuOnce() {
        guard let statusItem = statusItem else { return }

        let config = ConfigManager.shared.loadConfig()
        let readings = FanManager.shared.availableTemperatureReadings()

        let menu = NSMenu()

        // 硬件信息
        let hwItem = NSMenuItem(
            title: FanManager.shared.fanCount > 0 ?
                appL10n("风扇 \(FanManager.shared.fanCount) | 上限 \(FanManager.shared.currentMaxRPM)", "Fans \(FanManager.shared.fanCount) | Max \(FanManager.shared.currentMaxRPM)") :
                appL10n("无可控风扇", "No controllable fan"),
            action: nil, keyEquivalent: ""
        )
        hwItem.isEnabled = false
        self.hardwareItem = hwItem

        // 温度源信息
        let sensorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        sensorItem.isEnabled = false
        self.currentSensorItem = sensorItem

        // A quiet status line replaces the nested card and duplicate headings.
        let controlStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let statusView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 28))
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.frame = NSRect(x: 20, y: 6, width: 160, height: 16)
        statusLabel.lineBreakMode = .byTruncatingTail
        let modeLabel = NSTextField(labelWithString: "")
        modeLabel.font = .systemFont(ofSize: 11)
        modeLabel.textColor = .secondaryLabelColor
        modeLabel.alignment = .right
        modeLabel.frame = NSRect(x: 170, y: 6, width: 60, height: 16)
        statusView.addSubview(statusLabel); statusView.addSubview(modeLabel)
        controlStatusItem.view = statusView; menu.addItem(controlStatusItem)
        self.controlStatusItem = controlStatusItem
        self.controlStatusContainerView = statusView
        self.controlStatusBottomLeftField = statusLabel
        self.controlModeField = modeLabel
        menu.addItem(NSMenuItem.separator())

        // 模式切换
        let modeItem = NSMenuItem(title: "", action: #selector(toggleMode), keyEquivalent: "m")
        modeItem.target = self
        menu.addItem(modeItem)
        self.modeItem = modeItem

        // 手动转速（仅手动模式显示）
        let spdItem = NSMenuItem(title: appL10n("设置转速...", "Set Speed..."), action: #selector(showSpeedSetting), keyEquivalent: "")
        spdItem.target = self
        spdItem.isHidden = true
        menu.addItem(spdItem)
        self.speedItem = spdItem

        // 温度源子菜单
        let temperatureSourceItem = NSMenuItem(title: appL10n("选择温度源", "Select Temperature Source"), action: nil, keyEquivalent: "")
        let temperatureSourceMenu = NSMenu()
        temperatureSourceMenu.addItem(sensorItem)
        temperatureSourceMenu.addItem(NSMenuItem.separator())

        let hottestItem = NSMenuItem(title: appL10n("自动选择（最热）", "Auto (Hottest)"), action: #selector(selectAutomaticTemperatureSource), keyEquivalent: "")
        hottestItem.target = self
        hottestItem.state = (config.temperatureSourceMode == "manual" || averagedTemperatureSourceDefinition(for: config.temperatureSourceMode) != nil) ? .off : .on
        temperatureSourceMenu.addItem(hottestItem)
        self.hottestItem = hottestItem

        let cpuAverageItem = NSMenuItem(title: appL10n("CPU 平均温度", "CPU Average Temperature"), action: #selector(selectCPUAverageTemperatureSource), keyEquivalent: "")
        cpuAverageItem.target = self
        cpuAverageItem.state = config.temperatureSourceMode == "cpu_average" ? .on : .off
        temperatureSourceMenu.addItem(cpuAverageItem)
        self.cpuAverageItem = cpuAverageItem

        let gpuAverageItem = NSMenuItem(title: appL10n("GPU 平均温度", "GPU Average Temperature"), action: #selector(selectGPUAverageTemperatureSource), keyEquivalent: "")
        gpuAverageItem.target = self
        gpuAverageItem.state = config.temperatureSourceMode == "gpu_average" ? .on : .off
        temperatureSourceMenu.addItem(gpuAverageItem)
        self.gpuAverageItem = gpuAverageItem

        sensorMenuItems.removeAll()
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
                    sensorMenuItems.append(item)
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

        // 编辑曲线
        let curveItem = NSMenuItem(title: appL10n("编辑曲线...", "Edit Curve..."), action: #selector(showFanCurveEditor), keyEquivalent: "c")
        curveItem.target = self
        menu.addItem(curveItem)

        menu.addItem(temperatureSourceItem)
        let powerItem = NSMenuItem(title: appL10n("电力消耗...", "Power Consumption..."), action: #selector(showPowerConsumption), keyEquivalent: "")
        powerItem.target = self; menu.addItem(powerItem)
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: appL10n("设置", "Settings"), action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.addItem(hwItem)
        settingsMenu.addItem(NSMenuItem.separator())
        // 安全兜底转速
        let safetyItem = NSMenuItem(title: appL10n("安全兜底转速...", "Safety Floor RPM..."), action: #selector(showSafetyFloorSetting), keyEquivalent: "")
        safetyItem.target = self
        settingsMenu.addItem(safetyItem)

        // 开机自启动
        let autoItem = NSMenuItem(title: appL10n("开机自启动", "Launch at Login"), action: #selector(toggleAutoStart), keyEquivalent: "")
        autoItem.target = self
        settingsMenu.addItem(autoItem)
        self.autoStartItem = autoItem

        // 信息栏展示
        let displayItem = NSMenuItem(title: appL10n("信息栏展示...", "Display..."), action: #selector(showDisplaySettings), keyEquivalent: "")
        displayItem.target = self
        settingsMenu.addItem(displayItem)

        // 语言
        let languageItem = NSMenuItem(title: appL10n("语言", "Language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        let zh = NSMenuItem(title: "中文", action: #selector(switchToChinese), keyEquivalent: "")
        zh.target = self
        languageMenu.addItem(zh)
        self.zhItem = zh
        let en = NSMenuItem(title: "English", action: #selector(switchToEnglish), keyEquivalent: "")
        en.target = self
        languageMenu.addItem(en)
        self.enItem = en
        settingsMenu.setSubmenu(languageMenu, for: languageItem)
        settingsMenu.addItem(languageItem)

        menu.setSubmenu(settingsMenu, for: settingsItem)
        menu.addItem(settingsItem)

        // 关于/帮助
        let aboutItem = NSMenuItem(title: appL10n("关于/帮助...", "About / Help..."), action: #selector(showHelp), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // 反馈入口（标准菜单项，自然对齐）
        let feedbackTitleItem = NSMenuItem(title: appL10n("告诉开发者 👋", "Talk to Dev 👋"), action: #selector(showFeedback), keyEquivalent: "")
        feedbackTitleItem.target = self
        menu.addItem(feedbackTitleItem)

        // Intentional invitation: it looks like a text field to encourage feedback,
        // and opens the dedicated composer rather than editing inside NSMenu.
        let feedbackItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let feedbackContainer = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 76))
        let feedbackField = NSTextField(frame: NSRect(x: 20, y: 6, width: 210, height: 64))
        feedbackField.identifier = NSUserInterfaceItemIdentifier("feedback-invitation")
        feedbackField.isEditable = false
        feedbackField.isSelectable = false
        feedbackField.isBezeled = true
        feedbackField.bezelStyle = .roundedBezel
        feedbackField.font = NSFontManager.shared.convert(.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
        feedbackField.textColor = .placeholderTextColor
        feedbackField.stringValue = appL10n("找作者聊聊，随便说两句...", "Just say anything...")
        feedbackField.alignment = .left
        feedbackField.lineBreakMode = .byWordWrapping
        feedbackField.maximumNumberOfLines = 2
        feedbackContainer.addSubview(feedbackField)
        // Native button hit testing also works during NSMenu tracking. Keep the
        // inviting text-field appearance while making its entire area clickable.
        let feedbackButton = NSButton(title: "", target: self, action: #selector(showFeedback))
        feedbackButton.frame = feedbackField.frame
        feedbackButton.isTransparent = true
        feedbackButton.identifier = NSUserInterfaceItemIdentifier("feedback-invitation-button")
        feedbackButton.setAccessibilityLabel(feedbackField.stringValue)
        feedbackButton.toolTip = appL10n("打开反馈窗口", "Open the feedback window")
        feedbackField.setAccessibilityElement(false)
        feedbackContainer.addSubview(feedbackButton)
        feedbackItem.view = feedbackContainer
        menu.addItem(feedbackItem)


        menu.addItem(NSMenuItem.separator())

        // 重启 / 退出
        let restartItem = NSMenuItem(title: appL10n("重新启动", "Restart"), action: #selector(restartApp), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: appL10n("退出", "Quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
        statusItem.menu = menu
    }

    /// 原地更新动态菜单项（每 2 秒调用，不重建菜单）
    func updateDynamicMenuItems() {
        guard let statusItem = statusItem else { return }

        let config = ConfigManager.shared.loadConfig()

        // 从后台读取器的缓存读取（零硬件 I/O，零磁盘 I/O）
        let bgSnapshot = BackgroundHardwareReader.shared.snapshot
        let readings: [TemperatureReading] = FanManager.shared.availableTemperatureSensors.compactMap { sensor in
            guard let value = bgSnapshot.temperatures[sensor.key] else { return nil }
            return TemperatureReading(sensor: sensor, value: value)
        }.sorted { lhs, rhs in
            if lhs.sensor.sortKey != rhs.sensor.sortKey { return lhs.sensor.sortKey < rhs.sensor.sortKey }
            return lhs.value > rhs.value
        }

        let selectedReading = selectedTemperatureReading(from: readings, config: config)

        if let reading = selectedReading {
            currentTemperature = reading.value
            currentTemperatureSensorName = sourceSummary(for: reading, config: config, in: readings)
        }

        let latestRPM = bgSnapshot.fanRPMs.values.max()
        if let rpm = latestRPM {
            currentFanRPM = rpm
        }
        let powerSnapshot = PowerTelemetryReader.shared.snapshot

        let displayData = makeStatusBarDisplayData(
            selectedReading: selectedReading,
            latestRPM: latestRPM,
            bgSnapshot: bgSnapshot,
            powerSnapshot: powerSnapshot
        )

        // 状态栏标题
        if displayMode == "compact" {
            miniStatusView?.isHidden = true
            statusItem.button?.imagePosition = .noImage
            let modeLetter = isAutoMode ? "A" : "M"
            statusItem.button?.title = "\(displayData.temperatureNumberText)｜\(displayData.rpmNumberText)｜\(modeLetter)"
            statusItem.button?.image = nil
            statusItem.length = NSStatusItem.variableLength
        } else if displayMode == "mini" {
            let modeLetter = isAutoMode ? "A" : "M"

            let snapshot = ControlStatusStore.load()
            let isAbnormal = snapshot != nil && snapshot?.mode != "normal"
            let accentColor: NSColor = isAbnormal ? .systemRed : .systemGreen

            let top = displayData.miniContent(sources: miniTopLine.sources, style: miniTopLine.style, modeLetter: modeLetter)
            let bot = displayData.miniContent(sources: miniBottomLine.sources, style: miniBottomLine.style, modeLetter: modeLetter)

            statusItem.button?.imagePosition = .noImage
            statusItem.button?.image = nil
            if let v = miniStatusView {
                v.topPrimaryText    = top.primary
                v.topAccentText     = top.accent
                v.topAccentColor    = accentColor
                v.bottomPrimaryText = bot.primary
                v.bottomAccentText  = bot.accent
                v.bottomAccentColor = accentColor
                v.isHidden = false
                v.setNeedsDisplay(v.bounds)
            }
            statusItem.button?.title = ""

            let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let topW = ("\(top.primary)\(top.accent)" as NSString).size(withAttributes: attrs).width
            let botW = ("\(bot.primary)\(bot.accent)" as NSString).size(withAttributes: attrs).width
            statusItem.length = max(topW, botW) + 8

            statusItem.button?.toolTip = "\(displayData.rpmTextWithUnit) | \(displayData.temperatureTextWithUnit) | \(displayData.powerTextWithUnit) [\(isAutoMode ? "Auto" : "Manual")]"
        } else {
            miniStatusView?.isHidden = true
            statusItem.button?.imagePosition = .noImage
            let temperatureText = displayData.temperatureTextWithUnit
            let fanText = displayData.rpmTextWithUnit
            let modeText = isAutoMode ? "[Auto]" : "[Manual]"
            var statusIcon = ""
            if displayData.isTemperatureAvailable && currentTemperature >= 90.0 {
                statusIcon = " 🔥"
            } else if displayData.isTemperatureAvailable && currentTemperature >= 85.0 {
                statusIcon = " ⚠️"
            }
            statusItem.button?.image = nil
            statusItem.button?.title = "\(temperatureText) | \(fanText) \(modeText)\(statusIcon)"
            statusItem.length = NSStatusItem.variableLength
        }

        // 硬件信息
        hardwareItem?.title = FanManager.shared.fanCount > 0 ?
            appL10n("风扇 \(FanManager.shared.fanCount) | 上限 \(FanManager.shared.currentMaxRPM)", "Fans \(FanManager.shared.fanCount) | Max \(FanManager.shared.currentMaxRPM)") :
            appL10n("无可控风扇", "No controllable fan")

        // 温度源
        currentSensorItem?.title = appL10n("温度源 \(currentTemperatureSensorName)", "Temperature Source \(currentTemperatureSensorName)")
        let controlStatus = currentControlStatusLine()
        controlStatusBottomLeftField?.stringValue = controlStatus.bottomLeft
        controlStatusBottomLeftField?.textColor = controlStatus.statusColor
        controlModeField?.stringValue = isAutoMode ? appL10n("自动", "Auto") : appL10n("手动", "Manual")
        controlStatusContainerView?.toolTip = controlStatus.detailText
        controlStatusContainerView?.setAccessibilityLabel(appL10n("控制状态", "Control status"))

        // 温度源子菜单：更新传感器数值和选中态
        hottestItem?.state = (config.temperatureSourceMode == "manual" || averagedTemperatureSourceDefinition(for: config.temperatureSourceMode) != nil) ? .off : .on
        cpuAverageItem?.state = config.temperatureSourceMode == "cpu_average" ? .on : .off
        gpuAverageItem?.state = config.temperatureSourceMode == "gpu_average" ? .on : .off
        var sensorIdx = 0
        for section in groupedTemperatureReadings(readings) {
            for (index, reading) in section.readings.enumerated() {
                if sensorIdx < sensorMenuItems.count {
                    let item = sensorMenuItems[sensorIdx]
                    item.title = shortTitle(for: reading, index: index)
                    item.toolTip = "\(reading.sensor.name) (\(reading.sensor.key))  \(String(format: "%.1f℃", reading.value))"
                    item.state = (config.temperatureSourceMode == "manual" && config.selectedTemperatureSensorKey == reading.sensor.key) ? .on : .off
                }
                sensorIdx += 1
            }
        }

        // 模式切换
        modeItem?.title = isAutoMode ? appL10n("切换至手动控制", "Switch to Manual Control") : appL10n("切换至自动控制", "Switch to Auto Control")

        // 手动转速项（仅手动模式可见）
        speedItem?.isHidden = isAutoMode

        // 开机自启动
        autoStartItem?.state = autoStartEnabled ? .on : .off

        // 语言选中态
        zhItem?.state = currentLanguage == "zh" ? .on : .off
        enItem?.state = currentLanguage == "en" ? .on : .off
    }

    private func currentControlStatusLine() -> (topLeft: String, topRight: String, bottomLeft: String, bottomRight: String, statusColor: NSColor, detailText: String) {
        guard let snapshot = ControlStatusStore.load() else {
            return (
                appL10n("控制状态", "Status"),
                appL10n("状态刷新", "Refresh"),
                appL10n("启动中", "Starting"),
                appL10n("刚刚", "Now"),
                .secondaryLabelColor,
                ""
            )
        }

        let interval = Int(Date().timeIntervalSince(snapshot.recordedAt))
        let ageText: String
        if interval < 60 {
            ageText = appL10n("\(max(interval, 0))秒前", "\(max(interval, 0))s ago")
        } else {
            ageText = appL10n("\(interval / 60)分钟前", "\(interval / 60)m ago")
        }

        let detailParts = snapshot.detail
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        let modeText: String
        let statusColor: NSColor
        switch snapshot.mode {
        case "normal":
            modeText = appL10n("控制正常", "Control normal")
            statusColor = .systemGreen
        case "sensor_loss_fixed_rpm":
            modeText = appL10n("⚠ 传感器丢失", "⚠ Sensor Lost")
            statusColor = .systemRed
        case "system_auto_fallback":
            modeText = appL10n("⚠ 已交还系统", "⚠ System Fallback")
            statusColor = .systemOrange
        default:
            modeText = snapshot.mode
            statusColor = .secondaryLabelColor
        }

        let bottomLeft: String
        if let firstPart = detailParts.first, !firstPart.isEmpty {
            if detailParts.count == 2, !detailParts[1].isEmpty {
                bottomLeft = "\(firstPart) / \(detailParts[1])"
            } else {
                bottomLeft = firstPart
            }
        } else {
            bottomLeft = ""
        }

        // recordedAt is a status/detail transition timestamp, not a health-check
        // freshness timestamp. Keep it out of the visible current-status row.
        let recordExplanation = appL10n(
            "最近一次状态记录：\(ageText)",
            "Last status record: \(ageText)"
        )
        let detailText = [bottomLeft, recordExplanation].filter { !$0.isEmpty }.joined(separator: "\n")

        return (
            appL10n("控制状态", "Status"),
            appL10n("状态刷新", "Refresh"),
            modeText,
            ageText,
            statusColor,
            detailText
        )
    }

    /// 完全重建菜单（仅在语言切换等需要重建结构时调用）
    func updateMenu() {
        buildMenuOnce()
        updateDynamicMenuItems()
    }
    
    @objc func showFanCurveEditor() {
        if let window = fanCurveWindowController?.window, window.isVisible { presentWindowFront(window); return }
        NSLog("iFanControl: showFanCurveEditor - creating FanCurvePresetWindowController")
        let config = ConfigManager.shared.loadConfig()
        fanCurveWindowController = FanCurvePresetWindowController(
            fanCurve: fanCurve,
            maxRPM: FanManager.shared.currentMaxRPM,
            presetNames: config.curvePresetNames,
            presets: config.curvePresets,
            activePresetIndex: config.activeCurvePreset
        )
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
        updateDynamicMenuItems()
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

        updateDynamicMenuItems()
    }
    
    // 启用开机自启动（SMAppService）
    private func enableAutoStart() {
        migrateFromLegacyLaunchAgent()

        do {
            try SMAppService.mainApp.register()
            logger.info("SMAppService registered")
        } catch {
            logger.error("SMAppService register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // 启动时确保自启动状态与配置一致
    func ensureAutoStartEnabled() {
        migrateFromLegacyLaunchAgent()

        if SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
                logger.info("SMAppService registered (startup sync)")
            } catch {
                logger.error("SMAppService register failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // 禁用开机自启动
    private func disableAutoStart() {
        do {
            try SMAppService.mainApp.unregister()
            logger.info("SMAppService unregistered")
        } catch {
            logger.error("SMAppService unregister failed: \(error.localizedDescription, privacy: .public)")
        }

        migrateFromLegacyLaunchAgent()
    }

    // 迁移旧的 LaunchAgent → SMAppService
    private func migrateFromLegacyLaunchAgent() {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.ifancontrol.app.plist")

        guard FileManager.default.fileExists(atPath: plistPath.path) else { return }

        let uid = getuid()
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = ["bootout", "gui/\(uid)/com.ifancontrol.app"]

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
            _ = semaphore.wait(timeout: .now() + 5)
        } catch {}

        try? FileManager.default.removeItem(at: plistPath)
        logger.info("Migrated from legacy LaunchAgent to SMAppService")
    }
    
    @objc func showSpeedSetting() {
        if let window = speedSettingWindowController?.window, window.isVisible { presentWindowFront(window); return }
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

    @objc func showDisplaySettings() {
        if let window = displaySettingsWindowController?.window, window.isVisible { presentWindowFront(window); return }
        displaySettingsWindowController = DisplaySettingsWindowController()
        displaySettingsWindowController?.onSettingsChanged = { [weak self] in
            self?.statusItem?.button?.font = nil
            self?.statusItem?.length = NSStatusItem.variableLength
            self?.updateDynamicMenuItems()
        }
        displaySettingsWindowController?.showWindow(nil)
        presentWindowFront(displaySettingsWindowController?.window)
    }

    @objc func showPowerConsumption() {
        if powerConsumptionWindowController == nil {
            powerConsumptionWindowController = PowerConsumptionWindowController()
        }
        PowerTelemetryReader.shared.refresh()
        powerConsumptionWindowController?.showWindow(nil)
        powerConsumptionWindowController?.refreshSnapshot()
        presentWindowFront(powerConsumptionWindowController?.window)
    }

    @objc func showSafetyFloorSetting() {
        if let window = safetyFloorWindowController?.window, window.isVisible { presentWindowFront(window); return }
        let config = ConfigManager.shared.loadConfig()
        let currentRPM = min(max(config.safetyFloorRPM ?? FanManager.shared.defaultSafetyRPM, 2000), FanManager.shared.currentMaxRPM)
        safetyFloorWindowController = SafetyFloorWindowController(initialRPM: currentRPM, maxRPM: FanManager.shared.currentMaxRPM)
        safetyFloorWindowController?.showWindow(nil)
        presentWindowFront(safetyFloorWindowController?.window)
    }

    @objc func switchToChinese() {
        UserDefaults.standard.set("zh", forKey: "ifancontrol.ui.language")
        showRestartRequiredAlert()
    }

    @objc func switchToEnglish() {
        UserDefaults.standard.set("en", forKey: "ifancontrol.ui.language")
        showRestartRequiredAlert()
    }

    private func showRestartRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = appL10n("语言已切换", "Language Changed")
        alert.informativeText = appL10n("重启应用后生效。是否现在重启？", "Restart the app to apply. Restart now?")
        alert.alertStyle = .informational
        alert.addButton(withTitle: appL10n("立即重启", "Restart Now"))
        alert.addButton(withTitle: appL10n("稍后", "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            restartApp()
        }
    }

    @objc func selectAutomaticTemperatureSource() {
        var config = ConfigManager.shared.loadConfig()
        config.temperatureSourceMode = "hottest"
        config.selectedTemperatureSensorKey = nil
        ConfigManager.shared.saveConfig(config)
        logger.info("Temperature source switched to automatic hottest sensor")
        updateDynamicMenuItems()
    }

    @objc func selectCPUAverageTemperatureSource() {
        var config = ConfigManager.shared.loadConfig()
        config.temperatureSourceMode = "cpu_average"
        config.selectedTemperatureSensorKey = nil
        ConfigManager.shared.saveConfig(config)
        logger.info("Temperature source switched to CPU sensor average")
        updateDynamicMenuItems()
    }

    @objc func selectGPUAverageTemperatureSource() {
        var config = ConfigManager.shared.loadConfig()
        config.temperatureSourceMode = "gpu_average"
        config.selectedTemperatureSensorKey = nil
        ConfigManager.shared.saveConfig(config)
        logger.info("Temperature source switched to GPU sensor average")
        updateDynamicMenuItems()
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
        updateDynamicMenuItems()
    }

    func maybeShowStartupGuidance() {
        let defaults = UserDefaults.standard

        // 首次启动语言选择
        if defaults.string(forKey: "ifancontrol.ui.language") == nil {
            let alert = NSAlert()
            alert.messageText = "选择语言 / Select Language"
            alert.informativeText = "请选择界面语言。你可以在菜单中随时更改。\nPlease select your language. You can change it anytime from the menu."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "中文")
            alert.addButton(withTitle: "English")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                defaults.set("en", forKey: "ifancontrol.ui.language")
            } else {
                defaults.set("zh", forKey: "ifancontrol.ui.language")
            }
        }

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
            InteractionNotice.shared.show(appL10n("温度源与控制模式可随时在菜单中调整。", "You can change the temperature source and control mode in the menu."), symbol: "info.circle")
        }
    }

    @objc func showHelp() {
        if helpWindowController == nil {
            helpWindowController = HelpWindowController()
        }
        helpWindowController?.showWindow(nil)
        presentWindowFront(helpWindowController?.window)
    }

    @objc func showFeedback() {
        menu?.cancelTracking()
        // 先关闭菜单，避免遮挡弹窗
        self.menu?.cancelTracking()

        if feedbackWindowController == nil {
            feedbackWindowController = FeedbackWindowController()
        }
        feedbackWindowController?.showWindow(nil)
        presentWindowFront(feedbackWindowController?.window)
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

    var currentFanCurve: [FanPoint] {
        return fanCurve
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
    private let systemAutoFallbackInterval: TimeInterval = 30.0
    private let sensorLossSafeRPM = 2200
    private let startupTelemetryGracePeriod: TimeInterval = 20.0
    private let missingTelemetryTriggerCount = 5
    private var statsHeartbeatTimer: DispatchSourceTimer?
    private var controlLoopTimer: DispatchSourceTimer?
    private var lastDiagLogTime: TimeInterval = 0
    private var lastSystemAutoFallbackAt: Date?
    private var activeSafetyAlertState: String?
    private var launchDate = Date()
    private var consecutiveMissingTelemetryCount = 0
    private var lastRecordedControlStatus: String?
    private let startupWindow = StartupProgressWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        launchDate = Date()
        NSApp.setActivationPolicy(.accessory)
        startupWindow.present()
        // Let the launch UI enter the run loop before the existing hardware probes.
        DispatchQueue.main.async { [weak self] in
            self?.finishLaunching()
        }
    }

    private func finishLaunching() {
        AppLog.shared.bootstrapSession()
        AppLog.shared.info("application did finish launching")
        updateControlStatus(mode: "normal", detail: appL10n("启动完成", "Startup complete"), force: true)

        FanManager.shared.refreshHardwareProfile()
        startupWindow.setStage(.preferences)
        let config = ConfigManager.shared.syncHardwareProfile(maxRPM: FanManager.shared.currentMaxRPM)
        MenuBarManager.shared.setFanCurve(config.curve)
        MenuBarManager.shared.setIsAutoMode(config.mode == "auto")
        MenuBarManager.shared.setAutoStartEnabled(config.autoStart)

        // 确保 LaunchAgent plist 存在并加载到 launchd
        if config.autoStart {
            MenuBarManager.shared.ensureAutoStartEnabled()
        }

        startupWindow.setStage(.controls)
        MenuBarManager.shared.setupMenuBar()
        
        // 解锁风扇
        FanManager.shared.unlockFans()
        
        // 启动控制循环
        startAutoControlLoop()

        // 启动后延迟进行后台更新检查
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            UpdateService.shared.checkForUpdates(triggeredByUser: false)
        }

        // 匿名运行反馈：启动后延迟入队并尝试上报一次，之后每 15 分钟 tick（入队/批量上报）
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            PrivacyStatsService.shared.startup()
        }
        statsHeartbeatTimer?.cancel()
        let hbTimer = DispatchSource.makeTimerSource(queue: .main)
        hbTimer.schedule(deadline: .now() + 15 * 60, repeating: 15 * 60)
        hbTimer.setEventHandler { PrivacyStatsService.shared.tick() }
        hbTimer.resume()
        statsHeartbeatTimer = hbTimer
        startupWindow.dismiss()
        AppLog.shared.info("startup ready: menu bar and control loop initialized")
        UpdateService.shared.presentInstalledUpdateIfNeeded()
        MenuBarManager.shared.maybeShowStartupGuidance()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        startupWindow.dismiss()
        AppLog.shared.info("application will terminate")
        statsHeartbeatTimer?.cancel()
        PrivacyStatsService.shared.shutdown()
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

        try? SMAppService.mainApp.unregister()
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
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let config = ConfigManager.shared.loadConfig()
            let curve = MenuBarManager.shared.currentFanCurve
            let isAutoMode = config.mode == "auto"
            let powerSnapshot = PowerTelemetryReader.shared.snapshot

            // 从后台读取器缓存读取（不触发主线程硬件 I/O）
            let bgSnapshot = BackgroundHardwareReader.shared.snapshot
            let bgTemps = bgSnapshot.temperatures
            let bgRPMs = bgSnapshot.fanRPMs
            let temperatureAge = bgSnapshot.secondsSinceTemperatureSuccess ?? .infinity
            let fanRPMAge = bgSnapshot.secondsSinceFanRPMSuccess ?? .infinity
            let telemetryState: TelemetrySnapshotState = {
                if temperatureAge.isFinite == false || temperatureAge > backgroundTelemetryExpiryThreshold {
                    return .expired
                }
                if temperatureAge > backgroundTelemetryStaleThreshold {
                    return .cachedStale
                }
                return .fresh
            }()
            let canUseTemperatureSnapshot = telemetryState != .expired
            let candidateTemperatures = canUseTemperatureSnapshot ? bgTemps : [:]
            let readings: [TemperatureReading] = FanManager.shared.availableTemperatureSensors.compactMap { sensor in
                guard let value = candidateTemperatures[sensor.key] else { return nil }
                return TemperatureReading(sensor: sensor, value: value)
            }
            let reading = selectedTemperatureReading(from: readings, config: config)

            ThermalAnomalyAlertService.shared.recordSample(
                timestamp: Date().timeIntervalSince1970,
                weightedHotTemperatureCelsius: bgTemps.isEmpty ? nil : {
                    let values = [
                        "Tp00", "Tp01", "Tp04", "Tp05", "Tp08", "Tp09", "Tp0C", "Tp0D",
                        "Tp0U", "Tp0V", "Tp0X", "Tp0Y", "Tp0a", "Tp0b", "Tp0d", "Tp0e", "Tp0f"
                    ].compactMap { bgTemps[$0] }.sorted()
                    guard !values.isEmpty else { return nil }
                    let cutoff = Int(floor(Double(values.count) * 0.35))
                    let keep = Array(values.dropFirst(cutoff))
                    let topCount = max(3, Int(floor(Double(values.count) * 0.25)))
                    let top = Array(values.suffix(topCount))
                    guard !keep.isEmpty, !top.isEmpty else { return nil }
                    let keepAverage = keep.reduce(0, +) / Double(keep.count)
                    let topAverage = top.reduce(0, +) / Double(top.count)
                    return 0.65 * keepAverage + 0.35 * topAverage
                }(),
                hottestFanRPM: bgSnapshot.fanRPMs.values.max(),
                currentMaxRPM: FanManager.shared.currentMaxRPM,
                hotWatts: powerSnapshot.cpuWatts + powerSnapshot.gpuWatts + powerSnapshot.aneWatts + powerSnapshot.ramWatts,
                controlModeAutomatic: isAutoMode
            )

            if reading == nil || telemetryState != .fresh || bgSnapshot.consecutiveTemperatureFailures >= 3 {
                if telemetryState != .fresh || bgSnapshot.consecutiveTemperatureFailures >= 3 {
                    AppLog.shared.warning("control loop detected telemetry degradation state=\(telemetryState.rawValue) bgFail=\(bgSnapshot.consecutiveTemperatureFailures) tempAge=\(String(format: "%.1f", temperatureAge)) rpmAge=\(String(format: "%.1f", fanRPMAge))")
                }
                BackgroundHardwareReader.shared.refresh(
                    sensors: FanManager.shared.availableTemperatureSensors,
                    fans: FanManager.shared.fans
                )
            }

            // 诊断日志：每隔 30 秒报告一次状态
            let now = Date().timeIntervalSince1970
            if now - lastDiagLogTime >= 30 {
                lastDiagLogTime = now
                let sensorKeys = FanManager.shared.availableTemperatureSensors.map(\.key)
                let bgAgeText = bgSnapshot.secondsSinceTemperatureSuccess.map { String(format: "%.1f", $0) } ?? "nil"
                let rpmAgeText = bgSnapshot.secondsSinceFanRPMSuccess.map { String(format: "%.1f", $0) } ?? "nil"
                AppLog.shared.info("ctrl diag model=\(systemModelIdentifier) os=\(ProcessInfo.processInfo.operatingSystemVersionString) bgTemps=\(bgTemps.count) bgRPMs=\(bgRPMs.count) sensors=\(sensorKeys.count) readings=\(readings.count) hasReading=\(reading != nil) telemetryState=\(telemetryState.rawValue) bgFail=\(bgSnapshot.consecutiveTemperatureFailures) bgAge=\(bgAgeText) rpmAge=\(rpmAgeText)")
            }

            guard let reading else {
                consecutiveMissingTelemetryCount += 1
                if !FanManager.shared.availableTemperatureSensors.isEmpty {
                    AppLog.shared.warning("ctrl loop skip: no readable temperatures sensors=\(FanManager.shared.availableTemperatureSensors.count) telemetryState=\(telemetryState.rawValue) bgFail=\(bgSnapshot.consecutiveTemperatureFailures) missingCount=\(consecutiveMissingTelemetryCount)")
                }
                let withinStartupGrace = Date().timeIntervalSince(launchDate) < startupTelemetryGracePeriod
                if withinStartupGrace {
                    AppLog.shared.info("startup telemetry grace active missingCount=\(consecutiveMissingTelemetryCount)")
                    return
                }
                if consecutiveMissingTelemetryCount < missingTelemetryTriggerCount {
                    return
                }
                let missingReason = telemetryState == .expired ? "temp_snapshot_expired" : "bg_temp_poll_empty"
                self.handleMissingTemperatureTelemetry(hasFanTelemetry: fanRPMAge <= backgroundTelemetryExpiryThreshold && !bgRPMs.isEmpty, reason: missingReason)
                return
            }
            consecutiveMissingTelemetryCount = 0
            self.clearSafetyAlertState(prefix: "sensor_loss")
            self.clearSafetyAlertState(prefix: "system_auto_fallback")
            let controlSourceName = averagedTemperatureSourceDefinition(for: config.temperatureSourceMode)?.name ?? reading.sensor.compactName
            self.updateControlStatus(
                mode: telemetryState == .cachedStale ? "telemetry_cached" : "normal",
                detail: isAutoMode
                    ? (telemetryState == .cachedStale
                        ? appL10n("自动 / \(controlSourceName) / 缓存", "Auto / \(controlSourceName) / Cached")
                        : appL10n("自动 / \(controlSourceName)", "Auto / \(controlSourceName)"))
                    : appL10n("手动 / \(config.manualRPM) RPM", "Manual / \(config.manualRPM) RPM")
            )

            if isAutoMode {
                let baseSafetyFloor = max(config.safetyFloorRPM ?? FanManager.shared.defaultSafetyRPM, 2000)
                let safetyFloorRPM = min(max(baseSafetyFloor, telemetryState == .cachedStale ? sensorLossSafeRPM : 0), FanManager.shared.currentMaxRPM)
                let targetRPM = FanManager.shared.calculateFanRPM(
                    temperature: reading.value,
                    curve: curve,
                    safetyFloorRPM: safetyFloorRPM
                )

                if targetRPM == -1 {
                    self.engageSystemAutoFallback(reason: "invalid_auto_target")
                } else {
                    FanManager.shared.setFanRPM(rpm: targetRPM)
                }
                self.logControlLoopSummaryIfNeeded(mode: telemetryState == .cachedStale ? "auto_cached" : "auto", reading: reading, targetRPM: targetRPM)
            } else {
                FanManager.shared.setFanRPM(rpm: config.manualRPM)
                self.logControlLoopSummaryIfNeeded(mode: telemetryState == .cachedStale ? "manual_cached" : "manual", reading: reading, targetRPM: config.manualRPM)
            }
        }
        timer.resume()
        self.controlLoopTimer = timer
    }

    private func handleMissingTemperatureTelemetry(hasFanTelemetry: Bool, reason: String) {
        let safeRPM = min(sensorLossSafeRPM, FanManager.shared.currentMaxRPM)
        if FanManager.shared.fanCount > 0 && safeRPM > 0 {
            AppLog.shared.warning("temperature telemetry missing; applying fixed fail-safe rpm=\(safeRPM) hasFanTelemetry=\(hasFanTelemetry) reason=\(reason)")
            FanManager.shared.setFanRPM(rpm: safeRPM)
            updateControlStatus(
                mode: "sensor_loss_fixed_rpm",
                detail: hasFanTelemetry
                    ? appL10n("温度丢失 / 2200 RPM", "Temp lost / 2200 RPM")
                    : appL10n("温度风扇信息丢失 / 2200 RPM", "Temp+fan telemetry lost / 2200 RPM")
            )
            let state = hasFanTelemetry ? "sensor_loss_fixed_rpm" : "sensor_loss_fixed_rpm_no_fan_telemetry"
            let message = hasFanTelemetry
                ? appL10n(
                    "iFanControl 当前读不到温度，但仍能读取风扇信息。已自动将目标转速设置为 2200 RPM 作为保守兜底。",
                    "iFanControl cannot currently read temperatures, but fan telemetry is still available. The target speed has been set to 2200 RPM as a conservative fail-safe."
                )
                : appL10n(
                    "iFanControl 当前读不到温度，也暂时读不到风扇信息。已先尝试将目标转速固定到 2200 RPM；如果控制失败，会自动交还系统。",
                    "iFanControl cannot currently read temperatures and fan telemetry is also unavailable. It is first attempting to hold the target speed at 2200 RPM; if control fails, it will automatically return control to the system."
                )
            showSafetyAlert(
                state: state,
                title: appL10n("已启用保守兜底转速", "Conservative Fail-Safe RPM Enabled"),
                message: message
            )
            return
        }

        engageSystemAutoFallback(reason: hasFanTelemetry ? reason : "temp_and_fan_unavailable")
    }

    private func engageSystemAutoFallback(reason: String) {
        if let lastSystemAutoFallbackAt,
           Date().timeIntervalSince(lastSystemAutoFallbackAt) < systemAutoFallbackInterval {
            return
        }
        lastSystemAutoFallbackAt = Date()
        AppLog.shared.warning("engaging system auto fallback reason=\(reason) model=\(systemModelIdentifier) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        recordSystemAutoFallback(reason: reason)
        showSafetyAlert(
            state: "system_auto_fallback_\(reason)",
            title: appL10n("风扇控制已交还系统", "Fan Control Returned to System"),
            message: appL10n(
                "iFanControl 当前无法可靠获取必要的硬件信息或维持安全控制，已自动将风扇控制权交还给系统。",
                "iFanControl can no longer reliably obtain the required hardware telemetry or maintain safe control, so fan control has been returned to the system automatically."
            )
        )
        CommandExecutor.shared.setFanAutoAsync()
    }

    func showSafetyAlert(state: String, title: String, message: String) {
        if activeSafetyAlertState == state {
            return
        }
        activeSafetyAlertState = state

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message + appL10n("\n\n如果问题持续，请到「关于/帮助 → 诊断与支持」导出诊断包。", "\n\nIf this persists, export diagnostics from About / Help → Diagnostics & Support.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: appL10n("知道了", "OK"))
        alert.runModal()
    }

    private func clearSafetyAlertState(prefix: String) {
        if activeSafetyAlertState?.hasPrefix(prefix) == true {
            activeSafetyAlertState = nil
        }
    }

    private func updateControlStatus(mode: String, detail: String, force: Bool = false) {
        let signature = "\(mode)|\(detail)"
        if !force && lastRecordedControlStatus == signature {
            return
        }
        lastRecordedControlStatus = signature
        ControlStatusStore.save(mode: mode, detail: detail)
        MenuBarManager.shared.updateDynamicMenuItems()
    }

    func recordSystemAutoFallback(reason: String) {
        updateControlStatus(mode: "system_auto_fallback", detail: reason, force: true)
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

// 信息栏展示设置窗口控制器
@MainActor
class DisplaySettingsWindowController: NSWindowController {
    var onSettingsChanged: (() -> Void)?

    private let previewField = NSTextField(labelWithString: "")
    private var fullRadio: NSButton!
    private var compactRadio: NSButton!
    private var miniRadio: NSButton!
    private var miniOptionsStack: NSStackView!
    private var modeControl: NSSegmentedControl!
    private var topStylePopup: NSPopUpButton!
    private var bottomStylePopup: NSPopUpButton!

    private var topSourceCheckboxes: [String: NSButton] = [:]
    private var topStyleRadios: [String: NSButton] = [:]
    private var bottomSourceCheckboxes: [String: NSButton] = [:]
    private var bottomStyleRadios: [String: NSButton] = [:]

    private let displayModeKey    = "ifancontrol.ui.display_mode"
    private let miniTopSourceKey = "ifancontrol.ui.mini_top_source"
    private let miniTopStyleKey = "ifancontrol.ui.mini_top_style"
    private let miniBottomSourceKey = "ifancontrol.ui.mini_bottom_source"
    private let miniBottomStyleKey = "ifancontrol.ui.mini_bottom_style"

    private enum MiniLineSource: String {
        case temperature
        case rpm
        case power
    }

    private enum MiniLineStyle: String {
        case value
        case unit
        case mode
        case full
    }

    private var currentDisplayMode: String {
        get { UserDefaults.standard.string(forKey: displayModeKey) ?? "full" }
        set { UserDefaults.standard.set(newValue, forKey: displayModeKey) }
    }
    private func parseMiniLineSources(_ rawValue: String?) -> [MiniLineSource] {
        guard let rawValue, !rawValue.isEmpty else { return [] }
        var seen = Set<String>()
        return rawValue
            .split(separator: ",")
            .compactMap { MiniLineSource(rawValue: String($0)) }
            .filter { seen.insert($0.rawValue).inserted }
    }

    private func serializedMiniLineSources(_ sources: [MiniLineSource]) -> String {
        var seen = Set<String>()
        return sources
            .filter { seen.insert($0.rawValue).inserted }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    private var currentMiniTopLine: (sources: [MiniLineSource], style: MiniLineStyle) {
        get {
            let defaults = UserDefaults.standard
            let sources = parseMiniLineSources(defaults.string(forKey: miniTopSourceKey))
            let style = defaults.string(forKey: miniTopStyleKey).flatMap(MiniLineStyle.init(rawValue:)) ?? .full
            return (sources.isEmpty ? [.temperature] : sources, style)
        }
        set {
            UserDefaults.standard.set(serializedMiniLineSources(newValue.sources), forKey: miniTopSourceKey)
            UserDefaults.standard.set(newValue.style.rawValue, forKey: miniTopStyleKey)
        }
    }
    private var currentMiniBottomLine: (sources: [MiniLineSource], style: MiniLineStyle) {
        get {
            let defaults = UserDefaults.standard
            let sources = parseMiniLineSources(defaults.string(forKey: miniBottomSourceKey))
            let style = defaults.string(forKey: miniBottomStyleKey).flatMap(MiniLineStyle.init(rawValue:)) ?? .unit
            return (sources.isEmpty ? [.rpm] : sources, style)
        }
        set {
            UserDefaults.standard.set(serializedMiniLineSources(newValue.sources), forKey: miniBottomSourceKey)
            UserDefaults.standard.set(newValue.style.rawValue, forKey: miniBottomStyleKey)
        }
    }

    private static let allSources: [(key: MiniLineSource, zh: String, en: String)] = [
        (.temperature, "温度  (65)", "Temperature  (65)"),
        (.rpm, "转速  (2400)", "RPM  (2400)"),
        (.power, "功率  (12.3)", "Power  (12.3)")
    ]

    private static let allStyles: [(key: MiniLineStyle, zh: String, en: String)] = [
        (.value, "纯数值  (65)", "Value Only  (65)"),
        (.unit, "带单位  (65℃)", "With Unit  (65℃)"),
        (.mode, "带模式  (65｜A)", "With Mode  (65｜A)"),
        (.full, "全部信息  (65℃｜A)", "Full  (65℃｜A)"),
    ]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = appL10n("信息栏展示", "Display Settings")
        window.center()
        super.init(window: window)
        applyWindowMaterialStyle(window)
        setupUI()
        loadCurrentSettings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(root)

        modeControl = NSSegmentedControl(labels: [appL10n("完整", "Full"), appL10n("简洁", "Compact"), appL10n("迷你", "Mini")], trackingMode: .selectOne, target: self, action: #selector(modeSelectionChanged))
        modeControl.segmentStyle = .rounded
        modeControl.setAccessibilityLabel(appL10n("菜单栏显示模式", "Menu bar display mode"))
        modeControl.controlSize = .small; modeControl.font = .systemFont(ofSize: 12)
        for index in 0..<3 { modeControl.setWidth(70, forSegment: index) }
        let modeRow = NSStackView(views: [NativeInterface.label(appL10n("显示模式", "Display mode"), size: 12, color: .secondaryLabelColor), NSView(), modeControl])
        root.addArrangedSubview(modeRow)
        modeRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        // The existing state controls preserve the update and preference semantics.
        fullRadio = makeRadioButton(""); compactRadio = makeRadioButton(""); miniRadio = makeRadioButton("")

        let preview = NSStackView(); preview.orientation = .vertical; preview.spacing = 10; preview.alignment = .centerX
        preview.addArrangedSubview(NativeInterface.label(appL10n("菜单栏预览", "Menu bar preview"), size: 11, weight: .medium, color: .secondaryLabelColor))
        previewField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        previewField.alignment = .center; previewField.maximumNumberOfLines = 2
        previewField.identifier = NSUserInterfaceItemIdentifier("display-preview")
        preview.addArrangedSubview(previewField)
        previewField.heightAnchor.constraint(equalToConstant: 50).isActive = true
        root.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        miniOptionsStack = NSStackView(); miniOptionsStack.orientation = .vertical
        miniOptionsStack.alignment = .leading; miniOptionsStack.spacing = 14
        miniOptionsStack.addArrangedSubview(makeLineRow(top: true))
        let separator = NSBox(); separator.boxType = .separator
        miniOptionsStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: miniOptionsStack.widthAnchor).isActive = true
        miniOptionsStack.addArrangedSubview(makeLineRow(top: false))
        root.addArrangedSubview(miniOptionsStack)
        miniOptionsStack.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let footer = NSStackView(); footer.spacing = 8
        let hint = NativeInterface.label(appL10n("示例数值 · 设置即时生效", "Sample values · Changes apply immediately"), size: 11, color: .secondaryLabelColor)
        footer.addArrangedSubview(hint); footer.addArrangedSubview(NSView())
        let swap = NativeInterface.button(appL10n("交换上下行", "Swap lines"), target: self, action: #selector(swapLines), small: true)
        swap.toolTip = appL10n("交换两行的内容和样式", "Swap the content and style of both lines")
        footer.addArrangedSubview(swap); root.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func makeLineRow(top: Bool) -> NSStackView {
        let column = NSStackView(); column.orientation = .vertical; column.alignment = .leading; column.spacing = 8
        let header = NSStackView(); header.spacing = 12
        header.addArrangedSubview(NativeInterface.label(top ? appL10n("上行", "Top line") : appL10n("下行", "Bottom line"), weight: .medium))
        header.addArrangedSubview(NSView())
        let popup = NSPopUpButton(); popup.controlSize = .small; popup.font = .systemFont(ofSize: 12)
        popup.addItems(withTitles: [appL10n("仅数值", "Numbers only"), appL10n("数值和单位", "Numbers and units"), appL10n("数值和模式", "Numbers and mode"), appL10n("数值、单位和模式", "Numbers, units and mode")])
        popup.target = self; popup.action = top ? #selector(topPopupChanged) : #selector(bottomPopupChanged)
        popup.setAccessibilityLabel(top ? appL10n("上行样式", "Top line style") : appL10n("下行样式", "Bottom line style"))
        header.addArrangedSubview(popup); column.addArrangedSubview(header)
        if top { topStylePopup = popup } else { bottomStylePopup = popup }
        let sources = NSStackView(); sources.spacing = 20
        for item in Self.allSources {
            let title = item.key == .temperature ? appL10n("温度", "Temperature") : item.key == .rpm ? appL10n("转速", "RPM") : appL10n("功率", "Power")
            let button = makeCheckboxButton(title); button.controlSize = .small; button.font = .systemFont(ofSize: 12)
            button.target = self; button.action = top ? #selector(topSourceChanged) : #selector(bottomSourceChanged)
            sources.addArrangedSubview(button)
            if top { topSourceCheckboxes[item.key.rawValue] = button } else { bottomSourceCheckboxes[item.key.rawValue] = button }
        }
        sources.addArrangedSubview(NSView()); column.addArrangedSubview(sources)
        for item in Self.allStyles {
            let state = makeRadioButton("")
            if top { topStyleRadios[item.key.rawValue] = state } else { bottomStyleRadios[item.key.rawValue] = state }
        }
        column.widthAnchor.constraint(equalToConstant: 492).isActive = true
        header.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        sources.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    @objc private func modeSelectionChanged(_ sender: NSSegmentedControl) {
        fullRadio.state = sender.selectedSegment == 0 ? .on : .off
        compactRadio.state = sender.selectedSegment == 1 ? .on : .off
        miniRadio.state = sender.selectedSegment == 2 ? .on : .off
        displayModeChanged(miniRadio)
    }
    @objc private func topPopupChanged(_ sender: NSPopUpButton) {
        guard Self.allStyles.indices.contains(sender.indexOfSelectedItem), let state = topStyleRadios[Self.allStyles[sender.indexOfSelectedItem].key.rawValue] else { return }
        topStyleChanged(state)
    }
    @objc private func bottomPopupChanged(_ sender: NSPopUpButton) {
        guard Self.allStyles.indices.contains(sender.indexOfSelectedItem), let state = bottomStyleRadios[Self.allStyles[sender.indexOfSelectedItem].key.rawValue] else { return }
        bottomStyleChanged(state)
    }

    private func refreshPreview() {
        func line(_ sources: [MiniLineSource], _ style: MiniLineStyle) -> String {
            let texts = sources.map { source -> (String, String) in
                switch source { case .temperature: return ("65", "65℃"); case .rpm: return ("2400", "2400 RPM"); case .power: return ("12.3", "12.3W") }
            }
            let result = MiniDisplayFormatter.line(values: texts.map { $0.0 }, units: texts.map { $0.1 }, style: style.rawValue, mode: "A")
            return result.primary + result.accent
        }
        switch currentDisplayMode {
        case "compact": previewField.stringValue = "65｜2400｜A"
        case "mini": previewField.stringValue = line(currentMiniTopLine.sources, currentMiniTopLine.style) + "\n" + line(currentMiniBottomLine.sources, currentMiniBottomLine.style)
        default: previewField.stringValue = "65℃ | 2400 RPM [Auto]"
        }
    }

    // MARK: - Helpers

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeSubsectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeRadioGroupStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeRadioButton(_ title: String) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeCheckboxButton(_ title: String) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func syncMiniLineControls() {
        let topSources = Set(currentMiniTopLine.sources.map(\.rawValue))
        for (key, checkbox) in topSourceCheckboxes {
            checkbox.state = topSources.contains(key) ? .on : .off
        }
        topStyleRadios[currentMiniTopLine.style.rawValue]?.state = .on
        topStylePopup.selectItem(at: Self.allStyles.firstIndex(where: { $0.key == currentMiniTopLine.style }) ?? 3)

        let bottomSources = Set(currentMiniBottomLine.sources.map(\.rawValue))
        for (key, checkbox) in bottomSourceCheckboxes {
            checkbox.state = bottomSources.contains(key) ? .on : .off
        }
        bottomStyleRadios[currentMiniBottomLine.style.rawValue]?.state = .on
        bottomStylePopup.selectItem(at: Self.allStyles.firstIndex(where: { $0.key == currentMiniBottomLine.style }) ?? 1)
    }

    private func loadCurrentSettings() {
        switch currentDisplayMode {
        case "compact": compactRadio.state = .on
        case "mini":    miniRadio.state = .on
        default:        fullRadio.state = .on
        }

        syncMiniLineControls()
        updateMiniOptionsVisibility()
        refreshPreview()
    }

    // MARK: - Actions

    @objc private func displayModeChanged(_ sender: NSButton) {
        if fullRadio.state == .on {
            currentDisplayMode = "full"
        } else if compactRadio.state == .on {
            currentDisplayMode = "compact"
        } else {
            currentDisplayMode = "mini"
        }
        updateMiniOptionsVisibility()
        refreshPreview()
        onSettingsChanged?()
    }

    @objc private func topSourceChanged(_ sender: NSButton) {
        guard let key = topSourceCheckboxes.first(where: { $0.value === sender })?.key,
              let source = MiniLineSource(rawValue: key) else { return }
        var sources = currentMiniTopLine.sources
        if sender.state == .on {
            if !sources.contains(source) { sources.append(source) }
        } else {
            sources.removeAll { $0 == source }
        }
        if sources.isEmpty {
            sources = [source]
        }
        currentMiniTopLine = (sources, currentMiniTopLine.style)
        syncMiniLineControls()
        refreshPreview()
        onSettingsChanged?()
    }

    @objc private func topStyleChanged(_ sender: NSButton) {
        guard let key = topStyleRadios.first(where: { $0.value === sender })?.key,
              let style = MiniLineStyle(rawValue: key) else { return }
        currentMiniTopLine = (currentMiniTopLine.sources, style)
        refreshPreview()
        onSettingsChanged?()
    }

    @objc private func bottomSourceChanged(_ sender: NSButton) {
        guard let key = bottomSourceCheckboxes.first(where: { $0.value === sender })?.key,
              let source = MiniLineSource(rawValue: key) else { return }
        var sources = currentMiniBottomLine.sources
        if sender.state == .on {
            if !sources.contains(source) { sources.append(source) }
        } else {
            sources.removeAll { $0 == source }
        }
        if sources.isEmpty {
            sources = [source]
        }
        currentMiniBottomLine = (sources, currentMiniBottomLine.style)
        syncMiniLineControls()
        refreshPreview()
        onSettingsChanged?()
    }

    @objc private func bottomStyleChanged(_ sender: NSButton) {
        guard let key = bottomStyleRadios.first(where: { $0.value === sender })?.key,
              let style = MiniLineStyle(rawValue: key) else { return }
        currentMiniBottomLine = (currentMiniBottomLine.sources, style)
        refreshPreview()
        onSettingsChanged?()
    }

    @objc private func swapLines(_ sender: Any) {
        let top    = currentMiniTopLine
        let bottom = currentMiniBottomLine
        currentMiniTopLine    = bottom
        currentMiniBottomLine = top
        syncMiniLineControls()
        refreshPreview()
        onSettingsChanged?()
    }

    private func updateMiniOptionsVisibility() {
        modeControl.selectedSegment = fullRadio.state == .on ? 0 : compactRadio.state == .on ? 1 : 2
        let showMini = miniRadio.state == .on
        miniOptionsStack.isHidden = !showMini
        refreshPreview()
        guard let window else { return }
        var frame = window.frame
        let height: CGFloat = showMini ? 400 : 235
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

    }
}

@MainActor
class PowerConsumptionWindowController: NSWindowController, NSWindowDelegate {
    private let rows: [(key: String, zh: String, en: String)] = [
        ("cpu", "CPU", "CPU"),
        ("gpu", "GPU", "GPU"),
        ("ane", "神经引擎", "Neural Engine"),
        ("ram", "内存", "Memory"),
        ("pci", "PCI", "PCI"),
        ("total", "总计（DC In）", "Total (DC In)"),
    ]
    private let samplingStatus = NSTextField(wrappingLabelWithString: "")
    private var valueLabels: [String: NSTextField] = [:]
    private var updateTimer: DispatchSourceTimer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = appL10n("电力消耗", "Power Consumption")
        window.center()

        super.init(window: window)
        window.delegate = self
        applyWindowMaterialStyle(window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        updateTimer?.cancel()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startTimerIfNeeded()
    }

    func refreshSnapshot() {
        let snapshot = PowerTelemetryReader.shared.snapshot
        if !snapshot.isSupported {
            samplingStatus.stringValue = appL10n("当前机型暂不支持功率读取。", "Power readings are not supported on this Mac.")
            for key in ["cpu", "gpu", "ane", "ram", "pci", "total"] {
                valueLabels[key]?.stringValue = "--"
            }
            return
        }

        samplingStatus.stringValue = snapshot.hasAnyReading
            ? appL10n("上次读取：\(Int(Date().timeIntervalSince(snapshot.lastUpdatedAt ?? Date())))秒前", "Last reading: \(Int(Date().timeIntervalSince(snapshot.lastUpdatedAt ?? Date())))s ago")
            : appL10n("正在读取首个样本…", "Reading the first sample…")
        updateValueLabel(for: "cpu", value: snapshot.cpuWatts, hasReading: snapshot.hasAnyReading)
        updateValueLabel(for: "gpu", value: snapshot.gpuWatts, hasReading: snapshot.hasAnyReading)
        updateValueLabel(for: "ane", value: snapshot.aneWatts, hasReading: snapshot.hasAnyReading)
        updateValueLabel(for: "ram", value: snapshot.ramWatts, hasReading: snapshot.hasAnyReading)
        updateValueLabel(for: "pci", value: snapshot.pciWatts, hasReading: snapshot.hasAnyReading)
        updateValueLabel(for: "total", value: snapshot.displayTotalWatts, hasReading: snapshot.hasAnyReading)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(root)
        root.addArrangedSubview(NativeInterface.label(appL10n("总计（DC In）", "Total (DC In)"), size: 12, weight: .medium, color: .secondaryLabelColor))
        let total = NativeInterface.label("--", size: 30, weight: .medium)
        root.addArrangedSubview(total); valueLabels["total"] = total
        let separator = NSBox(); separator.boxType = .separator; root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let grid = NSGridView(); grid.rowSpacing = 10; grid.columnSpacing = 24; root.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        for row in rows where row.key != "total" {
            let title = NativeInterface.label(appL10n(row.zh, row.en), size: 12)
            let value = NativeInterface.label("--", size: 12)
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); value.alignment = .right
            valueLabels[row.key] = value; grid.addRow(with: [title, value])
        }
        samplingStatus.font = .systemFont(ofSize: 11); samplingStatus.textColor = .secondaryLabelColor
        root.addArrangedSubview(samplingStatus)
        let footnote = NativeInterface.label(appL10n("基于 Apple Silicon Energy Model 的估算值。", "Estimate from Apple Silicon Energy Model."), size: 10, color: .secondaryLabelColor, wrapping: true)
        root.addArrangedSubview(footnote); footnote.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22), root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24), root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24), root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])
    }

    func windowWillClose(_ notification: Notification) { updateTimer?.cancel(); updateTimer = nil }

    private func startTimerIfNeeded() {
        guard updateTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.refreshSnapshot()
        }
        timer.resume()
        updateTimer = timer
    }

    private func updateValueLabel(for key: String, value: Double, hasReading: Bool) {
        guard let label = valueLabels[key] else { return }
        if key == "total" && hasReading { label.attributedStringValue = NativeInterface.measurement(String(format: "%.2f", value), unit: "W") }
        else { label.stringValue = hasReading ? String(format: "%.2f W", value) : "--" }
    }
}

// 转速设置窗口控制器
@MainActor
class SpeedSettingWindowController: NSWindowController {
    private var completionButton: NSButton?
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
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
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .centerX; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(root)
        let title = NativeInterface.label(appL10n("目标转速", "Target speed"), size: 15, weight: .medium)
        root.addArrangedSubview(title); title.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let value = NSTextField(labelWithString: ""); value.attributedStringValue = NativeInterface.rpm(currentRPM)
        root.addArrangedSubview(value); rpmLabel = value
        let explanation = NativeInterface.label(appL10n("实际转速接近目标值即可，不一定完全相等。", "Actual RPM may stay near the target without matching it exactly."), size: 12, color: .secondaryLabelColor, wrapping: true)
        explanation.alignment = .center
        let help = NSButton(title: "?", target: self, action: #selector(showRPMHelp)); help.bezelStyle = .helpButton
        let hintRow = NSStackView(views: [explanation, help]); hintRow.spacing = 6; root.addArrangedSubview(hintRow)
        hintRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let slider = NSSlider(value: Double(currentRPM), minValue: 0, maxValue: Double(maxRPM), target: self, action: #selector(sliderChanged))
        root.addArrangedSubview(slider); slider.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true; rpmSlider = slider
        let range = NSStackView(views: [NativeInterface.label("0 RPM", size: 10, color: .secondaryLabelColor), NSView(), NativeInterface.label("\(maxRPM) RPM", size: 10, color: .secondaryLabelColor)])
        root.addArrangedSubview(range); range.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        root.setCustomSpacing(3, after: slider)
        let control = NSSegmentedControl(labels: [appL10n("连续", "Continuous"), appL10n("档位", "Stepped")], trackingMode: .selectOne, target: self, action: #selector(controlModeChanged))
        control.controlSize = .small; control.font = .systemFont(ofSize: 12)
        let modeRow = NSStackView(views: [NativeInterface.label(appL10n("调节方式", "Adjustment"), size: 12, color: .secondaryLabelColor), NSView(), control])
        root.addArrangedSubview(modeRow); modeRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true; controlModeSegmentedControl = control
        let step = NativeInterface.label("", size: 11, color: .secondaryLabelColor); root.addArrangedSubview(step); stepHintLabel = step
        let status = NativeInterface.label(appL10n("✓ 已应用", "✓ Applied"), size: 11, color: .systemGreen, wrapping: true)
        status.alphaValue = 0; applyStatusLabel = status
        let cancelButton = NativeInterface.button(appL10n("取消", "Cancel"), target: self, action: #selector(cancel)); cancelButton.keyEquivalent = "\u{1b}"
        completionButton = cancelButton
        let apply = NativeInterface.button(appL10n("应用", "Apply"), target: self, action: #selector(applySpeed)); apply.keyEquivalent = "\r"
        let footer = NSStackView(views: [status, NSView(), cancelButton, apply]); footer.spacing = 8
        root.addArrangedSubview(footer); footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22), root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24), root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24), root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])
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
        window?.setContentSize(NSSize(width: 400, height: isStepped ? 310 : 280))
    }

    private func updateSliderDisplay() {
        let effectiveRPM = (controlMode == .stepped) ? snappedRPM(for: currentRPM) : boundedRPM(currentRPM)
        currentRPM = effectiveRPM
        rpmSlider?.doubleValue = Double(effectiveRPM)
        rpmLabel?.attributedStringValue = NativeInterface.rpm(effectiveRPM)
        updateModeUI()
    }

    @objc func sliderChanged() {
        completionButton?.title = appL10n("取消", "Cancel")
        guard let slider = rpmSlider else { return }
        let rpm = effectiveRPM(for: slider.doubleValue)
        currentRPM = rpm
        slider.doubleValue = Double(rpm)
        rpmLabel?.attributedStringValue = NativeInterface.rpm(rpm)
    }

    @objc private func controlModeChanged() {
        completionButton?.title = appL10n("取消", "Cancel")
        controlMode = (controlModeSegmentedControl?.selectedSegment == 1) ? .stepped : .continuous
        updateSliderDisplay()
    }

    @objc private func showRPMHelp() {
        let alert = NSAlert()
        alert.messageText = appL10n("为什么实际转速不完全等于设定值？", "Why doesn't actual RPM exactly match the target?")
        alert.informativeText = appL10n(
            """
            iFanControl 会向系统发送目标转速，但最终转速仍由 SMC、风扇硬件和系统保护策略共同决定。

            因此实际 RPM 可能会有轻微上下浮动。例如目标是 3000 RPM，实际稳定在 2960 RPM 附近，通常就说明控制已经生效。

            这是正常现象，不代表设置失败。
            """,
            """
            iFanControl sends a target RPM to the system, but the final speed is still affected by the SMC, fan hardware, and system protection behavior.

            Actual RPM may fluctuate slightly. For example, if the target is 3000 RPM and the fan stabilizes near 2960 RPM, control is usually working as expected.

            This is normal and does not mean the setting failed.
            """
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: appL10n("明白了", "Got it"))
        alert.runModal()
    }

    @objc func applySpeed() {
        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.manualRPM = currentRPM
        newConfig.manualRPMControlMode = controlMode.rawValue
        newConfig.manualRPMStep = stepRPM
        guard ConfigManager.shared.saveConfig(newConfig) else {
            applyStatusResetWorkItem?.cancel()
            applyStatusLabel?.stringValue = appL10n("设置未保存，请重试。", "Settings were not saved. Please try again.")
            applyStatusLabel?.textColor = .systemRed
            applyStatusLabel?.alphaValue = 1
            return
        }
        
        MenuBarManager.shared.setFanCurve(newConfig.curve)
        showApplyFeedback()
    }
    
    @objc func cancel() {
        window?.close()
    }

    private func showApplyFeedback() {
        applyStatusResetWorkItem?.cancel()
        guard let label = applyStatusLabel else { return }

        completionButton?.title = appL10n("完成", "Done")
        label.stringValue = appL10n("✓ 已应用", "✓ Applied")
        label.textColor = .systemGreen
        label.alphaValue = 1.0

        let workItem = DispatchWorkItem { [weak label] in
            guard let label else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { label.alphaValue = 0 }
                else { label.animator().alphaValue = 0 }
            }
        }
        applyStatusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
}

@MainActor
class FeedbackWindowController: NSWindowController {
    private var submittedSuccessfully = false
    private var closeAfterSuccess: DispatchWorkItem?
    private var contentTextView: NSTextView?
    private var emailField: NSTextField?
    private var sendButton: NSButton?
    private var statusLabel: NSTextField?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = appL10n("告诉开发者", "Talk to Dev")
        window.center()

        super.init(window: window)

        applyWindowMaterialStyle(window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        if submittedSuccessfully {
            closeAfterSuccess?.cancel()
            closeAfterSuccess = nil
            contentTextView?.string = ""
            sendButton?.isEnabled = true
            sendButton?.title = appL10n("发送", "Send")
            statusLabel?.alphaValue = 0
            submittedSuccessfully = false
        }
        super.showWindow(sender)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 标题提示
        let hintLabel = NSTextField(labelWithString: appL10n("有什么想告诉我的？随便说两句就行", "Got something to tell me? Just say anything."))
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hintLabel)

        // 多行文本输入
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 14)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 340, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        self.contentTextView = textView

        // 邮箱
        let emailLabel = NSTextField(labelWithString: appL10n("邮箱（选填，方便我回复你）", "Email (optional, so I can reply)"))
        emailLabel.textColor = .secondaryLabelColor
        emailLabel.font = .systemFont(ofSize: 12)
        emailLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emailLabel)

        let emailField = NSTextField()
        emailField.placeholderString = appL10n("your@email.com", "your@email.com")
        emailField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emailField)
        self.emailField = emailField

        // 发送按钮
        let sendButton = NSButton(title: appL10n("发送", "Send"), target: self, action: #selector(sendFeedback))
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = [.command]
        sendButton.toolTip = appL10n("发送 · ⌘↩", "Send · ⌘↩")
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sendButton)
        self.sendButton = sendButton

        let cancelButton = NativeInterface.button(appL10n("关闭", "Close"), target: self, action: #selector(closeFeedbackWindow))
        cancelButton.keyEquivalent = "\u{1b}"; cancelButton.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(cancelButton)
        let shortcut = NativeInterface.label("⌘↩", size: 11, color: .secondaryLabelColor)
        shortcut.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(shortcut)

        // 状态标签
        let statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.textColor = .systemGreen
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.alignment = .left
        statusLabel.alphaValue = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)
        self.statusLabel = statusLabel

        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 120),

            emailLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            emailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            emailField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 4),
            emailField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            emailField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            emailField.heightAnchor.constraint(equalToConstant: 24),

            statusLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

            sendButton.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 16),
            sendButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            shortcut.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            shortcut.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            sendButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @objc private func closeFeedbackWindow() { window?.close() }

    @objc private func sendFeedback() {
        let content = contentTextView?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            showStatus(appL10n("请输入内容", "Please enter something"), isError: true)
            return
        }

        guard FeedbackService.shared.canSend() else {
            showStatus(appL10n("每小时最多发送5次，请稍后再试。", "You can send up to 5 messages per hour. Please try again later."), isError: true)
            return
        }

        let email = emailField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        sendButton?.isEnabled = false
        sendButton?.title = appL10n("发送中...", "Sending...")
        statusLabel?.alphaValue = 0

        Task { [self] in
            let success = await FeedbackService.shared.sendFeedback(content: content, email: email)
            if success {
                submittedSuccessfully = true
                sendButton?.title = appL10n("已送达", "Delivered")
                showStatus(email.isEmpty ? appL10n("✓ 收到啦，感谢你的反馈！", "✓ Received. Thanks for your feedback!") : appL10n("✓ 收到啦，我会通过邮箱回复你。", "✓ Received. I'll reply by email."), isError: false)
                let close = DispatchWorkItem { [weak self] in
                    self?.window?.close()
                }
                closeAfterSuccess = close
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: close)
            } else {
                showStatus(appL10n("发送失败，请稍后再试", "Failed, please try later"), isError: true)
                sendButton?.isEnabled = true
                sendButton?.title = appL10n("发送", "Send")
            }
        }
    }

    private func showStatus(_ text: String, isError: Bool) {
        statusLabel?.stringValue = text
        statusLabel?.textColor = isError ? .systemRed : .systemGreen
        statusLabel?.alphaValue = 1
    }
}

final class FeedbackService: @unchecked Sendable {
    static let shared = FeedbackService()

    private let endpointURL = URL(string: "https://ifan-59w.pages.dev/api/feedback")!
    private let timestampsKey = "ifancontrol.feedback.send_timestamps"
    private let maxPerHour = 5

    /// 检查是否超过频率限制，返回 true 表示可以发送
    func canSend() -> Bool {
        let now = Date().timeIntervalSince1970
        let cutoff = now - 3600
        var timestamps = UserDefaults.standard.array(forKey: timestampsKey) as? [TimeInterval] ?? []
        timestamps = timestamps.filter { $0 > cutoff }
        return timestamps.count < maxPerHour
    }

    /// 记录一次发送时间戳
    private func recordSend() {
        let now = Date().timeIntervalSince1970
        let cutoff = now - 3600
        var timestamps = UserDefaults.standard.array(forKey: timestampsKey) as? [TimeInterval] ?? []
        timestamps = timestamps.filter { $0 > cutoff }
        timestamps.append(now)
        UserDefaults.standard.set(timestamps, forKey: timestampsKey)
    }

    func sendFeedback(content: String, email: String) async -> Bool {
        guard canSend() else { return false }

        let installID = PrivacyStatsService.shared.currentInstallID()
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

        let payload: [String: Any] = [
            "install_id": installID,
            "content": content,
            "email": email,
            "version": shortVersion,
            "build": buildVersion,
        ]

        do {
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 8

            let body = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.upload(for: request, from: body)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            recordSend()
            return true
        } catch {
            return false
        }
    }
}

@MainActor
class SafetyFloorWindowController: NSWindowController {
    private var completionButton: NSButton?
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 270),
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
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .centerX; root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(root)
        let title = NativeInterface.label(appL10n("最低安全转速", "Minimum safety speed"), size: 15, weight: .medium)
        root.addArrangedSubview(title); title.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let value = NSTextField(labelWithString: ""); value.attributedStringValue = NativeInterface.rpm(currentRPM)
        root.addArrangedSubview(value); rpmLabel = value
        let hint = NativeInterface.label(appL10n("在临界温度（\(Int(FanManager.shared.criticalTemperatureForDisplay))℃）下托底，保留曲线要求的更高转速。", "A floor at \(Int(FanManager.shared.criticalTemperatureForDisplay))°C. Higher speeds requested by your curve are retained."), size: 12, color: .secondaryLabelColor, wrapping: true)
        hint.alignment = .center; root.addArrangedSubview(hint); hint.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let slider = NSSlider(value: Double(currentRPM), minValue: Double(minRPM), maxValue: Double(maxRPM), target: self, action: #selector(sliderChanged))
        root.addArrangedSubview(slider); slider.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true; rpmSlider = slider
        let range = NSStackView(views: [NativeInterface.label("\(minRPM) RPM", size: 10, color: .secondaryLabelColor), NSView(), NativeInterface.label("\(maxRPM) RPM", size: 10, color: .secondaryLabelColor)])
        root.addArrangedSubview(range); range.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true; root.setCustomSpacing(3, after: slider)
        let status = NativeInterface.label(appL10n("✓ 已应用", "✓ Applied"), size: 11, color: .systemGreen, wrapping: true)
        status.alphaValue = 0; applyStatusLabel = status
        let cancelButton = NativeInterface.button(appL10n("取消", "Cancel"), target: self, action: #selector(cancel)); cancelButton.keyEquivalent = "\u{1b}"; completionButton = cancelButton
        let apply = NativeInterface.button(appL10n("应用", "Apply"), target: self, action: #selector(applyValue)); apply.keyEquivalent = "\r"
        let footer = NSStackView(views: [status, NSView(), cancelButton, apply]); footer.spacing = 8
        root.addArrangedSubview(footer); footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22), root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24), root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24), root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])
    }

    @objc private func sliderChanged() {
        completionButton?.title = appL10n("取消", "Cancel")
        guard let slider = rpmSlider else { return }
        let rpm = Int(slider.doubleValue.rounded())
        rpmLabel?.attributedStringValue = NativeInterface.rpm(rpm)
    }

    @objc private func applyValue() {
        guard let slider = rpmSlider else { return }
        let rpm = min(max(Int(slider.doubleValue.rounded()), minRPM), maxRPM)

        let config = ConfigManager.shared.loadConfig()
        var newConfig = config
        newConfig.safetyFloorRPM = rpm
        guard ConfigManager.shared.saveConfig(newConfig) else {
            applyStatusResetWorkItem?.cancel()
            applyStatusLabel?.stringValue = appL10n("设置未保存，请重试。", "Settings were not saved. Please try again.")
            applyStatusLabel?.textColor = .systemRed
            applyStatusLabel?.alphaValue = 1
            return
        }
        showApplyFeedback()
    }

    @objc private func cancel() {
        window?.close()
    }

    private func showApplyFeedback() {
        applyStatusResetWorkItem?.cancel()
        guard let label = applyStatusLabel else { return }

        completionButton?.title = appL10n("完成", "Done")
        label.stringValue = appL10n("✓ 已应用", "✓ Applied")
        label.textColor = .systemGreen
        label.alphaValue = 1.0

        let workItem = DispatchWorkItem { [weak label] in
            guard let label else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { label.alphaValue = 0 }
                else { label.animator().alphaValue = 0 }
            }
        }
        applyStatusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
}

@MainActor
final class AdaptiveCardView: NSView {
    private let backgroundAlpha: CGFloat

    init(cornerRadius: CGFloat = 16, backgroundAlpha: CGFloat = 0.84) {
        self.backgroundAlpha = backgroundAlpha
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
        refreshThemeColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshThemeColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshThemeColors()
    }

    func refreshThemeColors() {
        guard let layer else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let borderColor = isDark
            ? NSColor(calibratedWhite: 0.32, alpha: 1)
            : NSColor(calibratedWhite: 0.78, alpha: 1)
        let backgroundColor = isDark
            ? NSColor(calibratedWhite: 0.12, alpha: backgroundAlpha)
            : NSColor(calibratedWhite: 1.0, alpha: backgroundAlpha)
        layer.borderColor = cgColor(for: borderColor)
        layer.backgroundColor = cgColor(for: backgroundColor)
        needsDisplay = true
    }

    private func cgColor(for color: NSColor) -> CGColor {
        var resolvedColor = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
        return resolvedColor
    }
}

@MainActor
final class AdaptiveQRCodeImageView: NSImageView {
    private static let qrContext = CIContext(options: nil)
    private var payload: String = ""
    private let targetSize: CGFloat

    init(targetSize: CGFloat) {
        self.targetSize = targetSize
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        refreshThemeColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPayload(_ payload: String) {
        self.payload = payload
        refreshThemeColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshThemeColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshThemeColors()
    }

    func refreshThemeColors() {
        layer?.backgroundColor = cgColor(for: backgroundColor)
        image = generateQRCodeImage()
        needsDisplay = true
    }

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var foregroundColor: NSColor {
        isDarkMode ? .white : .black
    }

    private var backgroundColor: NSColor {
        isDarkMode ? NSColor(calibratedWhite: 0.08, alpha: 1) : .white
    }

    private func cgColor(for color: NSColor) -> CGColor {
        var resolvedColor = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
        return resolvedColor
    }

    private func generateQRCodeImage() -> NSImage? {
        guard let data = payload.data(using: .utf8),
              let generator = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        generator.setValue(data, forKey: "inputMessage")
        generator.setValue("M", forKey: "inputCorrectionLevel")
        guard var outputImage = generator.outputImage else { return nil }

        if let colorFilter = CIFilter(name: "CIFalseColor") {
            colorFilter.setValue(outputImage, forKey: kCIInputImageKey)
            colorFilter.setValue(CIColor(color: foregroundColor), forKey: "inputColor0")
            colorFilter.setValue(CIColor(color: backgroundColor), forKey: "inputColor1")
            outputImage = colorFilter.outputImage ?? outputImage
        }

        let extent = outputImage.extent.integral
        guard extent.width > 0 else { return nil }
        let scale = max(1, floor(targetSize / extent.width))
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = Self.qrContext.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
    }
}

@MainActor
class HelpWindowController: NSWindowController {
    private enum Section: Int, CaseIterable {
        case overview
        case diagnostics
        case faq
        case donation
        case developer

        func title() -> String {
            switch self {
                case .overview: return appL10n("简介", "Overview")
                case .diagnostics: return appL10n("诊断与支持", "Diagnostics & Support")
                case .faq: return appL10n("常见问题", "FAQ")
                case .donation: return appL10n("支持作者", "Support the Author")
                case .developer: return appL10n("开发者", "Developer")
            }
        }
    }

    private var versionLabel: NSTextField?
    private var automaticUpdateCheckbox: NSButton?
    private var anonymousStatsCheckbox: NSButton?
    private var currentSection: Section = .overview
    private var sidebarButtons: [Section: NSButton] = [:]
    private var sidebarStack: NSStackView?
    private var betaUpdateCheckbox: NSButton?
    private var updateRouteLabel: NSTextField?
    private var developerUnlockCounter = DeveloperModeUnlockCounter()
    private var appHeaderView: NSView?
    private var headerSeparatorView: NSView?
    private var sectionContainerView: NSView?
    private var sectionTitleLabel: NSTextField?
    private var sectionViews: [Section: NSView] = [:]
    private var donationMethodControl: NSSegmentedControl?
    private var qrImageView: AdaptiveQRCodeImageView?
    private var qrCaptionLabel: NSTextField?
    private var adaptiveCards: [AdaptiveCardView] = []
    private let sidebarWidth: CGFloat = 164
    private let contentWidth: CGFloat = 488

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(helpWindowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged(_:)),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        return label
    }

    private func makeCardView() -> NSView {
        let card = AdaptiveCardView()
        adaptiveCards.append(card)
        return card
    }

    private func makeBodyLabel(_ text: String) -> NSTextField {
        NativeInterface.label(text, size: 12, color: .secondaryLabelColor, wrapping: true)
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
        stack.spacing = 14
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
        let title: String
        switch section {
            case .diagnostics: title = appL10n("诊断与支持", "Support")
            case .donation: title = appL10n("支持作者", "Support Author")
            default: title = section.title()
        }
        let symbols = ["info.circle", "wrench.and.screwdriver", "questionmark.circle", "heart", "hammer"]
        let button = NSButton(title: (section == .diagnostics ? " " : "  ") + title, target: self, action: #selector(sidebarButtonClicked(_:)))
        button.image = NSImage(systemSymbolName: symbols[section.rawValue], accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        button.image?.size = NSSize(width: 15, height: 15)
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageLeading
        button.bezelStyle = .regularSquare; button.isBordered = false
        button.setButtonType(.momentaryChange); button.font = .systemFont(ofSize: 14)
        button.alignment = .left; button.contentTintColor = .secondaryLabelColor
        button.wantsLayer = true; button.layer?.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(equalToConstant: sidebarWidth - 24).isActive = true
        button.identifier = NSUserInterfaceItemIdentifier("sidebar-\(section.rawValue)")
        button.setAccessibilityLabel(section.title())
        return button
    }

    private func updateSidebarSelection() {
        for (section, button) in sidebarButtons {
            let isSelected = section == currentSection
            button.contentTintColor = .labelColor
            button.font = .systemFont(ofSize: 14, weight: isSelected ? .medium : .regular)
            button.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
                : NSColor.clear.cgColor
        }
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar; sidebar.blendingMode = .withinWindow; sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(sidebar)
        let navigation = NSStackView(); navigation.orientation = .vertical; navigation.alignment = .leading; navigation.spacing = 4
        navigation.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(navigation)
        let caption = NativeInterface.label("iFanControl", size: 12, weight: .medium, color: .secondaryLabelColor)
        navigation.addArrangedSubview(caption)
        navigation.setCustomSpacing(12, after: caption)
        for section in Section.allCases where section != .developer || UpdatePreferences.shared.developerModeEnabled {
            let button = makeSidebarButton(for: section); navigation.addArrangedSubview(button); sidebarButtons[section] = button
        }
        sidebarStack = navigation
        let divider = NSBox(); divider.boxType = .separator; divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(content)
        let title = makeSectionTitle(""); content.addArrangedSubview(title); sectionTitleLabel = title
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        content.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        let sections = NSStackView(); sections.orientation = .vertical; sections.alignment = .centerX
        sections.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = sections
        sections.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        sections.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
        sectionContainerView = sections
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), sidebar.topAnchor.constraint(equalTo: contentView.topAnchor), sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),
            navigation.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24), navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), divider.topAnchor.constraint(equalTo: sidebar.topAnchor), divider.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor), divider.widthAnchor.constraint(equalToConstant: 1),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 24), content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24), content.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24), content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
        buildSectionViews(); refreshDonationPreview(); updateSidebarSelection()
    }

    private func buildSectionViews() {
        sectionViews = [.overview: makeOverviewSection(), .diagnostics: makeDiagnosticsSection(), .faq: makeFAQSection(), .donation: makeDonationSection()]
        for view in sectionViews.values { view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true }
        addDeveloperSectionIfNeeded()
    }

    private func makeOverviewSection() -> NSView {
        let (view, stack) = makeSectionRoot(horizontalCentered: true, verticalCentered: true)

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 14
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        iconView.identifier = NSUserInterfaceItemIdentifier("developer-unlock-icon")
        let unlockClick = NSClickGestureRecognizer(target: self, action: #selector(overviewIconClicked(_:)))
        iconView.addGestureRecognizer(unlockClick)
        stack.addArrangedSubview(iconView)

        let appName = NSTextField(labelWithString: "iFanControl")
        appName.font = .systemFont(ofSize: 26, weight: .semibold)
        appName.alignment = .center
        stack.addArrangedSubview(appName)

        let version = NSTextField(labelWithString: appL10n("版本 \(UpdateService.shared.currentVersionDisplay)", "Version \(UpdateService.shared.currentVersionDisplay)"))
        version.font = .systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        stack.addArrangedSubview(version)

        let intro = makeBodyLabel(
            appL10n(
                "面向 Apple Silicon 的温度监测与风扇控制工具。",
                "Temperature monitoring and fan control for Apple Silicon."
            )
        )
        intro.font = .systemFont(ofSize: 13)
        intro.alignment = .center
        intro.preferredMaxLayoutWidth = 360
        intro.widthAnchor.constraint(equalToConstant: 360).isActive = true
        stack.addArrangedSubview(intro)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        let updateButton = NSButton(title: appL10n("检查更新", "Check Updates"), target: self, action: #selector(checkUpdates))
        updateButton.bezelStyle = .rounded
        let githubButton = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        let websiteButton = NSButton(title: appL10n("访问官网", "Visit Website"), target: self, action: #selector(openWebsite))
        websiteButton.bezelStyle = .rounded
        websiteButton.identifier = NSUserInterfaceItemIdentifier("visit-website")
        websiteButton.toolTip = "https://ifancontrol.puremilkchun.top"
        // Restart is available with the diagnostic quick checks.
        buttonRow.addArrangedSubview(updateButton)
        buttonRow.addArrangedSubview(websiteButton)
        buttonRow.addArrangedSubview(githubButton)
        stack.addArrangedSubview(buttonRow)

        let autoCheck = NSButton(
            checkboxWithTitle: appL10n("自动检查更新", "Check updates automatically"),
            target: self,
            action: #selector(toggleAutomaticChecks(_:))
        )
        autoCheck.state = UpdateService.shared.automaticChecksEnabled ? .on : .off
        automaticUpdateCheckbox = autoCheck
        autoCheck.controlSize = .small; autoCheck.font = .systemFont(ofSize: 12)
        let preferences = NSStackView(); preferences.orientation = .vertical; preferences.alignment = .leading; preferences.spacing = 10
        preferences.addArrangedSubview(autoCheck)

        let statsCheck = NSButton(
            checkboxWithTitle: appL10n("匿名统计用户量", "Anonymous user-count stats"),
            target: self,
            action: #selector(toggleAnonymousStats(_:))
        )
        statsCheck.state = PrivacyStatsService.shared.anonymousStatsEnabled ? .on : .off
        anonymousStatsCheckbox = statsCheck

        let statsHelpButton = NSButton(title: "?", target: self, action: #selector(showAnonymousStatsHelp))
        statsHelpButton.bezelStyle = .helpButton
        statsHelpButton.font = .systemFont(ofSize: 11, weight: .semibold)
        statsHelpButton.setContentHuggingPriority(.required, for: .horizontal)

        let statsRow = NSStackView()
        statsRow.orientation = .horizontal
        statsRow.alignment = .centerY
        statsRow.spacing = 6
        statsRow.addArrangedSubview(statsCheck)
        statsRow.addArrangedSubview(statsHelpButton)
        statsRow.setHuggingPriority(.required, for: .horizontal)
        statsCheck.controlSize = .small; statsCheck.font = .systemFont(ofSize: 12)
        preferences.addArrangedSubview(statsRow)

        let statsHint = makeBodyLabel(
            appL10n(
                "匿名统计使用人数，不上传姓名、邮箱、序列号或设备名称。",
                "Counts usage anonymously. No name, email, serial number or device name is uploaded."
            )
        )
        statsHint.font = .systemFont(ofSize: 11)
        statsHint.alignment = .left
        statsHint.preferredMaxLayoutWidth = 360
        statsHint.widthAnchor.constraint(equalToConstant: 360).isActive = true
        preferences.addArrangedSubview(statsHint)
        stack.addArrangedSubview(preferences)

        return view
    }

    private func addDeveloperSectionIfNeeded() {
        guard UpdatePreferences.shared.developerModeEnabled,
              sectionViews[.developer] == nil, sectionContainerView != nil else { return }
        if sidebarButtons[.developer] == nil {
            let button = makeSidebarButton(for: .developer)
            sidebarButtons[.developer] = button
            sidebarStack?.addArrangedSubview(button)
        }

        let (view, stack) = makeSectionRoot(horizontalCentered: true, verticalCentered: true)
        stack.alignment = .centerX
        let betaCheck = NSButton(
            checkboxWithTitle: appL10n("接收 Beta 更新", "Receive Beta Updates"),
            target: self, action: #selector(toggleBetaUpdates(_:))
        )
        betaCheck.identifier = NSUserInterfaceItemIdentifier("beta-update-checkbox")
        stack.addArrangedSubview(betaCheck)
        betaUpdateCheckbox = betaCheck

        let routeLabel = NSTextField(labelWithString: "")
        routeLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(routeLabel)
        updateRouteLabel = routeLabel

        let hint = makeBodyLabel(appL10n(
            "启用后，自动与手动检查都会使用 Beta 通道。\n切回正式通道只改变后续更新路线，当前安装版本不会改变。",
            "When enabled, automatic and manual checks use the Beta channel.\nSwitching to Stable changes future updates; your installed version stays the same."
        ))
        hint.alignment = .center
        hint.preferredMaxLayoutWidth = 360
        hint.widthAnchor.constraint(equalToConstant: 360).isActive = true
        stack.addArrangedSubview(hint)

        let updateButton = NSButton(title: appL10n("检查更新", "Check Updates"), target: self, action: #selector(checkUpdates))
        updateButton.bezelStyle = .rounded
        stack.addArrangedSubview(updateButton)

        let exitButton = NSButton(title: appL10n("退出开发者模式", "Exit Developer Mode"), target: self, action: #selector(exitDeveloperMode))
        exitButton.bezelStyle = .rounded
        exitButton.identifier = NSUserInterfaceItemIdentifier("exit-developer-mode")
        stack.addArrangedSubview(exitButton)

        sectionViews[.developer] = view
        view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        refreshDeveloperSettings()
    }

    private func refreshDeveloperSettings() {
        let preferences = UpdatePreferences.shared
        betaUpdateCheckbox?.state = preferences.betaEnabled ? .on : .off
        updateRouteLabel?.stringValue = preferences.betaEnabled
            ? appL10n("当前更新通道：Beta", "Update Channel: Beta")
            : appL10n("当前更新通道：正式版", "Update Channel: Stable")
    }

    @objc private func overviewIconClicked(_ sender: NSClickGestureRecognizer) {
        guard !UpdatePreferences.shared.developerModeEnabled,
              developerUnlockCounter.registerClick() else { return }
        UpdatePreferences.shared.unlockDeveloperMode()
        addDeveloperSectionIfNeeded()
        select(section: .developer)
    }

    @objc private func helpWindowWillClose(_ notification: Notification) {
        developerUnlockCounter.reset()
    }

    @objc private func toggleBetaUpdates(_ sender: NSButton) {
        UpdatePreferences.shared.setBetaEnabled(sender.state == .on)
        refreshDeveloperSettings()
    }

    @objc private func exitDeveloperMode() {
        UpdatePreferences.shared.exitDeveloperMode()
        developerUnlockCounter.reset()
        select(section: .overview)
        sectionViews.removeValue(forKey: .developer)?.removeFromSuperview()
        if let button = sidebarButtons.removeValue(forKey: .developer) {
            sidebarStack?.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        betaUpdateCheckbox = nil
        updateRouteLabel = nil
    }

    private func makeDiagnosticsSection() -> NSView {
        let (view, stack) = makeSectionRoot()
        stack.alignment = .leading
        func section(_ title: String, _ detail: String) {
            let heading = NSTextField(labelWithString: title)
            heading.font = .systemFont(ofSize: 13, weight: .medium)
            stack.addArrangedSubview(heading)
            let body = makeBodyLabel(detail)
            body.preferredMaxLayoutWidth = contentWidth
            body.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            stack.addArrangedSubview(body)
        }
        func buttons(_ entries: [(String, Selector)]) {
            let row = NSStackView(); row.spacing = 10
            for (title, action) in entries {
                let button = NSButton(title: title, target: self, action: action)
                button.bezelStyle = .rounded; button.controlSize = .small; button.font = .systemFont(ofSize: 12); row.addArrangedSubview(button)
            }
            stack.addArrangedSubview(row)
        }
        section(appL10n("先做一次快速自检", "Start with a Quick Check"),
                appL10n("小异常可以先重启应用，或检查是否有可用更新。", "For a minor issue, try restarting the app or checking for an update."))
        buttons([(appL10n("重新启动", "Restart"), #selector(restartApp)), (appL10n("检查更新", "Check Updates"), #selector(checkUpdates))])
        let separator = NSBox(); separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true; stack.addArrangedSubview(separator)
        section(appL10n("联系支持", "Contact support"),
                appL10n("诊断包会保存在本机并在访达中显示。你可以检查内容，再自行附到支持邮件中。", "The diagnostic ZIP is saved locally and revealed in Finder. Review it, then attach it to your support email."))
        buttons([(appL10n("导出诊断包", "Export Diagnostics"), #selector(exportDiagnostics)), (appL10n("联系支持", "Contact Support"), #selector(contactSupport))])
        buttons([(appL10n("打开日志目录", "Open Log Folder"), #selector(openLogFolder))])
        let separator2 = NSBox(); separator2.boxType = .separator
        separator2.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true; stack.addArrangedSubview(separator2)
        section(appL10n("移除 iFanControl", "Remove iFanControl"),
                appL10n("完整卸载会移除应用、控制组件和本机设置。开始前会再次确认删除范围。", "A full uninstall removes the app, control components and local settings. You will confirm the scope before removal."))
        buttons([(appL10n("完整卸载…", "Full Uninstall…"), #selector(uninstallControlComponents))])
        return view
    }

    private func makeFAQSection() -> NSView {
        let (view, stack) = makeSectionRoot(horizontalCentered: true)


        let faqItems: [(String, String)] = [
            (
                appL10n("温度源是自动选择的吗？", "How is the temperature source selected?"),
                appL10n("默认自动选择最热传感器；也可以选择 CPU 或 GPU 传感器的平均温度，或在主界面手动固定某个温度源。", "By default the hottest sensor is selected automatically; you can also use a CPU or GPU sensor average or pin a specific source in the main panel.")
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
            qaStack.alignment = .leading
            qaStack.orientation = .vertical
            qaStack.spacing = 8
            qaStack.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(qaStack)

            let q = NSTextField(labelWithString: item.0)
            q.font = .systemFont(ofSize: 13, weight: .medium)
            q.maximumNumberOfLines = 0
            q.lineBreakMode = .byWordWrapping
            q.preferredMaxLayoutWidth = contentWidth - 32
            qaStack.addArrangedSubview(q)

            let a = makeBodyLabel(item.1)
            a.font = .systemFont(ofSize: 12)
            a.preferredMaxLayoutWidth = contentWidth - 32
            qaStack.addArrangedSubview(a)

            NSLayoutConstraint.activate([
                qaStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
                qaStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                qaStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                qaStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
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
        introTitle.font = .systemFont(ofSize: 18, weight: .semibold)
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

        let qrCard = AdaptiveCardView(cornerRadius: 18, backgroundAlpha: 0.9)
        adaptiveCards.append(qrCard)
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

        let qrImage = AdaptiveQRCodeImageView(targetSize: 168)
        qrImage.translatesAutoresizingMaskIntoConstraints = false
        qrImage.widthAnchor.constraint(equalToConstant: 168).isActive = true
        qrImage.heightAnchor.constraint(equalToConstant: 168).isActive = true

        let hint = NSTextField(wrappingLabelWithString: appL10n("感谢支持，帮助 iFanControl 持续改进。", "Thank you for helping iFanControl keep improving."))
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 13)
        hint.alignment = .center

        qrStack.addArrangedSubview(caption)
        qrStack.addArrangedSubview(qrImage)
        qrStack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: qrStack.widthAnchor).isActive = true

        self.donationMethodControl = methodControl
        self.qrImageView = qrImage
        self.qrCaptionLabel = caption
        return view
    }

    override func showWindow(_ sender: Any?) {
        window?.title = appL10n("关于/帮助", "About / Help")
        versionLabel?.stringValue = appL10n("版本 \(UpdateService.shared.currentVersionDisplay)", "Version \(UpdateService.shared.currentVersionDisplay)")
        automaticUpdateCheckbox?.state = UpdateService.shared.automaticChecksEnabled ? .on : .off
        anonymousStatsCheckbox?.state = PrivacyStatsService.shared.anonymousStatsEnabled ? .on : .off
        refreshDeveloperSettings()
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
        if let container = sectionContainerView as? NSStackView {
            for child in container.arrangedSubviews { container.removeArrangedSubview(child); child.removeFromSuperview() }
            if let page = sectionViews[section] { page.isHidden = false; container.addArrangedSubview(page) }
            container.layoutSubtreeIfNeeded()
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
        qrImageView?.setPayload(payload)
    }

    @objc private func systemAppearanceChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshAdaptiveThemeColors()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshAdaptiveThemeColors()
        }
    }

    private func refreshAdaptiveThemeColors() {
        for card in adaptiveCards {
            card.refreshThemeColors()
        }
        qrImageView?.refreshThemeColors()
        updateSidebarSelection()
        window?.contentView?.needsDisplay = true
    }

    @objc private func checkUpdates() {
        UpdateService.shared.checkForUpdates(triggeredByUser: true)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(UpdateService.shared.releasesURL)
    }

    @objc private func openWebsite() {
        guard let url = URL(string: "https://ifancontrol.puremilkchun.top") else { return }
        NSWorkspace.shared.open(url)
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

    @objc private func showAnonymousStatsHelp() {
        let alert = NSAlert()
        alert.messageText = appL10n("匿名统计到底在统计什么？", "What does anonymous stats actually collect?")
        alert.informativeText = appL10n(
            """
            这里只统计“有多少人在用 iFanControl”。

            应用会定期发送一个随机安装 ID、版本号和 build，用来估算使用人数。不包含你的姓名、邮箱、序列号、设备名称，也不会上传风扇曲线内容。

            说得直白一点：这个功能主要是让开发者知道，原来真的还有人在用他的软件，他会开心一下。

            不过截至这个版本发出时，最新版的活跃用户基本上还是开发者本人。是的，看到后台时会有一点点想哭。
            """,
            """
            This only counts how many people are using iFanControl.

            The app periodically sends a random install ID, version, and build so the developer can estimate active usage. It does not include your name, email, serial number, device name, or your fan-curve content.

            Put simply: this feature mainly exists so the developer knows someone is actually using the app, which makes them a little happier.

            As of this version, the latest build is still mostly being used by the developer himself. Yes, the stats dashboard can be emotionally devastating.
            """
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: appL10n("明白了", "Got it"))
        alert.runModal()
    }

    @objc private func toggleAnonymousStats(_ sender: NSButton) {
        let shouldEnable = (sender.state == .on)
        if !shouldEnable {
            let alert = NSAlert()
            alert.messageText = appL10n("真的要关闭匿名统计吗？", "Really turn off anonymous stats?")
            alert.informativeText = appL10n(
                """
                iFanControl 的匿名统计只用来估算“有多少人在使用这个软件”。

                现实情况是：用户并不多，最新版很多时候甚至只有开发者自己在用。每多一个保持开启的用户，后台那个孤零零的数字都会稍微体面一点，也会让开发者更有动力继续更新。

                如果你还是想关闭，当然完全可以。这只是一次带着一点点求生欲的挽留。
                """,
                """
                Anonymous stats in iFanControl are only used to estimate how many people are actually using the app.

                The honest reality: there are not many users, and sometimes the latest build is effectively used only by the developer. Every person who leaves this on makes that lonely dashboard number a little less bleak, and gives the developer a bit more motivation to keep shipping updates.

                If you still want to turn it off, that is absolutely fine. This is simply a mildly dramatic attempt to ask you to reconsider.
                """
            )
            alert.alertStyle = .informational
            alert.addButton(withTitle: appL10n("继续支持开发者", "Keep it on"))
            alert.addButton(withTitle: appL10n("还是关闭吧", "Turn it off anyway"))

            if alert.runModal() == .alertFirstButtonReturn {
                sender.state = .on
                return
            }
        }

        PrivacyStatsService.shared.anonymousStatsEnabled = shouldEnable
        if sender.state == .on {
            PrivacyStatsService.shared.startup()
        }
    }

}

// 主函数
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
