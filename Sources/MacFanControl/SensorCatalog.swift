import Foundation

private let currentLanguage: String = {
    if let saved = UserDefaults.standard.string(forKey: "ifancontrol.ui.language") {
        return saved
    }
    return Locale.preferredLanguages.first?.lowercased().hasPrefix("en") == true ? "en" : "zh"
}()
private func sensorL10n(_ zh: String, _ en: String) -> String {
    currentLanguage == "en" ? en : zh
}

enum TemperatureSensorCategory: Int, CaseIterable {
    case cpu
    case gpu
    case memory
    case airflow
    case storage
    case power
    case other

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return sensorL10n("内存", "Memory")
        case .airflow: return sensorL10n("气流", "Airflow")
        case .storage: return sensorL10n("存储", "Storage")
        case .power: return sensorL10n("电源/电池", "Power/Battery")
        case .other: return sensorL10n("其他", "Other")
        }
    }
}

struct TemperatureSensorDefinition: Hashable {
    let key: String
    let name: String

    var category: TemperatureSensorCategory {
        let lowered = name.lowercased()
        if lowered.contains("cpu") {
            return .cpu
        }
        if lowered.contains("gpu") {
            return .gpu
        }
        if lowered.contains("memory") {
            return .memory
        }
        if lowered.contains("airflow") {
            return .airflow
        }
        if lowered.contains("nand") || lowered.contains("ssd") || lowered.contains("drive") {
            return .storage
        }
        if lowered.contains("battery") || lowered.contains("airport") || lowered.contains("display") || lowered.contains("thunderbolt") {
            return .power
        }
        return .other
    }

    var compactName: String {
        switch category {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return sensorL10n("内存", "Memory")
        case .airflow: return sensorL10n("气流", "Airflow")
        case .storage: return sensorL10n("存储", "Storage")
        case .power: return sensorL10n("系统", "System")
        case .other: return sensorL10n("其他", "Other")
        }
    }

    var sortKey: (Int, Int, Int, String) {
        switch category {
        case .cpu:
            return (category.rawValue, cpuTierRank, trailingNumber ?? 0, key)
        case .gpu, .memory, .power:
            return (category.rawValue, 0, trailingNumber ?? 0, key)
        case .airflow:
            return (category.rawValue, 0, airflowRank, key)
        case .storage, .other:
            return (category.rawValue, 0, 0, compactName)
        }
    }

    private var trailingNumber: Int? {
        guard let range = name.range(of: "(\\d+)$", options: .regularExpression) else {
            return nil
        }
        return Int(name[range])
    }

    private var cpuTierRank: Int {
        let lowered = name.lowercased()
        if lowered.contains("efficiency") { return 0 }
        if lowered.contains("performance") { return 1 }
        if lowered.contains("super") { return 2 }
        return 3
    }

    private var airflowRank: Int {
        let lowered = name.lowercased()
        if lowered.contains("left") { return 0 }
        if lowered.contains("right") { return 1 }
        return 2
    }
}

enum SensorCatalog {
    // 基于 Stats 项目对 Apple Silicon 传感器键的公开整理，并保留常见系统温度键作为补充。
    static let appleSiliconTemperatureSensors: [TemperatureSensorDefinition] = [
        TemperatureSensorDefinition(key: "Tp09", name: "CPU efficiency core 1"),
        TemperatureSensorDefinition(key: "Tp0T", name: "CPU efficiency core 2"),
        TemperatureSensorDefinition(key: "Tp01", name: "CPU performance core 1"),
        TemperatureSensorDefinition(key: "Tp05", name: "CPU performance core 2"),
        TemperatureSensorDefinition(key: "Tp0D", name: "CPU performance core 3"),
        TemperatureSensorDefinition(key: "Tp0H", name: "CPU performance core 4"),
        TemperatureSensorDefinition(key: "Tp0L", name: "CPU performance core 5"),
        TemperatureSensorDefinition(key: "Tp0P", name: "CPU performance core 6"),
        TemperatureSensorDefinition(key: "Tp0X", name: "CPU performance core 7"),
        TemperatureSensorDefinition(key: "Tp0b", name: "CPU performance core 8"),
        TemperatureSensorDefinition(key: "Tg05", name: "GPU 1"),
        TemperatureSensorDefinition(key: "Tg0D", name: "GPU 2"),
        TemperatureSensorDefinition(key: "Tg0L", name: "GPU 3"),
        TemperatureSensorDefinition(key: "Tg0T", name: "GPU 4"),
        TemperatureSensorDefinition(key: "Tm02", name: "Memory 1"),
        TemperatureSensorDefinition(key: "Tm06", name: "Memory 2"),
        TemperatureSensorDefinition(key: "Tm08", name: "Memory 3"),
        TemperatureSensorDefinition(key: "Tm09", name: "Memory 4"),

        TemperatureSensorDefinition(key: "Tp1h", name: "CPU efficiency core 1"),
        TemperatureSensorDefinition(key: "Tp1t", name: "CPU efficiency core 2"),
        TemperatureSensorDefinition(key: "Tp1p", name: "CPU efficiency core 3"),
        TemperatureSensorDefinition(key: "Tp1l", name: "CPU efficiency core 4"),
        TemperatureSensorDefinition(key: "Tp0f", name: "CPU performance core 7"),
        TemperatureSensorDefinition(key: "Tp0j", name: "CPU performance core 8"),
        TemperatureSensorDefinition(key: "Tg0f", name: "GPU 1"),
        TemperatureSensorDefinition(key: "Tg0j", name: "GPU 2"),

        TemperatureSensorDefinition(key: "Te05", name: "CPU efficiency core 1"),
        TemperatureSensorDefinition(key: "Te0L", name: "CPU efficiency core 2"),
        TemperatureSensorDefinition(key: "Te0P", name: "CPU efficiency core 3"),
        TemperatureSensorDefinition(key: "Te0S", name: "CPU efficiency core 4"),
        TemperatureSensorDefinition(key: "Tf04", name: "CPU performance core 1"),
        TemperatureSensorDefinition(key: "Tf09", name: "CPU performance core 2"),
        TemperatureSensorDefinition(key: "Tf0A", name: "CPU performance core 3"),
        TemperatureSensorDefinition(key: "Tf0B", name: "CPU performance core 4"),
        TemperatureSensorDefinition(key: "Tf0D", name: "CPU performance core 5"),
        TemperatureSensorDefinition(key: "Tf0E", name: "CPU performance core 6"),
        TemperatureSensorDefinition(key: "Tf44", name: "CPU performance core 7"),
        TemperatureSensorDefinition(key: "Tf49", name: "CPU performance core 8"),
        TemperatureSensorDefinition(key: "Tf4A", name: "CPU performance core 9"),
        TemperatureSensorDefinition(key: "Tf4B", name: "CPU performance core 10"),
        TemperatureSensorDefinition(key: "Tf4D", name: "CPU performance core 11"),
        TemperatureSensorDefinition(key: "Tf4E", name: "CPU performance core 12"),
        TemperatureSensorDefinition(key: "Tf14", name: "GPU 1"),
        TemperatureSensorDefinition(key: "Tf18", name: "GPU 2"),
        TemperatureSensorDefinition(key: "Tf19", name: "GPU 3"),
        TemperatureSensorDefinition(key: "Tf1A", name: "GPU 4"),
        TemperatureSensorDefinition(key: "Tf24", name: "GPU 5"),
        TemperatureSensorDefinition(key: "Tf28", name: "GPU 6"),
        TemperatureSensorDefinition(key: "Tf29", name: "GPU 7"),
        TemperatureSensorDefinition(key: "Tf2A", name: "GPU 8"),

        TemperatureSensorDefinition(key: "Te09", name: "CPU efficiency core 3"),
        TemperatureSensorDefinition(key: "Te0H", name: "CPU efficiency core 4"),
        TemperatureSensorDefinition(key: "Tp0V", name: "CPU performance core 5"),
        TemperatureSensorDefinition(key: "Tp0Y", name: "CPU performance core 6"),
        TemperatureSensorDefinition(key: "Tp0e", name: "CPU performance core 8"),
        TemperatureSensorDefinition(key: "Tg0G", name: "GPU 1"),
        TemperatureSensorDefinition(key: "Tg0H", name: "GPU 2"),
        TemperatureSensorDefinition(key: "Tg1U", name: "GPU 1"),
        TemperatureSensorDefinition(key: "Tg1k", name: "GPU 2"),
        TemperatureSensorDefinition(key: "Tg0K", name: "GPU 3"),
        TemperatureSensorDefinition(key: "Tg0d", name: "GPU 5"),
        TemperatureSensorDefinition(key: "Tg0e", name: "GPU 6"),
        TemperatureSensorDefinition(key: "Tg0k", name: "GPU 8"),
        TemperatureSensorDefinition(key: "Tm0p", name: "Memory proximity 1"),
        TemperatureSensorDefinition(key: "Tm1p", name: "Memory proximity 2"),
        TemperatureSensorDefinition(key: "Tm2p", name: "Memory proximity 3"),

        TemperatureSensorDefinition(key: "Tp00", name: "CPU super core 1"),
        TemperatureSensorDefinition(key: "Tp04", name: "CPU super core 2"),
        TemperatureSensorDefinition(key: "Tp08", name: "CPU super core 3"),
        TemperatureSensorDefinition(key: "Tp0C", name: "CPU super core 4"),
        TemperatureSensorDefinition(key: "Tp0G", name: "CPU super core 5"),
        TemperatureSensorDefinition(key: "Tp0K", name: "CPU super core 6"),
        TemperatureSensorDefinition(key: "Tp0O", name: "CPU performance core 1"),
        TemperatureSensorDefinition(key: "Tp0R", name: "CPU performance core 2"),
        TemperatureSensorDefinition(key: "Tp0U", name: "CPU performance core 3"),
        TemperatureSensorDefinition(key: "Tp0a", name: "CPU performance core 5"),
        TemperatureSensorDefinition(key: "Tp0d", name: "CPU performance core 6"),
        TemperatureSensorDefinition(key: "Tp0g", name: "CPU performance core 7"),
        TemperatureSensorDefinition(key: "Tp0m", name: "CPU performance core 9"),
        TemperatureSensorDefinition(key: "Tp0p", name: "CPU performance core 10"),
        TemperatureSensorDefinition(key: "Tp0u", name: "CPU performance core 11"),
        TemperatureSensorDefinition(key: "Tp0y", name: "CPU performance core 12"),
        TemperatureSensorDefinition(key: "Tg0U", name: "GPU 1"),
        TemperatureSensorDefinition(key: "Tg0X", name: "GPU 2"),
        TemperatureSensorDefinition(key: "Tg0g", name: "GPU 4"),
        TemperatureSensorDefinition(key: "Tg1Y", name: "GPU 6"),
        TemperatureSensorDefinition(key: "Tg1c", name: "GPU 7"),
        TemperatureSensorDefinition(key: "Tg1g", name: "GPU 8"),

        TemperatureSensorDefinition(key: "TaLP", name: "Airflow left"),
        TemperatureSensorDefinition(key: "TaRF", name: "Airflow right"),
        TemperatureSensorDefinition(key: "TH0x", name: "NAND"),
        TemperatureSensorDefinition(key: "TB1T", name: "Battery 1"),
        TemperatureSensorDefinition(key: "TB2T", name: "Battery 2"),
        TemperatureSensorDefinition(key: "TW0P", name: "Airport"),
        TemperatureSensorDefinition(key: "TL0P", name: "Display"),
        TemperatureSensorDefinition(key: "TTLD", name: "Thunderbolt left"),
        TemperatureSensorDefinition(key: "TTRD", name: "Thunderbolt right")
    ]
}
