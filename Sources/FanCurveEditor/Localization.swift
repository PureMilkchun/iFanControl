import Foundation

public enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case chinese = "zh-Hans"

    public static var fallback: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferred.hasPrefix("zh") ? .chinese : .english
    }

    public var menuTitle: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }

    fileprivate var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US_POSIX")
        case .chinese:
            return Locale(identifier: "zh-Hans")
        }
    }
}

public enum LocalizationKey {
    case appLanguage
    case fanCurveEditor
    case manualMode
    case automaticMode
    case setSpeed
    case launchAtLogin
    case quit
    case speedWindowTitle
    case manualTargetRPM
    case apply
    case cancel
    case reset
    case save
    case close
    case saveSuccessTitle
    case saveSuccessMessage
    case saveFailureTitle
    case speedSetSuccessTitle
    case speedSetSuccessMessage
    case ok
    case autoModeShort
    case manualModeShort
}

public extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("AppLanguageDidChange")
}

@MainActor
public final class LocalizationManager {
    public static let shared = LocalizationManager()

    public private(set) var currentLanguage: AppLanguage = .fallback

    private init() {}

    public func configure(savedLanguageCode: String?) {
        let language = savedLanguageCode.flatMap(AppLanguage.init(rawValue:)) ?? .fallback
        currentLanguage = language
    }

    public func setLanguage(_ language: AppLanguage) {
        guard currentLanguage != language else { return }
        currentLanguage = language
        NotificationCenter.default.post(name: .appLanguageDidChange, object: language)
    }

    public func text(_ key: LocalizationKey) -> String {
        switch currentLanguage {
        case .english:
            return englishValue(for: key)
        case .chinese:
            return chineseValue(for: key)
        }
    }

    public func text(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: currentLanguage.locale, arguments: arguments)
    }

    private func englishValue(for key: LocalizationKey) -> String {
        switch key {
        case .appLanguage:
            return "Language"
        case .fanCurveEditor:
            return "Fan Curve Editor..."
        case .manualMode:
            return "Manual Mode"
        case .automaticMode:
            return "Automatic Mode"
        case .setSpeed:
            return "Set Speed..."
        case .launchAtLogin:
            return "Launch at Login"
        case .quit:
            return "Quit"
        case .speedWindowTitle:
            return "Set Fan Speed"
        case .manualTargetRPM:
            return "Manual Mode Target RPM:"
        case .apply:
            return "Apply"
        case .cancel:
            return "Cancel"
        case .reset:
            return "Reset"
        case .save:
            return "Save"
        case .close:
            return "Close"
        case .saveSuccessTitle:
            return "Save Successful"
        case .saveSuccessMessage:
            return "The fan curve has been saved."
        case .saveFailureTitle:
            return "Save Failed"
        case .speedSetSuccessTitle:
            return "Speed Updated"
        case .speedSetSuccessMessage:
            return "Target speed has been set to %d RPM"
        case .ok:
            return "OK"
        case .autoModeShort:
            return "[Auto]"
        case .manualModeShort:
            return "[Manual]"
        }
    }

    private func chineseValue(for key: LocalizationKey) -> String {
        switch key {
        case .appLanguage:
            return "语言"
        case .fanCurveEditor:
            return "风扇曲线编辑器..."
        case .manualMode:
            return "手动模式"
        case .automaticMode:
            return "自动模式"
        case .setSpeed:
            return "设置转速..."
        case .launchAtLogin:
            return "开机自启动"
        case .quit:
            return "退出"
        case .speedWindowTitle:
            return "设置风扇转速"
        case .manualTargetRPM:
            return "手动模式目标转速:"
        case .apply:
            return "应用"
        case .cancel:
            return "取消"
        case .reset:
            return "重置"
        case .save:
            return "保存"
        case .close:
            return "关闭"
        case .saveSuccessTitle:
            return "保存成功"
        case .saveSuccessMessage:
            return "风扇曲线已保存"
        case .saveFailureTitle:
            return "保存失败"
        case .speedSetSuccessTitle:
            return "设置成功"
        case .speedSetSuccessMessage:
            return "目标转速已设置为 %d RPM"
        case .ok:
            return "确定"
        case .autoModeShort:
            return "[自动]"
        case .manualModeShort:
            return "[手动]"
        }
    }
}
